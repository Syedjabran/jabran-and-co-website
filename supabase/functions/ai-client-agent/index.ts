// ============================================================================
// JABRAN & CO. — ai-client-agent Edge Function (Increment 9)
// Deploy name: ai-client-agent · JWT verification: ON (authenticated clients only)
// Secrets: AI_API_KEY (shared with ai-agent). Optional: AI_MODEL_CLIENT
//   (default AI_MODEL_PUBLIC → 'claude-3-5-haiku-latest'), AI_MAX_TOKENS,
//   ALLOWED_ORIGIN.
//
// Security model (Section 8.3, implemented literally):
//   1. Supabase verifies the JWT before this code runs (toggle ON).
//   2. A user-scoped client re-validates the session and executes
//      ai_client_snapshot() AS THE CLIENT — so the data bundle is exactly
//      what RLS and the definer function permit for that organisation.
//   3. A service client is used ONLY to write conversation rows
//      (assistant messages, status) — never to read CRM data for the model.
//   4. The model receives the snapshot and nothing else; permissions are
//      enforced by code and RLS, never by the language model.
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const svc = createClient(URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";
const CORS = {
  "Access-Control-Allow-Origin": ORIGIN,
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: CORS });

const redact = (t: string) =>
  t.replace(/\b(?:\d[ -]?){13,19}\b/g, "[redacted card number]")
   .replace(/\b(password|passcode)\s*[:=]\s*\S+/gi, "$1: [redacted]");

function parseControl(raw: string) {
  const fb = { reply: raw.trim(), handoff: false, handoff_reason: null as string | null, confidence: 0.6 };
  try {
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) return fb;
    const p = JSON.parse(m[0]);
    if (typeof p.reply !== "string" || !p.reply.trim()) return fb;
    return { reply: p.reply.trim(), handoff: !!p.handoff,
             handoff_reason: p.handoff_reason || null,
             confidence: typeof p.confidence === "number" ? p.confidence : 0.7 };
  } catch { return fb; }
}

async function callAnthropic(system: string, history: { role: string; content: string }[],
                             model: string, maxTokens: number) {
  const key = Deno.env.get("AI_API_KEY");
  if (!key) throw new Error("AI_API_KEY secret is not set");
  const t0 = Date.now();
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model, max_tokens: maxTokens, temperature: 0.2, system, messages: history }),
  });
  const d = await r.json();
  if (!r.ok) throw new Error(d?.error?.message || "provider error");
  const text = (d.content || []).map((c: { text?: string }) => c.text || "").join("");
  const tokens = (d.usage?.input_tokens || 0) + (d.usage?.output_tokens || 0);
  return { text, tokens, latency: Date.now() - t0, model };
}

