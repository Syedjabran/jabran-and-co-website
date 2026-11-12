// ============================================================================
// JABRAN & CO. — EDGE FUNCTION: advisory-agent  (public website chat) — v2
//
// v2 (2026-08-06): switched backend from OpenAI (gpt-4o-mini, paid) to
// Google Gemini (gemini-3.1-flash-lite, free tier) via Gemini's
// OpenAI-compatible endpoint. Everything else — origin allowlist, caps,
// verified-facts-only prompt — is unchanged.
//
// Visitors have no login, so deploy with the JWT toggle **OFF** — protection:
//   • an Origin allowlist (only jabranandco.com may call it),
//   • hard caps (short replies, cheap model, message length limits),
//   • a verified-facts-only system prompt: it must never invent clients,
//     results, prices, or promises.
//
// Requires secret: GEMINI_API_KEY
// ============================================================================

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
      return new Response(JSON.stringify({ error: "The assistant is temporarily unavailable — please use WhatsApp +92 336 4864345." }), { status: 502, headers: cors });
    }

    const data = await resp.json();
    const reply = String(data?.choices?.[0]?.message?.content ?? "").slice(0, 1600);
    return new Response(JSON.stringify({ reply }), { status: 200, headers: cors });
  } catch (e) {
    console.error("REJECT 500: unexpected:", String(e).slice(0, 300));
    return new Response(JSON.stringify({ error: "Something went wrong — please use the contact form." }), { status: 500, headers: cors });
  }
});
