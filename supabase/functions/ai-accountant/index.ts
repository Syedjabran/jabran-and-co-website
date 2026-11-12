// ============================================================================
// JABRAN & CO. CRM — EDGE FUNCTION: ai-accountant
//
// Drop-in replacement: same function name, same request/response shape, so
// crm-ai-accountant.html and all SQL stay exactly as deployed.
//
// AI provider (shared client ../_shared/llm.ts, the same choices as ScholexAI):
//   Claude (Anthropic) when ANTHROPIC_API_KEY is set, else Google Gemini
//   (gemini-3.1-flash-lite, OpenAI-compatible endpoint, JSON mode, temperature
//   0); AI_PROVIDER=anthropic|gemini overrides. Claude: claude-haiku-5-5 at
//   effort low by default, no temperature, the long system prompt cached, the
//   JSON reply read from its text.
//   History: Anthropic → OpenAI gpt-4o-mini → Gemini (v2 2026-08-06) →
//   Claude preferred, Gemini fallback (v3 2026-11-13).
//
// ROLE: language → structured proposal ONLY. No service-role key, no writes.
// The page executes confirmed actions under the user's own session (RLS).
//
// SECRETS (Supabase → Edge Functions → Secrets):
//   ANTHROPIC_API_KEY   Claude (preferred when set)
//   ANTHROPIC_MODEL     optional, default claude-haiku-5-5
//   ANTHROPIC_EFFORT    optional, low|medium|high|xhigh|max (default low)
//   AI_PROVIDER         optional, anthropic|gemini forces one provider
//   GEMINI_API_KEY      fallback when ANTHROPIC_API_KEY is not set
//   — at least one of ANTHROPIC_API_KEY / GEMINI_API_KEY is required.
//
// DEPLOY: from the repo (docs/DEPLOYMENT.md). JWT verification stays ON.
//   No HTML or SQL changes.
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import { callLlm, selectProvider } from "../_shared/llm.ts";
const CATEGORIES = [
  "fuel",
  "travel",
  "food_entertainment",
  "courier",
  "parking_toll",
  "office_supplies",
  "software_subscription",
  "domain_hosting",
  "marketing",
  "utilities",
  "phone_internet",
  "repairs",
  "professional_fees",
  "customs",
  "other"
];
Deno.serve(async (req)=>{
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json"
  };
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: cors
  });
  try {
    // User-scoped client: every check runs as the caller, never elevated.
    const auth = req.headers.get("Authorization") ?? "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: {
        headers: {
          Authorization: auth
        }
      }
    });
    const { data: isStaff, error: staffErr } = await sb.rpc("crm_is_staff");
    if (staffErr || isStaff !== true) {
      console.error("REJECT 403: staff check failed", staffErr ? String(staffErr.message) : "not staff");
      return new Response(JSON.stringify({
        error: "Staff accounts only."
      }), {
        status: 403,
        headers: cors
      });
    }
    const body = await req.json();
    const messages = Array.isArray(body?.messages) ? body.messages.slice(-12) : [];
    const ctx = body?.context ?? {};
    if (!messages.length) {
      return new Response(JSON.stringify({
        error: "No message."
      }), {
        status: 400,
        headers: cors
      });
    }
    if (!selectProvider()) {
      console.error("REJECT 500: no AI key secret (ANTHROPIC_API_KEY / GEMINI_API_KEY) is set");
      return new Response(JSON.stringify({
        error: "ANTHROPIC_API_KEY (or GEMINI_API_KEY) not configured — add it in Edge Function Secrets."
      }), {
        status: 500,
        headers: cors
      });
    }
    const today = new Date().toISOString().slice(0, 10);
    const system = `You are the accounting intake agent for JABRAN & CO. (Lahore, Pakistan). You parse staff messages about money and work hours into ONE structured proposal. You never invent amounts, names, or dates. Default currency is PKR. Today is ${today}.

Respond with ONLY a JSON object:
{"reply": "<short human reply>", "action": <object or null>}

Action types (include "type" plus the listed fields):
1. record_expense — {description, amount, currency, category, entry_date, order_ref} · category must be one of: ${CATEGORIES.join(", ")} · order_ref only if the user names an order · goes to the Owner approval queue, say so in reply.
2. log_hours — {employee_name, hours, work_date, order_ref, description} · employee_name null means the speaker themself.
3. add_subscription — {software_name, cost, billing_cycle(monthly|quarterly|yearly), currency, renewal_date}
4. update_subscription — {software_name, new_cost, new_billing_cycle} (only fields the user stated)
5. cancel_subscription — {software_name}
6. add_fixed_expense — {name, category, frequency(daily|weekly|monthly|quarterly|half_yearly|yearly|one_time), amount, currency}
7. update_salary — {employee_name, new_monthly_salary}
8. renew_subscription — {software_name} (user says a subscription renewed/was paid — treat the payment itself as a record_expense ONLY if they state an amount)

Rules:
- A required field missing (especially an amount) → action = null and reply asks ONE specific question. Never guess amounts.
- Amounts like "Rs 5,700", "5700 rupees", "PKR 5700" → 5700, PKR.
- Relative dates: "today" = ${today}; resolve "yesterday" etc. from it.
- Subscription/salary/fixed-expense changes are Owner-restricted; if context says the user is not management, still parse, but the reply must note it may be blocked by permissions.
- Questions about figures: answer ONLY from the context snapshot below; if it isn't there, say you don't have that figure rather than estimating. action = null.
- If the user lists MANY items in one message, take the FIRST actionable item, and in the reply tell them you'll handle the rest one at a time — ask them to send the next item after confirming this one.
- The user confirms in the app, so phrase replies as proposals ("I've prepared… confirm below").

Context snapshot (already permission-filtered by the app):
${JSON.stringify(ctx).slice(0, 4000)}`;
    const result = await callLlm({
      system,
      cache: true,
      json: true,
      temperature: 0, // Gemini only
      maxTokens: 700,
      messages: messages.map((m: { role?: string; content?: unknown })=>({
          role: m.role === "assistant" ? "assistant" as const : "user" as const,
          content: String(m.content ?? "").slice(0, 2000)
        }))
    });
    if (!result.ok && (result.reason === "http" || result.reason === "timeout" || result.reason === "no-provider")) {
      console.error("REJECT 502: AI error:", result.reason, result.status ?? "");
      return new Response(JSON.stringify({
        error: "AI service error: " + String(result.detail ?? result.reason).slice(0, 300)
      }), {
        status: 502,
        headers: cors
      });
    }
    let parsed: { reply?: unknown; action?: unknown } = {};
    if (!result.ok) {
      // "empty" (no text came back) or "blocked" (the AI declined the request).
      parsed = {
        reply: result.reason === "blocked" ? "I can't help with that one — please rephrase it as an expense, hours or subscription entry." : "I couldn't parse that — please rephrase.",
        action: null
      };
    } else if (result.json && typeof result.json === "object") {
      parsed = result.json as { reply?: unknown; action?: unknown };
    } else {
      const text = result.text.replace(/```json|```/g, "").trim();
      parsed = {
        reply: text || "I couldn't parse that — please rephrase.",
        action: null
      };
    }
    return new Response(JSON.stringify({
      reply: String(parsed.reply ?? "").slice(0, 1200),
      action: parsed.action ?? null
    }), {
      status: 200,
      headers: cors
    });
  } catch (e) {
    console.error("REJECT 500: unexpected:", String(e).slice(0, 300));
    return new Response(JSON.stringify({
      error: "Unexpected error: " + String(e).slice(0, 200)
    }), {
      status: 500,
      headers: cors
    });
  }
});
