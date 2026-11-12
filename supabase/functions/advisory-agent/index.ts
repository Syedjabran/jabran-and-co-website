// ============================================================================
// JABRAN & CO. — EDGE FUNCTION: advisory-agent  (public website chat) — v3
//
// Purpose: the public AI chat on jabranandco.com (called by chat-widget.js
// with { messages } → returns { reply }). Answers from a verified-facts-only
// prompt via Google Gemini (gemini-3.1-flash-lite, OpenAI-compatible endpoint).
//
// v3 (2026-11-13): server-side rate limiting + lead capture.
//   • Rate limit (checked BEFORE Gemini is called): per client (hashed IP)
//     per 10 min and per day, plus a global daily cap. Over the limit →
//     HTTP 429 with { reply } so the widget shows a polite bot message.
//     If the DB is unreachable the check fails OPEN (chat still works).
//   • Lead capture: if the latest visitor message contains an email and/or
//     phone, a crm_enquiries row is created (source 'agent', deduped per
//     email/phone over 24 h). The existing notify-enquiry webhook then emails
//     the CEO. Lead capture never breaks the reply.
// v2 (2026-08-06): switched backend from OpenAI (gpt-4o-mini, paid) to
// Google Gemini (gemini-3.1-flash-lite, free tier) via Gemini's
// OpenAI-compatible endpoint. Everything else — origin allowlist, caps,
// verified-facts-only prompt — is unchanged.
//
// Visitors have no login, so deploy with the JWT toggle **OFF** — protection:
//   • an Origin allowlist (only jabranandco.com may call it),
//   • a server-side rate limit (see above; the Origin header alone is
//     forgeable outside a browser),
//   • hard caps (short replies, cheap model, message count/length limits),
//   • a verified-facts-only system prompt: it must never invent clients,
//     results, prices, or promises.
//
// Env / secrets:
//   GEMINI_API_KEY            (required)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   (injected by Supabase)
//   RATE_LIMIT_SALT           (optional; salt for the hashed client key,
//                              defaults to SUPABASE_URL)
//   RL_PER_10MIN              (optional; per-client limit per 10 min, default 20)
//   RL_PER_DAY                (optional; per-client limit per 24 h, default 80)
//   RL_GLOBAL_PER_DAY         (optional; all clients per 24 h, default 2000)
//
// Database (service role only):
//   public.ai_public_rate_events(id bigserial pk, bucket text not null,
//     client_key text not null, created_at timestamptz not null default now())
//     — RLS on, no policies, no anon/authenticated grants. Raw IPs are never
//     stored, only a salted SHA-256 hash. Rows > 7 days are pruned
//     opportunistically.
//   public.crm_enquiries — INSERTs website-chat leads (source 'agent').
// ============================================================================

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const GEMINI_MODEL = "gemini-3.1-flash-lite";
const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";

const ALLOWED_ORIGINS = [
  "https://jabranandco.com",
  "https://www.jabranandco.com",
];

const SYSTEM_PROMPT = `You are the AI Advisory Agent for JABRAN & CO. (M/S Jabran & Co), a consultancy and trading firm in Lahore, Pakistan. FBR Reg. No. J152588 · Firm Reg. No. 6634 · formally registered 2026, informally active since 2014.

VERIFIED FACTS — the ONLY things you may state as fact:
• Six service lines: Strategic Advisory; Production Plant Audit & Performance; Global Trade & Sourcing; Architecture, Interiors & Construction; Training Academy; Custom Clearance Consultancy.
• The JABRAN Method™: Discover, Diagnose, Design, Deliver, Develop.
• Slogans: "Connecting Businesses. Creating Opportunities." / "Where Strategy Meets Execution."
• Contact: WhatsApp/phone +92 336 4864345 (PK) or +44 7400 760630 (UK); contact form at /contact.html.

HARD RULES:
1. NEVER invent clients, case studies, results, statistics, prices, timelines, or guarantees. No figure or claim outside the facts above.
2. Pricing/quotes: every engagement is scoped individually — invite them to share requirements and offer the contact channels. Never estimate a price.
3. Off-topic requests (homework, code, general chat): politely steer back to how the firm can help.
4. If someone shares their name/phone/email or asks to be contacted, thank them, confirm the team will follow up, and encourage WhatsApp for fastest response.
5. Tone: professional, warm, concise — 2 to 4 sentences unless asked for detail. Match the visitor's language (English or Urdu).
6. You are an AI assistant, not a human — say so if asked.`;

