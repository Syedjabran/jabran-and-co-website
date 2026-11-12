// ============================================================================
// JABRAN & CO. CRM — EDGE FUNCTION: ai-accountant  (OpenAI / ChatGPT version)
//
// Drop-in replacement: same function name, same request/response shape, so
// crm-ai-accountant.html and all SQL stay exactly as deployed. Only the AI
// provider changes: Anthropic → OpenAI (model: gpt-4o-mini, JSON mode).
//
// ROLE: language → structured proposal ONLY. No service-role key, no writes.
// The page executes confirmed actions under the user's own session (RLS).
//
// DEPLOY:
//   1. Supabase → Edge Functions → Secrets → add:  OPENAI_API_KEY = sk-...
//      (from platform.openai.com → API keys. ChatGPT Plus does NOT include
//      API access — add a small pay-as-you-go credit on the platform.)
//   2. Edge Functions → ai-accountant → replace ALL code with this file
//      → Deploy. JWT toggle stays ON.
//   3. Nothing else changes — no HTML, no SQL.
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
const OPENAI_MODEL = "gemini-3.1-flash-lite"; // v2 2026-08-06: Gemini free tier via OpenAI-compat endpoint (was gpt-4o-mini)
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
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_ANON_KEY"), {
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
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      console.error("REJECT 500: GEMINI_API_KEY secret is missing");
      return new Response(JSON.stringify({
        error: "GEMINI_API_KEY not configured — add it in Edge Function Secrets."
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
    const resp = await fetch("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": "Bearer " + apiKey
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        temperature: 0,
        max_tokens: 700,
        response_format: {
          type: "json_object"
        },
        messages: [
          {
            role: "system",
            content: system
          },
          ...messages.map((m)=>({
              role: m.role === "assistant" ? "assistant" : "user",
              content: String(m.content ?? "").slice(0, 2000)
            }))
        ]
      })
    });
    if (!resp.ok) {
      const t = await resp.text();
      console.error("REJECT 502: OpenAI error:", t.slice(0, 300));
      return new Response(JSON.stringify({
        error: "AI service error: " + t.slice(0, 300)
      }), {
        status: 502,
        headers: cors
      });
    }
    const data = await resp.json();
    const text = String(data?.choices?.[0]?.message?.content ?? "").replace(/```json|```/g, "").trim();
    let parsed = {};
    try {
      parsed = JSON.parse(text);
    } catch (_e) {
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
