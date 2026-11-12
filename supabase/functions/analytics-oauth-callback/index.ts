// ============================================================================
// JABRAN & CO. CRM — EDGE FUNCTION: analytics-oauth-callback
// BUILD 2026-07-16.5 — the provider redirects HERE, not to a web page.
//
// WHY THIS EXISTS
//   The first design sent Google back to analytics-oauth.html, which then had
//   to (a) load the Supabase CDN, (b) still hold your session in that exact
//   tab, and (c) call another function. Any one of those failing left a
//   spinner and no error. That was my mistake: the browser was never needed.
//   The state row already records WHO started the flow (user_id) and FOR WHICH
//   source (provider), so the server can finish the job alone.
//
// FLOW
//   Google/Meta/LinkedIn  ->  this function (?code&state)
//     1. consume the state atomically: must exist, be unused, be unexpired
//     2. read provider + user_id FROM that row (never from the browser)
//     3. exchange the code for tokens using the secret, server-side
//     4. AES-256-GCM encrypt and store; mark the connection connected
//     5. 302 the browser back to crm-analytics.html?connected=ga4
//   No JS, no session, no CDN, no tab affinity. It cannot hang.
//
// DEPLOY: Edge Functions -> Deploy new function
//         name: analytics-oauth-callback
//         *** JWT VERIFICATION MUST BE **OFF** ***
//   Google calls this URL directly and carries no Supabase token. Safety comes
//   from the state: 256 bits of randomness, single use, 10-minute expiry, bound
//   in our database to one user and one provider. Without a valid unused state
//   this function does nothing at all.
//
// REDIRECT URI TO REGISTER WITH THE PROVIDERS (replace the old one):
//   https://dvsaqjvcxqlzgpbvexnu.supabase.co/functions/v1/analytics-oauth-callback
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const APP_RETURN = "https://jabranandco.com/crm-analytics.html";
const CALLBACK_URL = "https://dvsaqjvcxqlzgpbvexnu.supabase.co/functions/v1/analytics-oauth-callback";

const FAMILY: Record<string, "google" | "meta" | "linkedin"> = {
  ga4: "google", search_console: "google", google_ads: "google",
  meta_business: "meta", meta_ads: "meta",
  linkedin_page: "linkedin", linkedin_ads: "linkedin",
};
const TOKEN_URL: Record<string, string> = {
  google: "https://oauth2.googleapis.com/token",
  meta: "https://graph.facebook.com/v21.0/oauth/access_token",
  linkedin: "https://www.linkedin.com/oauth/v2/accessToken",
};

function creds(family: string) {
  if (family === "google") return { id: Deno.env.get("GOOGLE_OAUTH_CLIENT_ID"), secret: Deno.env.get("GOOGLE_OAUTH_CLIENT_SECRET") };
  if (family === "meta") return { id: Deno.env.get("META_APP_ID"), secret: Deno.env.get("META_APP_SECRET") };
  return { id: Deno.env.get("LINKEDIN_CLIENT_ID"), secret: Deno.env.get("LINKEDIN_CLIENT_SECRET") };
}

