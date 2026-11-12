// ============================================================================
// JABRAN & CO. CRM — EDGE FUNCTION: analytics-oauth
// The OAuth layer the audit found missing (16 of 18 components). One function,
// three actions, deployed once:
//     action: 'start'      -> mint one-use state + PKCE, return the authorize URL
//     action: 'exchange'   -> validate state, swap code for tokens, encrypt, store
//     action: 'disconnect' -> revoke at the provider, wipe the vault row
//
// SECURITY
//   · JWT ON. The caller is verified with THEIR OWN session; only
//     analytics.connect_sources / analytics.admin may start or disconnect.
//   · Client secrets live ONLY in Edge Function secrets. They never reach a
//     browser and are never returned by any action.
//   · State: 256-bit random, single use, 10-minute expiry, bound to the user
//     AND the provider. A replayed or foreign state is rejected.
//   · PKCE S256 for Google and LinkedIn.
//   · Refresh tokens are AES-256-GCM encrypted with TOKEN_ENC_KEY before they
//     touch the database, and the vault table has RLS on with zero policies.
//   · connected_by, scopes and timestamps are recorded; every action is audited.
//
// DEPLOY: Edge Functions -> Deploy new function -> name: analytics-oauth
//   -> paste this file -> Deploy -> JWT verification ON.
//
// SECRETS REQUIRED (Edge Functions -> Secrets). Add only the ones you use:
//   TOKEN_ENC_KEY                 32-byte key, base64  (see note below)
//   GOOGLE_OAUTH_CLIENT_ID        xxxxx.apps.googleusercontent.com
//   GOOGLE_OAUTH_CLIENT_SECRET    GOCSPX-...
//   META_APP_ID / META_APP_SECRET
//   LINKEDIN_CLIENT_ID / LINKEDIN_CLIENT_SECRET
// Generate TOKEN_ENC_KEY on your device, never in chat:
//   in any browser console:  btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

// The redirect URI is the CALLBACK FUNCTION, not a web page. The browser is
// no longer part of the exchange, which removes every silent-hang failure
// mode (CDN blocked, session missing in that tab, page JS throwing).
const CANONICAL_REDIRECT = "https://dvsaqjvcxqlzgpbvexnu.supabase.co/functions/v1/analytics-oauth-callback";

type Provider = "ga4" | "search_console" | "google_ads" | "meta_business" | "meta_ads" | "linkedin_page" | "linkedin_ads";

const FAMILY: Record<Provider, "google" | "meta" | "linkedin"> = {
  ga4: "google", search_console: "google", google_ads: "google",
  meta_business: "meta", meta_ads: "meta",
  linkedin_page: "linkedin", linkedin_ads: "linkedin",
};

const SCOPES: Record<Provider, string> = {
  ga4: "https://www.googleapis.com/auth/analytics.readonly",
  search_console: "https://www.googleapis.com/auth/webmasters.readonly",
  google_ads: "https://www.googleapis.com/auth/adwords",
  meta_business: "pages_read_engagement,read_insights,pages_show_list,business_management",
  meta_ads: "ads_read,business_management",
  linkedin_page: "r_organization_social,rw_organization_admin",
  linkedin_ads: "r_ads,r_ads_reporting",
};

const AUTHORIZE: Record<string, string> = {
  google: "https://accounts.google.com/o/oauth2/v2/auth",
  meta: "https://www.facebook.com/v21.0/dialog/oauth",
  linkedin: "https://www.linkedin.com/oauth/v2/authorization",
};
const TOKEN_URL: Record<string, string> = {
  google: "https://oauth2.googleapis.com/token",
  meta: "https://graph.facebook.com/v21.0/oauth/access_token",
  linkedin: "https://www.linkedin.com/oauth/v2/accessToken",
};

function b64url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function rand(n: number) { return crypto.getRandomValues(new Uint8Array(n)); }

async function sha256b64url(input: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return b64url(new Uint8Array(d));
}

async function encKey() {
  const raw = Deno.env.get("TOKEN_ENC_KEY");
  if (!raw) throw new Error("TOKEN_ENC_KEY secret is not configured.");
  const bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
  if (bytes.length !== 32) throw new Error("TOKEN_ENC_KEY must be exactly 32 bytes, base64-encoded.");
  return await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}