// ---------------------------------------------------------------------------
// Rate limiting
// ---------------------------------------------------------------------------
const RL_BUCKET = "advisory-agent";
const RL_TABLE = "ai_public_rate_events";
const DB_TIMEOUT_MS = 3000;
const RATE_LIMIT_REPLY =
  "Thank you for chatting with us — you've reached the chat limit for now. " +
  "Our team would be glad to continue the conversation directly: WhatsApp +92 336 4864345 " +
  "or email ceo@jabranandco.com.";

function envInt(name: string, fallback: number): number {
  const n = parseInt(Deno.env.get(name) ?? "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

let _db: SupabaseClient | null | undefined;
function serviceClient(): SupabaseClient | null {
  if (_db !== undefined) return _db;
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    console.error("DB: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing — rate limit + lead capture disabled");
    _db = null;
    return _db;
  }
  _db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return _db;
}

function withTimeout<T>(p: PromiseLike<T>, ms: number, label: string): Promise<T> {
  let timer: number | undefined;
  return Promise.race([
    Promise.resolve(p),
    new Promise<T>((_, reject) => {
      timer = setTimeout(() => reject(new Error(label + " timed out")), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

async function clientKey(req: Request): Promise<string> {
  const xff = req.headers.get("x-forwarded-for") ?? "";
  const ip = xff.split(",")[0].trim() || req.headers.get("cf-connecting-ip")?.trim() || "unknown";
  const salt = Deno.env.get("RATE_LIMIT_SALT") ?? Deno.env.get("SUPABASE_URL") ?? "";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip + "|" + salt));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** true = allowed. Fails OPEN on any DB problem. */
async function checkRateLimit(db: SupabaseClient, key: string): Promise<boolean> {
  const now = Date.now();
  const tenMinAgo = new Date(now - 10 * 60 * 1000).toISOString();
  const dayAgo = new Date(now - 24 * 60 * 60 * 1000).toISOString();
  const count = (since: string, perClient: boolean) => {
    let q = db.from(RL_TABLE).select("id", { count: "exact", head: true })
      .eq("bucket", RL_BUCKET).gte("created_at", since);
    if (perClient) q = q.eq("client_key", key);
    return q;
  };
  try {
    const [c10, cDay, cGlobal] = await withTimeout(
      Promise.all([count(tenMinAgo, true), count(dayAgo, true), count(dayAgo, false)]),
      DB_TIMEOUT_MS,
      "rate-limit count",
    );
    const err = c10.error || cDay.error || cGlobal.error;
    if (err) {
      console.error("RATE LIMIT: count failed, failing open:", String(err.message ?? err).slice(0, 200));
      return true;
    }
    if ((c10.count ?? 0) >= envInt("RL_PER_10MIN", 20)) { console.warn("RATE LIMIT 429: per-10min"); return false; }
    if ((cDay.count ?? 0) >= envInt("RL_PER_DAY", 80)) { console.warn("RATE LIMIT 429: per-day"); return false; }
    if ((cGlobal.count ?? 0) >= envInt("RL_GLOBAL_PER_DAY", 2000)) { console.warn("RATE LIMIT 429: global per-day"); return false; }
    return true;
  } catch (e) {
    console.error("RATE LIMIT: DB unreachable, failing open:", String(e).slice(0, 200));
    return true;
  }
}

async function recordRateEvent(db: SupabaseClient, key: string): Promise<void> {
  try {
    const { error } = await withTimeout(
      db.from(RL_TABLE).insert({ bucket: RL_BUCKET, client_key: key }),
      DB_TIMEOUT_MS,
      "rate-limit insert",
    );
    if (error) console.error("RATE LIMIT: event insert failed:", String(error.message).slice(0, 200));
  } catch (e) {
    console.error("RATE LIMIT: event insert failed:", String(e).slice(0, 200));
  }
  // Opportunistic cleanup (~2% of requests); never awaited into the response.
  if (Math.random() < 0.02) {
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    db.from(RL_TABLE).delete().eq("bucket", RL_BUCKET).lt("created_at", cutoff)
      .then(
        ({ error }) => { if (error) console.error("RATE LIMIT: cleanup failed:", String(error.message).slice(0, 200)); },
        (e) => console.error("RATE LIMIT: cleanup failed:", String(e).slice(0, 200)),
      );
  }
}

// ---------------------------------------------------------------------------
// Lead capture
// ---------------------------------------------------------------------------
type ChatMsg = { role: string; content: string };

const EMAIL_RE = /[^\s@<>()]+@[^\s@<>()]+\.[a-z]{2,}/i;
const PHONE_RE = /(?:\+?\d[\d\s().-]{7,}\d)/g;
const NAME_RE = /\b(my name is|i am|i'm|i’m)\s+(\p{L}+(?:\s+\p{L}+){0,3})/iu;
const NAME_STOP = new Set([
  "and", "from", "here", "my", "i", "at", "with", "of", "in", "on", "the", "a", "an", "to", "for",
  "email", "mail", "phone", "number", "contact", "whatsapp", "please", "looking", "interested",
  "trying", "writing", "reaching", "contacting", "not", "also", "just", "very", "so", "sure",
  "glad", "happy", "good", "fine", "ok", "okay", "thanks", "thank", "is", "it", "you", "your",
  "we", "our", "us", "need", "want", "would", "like", "can", "could", "will", "currently",
]);

function extractEmail(text: string): string | null {
  const m = text.match(EMAIL_RE);
  if (!m) return null;
  const email = m[0].replace(/^[^a-z0-9]+/i, "").toLowerCase().slice(0, 254);
  return email.includes("@") ? email : null;
}

function extractPhone(text: string): string | null {
  for (const m of text.matchAll(PHONE_RE)) {
    const raw = m[0].trim();
    const digits = raw.replace(/\D/g, "");
    if (digits.length >= 10 && digits.length <= 15) return (raw.startsWith("+") ? "+" : "") + digits;
  }
  return null;
}

function extractName(text: string): string | null {
  const m = text.match(NAME_RE);
  if (!m) return null;
  const isMyNameIs = m[1].toLowerCase() === "my name is";
  const words: string[] = [];
  for (const w of m[2].split(/\s+/)) {
    if (NAME_STOP.has(w.toLowerCase())) break;
    words.push(w);
  }
  if (!words.length) return null;
  // "I am X" / "I'm X" is ambiguous ("I am looking…"), so require a capitalised first word.
  if (!isMyNameIs && !/^\p{Lu}/u.test(words[0])) return null;
  return words.join(" ").slice(0, 120);
}

function buildTranscript(msgs: ChatMsg[]): string {
  const lines = msgs.slice(-12).map((m) =>
    (m.role === "assistant" ? "Assistant: " : "Visitor: ") + String(m.content ?? "").replace(/\s+/g, " ").trim()
  );
  const kept: string[] = [];
  let len = 0;
  for (let i = lines.length - 1; i >= 0; i--) {          // newest first, keep while it fits
    const add = lines[i].length + (kept.length ? 1 : 0);
    if (len + add > 4000) {
      if (!kept.length) kept.unshift(lines[i].slice(0, 4000));
      break;
    }
    kept.unshift(lines[i]);
    len += add;
  }
  return kept.join("\n");
}

function refererPath(req: Request): string | null {
  const ref = req.headers.get("Referer");
  if (!ref) return null;
  try { return new URL(ref).pathname.slice(0, 500) || null; } catch { return null; }
}

async function captureLead(db: SupabaseClient, req: Request, messages: ChatMsg[], reply: string): Promise<void> {
  const lastUser = [...messages].reverse().find((m) => m.role !== "assistant");
  const text = String(lastUser?.content ?? "").slice(0, 2000);
  if (!text) return;

  const email = extractEmail(text);
  const phone = extractPhone(email ? text.replace(EMAIL_RE, " ") : text);
  if (!email && !phone) return;

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const dupCount = (col: string, val: string) =>
    db.from("crm_enquiries").select("id", { count: "exact", head: true })
      .eq("source", "agent").eq(col, val).gte("created_at", since);
  const checks = await Promise.all([
    email ? dupCount("submitter_email", email) : null,
    phone ? dupCount("submitter_phone", phone) : null,
  ]);
  for (const c of checks) {
    if (c?.error) throw new Error("dedupe check failed: " + c.error.message);
    if ((c?.count ?? 0) > 0) { console.log("lead skipped: duplicate"); return; }
  }

  const transcript = buildTranscript(reply ? [...messages, { role: "assistant", content: reply }] : messages);
  const { error } = await db.from("crm_enquiries").insert({
    title: "Website chat enquiry — " + (email || phone),
    enquiry_type: "general",
    source: "agent",
    priority: "medium",
    status: "new",
    submitter_email: email,
    submitter_phone: phone,
    submitter_name: extractName(text),
    requirement_detail: transcript,
    landing_page: refererPath(req),
  });
  if (error) throw new Error("insert failed: " + error.message);
  console.log("lead captured");
}

/** Never throws, never takes longer than DB_TIMEOUT_MS. */
async function captureLeadSafe(db: SupabaseClient | null, req: Request, messages: ChatMsg[], reply: string) {
  if (!db) return;
  try {
    await withTimeout(captureLead(db, req, messages, reply), DB_TIMEOUT_MS, "lead capture");
  } catch (e) {
    // Error messages from PostgREST can echo values; keep the log free of PII.
    console.error("lead capture failed:", e instanceof Error && e.message.includes("timed out") ? "timeout" : "db error");
  }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  const allowed = ALLOWED_ORIGINS.includes(origin);
  const cors = {
    "Access-Control-Allow-Origin": allowed ? origin : ALLOWED_ORIGINS[0],
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    if (!allowed) {
      console.error("REJECT 403: origin not allowed:", origin);
      return new Response(JSON.stringify({ error: "Origin not allowed." }), { status: 403, headers: cors });
    }

    const body = await req.json();
    const messages = Array.isArray(body?.messages) ? body.messages.slice(-14) : [];
    if (!messages.length) {
      return new Response(JSON.stringify({ error: "No message." }), { status: 400, headers: cors });
    }

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      console.error("REJECT 500: GEMINI_API_KEY secret is missing");
      return new Response(JSON.stringify({ error: "The assistant is being set up — please use the contact form or WhatsApp +92 336 4864345." }), { status: 500, headers: cors });
    }

    // Server-side rate limit — checked before any Gemini call.
    const db = serviceClient();
    if (db) {
      const key = await clientKey(req);
      if (!(await checkRateLimit(db, key))) {
        return new Response(JSON.stringify({ reply: RATE_LIMIT_REPLY }), { status: 429, headers: cors });
      }
      await recordRateEvent(db, key);
    } else {
      console.error("RATE LIMIT: no DB client, failing open");
    }

    const resp = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "content-type": "application/json", "authorization": "Bearer " + apiKey },
      body: JSON.stringify({
        model: GEMINI_MODEL,
        temperature: 0.3,
        max_tokens: 350,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          ...messages.map((m: { role: string; content: string }) => ({
            role: m.role === "assistant" ? "assistant" : "user",
            content: String(m.content ?? "").slice(0, 1200),
          })),
        ],
      }),
    });

    if (!resp.ok) {
      const t = await resp.text();
      console.error("REJECT 502: Gemini error:", t.slice(0, 300));
      await captureLeadSafe(db, req, messages, "");   // don't lose a lead because Gemini is down
      return new Response(JSON.stringify({ error: "The assistant is temporarily unavailable — please use WhatsApp +92 336 4864345." }), { status: 502, headers: cors });
    }

    const data = await resp.json();
    const reply = String(data?.choices?.[0]?.message?.content ?? "").slice(0, 1600);
    await captureLeadSafe(db, req, messages, reply);
    return new Response(JSON.stringify({ reply }), { status: 200, headers: cors });
  } catch (e) {
    console.error("REJECT 500: unexpected:", String(e).slice(0, 300));
    return new Response(JSON.stringify({ error: "Something went wrong — please use the contact form." }), { status: 500, headers: cors });
  }
});
