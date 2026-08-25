// ============================================================================
// JABRAN & CO. CRM — Supabase Edge Function: send-client-email
// Sends a branded, letterhead email to a client THROUGH ceo@jabranandco.com
// (via the Google Apps Script Gmail relay). Role-gated, and every send is
// logged to crm_email_log.
//
// DEPLOY (Supabase Dashboard, no CLI):
//   1. Edge Functions → Deploy new function → name: send-client-email
//      → paste this file → Deploy.  (Leave "Verify JWT" ON — default.)
//   2. Edge Functions → send-client-email → Secrets, add:
//        GMAIL_RELAY_URL     = the /exec Web-app URL from the Apps Script
//        GMAIL_RELAY_SECRET  = the SAME long secret you put in the script
//        REPLY_TO            = ceo@jabranandco.com          (optional)
//        SENDER_NAME         = Syed Jabran Ali Kamran — Jabran & Co   (optional)
//      (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY are injected
//       automatically by Supabase — do not add them.)
//   The CRM compose page calls this function with the staff member's own login
//   token; the function verifies their role before doing anything.
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
const ATTACHMENT_BUCKET = "crm-private";
const MAX_CC = 10;
const MAX_ATTACHMENTS = 5;
const MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024;
const MAX_TOTAL_ATTACHMENT_BYTES = 18 * 1024 * 1024;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const MIME_BY_EXTENSION: Record<string, string> = {
  pdf: "application/pdf", doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xls: "application/vnd.ms-excel",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ppt: "application/vnd.ms-powerpoint",
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp",
  csv: "text/csv", txt: "text/plain", zip: "application/zip",
};

type AttachmentRequest = {
  bucket?: unknown; path?: unknown; name?: unknown; type?: unknown; size?: unknown;
};
type RelayAttachment = { name: string; contentType: string; dataBase64: string };

class InputError extends Error {
  constructor(message: string) { super(message); this.name = "InputError"; }
}

function parseCc(value: unknown, to: string): string[] {
  const raw = Array.isArray(value) ? value : String(value ?? "").split(/[;,]/);
  const entries = raw.map((x) => String(x ?? "").trim()).filter(Boolean);
  if (entries.length > MAX_CC) throw new InputError(`A maximum of ${MAX_CC} Cc recipients is allowed.`);
  const seen = new Set<string>();
  const result: string[] = [];
  for (const email of entries) {
    if (!EMAIL_RE.test(email)) throw new InputError(`Invalid Cc email: ${email}`);
    const key = email.toLowerCase();
    if (key === to.toLowerCase()) throw new InputError("The main recipient is already listed in Cc.");
    if (!seen.has(key)) { seen.add(key); result.push(email); }
  }
  return result;
}

function extensionOf(name: string): string {
  return name.toLowerCase().match(/\.([a-z0-9]+)$/)?.[1] ?? "";
}

function cleanFileName(value: unknown): string {
  const cleaned = String(value ?? "attachment")
    .replace(/[^A-Za-z0-9._()\- ]+/g, "_")
    .replace(/\s+/g, "_")
    .slice(-120);
  return cleaned || "attachment";
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + chunkSize, bytes.length)));
  }
  return btoa(binary);
}

function callerAttachmentPaths(value: unknown, uid: string): string[] {
  if (!Array.isArray(value)) return [];
  const prefix = `attachments/email/${uid}/`;
  return value.map((x) => String((x as AttachmentRequest)?.path ?? ""))
    .filter((path) => path.startsWith(prefix));
}

async function removeStoredAttachments(admin: any, paths: string[]): Promise<void> {
  if (!paths.length) return;
  try { await admin.storage.from(ATTACHMENT_BUCKET).remove(paths); } catch (_) { /* best effort */ }
}