async function decrypt(ciphertextB64: string, ivB64: string) {
  const key = await encKey();
  const iv = Uint8Array.from(atob(ivB64), (c) => c.charCodeAt(0));
  const ct = Uint8Array.from(atob(ciphertextB64), (c) => c.charCodeAt(0));
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct);
  return new TextDecoder().decode(plain);
}
async function encrypt(plain: string) {
  const key = await encKey();
  const iv = rand(12);
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plain));
  return { ciphertext: btoa(String.fromCharCode(...new Uint8Array(ct))), iv: btoa(String.fromCharCode(...iv)) };
}

function creds(family: string) {
  if (family === "google") return { id: Deno.env.get("GOOGLE_OAUTH_CLIENT_ID"), secret: Deno.env.get("GOOGLE_OAUTH_CLIENT_SECRET") };
  if (family === "meta") return { id: Deno.env.get("META_APP_ID"), secret: Deno.env.get("META_APP_SECRET") };
  return { id: Deno.env.get("LINKEDIN_CLIENT_ID"), secret: Deno.env.get("LINKEDIN_CLIENT_SECRET") };
}

Deno.serve(async (req: Request) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  async function audit(action: string, provider: string, uid: string | null, detail: unknown) {
    try {
      await admin.from("crm_audit_logs").insert({
        action, entity: "analytics_connections", entity_id: provider,
        after_value: { by: uid, at: new Date().toISOString(), detail },
      });
    } catch (_e) { /* audit is best-effort */ }
  }

  try {
    // ---- caller identity + permission (their own session, never elevated) ----
    const auth = req.headers.get("Authorization") ?? "";
    const user = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: auth } },
    });
    const { data: me } = await user.auth.getUser();
    const uid = me?.user?.id ?? null;
    if (!uid) {
      return new Response(JSON.stringify({ error: "Sign in first." }), { status: 401, headers: cors });
    }
    const { data: perms } = await user.rpc("analytics_my_permissions");
    const allowed = Array.isArray(perms) &&
      (perms.includes("analytics.connect_sources") || perms.includes("analytics.manage_connections") || perms.includes("analytics.admin"));
    if (!allowed) {
      console.error("REJECT 403: caller lacks analytics.connect_sources");
      return new Response(JSON.stringify({ error: "You need analytics.connect_sources to manage data sources." }),
        { status: 403, headers: cors });
    }

    const body = await req.json();
    const action = String(body?.action ?? "");
    let provider = String(body?.provider ?? "") as Provider;

    // EXCHANGE derives the provider from the STATE ROW, never from the browser.
    // The callback page runs in whatever tab the provider chose to open, so any
    // browser-held hint (sessionStorage) may legitimately be missing. The state
    // is the authoritative record of what was started, by whom, for which source.
    if (action === "exchange") {
      const st0 = String(body?.state ?? "");
      if (!st0) return new Response(JSON.stringify({ error: "Missing state." }), { status: 400, headers: cors });
      const { data: peek } = await admin.from("analytics_oauth_states")
        .select("provider").eq("state", st0).maybeSingle();
      if (!peek) {
        return new Response(JSON.stringify({ error: "This authorisation link is unknown, expired or already used. Start again from Data Sources." }),
          { status: 400, headers: cors });
      }
      provider = peek.provider as Provider;
    }

    if (!FAMILY[provider]) {
      return new Response(JSON.stringify({ error: "Unknown provider: " + provider }), { status: 400, headers: cors });
    }
    const family = FAMILY[provider];
    const { id: clientId, secret: clientSecret } = creds(family);

    // ================================ START ================================
    if (action === "start") {
      if (!clientId || !clientSecret) {
        return new Response(JSON.stringify({
          error: "Credentials for " + family + " are not configured yet. Add them in Edge Function Secrets first.",
        }), { status: 400, headers: cors });
      }
      const state = b64url(rand(32));
      let codeVerifier: string | null = null;
      const params = new URLSearchParams();
      params.set("client_id", clientId);
      params.set("redirect_uri", CANONICAL_REDIRECT);
      params.set("state", state);
      params.set("response_type", "code");
      params.set("scope", SCOPES[provider]);

      if (family === "google") {
        codeVerifier = b64url(rand(64));
        params.set("code_challenge", await sha256b64url(codeVerifier));
        params.set("code_challenge_method", "S256");
        params.set("access_type", "offline");       // required for a refresh token
        params.set("prompt", "consent");            // force a refresh token every time
        params.set("include_granted_scopes", "true");
      } else if (family === "linkedin") {
        codeVerifier = b64url(rand(64));
        params.set("code_challenge", await sha256b64url(codeVerifier));
        params.set("code_challenge_method", "S256");
      }

      const { error } = await admin.from("analytics_oauth_states").insert({
        state, provider, user_id: uid, code_verifier: codeVerifier, redirect_uri: CANONICAL_REDIRECT,
      });
      if (error) throw new Error("Could not store state: " + error.message);

      await admin.from("analytics_connections")
        .update({ status: "connection_pending", last_error: null }).eq("platform", provider);
      await audit("oauth_start", provider, uid, { family });

      return new Response(JSON.stringify({ authorize_url: AUTHORIZE[family] + "?" + params.toString() }),
        { status: 200, headers: cors });
    }

    // ============================== EXCHANGE ==============================
    if (action === "exchange") {
      const code = String(body?.code ?? "");
      const state = String(body?.state ?? "");
      if (!code || !state) return new Response(JSON.stringify({ error: "Missing code or state." }), { status: 400, headers: cors });

      // one-use state: consume atomically, bound to this user and provider
      const { data: rows, error: stErr } = await admin.from("analytics_oauth_states")
        .update({ used_at: new Date().toISOString() })
        .eq("state", state).is("used_at", null).gt("expires_at", new Date().toISOString())
        .select("*");
      const st = rows && rows[0];
      if (stErr || !st) {
        console.error("REJECT 400: state invalid/expired/replayed");
        await audit("oauth_state_rejected", provider, uid, { reason: "invalid, expired or already used" });
        return new Response(JSON.stringify({ error: "This authorisation link is invalid, expired or already used. Start again." }),
          { status: 400, headers: cors });
      }
      if (st.user_id !== uid || st.provider !== provider) {
        console.error("REJECT 403: state does not belong to this caller/provider");
        await audit("oauth_state_rejected", provider, uid, { reason: "state bound to a different user or provider" });
        return new Response(JSON.stringify({ error: "This authorisation does not belong to your session." }),
          { status: 403, headers: cors });
      }

      const form = new URLSearchParams();
      form.set("client_id", clientId!);
      form.set("client_secret", clientSecret!);
      form.set("code", code);
      form.set("redirect_uri", st.redirect_uri);
      form.set("grant_type", "authorization_code");
      if (st.code_verifier) form.set("code_verifier", st.code_verifier);

      const tr = await fetch(TOKEN_URL[family], {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
      const tj = await tr.json().catch(() => ({}));
      if (!tr.ok || (!tj.refresh_token && !tj.access_token)) {
        const msg = String(tj?.error_description || tj?.error?.message || tj?.error || "token exchange failed");
        console.error("REJECT 502: token exchange:", msg.slice(0, 200));
        await admin.from("analytics_connections")
          .update({ status: "sync_failed", last_error: msg.slice(0, 300) }).eq("platform", provider);
        await audit("oauth_exchange_failed", provider, uid, { message: msg.slice(0, 300) });
        return new Response(JSON.stringify({ error: "Provider rejected the exchange: " + msg.slice(0, 200) }),
          { status: 502, headers: cors });
      }

      // Meta returns only a short-lived token here: upgrade to long-lived.
      let longLived = tj.access_token as string;
      if (family === "meta") {
        const ex = new URLSearchParams({
          grant_type: "fb_exchange_token", client_id: clientId!, client_secret: clientSecret!,
          fb_exchange_token: tj.access_token,
        });
        const lr = await fetch("https://graph.facebook.com/v21.0/oauth/access_token?" + ex.toString());
        const lj = await lr.json().catch(() => ({}));
        if (lr.ok && lj.access_token) longLived = lj.access_token;
      }

      // Store the long-term credential encrypted: Google/LinkedIn refresh token,
      // Meta long-lived access token (Meta issues no refresh token).
      const secretToStore = tj.refresh_token || longLived;
      const { ciphertext, iv } = await encrypt(secretToStore);
      const expiresIn = Number(tj.expires_in || 0);
      const accessExpires = expiresIn ? new Date(Date.now() + expiresIn * 1000).toISOString() : null;
      const grantedScopes = String(tj.scope || SCOPES[provider]).split(/[ ,]+/).filter(Boolean);

      const { error: vErr } = await admin.from("analytics_oauth_tokens").upsert({
        provider, ciphertext, iv, scopes: grantedScopes, access_expires: accessExpires,
        connected_by: uid, connected_at: new Date().toISOString(), rotated_at: new Date().toISOString(),
      }, { onConflict: "provider" });
      if (vErr) throw new Error("Vault write failed: " + vErr.message);

      await admin.from("analytics_connections").update({
        status: "connected",
        connected_by: uid,
        connected_at: new Date().toISOString(),
        scopes: grantedScopes,
        token_status: tj.refresh_token ? "refresh_token_stored" : "long_lived_token_stored",
        last_error: null,
      }).eq("platform", provider);

      await audit("oauth_connected", provider, uid, { scopes: grantedScopes, refresh_token: !!tj.refresh_token });
      return new Response(JSON.stringify({ ok: true, provider, scopes: grantedScopes }), { status: 200, headers: cors });
    }

    // ============================= DISCONNECT =============================
    if (action === "disconnect") {
      // TRUE revocation: kill the grant AT THE PROVIDER first, then wipe our copy.
      // (Earlier builds only deleted locally, which left the grant alive in the
      //  user's Google/LinkedIn account. Fixed.)
      let revoked = "not_attempted";
      try {
        const { data: v } = await admin.from("analytics_oauth_tokens")
          .select("ciphertext, iv").eq("provider", provider).maybeSingle();
        if (v) {
          const token = await decrypt(v.ciphertext, v.iv);
          if (family === "google") {
            const r = await fetch("https://oauth2.googleapis.com/revoke", {
              method: "POST",
              headers: { "content-type": "application/x-www-form-urlencoded" },
              body: new URLSearchParams({ token }).toString(),
            });
            revoked = r.ok ? "revoked_at_google" : "google_returned_" + r.status;
          } else if (family === "linkedin") {
            const r = await fetch("https://www.linkedin.com/oauth/v2/revoke", {
              method: "POST",
              headers: { "content-type": "application/x-www-form-urlencoded" },
              body: new URLSearchParams({
                client_id: clientId ?? "", client_secret: clientSecret ?? "", token,
              }).toString(),
            });
            revoked = r.ok ? "revoked_at_linkedin" : "linkedin_returned_" + r.status;
          } else {
            // Meta issues no revocable refresh token; the grant is removed from
            // Business settings or the user's Apps and Websites page.
            revoked = "meta_requires_manual_removal";
          }
        } else {
          revoked = "no_stored_token";
        }
      } catch (e) {
        revoked = "revoke_failed: " + String(e).slice(0, 120);
      }

      await admin.from("analytics_oauth_tokens").delete().eq("provider", provider);
      await admin.from("analytics_connections").update({
        status: "not_connected", token_status: null, connected_by: null,
        connected_at: null, scopes: [], last_error: null,
      }).eq("platform", provider);
      await audit("oauth_disconnected", provider, uid, { revocation: revoked });
      return new Response(JSON.stringify({ ok: true, provider, revocation: revoked }),
        { status: 200, headers: cors });
    }

    return new Response(JSON.stringify({ error: "Unknown action." }), { status: 400, headers: cors });
  } catch (e) {
    console.error("REJECT 500:", String(e).slice(0, 300));
    return new Response(JSON.stringify({ error: "Unexpected error: " + String(e).slice(0, 200) }),
      { status: 500, headers: cors });
  }
});
