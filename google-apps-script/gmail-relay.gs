/**
 * ============================================================================
 * JABRAN & CO — Gmail Relay (Google Apps Script)
 * Lets the CRM send email THROUGH your real ceo@jabranandco.com mailbox.
 * Every message appears in your Gmail "Sent", and replies land in your inbox.
 *
 * ONE-TIME SETUP (do this signed in as ceo@jabranandco.com):
 *   1. Go to  script.google.com  →  New project.
 *   2. Delete the sample, paste THIS whole file.
 *   3. Put a long random secret in RELAY_SECRET below (letters+numbers, ~40 chars).
 *      Use the SAME value later as the CRM's GMAIL_RELAY_SECRET.
 *   4. Click  Deploy → New deployment → (gear) Web app.
 *        • Description: JCO Gmail Relay
 *        • Execute as:  Me (ceo@jabranandco.com)
 *        • Who has access:  Anyone
 *      → Deploy → Authorize access → allow Gmail permission → copy the
 *      "Web app URL" (ends in /exec). That URL = your GMAIL_RELAY_URL.
 *
 * SECURITY: the URL is useless without the secret, and the secret lives only
 * inside the CRM's server-side Edge Function — never in a browser.
 * ============================================================================
 */

// >>> CHANGE THIS to a long random string, then use the same value as GMAIL_RELAY_SECRET in the CRM <<<
const RELAY_SECRET = 'CHANGE_ME_TO_A_LONG_RANDOM_SECRET';
const MAX_ATTACHMENTS = 5;
const MAX_BASE64_CHARS = 25 * 1024 * 1024;
const ATTACHMENT_MIME = {
  pdf: 'application/pdf', doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ppt: 'application/vnd.ms-powerpoint',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp',
  csv: 'text/csv', txt: 'text/plain', zip: 'application/zip'
};

function _attachmentName(value) {
  var name = String(value || 'attachment')
    .replace(/[^A-Za-z0-9._()\- ]+/g, '_')
    .replace(/\s+/g, '_');
  return name.slice(-120) || 'attachment';
}

function _attachmentType(name) {
  var match = String(name || '').toLowerCase().match(/\.([a-z0-9]+)$/);
  return match ? ATTACHMENT_MIME[match[1]] : null;
}

function doPost(e) {
  try {
    var body = {};
    try { body = JSON.parse((e && e.postData && e.postData.contents) || '{}'); } catch (_) {}

    if (!RELAY_SECRET || RELAY_SECRET === 'CHANGE_ME_TO_A_LONG_RANDOM_SECRET') {
      return _json({ ok: false, error: 'relay not configured (set RELAY_SECRET)' });
    }
    if (body.secret !== RELAY_SECRET) {
      return _json({ ok: false, error: 'unauthorized' });
    }

    var to = String(body.to || '').trim();
    var subject = String(body.subject || '(no subject)');
    var html = String(body.htmlBody || '');
    if (!to) return _json({ ok: false, error: 'missing recipient' });
    if (!html) return _json({ ok: false, error: 'missing body' });

    var options = {
      htmlBody: html,
      name: String(body.senderName || 'Syed Jabran Ali Kamran — Jabran & Co')
    };
    if (body.cc)      options.cc = String(body.cc);
    if (body.bcc)     options.bcc = String(body.bcc);
    if (body.replyTo) options.replyTo = String(body.replyTo);

    var rawAttachments = Array.isArray(body.attachments) ? body.attachments : [];
    if (rawAttachments.length > MAX_ATTACHMENTS) {
      return _json({ ok: false, error: 'too many attachments' });
    }
    var blobs = [], encodedTotal = 0;
    for (var i = 0; i < rawAttachments.length; i++) {
      var item = rawAttachments[i] || {};
      var name = _attachmentName(item.name);
      var contentType = _attachmentType(name);
      var encoded = String(item.dataBase64 || '');
      if (!contentType) return _json({ ok: false, error: 'attachment type not allowed: ' + name });
      if (!encoded) return _json({ ok: false, error: 'attachment content missing: ' + name });
      encodedTotal += encoded.length;
      if (encodedTotal > MAX_BASE64_CHARS) return _json({ ok: false, error: 'attachments exceed message limit' });
      blobs.push(Utilities.newBlob(Utilities.base64Decode(encoded), contentType, name));
    }
    if (blobs.length) options.attachments = blobs;

    // Plain-text fallback derived from the HTML (for clients that block HTML).
    var plain = html.replace(/<style[\s\S]*?<\/style>/gi, ' ')
                    .replace(/<[^>]+>/g, ' ')
                    .replace(/&nbsp;/g, ' ')
                    .replace(/\s+/g, ' ')
                    .trim();

    GmailApp.sendEmail(to, subject, plain, options);   // sends AS ceo@jabranandco.com
    return _json({ ok: true, sentAs: Session.getActiveUser().getEmail() });

  } catch (err) {
    return _json({ ok: false, error: String(err) });
  }
}

// Simple health check when the URL is opened in a browser.
function doGet() {
  return _json({ ok: true, service: 'jco-gmail-relay' });
}

function _json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
