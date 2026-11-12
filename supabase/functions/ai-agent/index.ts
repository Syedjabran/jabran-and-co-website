// ============================================================================
// JABRAN & CO. — ai-agent Edge Function (Increment 7)
// Deploy name: ai-agent · JWT verification: OFF (public widget)
// Secrets required: AI_API_KEY  (Anthropic key)
// Optional secrets: AI_PROVIDER (default 'anthropic'), AI_MODEL_PUBLIC
//   (default 'claude-3-5-haiku-latest'), AI_MAX_TOKENS (default 600),
//   ALLOWED_ORIGIN (default '*')
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Security model: the browser holds only {conversation_id, visitor_token}.
// Every request is authenticated against ai_conversations.visitor_token.
// All database writes happen here with the service role — the anonymous
// key has no access to any ai_* table. Permissions are enforced by this
// code and RLS, never by the language model.
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";
const CORS = {
  "Access-Control-Allow-Origin": ORIGIN,
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: CORS });

// ---------------------------------------------------------------- helpers
const redact = (t: string) =>
  t.replace(/\b(?:\d[ -]?){13,19}\b/g, "[redacted card number]")
   .replace(/\b(password|passcode)\s*[:=]\s*\S+/gi, "$1: [redacted]");

function score(st: Record<string, unknown>): { score: number; cls: string } {
  let s = 0;
  if (st.email) s += 20;
  if (st.phone) s += 15;
  if (st.company) s += 10;
  if (st.country) s += 10;
  if (st.budget) s += 15;
  if (st.timeline) s += 15;
  if (typeof st.requirement === "string" && st.requirement.length > 40) s += 15;
  const cls = s >= 70 ? "sales_qualified" : s >= 40 ? "marketing_qualified" : s >= 15 ? "early_enquiry" : "unqualified";
  return { score: s, cls };
}

async function callProvider(system: string, history: { role: string; content: string }[],
                            model: string, maxTokens: number, temperature: number) {
  const provider = (Deno.env.get("AI_PROVIDER") || "anthropic").toLowerCase();
  const key = Deno.env.get("AI_API_KEY");
  if (!key) throw new Error("AI_API_KEY secret is not set");
  const t0 = Date.now();
  if (provider === "anthropic") {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model, max_tokens: maxTokens, temperature, system, messages: history }),
    });
    const d = await r.json();
    if (!r.ok) throw new Error(d?.error?.message || "provider error");
    const text = (d.content || []).map((c: { text?: string }) => c.text || "").join("");
    const tokens = (d.usage?.input_tokens || 0) + (d.usage?.output_tokens || 0);
    return { text, tokens, latency: Date.now() - t0, provider, model };
  }
  throw new Error(`Unsupported AI_PROVIDER '${provider}' — extend callProvider() to add it.`);
}

// tolerant JSON extraction from the model reply
function parseControl(raw: string) {
  const fallback = { reply: raw.trim(), state: {}, qualified: false, handoff: false, handoff_reason: null, confidence: 0.5 };
  try {
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) return fallback;
    const p = JSON.parse(m[0]);
    if (typeof p.reply !== "string" || !p.reply.trim()) return fallback;
    return {
      reply: p.reply.trim(),
      state: (typeof p.state === "object" && p.state) || {},
      qualified: !!p.qualified,
      handoff: !!p.handoff,
      handoff_reason: p.handoff_reason || null,
      confidence: typeof p.confidence === "number" ? p.confidence : 0.7,
    };
  } catch { return fallback; }
}

const HUMAN_FALLBACK =
  "I want to make sure you get an accurate answer, so I've flagged this for one of our specialists — " +
  "you can also reach the team directly on WhatsApp +92 336 4864345. Is there anything else I can note for them?";