async function loadAttachments(admin: any, uid: string, value: unknown): Promise<{
  relay: RelayAttachment[]; paths: string[]; names: string[];
}> {
  if (value == null) return { relay: [], paths: [], names: [] };
  if (!Array.isArray(value)) throw new InputError("Attachments must be supplied as a list.");
  if (value.length > MAX_ATTACHMENTS) {
    throw new InputError(`A maximum of ${MAX_ATTACHMENTS} attachments is allowed.`);
  }

  const prefix = `attachments/email/${uid}/`;
  const relay: RelayAttachment[] = [], paths: string[] = [], names: string[] = [];
  let totalBytes = 0;
  for (const raw of value as AttachmentRequest[]) {
    const bucket = String(raw?.bucket ?? ATTACHMENT_BUCKET);
    const path = String(raw?.path ?? "");
    const name = cleanFileName(raw?.name);
    const extension = extensionOf(name);
    const contentType = MIME_BY_EXTENSION[extension];
    if (bucket !== ATTACHMENT_BUCKET) throw new InputError("Attachments must use the private CRM bucket.");
    if (!path.startsWith(prefix)) throw new InputError("Invalid attachment storage path.");
    if (!contentType) throw new InputError(`File type not allowed: ${name}`);

    const { data, error } = await admin.storage.from(ATTACHMENT_BUCKET).download(path);
    if (error || !data) throw new InputError(`Attachment is unavailable: ${name}`);
    const bytes = new Uint8Array(await data.arrayBuffer());
    if (bytes.byteLength > MAX_ATTACHMENT_BYTES) throw new InputError(`${name} exceeds the 8 MB per-file limit.`);
    totalBytes += bytes.byteLength;
    if (totalBytes > MAX_TOTAL_ATTACHMENT_BYTES) throw new InputError("Attachments exceed the 18 MB total limit.");

    relay.push({ name, contentType, dataBase64: bytesToBase64(bytes) });
    paths.push(path); names.push(name);
  }
  return { relay, paths, names };
}

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));

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
    if (!uid) {
      return new Response(JSON.stringify({ error: "Your staff session expired. Sign in again." }),
        { status: 401, headers: jsonHeaders });
    }
    const admin = createClient(url, service);

    // 2 · Validate input
    const body = await req.json();
    const to = String(body?.to ?? "").trim();
    const subject = String(body?.subject ?? "").trim();
    const message = String(body?.message ?? "");
    const clientName = String(body?.client_name ?? "").trim();
    const ref = String(body?.ref ?? "").trim();
    const organization_id = body?.organization_id ?? null;
    const opportunity_id = body?.opportunity_id ?? null;
    const enquiry_id = body?.enquiry_id ?? null;
    const uploadedPaths = callerAttachmentPaths(body?.attachments, uid);
    let cc: string[] = [];
    let attachments: { relay: RelayAttachment[]; paths: string[]; names: string[] } = {
      relay: [], paths: [], names: [],
    };

    try {
      if (!EMAIL_RE.test(to)) throw new InputError("A valid recipient email is required.");
      cc = parseCc(body?.cc, to);
      if (!subject) throw new InputError("Subject is required.");
      if (!message.trim()) throw new InputError("Message is required.");
      attachments = await loadAttachments(admin, uid, body?.attachments);
    } catch (e) {
      await removeStoredAttachments(admin, uploadedPaths);
      const error = e instanceof InputError ? e.message : "Could not prepare attachments.";
      return new Response(JSON.stringify({ error }), { status: 400, headers: jsonHeaders });
    }

    // 3 · Render branded letterhead
    const dateStr = new Intl.DateTimeFormat("en-GB", {
      day: "numeric", month: "long", year: "numeric", timeZone: "Asia/Karachi",
    }).format(new Date());
    const html = renderEmail({ clientName, message, ref, dateStr });

    // 4 · Send via the Gmail relay (ceo@jabranandco.com)
    let ok = false, sendErr = "", sentAs = "";
    try {
      const r = await fetch(relayUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          secret: relaySecret, to, cc: cc.length ? cc.join(", ") : undefined,
          subject, htmlBody: html, replyTo, senderName,
          attachments: attachments.relay.length ? attachments.relay : undefined,
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
    if (!ok) await removeStoredAttachments(admin, attachments.paths);

    // 5 · Log (service role — bypasses RLS)
    try {
      const attachmentNote = attachments.names.length ? `\nAttachments: ${attachments.names.join(", ")}` : "";
      await admin.from("crm_email_log").insert({
        organization_id, opportunity_id, enquiry_id,
        to_email: to, cc_email: cc.length ? cc.join(", ") : null, subject,
        body_preview: (message + attachmentNote).slice(0, 500),
        status: ok ? "sent" : "failed",
        provider: "gmail-relay", provider_ref: sentAs || null,
        error: ok ? null : sendErr, sent_by: uid,
      });
    } catch (_) { /* logging must never break the response */ }

    if (!ok) {
      return new Response(JSON.stringify({ error: "Send failed: " + sendErr }), { status: 502, headers: jsonHeaders });
    }
    return new Response(JSON.stringify({
      ok: true, sent_as: sentAs || "ceo@jabranandco.com", attachments_sent: attachments.relay.length,
    }), { status: 200, headers: jsonHeaders });

  } catch (e) {
    console.error("send-client-email failure:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), { status: 500, headers: jsonHeaders });
  }
});