const FALLBACK =
  "I've flagged this for your Relationship Manager so a person follows up directly. " +
  "You can also reach the team on WhatsApp +92 336 4864345.";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // 1–2 · identity: user-scoped client from the caller's own JWT
  const auth = req.headers.get("authorization") || "";
  const user_sb = createClient(URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: udata, error: uerr } = await user_sb.auth.getUser();
  if (uerr || !udata?.user) return json({ error: "unauthorised" }, 401);
  const uid = udata.user.id;

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  const action = String(body.action || "");

  const { data: cfg } = await svc.from("ai_agent_configs").select("*").limit(1).maybeSingle();
  if (!cfg || !cfg.is_enabled) return json({ error: "disabled" }, 503);

  // find-or-create the client's open conversation (service role, identity-bound)
  async function getConversation() {
    const { data: existing } = await svc.from("ai_conversations").select("*")
      .eq("user_id", uid).eq("conversation_type", "client")
      .in("status", ["ai_active", "human_requested", "human_active", "waiting_client"])
      .order("last_message_at", { ascending: false }).limit(1).maybeSingle();
    if (existing) return existing;
    let org: string | null = null;
    try {
      const { data: pm } = await svc.from("crm_portal_members")
        .select("organization_id").eq("user_id", uid).limit(1).maybeSingle();
      org = pm?.organization_id || null;
    } catch { /* leave null */ }
    const { data: c } = await svc.from("ai_conversations").insert({
      channel: "client_portal", conversation_type: "client",
      user_id: uid, organization_id: org,
    }).select("*").single();
    return c;
  }

  if (action === "history") {
    const conv = await getConversation();
    const { data: msgs } = await svc.from("ai_messages")
      .select("sender_type, content, created_at")
      .eq("conversation_id", conv.id).eq("message_type", "text")
      .order("created_at").limit(80);
    return json({ reference: conv.conversation_reference, status: conv.status, messages: msgs || [] });
  }

  if (action === "message") {
    let content = String(body.content || "").trim();
    if (!content) return json({ error: "empty" }, 400);
    if (content.length > cfg.max_message_chars) content = content.slice(0, cfg.max_message_chars);
    content = redact(content);

    const conv = await getConversation();

    if (["human_active", "human_requested"].includes(conv.status)) {
      await svc.from("ai_messages").insert({
        conversation_id: conv.id, sender_type: "client", sender_user_id: uid,
        message_type: "text", content,
      });
      return json({ reply: null, human: true, reference: conv.conversation_reference });
    }

    // rate limit
    const minuteAgo = new Date(Date.now() - 60_000).toISOString();
    const { count: recent } = await svc.from("ai_messages")
      .select("id", { count: "exact", head: true })
      .eq("conversation_id", conv.id).eq("sender_type", "client").gte("created_at", minuteAgo);
    if ((recent || 0) >= cfg.rate_per_minute) {
      return json({ reply: "One message at a time works best — I'm still with you.", throttled: true });
    }

    await svc.from("ai_messages").insert({
      conversation_id: conv.id, sender_type: "client", sender_user_id: uid,
      message_type: "text", content,
    });

    // 2 · the snapshot — fetched AS THE CLIENT (definer function + auth.uid())
    let snapshot: unknown = null;
    try {
      const { data: snap, error: serr } = await user_sb.rpc("ai_client_snapshot");
      if (serr) throw serr;
      snapshot = snap;
    } catch {
      await svc.from("ai_agent_handoffs").insert({
        conversation_id: conv.id, requested_by: "rule",
        handoff_reason: "Client snapshot unavailable (account may be unlinked)",
      });
      return json({ reply: "Your portal account isn't fully linked yet — I've flagged it for the team. " +
        "Meanwhile you can reach us on WhatsApp +92 336 4864345.", human: true });
    }

    const { data: pv } = await svc.from("ai_prompt_versions")
      .select("version_number, prompt_text").eq("agent", "client").eq("is_active", true).maybeSingle();
    if (!pv) return json({ reply: FALLBACK, human: true });

    const system = pv.prompt_text +
      `\n\nCLIENT DATA SNAPSHOT (authorised, live):\n${JSON.stringify(snapshot)}` +
      `\n\nRESPOND WITH ONLY a JSON object, no markdown fences:` +
      `\n{"reply":"<your message>","handoff":false,"handoff_reason":null,"confidence":0.9}`;

    const { data: hist } = await svc.from("ai_messages")
      .select("sender_type, content").eq("conversation_id", conv.id)
      .eq("message_type", "text").order("created_at", { ascending: false }).limit(12);
    const history = (hist || []).reverse()
      .filter((m) => ["client", "assistant", "staff"].includes(m.sender_type) && m.content)
      .map((m) => ({ role: m.sender_type === "assistant" ? "assistant" : "user", content: m.content as string }));
    if (!history.length || history[history.length - 1].role !== "user") {
      history.push({ role: "user", content });
    }

    const model = Deno.env.get("AI_MODEL_CLIENT") || cfg.model_public ||
                  Deno.env.get("AI_MODEL_PUBLIC") || "claude-3-5-haiku-latest";
    let out;
    try {
      out = await callAnthropic(system, history, model, Number(Deno.env.get("AI_MAX_TOKENS") || 700));
    } catch (e) {
      await svc.from("ai_usage_log").insert({ conversation_id: conv.id, provider: "anthropic",
        model, error: String(e).slice(0, 400) });
      await svc.from("ai_agent_handoffs").insert({ conversation_id: conv.id,
        requested_by: "rule", handoff_reason: "Provider failure (client agent)" });
      return json({ reply: FALLBACK, human: true });
    }
    await svc.from("ai_usage_log").insert({
      conversation_id: conv.id, provider: "anthropic", model: out.model,
      prompt_version: pv.version_number, token_usage: out.tokens, latency_ms: out.latency,
    });

    const ctl = parseControl(out.text);
    if (ctl.handoff) {
      await svc.from("ai_agent_handoffs").insert({
        conversation_id: conv.id, requested_by: "ai",
        handoff_reason: ctl.handoff_reason || "Client requested human follow-up",
      });
    }
    await svc.from("ai_messages").insert({
      conversation_id: conv.id, sender_type: "assistant", message_type: "text",
      content: ctl.reply, model_name: out.model, prompt_version: String(pv.version_number),
      token_usage: out.tokens, confidence_score: ctl.confidence,
      requires_human_review: ctl.confidence < 0.4,
    });
    await svc.from("ai_conversations").update({ last_message_at: new Date().toISOString() })
      .eq("id", conv.id);

    return json({ reply: ctl.reply, reference: conv.conversation_reference, handoff: ctl.handoff });
  }

  return json({ error: "unknown action" }, 400);
});