// ---------------------------------------------------------------- handler
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  const action = String(body.action || "");

  const { data: cfg } = await sb.from("ai_agent_configs").select("*").limit(1).maybeSingle();
  if (!cfg) return json({ error: "agent not configured" }, 503);

  // -------- config (widget boot) --------
  if (action === "config") {
    return json({
      enabled: cfg.is_enabled,
      agent_name: cfg.agent_name,
      greeting: cfg.greeting,
      disclosure: cfg.disclosure,
      proactive: cfg.proactive_enabled
        ? { seconds: cfg.proactive_seconds, scroll_pct: cfg.proactive_scroll_pct, cap_hours: cfg.frequency_cap_hours }
        : null,
    });
  }

  if (!cfg.is_enabled) return json({ error: "disabled" }, 503);

  // -------- start --------
  if (action === "start") {
    const { data: c, error } = await sb.from("ai_conversations").insert({
      channel: "web_widget",
      conversation_type: "public",
      session_id: String(body.session_id || "").slice(0, 80) || null,
      source_url: String(body.url || "").slice(0, 500) || null,
      landing_page: String(body.landing || "").slice(0, 500) || null,
      utm_source: String(body.utm_source || "").slice(0, 120) || null,
      utm_medium: String(body.utm_medium || "").slice(0, 120) || null,
      utm_campaign: String(body.utm_campaign || "").slice(0, 120) || null,
    }).select("id, visitor_token, conversation_reference").single();
    if (error) return json({ error: "could not start conversation" }, 500);
    await sb.from("ai_messages").insert({
      conversation_id: c.id, sender_type: "assistant", message_type: "text", content: cfg.greeting,
    });
    return json({ conversation_id: c.id, visitor_token: c.visitor_token, reference: c.conversation_reference });
  }

  // ---- everything below requires token auth ----
  const convId = String(body.conversation_id || "");
  const token = String(body.visitor_token || "");
  if (!convId || !token) return json({ error: "unauthorised" }, 401);
  const { data: conv } = await sb.from("ai_conversations").select("*")
    .eq("id", convId).eq("visitor_token", token).maybeSingle();
  if (!conv) return json({ error: "unauthorised" }, 401);

  // -------- history (resume) --------
  if (action === "history") {
    const { data: msgs } = await sb.from("ai_messages")
      .select("sender_type, content, created_at")
      .eq("conversation_id", convId).eq("message_type", "text")
      .order("created_at").limit(60);
    return json({ reference: conv.conversation_reference, status: conv.status, messages: msgs || [] });
  }

  // -------- feedback --------
  if (action === "feedback") {
    const rating = Number(body.rating);
    if (rating >= 1 && rating <= 5) {
      await sb.from("ai_agent_feedback").insert({
        conversation_id: convId, rating, feedback: String(body.feedback || "").slice(0, 1000) || null,
      });
    }
    return json({ ok: true });
  }

  // -------- message --------
  if (action === "message") {
    let content = String(body.content || "").trim();
    if (!content) return json({ error: "empty" }, 400);
    if (content.length > cfg.max_message_chars) content = content.slice(0, cfg.max_message_chars);
    content = redact(content);

    if (["human_active", "human_requested"].includes(conv.status)) {
      await sb.from("ai_messages").insert({
        conversation_id: convId, sender_type: "visitor", message_type: "text", content,
      });
      return json({ reply: null, human: true, reference: conv.conversation_reference });
    }
    if (["resolved", "abandoned", "spam"].includes(conv.status)) {
      return json({ error: "closed", reference: conv.conversation_reference }, 409);
    }

    // rate limits
    const minuteAgo = new Date(Date.now() - 60_000).toISOString();
    const { count: recent } = await sb.from("ai_messages")
      .select("id", { count: "exact", head: true })
      .eq("conversation_id", convId).eq("sender_type", "visitor").gte("created_at", minuteAgo);
    if ((recent || 0) >= cfg.rate_per_minute) {
      return json({ reply: "Please give me a moment to keep up — one message at a time works best.", throttled: true });
    }
    const { count: total } = await sb.from("ai_messages")
      .select("id", { count: "exact", head: true }).eq("conversation_id", convId);
    if ((total || 0) >= cfg.max_messages) {
      await sb.from("ai_agent_handoffs").insert({ conversation_id: convId, requested_by: "rule", handoff_reason: "Conversation length limit reached" });
      return json({ reply: HUMAN_FALLBACK, human: true });
    }

    await sb.from("ai_messages").insert({
      conversation_id: convId, sender_type: "visitor", message_type: "text", content,
    });

    // daily budget guard
    const dayStart = new Date(); dayStart.setUTCHours(0, 0, 0, 0);
    const { data: usage } = await sb.from("ai_usage_log")
      .select("token_usage").gte("created_at", dayStart.toISOString()).limit(2000);
    const spent = (usage || []).reduce((a, u) => a + (u.token_usage || 0), 0);
    if (spent >= cfg.daily_token_budget) {
      await sb.from("ai_agent_handoffs").insert({ conversation_id: convId, requested_by: "rule", handoff_reason: "Daily AI budget reached" });
      return json({ reply: HUMAN_FALLBACK, human: true });
    }

    // build the model request
    const { data: pv } = await sb.from("ai_prompt_versions").select("version_number, prompt_text")
      .eq("agent", "public").eq("is_active", true).maybeSingle();
    if (!pv) return json({ reply: HUMAN_FALLBACK, human: true });

    const known = {
      name: conv.contact_name, email: conv.contact_email, phone: conv.contact_phone,
      company: conv.contact_company, country: conv.contact_country,
      service: conv.service_context, requirement: conv.intent,
    };
    const system = pv.prompt_text +
      `\n\nCURRENT PAGE: ${String(body.page || "").slice(0, 200)}` +
      `\nKNOWN VISITOR DETAILS (never re-ask for these): ${JSON.stringify(known)}` +
      `\n\nRESPOND WITH ONLY a JSON object, no markdown fences, in this exact shape:` +
      `\n{"reply":"<your message to the visitor>","state":{"name":null,"email":null,"phone":null,"company":null,"country":null,"service":null,"budget":null,"timeline":null,"requirement":null},"qualified":false,"handoff":false,"handoff_reason":null,"confidence":0.9}` +
      `\nFill state with any NEW details learned this turn (null otherwise). Set qualified true once you hold a name, a contact channel, and a clear requirement. Set handoff true when a human is needed.`;

    const { data: hist } = await sb.from("ai_messages")
      .select("sender_type, content").eq("conversation_id", convId)
      .eq("message_type", "text").order("created_at", { ascending: false }).limit(14);
    const history = (hist || []).reverse()
      .filter((m) => ["visitor", "assistant", "client"].includes(m.sender_type) && m.content)
      .map((m) => ({ role: m.sender_type === "assistant" ? "assistant" : "user", content: m.content as string }));
    if (!history.length || history[history.length - 1].role !== "user") {
      history.push({ role: "user", content });
    }

    let out;
    const model = cfg.model_public || Deno.env.get("AI_MODEL_PUBLIC") || "claude-3-5-haiku-latest";
    const maxTokens = Number(Deno.env.get("AI_MAX_TOKENS") || 600);
    try {
      out = await callProvider(system, history, model, maxTokens, Number(cfg.temperature || 0.3));
    } catch (e) {
      await sb.from("ai_usage_log").insert({ conversation_id: convId, provider: "anthropic", model, error: String(e).slice(0, 400) });
      await sb.from("ai_agent_handoffs").insert({ conversation_id: convId, requested_by: "rule", handoff_reason: "Provider failure" });
      return json({ reply: HUMAN_FALLBACK, human: true });
    }
    await sb.from("ai_usage_log").insert({
      conversation_id: convId, provider: out.provider, model: out.model,
      prompt_version: pv.version_number, token_usage: out.tokens, latency_ms: out.latency,
    });

    const ctl = parseControl(out.text);

    // merge newly learned state (server-side truth)
    const st = ctl.state as Record<string, string | null>;
    const upd: Record<string, unknown> = { last_message_at: new Date().toISOString() };
    if (st.name && !conv.contact_name) upd.contact_name = String(st.name).slice(0, 160);
    if (st.email && !conv.contact_email) upd.contact_email = String(st.email).slice(0, 200);
    if (st.phone && !conv.contact_phone) upd.contact_phone = String(st.phone).slice(0, 40);
    if (st.company && !conv.contact_company) upd.contact_company = String(st.company).slice(0, 200);
    if (st.country && !conv.contact_country) upd.contact_country = String(st.country).slice(0, 80);
    if (st.service) upd.service_context = String(st.service).slice(0, 120);
    if (st.requirement) upd.intent = String(st.requirement).slice(0, 1000);

    const merged = {
      email: upd.contact_email || conv.contact_email, phone: upd.contact_phone || conv.contact_phone,
      company: upd.contact_company || conv.contact_company, country: upd.contact_country || conv.contact_country,
      budget: st.budget, timeline: st.timeline, requirement: upd.intent || conv.intent,
    };
    const sc = score(merged);
    upd.lead_score = sc.score; upd.lead_class = sc.cls;

    // qualified → create the CRM enquiry once (deduped by conversation link)
    let reference = conv.conversation_reference;
    if ((ctl.qualified || sc.score >= 40) && merged.email && !conv.enquiry_id) {
      const detail =
        `AI Advisory Agent conversation ${reference}\n` +
        `Service interest: ${upd.service_context || conv.service_context || "—"}\n` +
        `Requirement: ${merged.requirement || "—"}\n` +
        (st.budget ? `Budget: ${st.budget}\n` : "") + (st.timeline ? `Timeline: ${st.timeline}\n` : "") +
        `Lead score: ${sc.score} (${sc.cls})`;
      const { data: enq } = await sb.from("crm_enquiries").insert({
        source: "ai_agent", status: "new", enquiry_type: "general",
        title: "AI Agent enquiry — " + (merged.company || upd.contact_name || conv.contact_name || "Website visitor"),
        submitter_name: (upd.contact_name || conv.contact_name || null) as string | null,
        submitter_email: merged.email as string,
        submitter_phone: (merged.phone || null) as string | null,
        submitter_company: (merged.company || null) as string | null,
        country: (merged.country || null) as string | null,
        requirement_detail: detail,
      }).select("id").maybeSingle();
      if (enq) upd.enquiry_id = enq.id;   // existing notify-enquiry webhook emails the CEO
    }

    if (ctl.handoff) {
      await sb.from("ai_agent_handoffs").insert({
        conversation_id: convId, requested_by: "ai",
        handoff_reason: ctl.handoff_reason || "Visitor requested a human specialist",
      });
    }

    await sb.from("ai_conversations").update(upd).eq("id", convId);
    await sb.from("ai_messages").insert({
      conversation_id: convId, sender_type: "assistant", message_type: "text",
      content: ctl.reply, model_name: out.model, prompt_version: String(pv.version_number),
      token_usage: out.tokens, confidence_score: ctl.confidence,
      requires_human_review: ctl.confidence < 0.4,
    });

    return json({ reply: ctl.reply, reference, handoff: ctl.handoff, qualified: !!upd.enquiry_id || !!conv.enquiry_id });
  }

  return json({ error: "unknown action" }, 400);
});
