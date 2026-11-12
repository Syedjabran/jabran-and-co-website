// ============================================================================
// JABRAN & CO. CRM — Supabase Edge Function: send-client-email  (v3)
// Sends a branded, letterhead email to a client THROUGH ceo@jabranandco.com
// (via the Google Apps Script Gmail relay). Role-gated; every send is logged.
//
// v3 additions:
//   • Multiple Cc + Bcc recipients (comma/array accepted).
//   • Attachments — either uploaded inline (base64 from the browser) OR pulled
//     from the connected private storage bucket "crm-private" by referencing an
//     existing crm_attachments row (attachment_id) or its file_path. Bucket
//     files are fetched server-side with the service-role key (bucket stays
//     private; the browser never needs bucket access).
//
// DEPLOY (Supabase Dashboard, no CLI):
//   1. Edge Functions → send-client-email → paste this file → Deploy.
//      (Leave "Verify JWT" ON — default.)
//   2. Secrets (unchanged): GMAIL_RELAY_URL, GMAIL_RELAY_SECRET,
//      REPLY_TO (optional), SENDER_NAME (optional).
//   SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_ROLES = [
  "owner", "super_admin", "ceo", "business_development",
  "account_manager", "consultancy_manager", "operations_manager", "project_manager",
];

const ASSETS = "https://www.jabranandco.com";
const ICONS = "https://ops.sjabrankamran.com/dl/email-feature/icons";

// Attachment safety limits
const ATTACH_BUCKET = "crm-private";
const MAX_TOTAL_BYTES = 22 * 1024 * 1024;  // ~22 MB total across all attachments
const MAX_FILES = 15;

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));

// Normalise a recipient list (string with commas/semicolons OR array) → clean "a, b, c"
function normList(v: unknown): string {
  const parts = Array.isArray(v) ? v : String(v ?? "").split(/[,;]+/);
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of parts) {
    const e = String(raw ?? "").trim();
    if (e && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) && !seen.has(e.toLowerCase())) {
      seen.add(e.toLowerCase()); out.push(e);
    }
  }
  return out.join(", ");
}

