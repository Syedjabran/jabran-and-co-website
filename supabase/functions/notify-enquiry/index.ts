// ============================================================================
// JABRAN & CO. CRM — Supabase Edge Function: notify-enquiry
// Sends an email to the CEO whenever a new enquiry is inserted.
// Triggered by a Supabase Database Webhook on INSERT into crm_enquiries.
//
// DEPLOY (Supabase Dashboard, no CLI required):
//   1. Edge Functions → Deploy new function → name: notify-enquiry
//      → paste this file → Deploy.
//   2. Edge Functions → notify-enquiry → Secrets, add:
//        RESEND_API_KEY   = <your Resend API key — create free at resend.com,
//                            verify the jabranandco.com domain there>
//        NOTIFY_EMAIL     = ceo@jabranandco.com
//        FROM_EMAIL       = crm@jabranandco.com   (must be on the verified domain)
//        SITE_URL         = https://www.jabranandco.com
//        WEBHOOK_SECRET   = <any long random string you generate>
//   3. Database → Webhooks → Create webhook:
//        Name: enquiry-email   · Table: crm_enquiries · Events: INSERT
//        Type: Supabase Edge Function → notify-enquiry
//        HTTP Header:  x-webhook-secret : <same WEBHOOK_SECRET value>
//   No credential ever appears in code or in the repository.
// ============================================================================

Deno.serve(async (req: Request) => {
  try {
    // Authenticate the webhook — reject anything without the shared secret.
    const secret = Deno.env.get("WEBHOOK_SECRET") ?? "";
    if (!secret || req.headers.get("x-webhook-secret") !== secret) {
      return new Response("Unauthorized", { status: 401 });
    }

    const payload = await req.json();
    const rec = payload?.record;
    if (!rec || payload?.type !== "INSERT" || payload?.table !== "crm_enquiries") {
      return new Response("Ignored", { status: 200 });
    }

    const apiKey = Deno.env.get("RESEND_API_KEY");
    const to = Deno.env.get("NOTIFY_EMAIL") ?? "ceo@jabranandco.com";
    const from = Deno.env.get("FROM_EMAIL") ?? "crm@jabranandco.com";
    const site = Deno.env.get("SITE_URL") ?? "https://www.jabranandco.com";
    if (!apiKey) return new Response("RESEND_API_KEY not configured", { status: 500 });

    const escapeHtml = (s: unknown) =>
      String(s ?? "").replace(/[&<>"']/g, (c) =>
        ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));

    const enquiryNo = escapeHtml(rec.enquiry_number ?? "(number assigned)");
    const title = escapeHtml(rec.title ?? "New enquiry");
    const who = escapeHtml(rec.submitter_name ?? "Portal client");
    const company = escapeHtml(rec.submitter_company ?? "");
    const email = escapeHtml(rec.submitter_email ?? "");
    const phone = escapeHtml(rec.submitter_phone ?? "");
    const source = escapeHtml(rec.source ?? "");
    const summary = escapeHtml(String(rec.requirement_detail ?? "").slice(0, 600));
    const crmLink = `${site}/crm.html`;

    const html = `
      <div style="font-family:Georgia,serif; background:#0B0F14; color:#F5F3EF; padding:32px; border:1px solid #C6A55A;">
        <h2 style="color:#E4C98A; margin:0 0 4px;">JABRAN &amp; CO.</h2>
        <p style="color:#9C9690; font-size:12px; letter-spacing:2px; margin:0 0 20px;">NEW ENQUIRY RECEIVED</p>
        <table style="font-size:14px; color:#F5F3EF; border-collapse:collapse;">
          <tr><td style="padding:4px 14px 4px 0; color:#C6A55A;">Enquiry No.</td><td>${enquiryNo}</td></tr>
          <tr><td style="padding:4px 14px 4px 0; color:#C6A55A;">Subject</td><td>${title}</td></tr>
          <tr><td style="padding:4px 14px 4px 0; color:#C6A55A;">Contact</td><td>${who}${company ? " · " + company : ""}</td></tr>
          <tr><td style="padding:4px 14px 4px 0; color:#C6A55A;">Email / Phone</td><td>${email}${phone ? " · " + phone : ""}</td></tr>
          <tr><td style="padding:4px 14px 4px 0; color:#C6A55A;">Source</td><td>${source}</td></tr>
        </table>
        <p style="margin:18px 0 6px; color:#C6A55A; font-size:12px; letter-spacing:2px;">SUMMARY</p>
        <p style="font-size:14px; white-space:pre-line;">${summary}</p>
        <p style="margin-top:24px;">
          <a href="${crmLink}" style="background:#C6A55A; color:#0a0a0b; padding:10px 22px; text-decoration:none; font-size:12px; letter-spacing:1px;">OPEN IN CRM (LOGIN REQUIRED)</a>
        </p>
        <p style="color:#9C9690; font-size:11px; margin-top:24px;">Confidential — M/S Jabran &amp; Co · FBR Reg. No. J152588 · Firm Reg. No. 6634</p>
      </div>`;

    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: `JABRAN & CO. CRM <${from}>`,
        to: [to],
        subject: `New Enquiry ${rec.enquiry_number ?? ""} — ${rec.title ?? ""}`.trim(),
        html,
      }),
    });

    if (!resp.ok) {
      const err = await resp.text();
      console.error("Resend error:", err);
      return new Response("Email provider error", { status: 502 });
    }
    return new Response("Sent", { status: 200 });
  } catch (e) {
    console.error("notify-enquiry failure:", e);
    return new Response("Internal error", { status: 500 });
  }
});