async function encrypt(plain: string) {
  const raw = Deno.env.get("TOKEN_ENC_KEY");
  if (!raw) throw new Error("TOKEN_ENC_KEY secret is not configured");
  const bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
  if (bytes.length !== 32) throw new Error("TOKEN_ENC_KEY must be 32 bytes, base64");
  const key = await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plain));
  return { ciphertext: btoa(String.fromCharCode(...new Uint8Array(ct))), iv: btoa(String.fromCharCode(...iv)) };
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  function back(qs: string) {
    return new Response(null, { status: 302, headers: { Location: APP_RETURN + qs } });
  }
  function fail(reason: string, provider?: string) {
    console.error("OAUTH CALLBACK FAILED: " + reason.slice(0, 300));
    return back("?oauth_error=" + encodeURIComponent(reason.slice(0, 220)) + (provider ? "&provider=" + provider : ""));
  }

  let provider = "";
  try {
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const perr = url.searchParams.get("error_description") || url.searchParams.get("error");

    if (perr) return fail("The provider refused or you cancelled: " + perr);
    if (!code || !state) return fail("The provider returned no authorisation code. Start again from Data Sources.");

    // ---- 1 · consume the state: exists, unused, unexpired. Atomic. ----
    const { data: rows, error: stErr } = await admin.from("analytics_oauth_states")
      .update({ used_at: new Date().toISOString() })
      .eq("state", state)
      .is("used_at", null)
      .gt("expires_at", new Date().toISOString())
      .select("*");
    const st = rows && rows[0];
    if (stErr || !st) {
      return fail("This authorisation link is invalid, expired or was already used. Start again from Data Sources.");
    }

    // ---- 2 · identity comes from the STATE ROW, never the browser ----
    provider = String(st.provider);
    const uid = String(st.user_id);
    const family = FAMILY[provider];
    if (!family) return fail("Unknown provider on the state record: " + provider);

    const { id: clientId, secret: clientSecret } = creds(family);
    if (!clientId || !clientSecret) {
      return fail("Credentials for " + family + " are not configured in Edge Function Secrets.", provider);
    }

    // ---- 3 · exchange, server-side ----
    const form = new URLSearchParams();
    form.set("client_id", clientId);
    form.set("client_secret", clientSecret);
    form.set("code", code);
    form.set("redirect_uri", CALLBACK_URL);
    form.set("grant_type", "authorization_code");
    if (st.code_verifier) form.set("code_verifier", st.code_verifier);

    const tr = await fetch(TOKEN_URL[family], {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
    const tj = await tr.json().catch(() => ({}));
    if (!tr.ok || (!tj.refresh_token && !tj.access_token)) {
      const msg = String(tj?.error_description || tj?.error?.message || tj?.error || ("HTTP " + tr.status));
      await admin.from("analytics_connections")
        .update({ status: "sync_failed", last_error: msg.slice(0, 300) }).eq("platform", provider);
      return fail("The provider rejected the exchange: " + msg, provider);
    }

    // Meta issues a short-lived token here; upgrade it to long-lived.
    let metaLong = tj.access_token as string;
    if (family === "meta") {
      const ex = new URLSearchParams({
        grant_type: "fb_exchange_token", client_id: clientId,
        client_secret: clientSecret, fb_exchange_token: tj.access_token,
      });
      const lr = await fetch("https://graph.facebook.com/v21.0/oauth/access_token?" + ex.toString());
      const lj = await lr.json().catch(() => ({}));
      if (lr.ok && lj.access_token) metaLong = lj.access_token;
    }

    // ---- 4 · encrypt + store ----
    const longTerm = tj.refresh_token || metaLong;
    const { ciphertext, iv } = await encrypt(longTerm);
    const scopes = String(tj.scope || "").split(/[ ,]+/).filter(Boolean);
    const accessExpires = tj.expires_in ? new Date(Date.now() + Number(tj.expires_in) * 1000).toISOString() : null;

    const { error: vErr } = await admin.from("analytics_oauth_tokens").upsert({
      provider, ciphertext, iv, scopes, access_expires: accessExpires,
      connected_by: uid, connected_at: new Date().toISOString(), rotated_at: new Date().toISOString(),
    }, { onConflict: "provider" });
    if (vErr) return fail("Could not store the credential: " + vErr.message, provider);

    await admin.from("analytics_connections").update({
      status: "connected",
      connected_by: uid,
      connected_at: new Date().toISOString(),
      scopes,
      token_status: tj.refresh_token ? "refresh_token_stored" : "long_lived_token_stored",
      last_error: null,
    }).eq("platform", provider);

    try {
      await admin.from("crm_audit_logs").insert({
        action: "oauth_connected", entity: "analytics_connections", entity_id: provider,
        after_value: { by: uid, at: new Date().toISOString(), scopes, refresh_token: !!tj.refresh_token },
      });
    } catch (_e) { /* audit is best-effort */ }

    // ---- 5 · hand the browser back to the CRM ----
    return back("?connected=" + encodeURIComponent(provider));
  } catch (e) {
    return fail("Unexpected error: " + String(e && (e as Error).message ? (e as Error).message : e), provider);
  }
});