function u8ToB64(u8: Uint8Array): string {
  let bin = ""; const chunk = 0x8000;
  for (let i = 0; i < u8.length; i += chunk) {
    bin += String.fromCharCode(...u8.subarray(i, i + chunk));
  }
  return btoa(bin);
}
function b64Len(b64: string): number {
  const s = String(b64 || "").replace(/=+$/, "");
  return Math.floor((s.length * 3) / 4);
}
function safeName(n: unknown, fallback = "attachment"): string {
  const base = String(n ?? "").split(/[\\/]/).pop() || fallback;
  return base.replace(/[\r\n"]/g, "").slice(0, 180) || fallback;
}

// Turn a plain-text message (what the sender typed) into safe paragraphs.
function messageToHtml(message: string): string {
  const blocks = String(message ?? "").replace(/\r\n/g, "\n").split(/\n{2,}/);
  return blocks
    .map((b) => `<p style="margin:0 0 16px 0;">${esc(b).replace(/\n/g, "<br>")}</p>`)
    .join("\n");
}

function renderEmail(opts: {
  clientName?: string; message: string; ref?: string; dateStr: string;
}): string {
  const greeting = opts.clientName
    ? `<p style="margin:0 0 16px 0;">Dear ${esc(opts.clientName)},</p>`
    : "";
  const refRow = opts.ref
    ? `<td align="right" style="font-size:12px; color:#8C8577; letter-spacing:0.5px;">Ref: ${esc(opts.ref)}</td>`
    : `<td align="right"></td>`;
  const icon = (name: string, href: string, alt: string, pad = "0 12px 0 0") =>
    `<td style="padding:${pad};"><a href="${href}" target="_blank"><img src="${ICONS}/${name}.png" width="26" height="26" alt="${alt}" style="display:block; border:0;"></a></td>`;

  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0; padding:0; background:#E9E4DA; -webkit-text-size-adjust:100%;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#E9E4DA; width:100%;"><tr>
<td align="center" style="padding:26px 12px;">
<!--[if mso]><table role="presentation" width="560" cellpadding="0" cellspacing="0"><tr><td><![endif]-->
<table role="presentation" align="center" width="560" cellpadding="0" cellspacing="0" style="width:560px; max-width:560px; margin:0 auto; background:#FFFFFF; border:1px solid #E4DCC9; box-shadow:0 2px 14px rgba(11,15,20,0.10);">
  <tr><td style="height:4px; background:#C6A55A; font-size:0; line-height:0;">&nbsp;</td></tr>
  <tr><td style="padding:28px 40px 16px 40px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      <td align="left" valign="middle" style="width:60%;">
        <img src="${ASSETS}/logo-full.png" width="148" alt="JABRAN &amp; CO." style="display:block; border:0; width:148px; max-width:148px; height:auto;">
      </td>
      <td align="right" valign="top" style="width:40%; font-family:Georgia,'Times New Roman',serif; color:#8A7A55; font-size:10px; letter-spacing:2px; line-height:1.7; text-transform:uppercase;">Where Strategy<br>Meets Execution</td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:0 40px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="border-top:1px solid #EAE2D0; font-size:0; line-height:0;">&nbsp;</td></tr></table></td></tr>
  <tr><td style="padding:14px 40px 0 40px; font-family:Arial,Helvetica,sans-serif; font-size:12px; color:#8C8577;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
      <td align="left" style="font-size:12px; color:#8C8577;">${esc(opts.dateStr)}</td>${refRow}
    </tr></table>
  </td></tr>
  <tr><td style="padding:18px 40px 8px 40px; font-family:Arial,Helvetica,sans-serif; font-size:14.5px; line-height:1.75; color:#2B2B2B;">
    ${greeting}
    ${messageToHtml(opts.message)}
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:24px;"><tr>
      <td valign="bottom" align="left" style="width:62%;">
        <p style="margin:0 0 6px 0; font-family:Arial,Helvetica,sans-serif; font-size:14px; color:#2B2B2B;">With warm regards,</p>
        <img src="${ASSETS}/signature-dark.png" width="180" alt="Signature" style="display:block; border:0; width:180px; max-width:180px; height:auto; margin:2px 0 6px 0;">
        <p style="margin:0; font-family:Georgia,'Times New Roman',serif; font-size:15px; color:#0B0F14; font-weight:bold;">Syed Jabran Ali Kamran</p>
        <p style="margin:2px 0 0 0; font-family:Arial,Helvetica,sans-serif; font-size:12px; color:#8A7A55; letter-spacing:0.5px;">Founder &amp; Chief Executive &middot; M/S Jabran &amp; Co</p>
      </td>
      <td valign="bottom" align="right" style="width:38%;">
        <img src="${ASSETS}/estamp-gold.png" width="100" alt="Jabran &amp; Co Certified Seal" style="display:block; border:0; width:100px; max-width:100px; height:auto;">
      </td>
    </tr></table>
  </td></tr>
  <tr><td style="padding:0;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0B0F14;"><tr>
    <td style="padding:18px 40px; font-family:Arial,Helvetica,sans-serif;">
      <p style="margin:0 0 6px 0; color:#E4C98A; font-size:12px; letter-spacing:1px;">M/S JABRAN &amp; CO</p>
      <p style="margin:0 0 3px 0; color:#B7B0A4; font-size:11.5px; line-height:1.7;">28, Sector M8, Lake City, Lahore, Pakistan</p>
      <p style="margin:0 0 3px 0; color:#B7B0A4; font-size:11.5px; line-height:1.7;">PK +92 336 4864345 &nbsp;&middot;&nbsp; UK +44 7400 760630</p>
      <p style="margin:0 0 12px 0; color:#B7B0A4; font-size:11.5px; line-height:1.7;">
        <a href="mailto:ceo@jabranandco.com" style="color:#C6A55A; text-decoration:none;">ceo@jabranandco.com</a> &nbsp;&middot;&nbsp;
        <a href="${ASSETS}" style="color:#C6A55A; text-decoration:none;">www.jabranandco.com</a>
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 12px 0;"><tr>
        ${icon("linkedin", "https://www.linkedin.com/company/jabran-co/", "LinkedIn")}
        ${icon("facebook", "https://www.facebook.com/profile.php?id=61591833980876", "Facebook")}
        ${icon("instagram", "https://www.instagram.com/jabranandco/", "Instagram")}
        ${icon("google", "https://share.google/amYjnjZoikyxjfDTK", "Google Business")}
        ${icon("youtube", "https://www.youtube.com/channel/UCpXz-vvwD996n176U8fy1uQ", "YouTube")}
        ${icon("x", "https://x.com/Syed_Jabran", "X", "0")}
      </tr></table>
      <p style="margin:0; color:#6E6A61; font-size:10px; letter-spacing:0.6px;">FBR REG. NO. J152588 &nbsp;&middot;&nbsp; FIRM REG. NO. 6634</p>
    </td>
  </tr></table></td></tr>
  <tr><td style="padding:12px 40px 20px 40px; font-family:Arial,Helvetica,sans-serif; font-size:10px; line-height:1.6; color:#A49E92; background:#FFFFFF;" data-frame="end">
    This message and any attachments are confidential and intended solely for the addressee. If you have received it in error, please notify us and delete it. Sent on behalf of M/S Jabran &amp; Co.
  </td></tr>
</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr></table></body></html>`;
}

type RelayAttachment = { filename: string; mimeType: string; contentBase64: string };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const jsonHeaders = { ...cors, "Content-Type": "application/json" };
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: jsonHeaders });
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const relayUrl = Deno.env.get("GMAIL_RELAY_URL");
    const relaySecret = Deno.env.get("GMAIL_RELAY_SECRET");
    const replyTo = Deno.env.get("REPLY_TO") ?? "ceo@jabranandco.com";
    const senderName = Deno.env.get("SENDER_NAME") ?? "Syed Jabran Ali Kamran — Jabran & Co";

    if (!relayUrl || !relaySecret) {
      return new Response(JSON.stringify({ error: "Email relay not configured. Add GMAIL_RELAY_URL and GMAIL_RELAY_SECRET." }),
        { status: 500, headers: jsonHeaders });
    }

    // 1 · Identify caller + verify governance role
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: allowed, error: roleErr } = await caller.rpc("crm_has_role", { roles: ALLOWED_ROLES });
    if (roleErr || allowed !== true) {
      return new Response(JSON.stringify({ error: "Not authorized to send client email." }), { status: 403, headers: jsonHeaders });
    }
    let uid: string | null = null;
    try { const u = await caller.auth.getUser(); uid = u.data.user?.id ?? null; } catch (_) { uid = null; }

    // service-role client (bucket downloads + logging; bypasses RLS)
    const admin = createClient(url, service);

    // 2 · Validate input
    const body = await req.json();
    const to = String(body?.to ?? "").trim();
    const cc = normList(body?.cc);
    const bcc = normList(body?.bcc);
    const subject = String(body?.subject ?? "").trim();
    const message = String(body?.message ?? "");
    const clientName = String(body?.client_name ?? "").trim();
    const ref = String(body?.ref ?? "").trim();
    const organization_id = body?.organization_id ?? null;
    const opportunity_id = body?.opportunity_id ?? null;
    const enquiry_id = body?.enquiry_id ?? null;
    const attIn = Array.isArray(body?.attachments) ? body.attachments : [];

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to)) {
      return new Response(JSON.stringify({ error: "A valid recipient email is required." }), { status: 400, headers: jsonHeaders });
    }
    if (!subject) return new Response(JSON.stringify({ error: "Subject is required." }), { status: 400, headers: jsonHeaders });
    if (!message.trim()) return new Response(JSON.stringify({ error: "Message is required." }), { status: 400, headers: jsonHeaders });
    if (attIn.length > MAX_FILES) {
      return new Response(JSON.stringify({ error: `Too many attachments (max ${MAX_FILES}).` }), { status: 400, headers: jsonHeaders });
    }

    // 3 · Resolve attachments (inline base64 OR from the connected crm-private bucket)
    const relayAttachments: RelayAttachment[] = [];
    const attNames: string[] = [];
    let totalBytes = 0;
    for (const a of attIn) {
      try {
        let filename = safeName(a?.filename);
        let mimeType = String(a?.mimeType || a?.content_type || "application/octet-stream");
        let contentBase64 = "";

        if (a?.contentBase64) {
          // uploaded from the browser
          contentBase64 = String(a.contentBase64);
        } else if (a?.attachment_id || a?.file_path) {
          // pull from the private CRM bucket via service role
          let file_path = a?.file_path ? String(a.file_path) : "";
          if (a?.attachment_id) {
            const { data: row, error: rowErr } = await admin
              .from("crm_attachments")
              .select("file_path,file_name,content_type,size_bytes,deleted_at")
              .eq("id", a.attachment_id)
              .is("deleted_at", null)
              .maybeSingle();
            if (rowErr || !row) throw new Error(`document not found (${safeName(a?.filename)})`);
            file_path = String(row.file_path);
            filename = safeName(a?.filename || row.file_name);
            mimeType = String(row.content_type || mimeType);
          }
          if (!file_path) throw new Error(`missing file_path for ${filename}`);
          const dl = await admin.storage.from(ATTACH_BUCKET).download(file_path);
          if (dl.error || !dl.data) throw new Error(`could not read ${filename} from storage`);
          const buf = new Uint8Array(await dl.data.arrayBuffer());
          contentBase64 = u8ToB64(buf);
        } else {
          continue; // nothing usable
        }

        const bytes = b64Len(contentBase64);
        totalBytes += bytes;
        if (totalBytes > MAX_TOTAL_BYTES) {
          return new Response(JSON.stringify({ error: "Attachments exceed the total size limit (~22 MB)." }),
            { status: 400, headers: jsonHeaders });
        }
        relayAttachments.push({ filename, mimeType, contentBase64 });
        attNames.push(filename);
      } catch (e) {
        return new Response(JSON.stringify({ error: "Attachment error: " + String(e instanceof Error ? e.message : e) }),
          { status: 400, headers: jsonHeaders });
      }
    }

    // 4 · Render branded letterhead
    const dateStr = new Intl.DateTimeFormat("en-GB", {
      day: "numeric", month: "long", year: "numeric", timeZone: "Asia/Karachi",
    }).format(new Date());
    const html = renderEmail({ clientName, message, ref, dateStr });

    // 5 · Send via the Gmail relay (ceo@jabranandco.com)
    let ok = false, sendErr = "", sentAs = "";
    try {
      const r = await fetch(relayUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          secret: relaySecret, to, cc: cc || undefined, bcc: bcc || undefined,
          subject, htmlBody: html, replyTo, senderName,
          attachments: relayAttachments.length ? relayAttachments : undefined,
        }),
      });
      const txt = await r.text();
      let j: any = {}; try { j = JSON.parse(txt); } catch (_) { j = { ok: false, error: txt.slice(0, 300) }; }
      ok = r.ok && j.ok === true;
      sentAs = j.sentAs ?? "";
      if (!ok) sendErr = j.error || `relay HTTP ${r.status}`;
    } catch (e) {
      ok = false; sendErr = String(e);
    }

    // 6 · Log (service role — bypasses RLS)
    try {
      const preview = message.slice(0, 500) +
        (attNames.length ? `\n\n[${attNames.length} attachment(s): ${attNames.join(", ")}]` : "");
      await admin.from("crm_email_log").insert({
        organization_id, opportunity_id, enquiry_id,
        to_email: to, cc_email: cc || null, subject,
        body_preview: preview,
        status: ok ? "sent" : "failed",
        provider: "gmail-relay", provider_ref: sentAs || null,
        error: ok ? null : sendErr, sent_by: uid,
      });
    } catch (_) { /* logging must never break the response */ }

    if (!ok) {
      return new Response(JSON.stringify({ error: "Send failed: " + sendErr }), { status: 502, headers: jsonHeaders });
    }
    return new Response(JSON.stringify({ ok: true, sent_as: sentAs || "ceo@jabranandco.com", attachments: attNames.length }),
      { status: 200, headers: jsonHeaders });

  } catch (e) {
    console.error("send-client-email failure:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), { status: 500, headers: jsonHeaders });
  }
});
