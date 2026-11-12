// ============================================================================
// JABRAN & CO. CRM — EDGE FUNCTION: analytics-sync
// The connector that actually FETCHES data. Connecting a source only stores a
// credential; this is what turns it into rows you can query.
//
//   action: 'sync', provider: 'ga4' | 'search_console', days: 90
//
// FLOW
//   1. verify the caller's own session + analytics permission
//   2. read the ENCRYPTED refresh token from the vault (service role only)
//   3. decrypt with TOKEN_ENC_KEY, swap it for a short-lived access token
//   4. call the provider's read-only reporting API
//   5. normalise into analytics_daily_metrics / analytics_content_metrics
//   6. record the sync job, freshness and any error — honestly
//
// The refresh token never leaves this function. The access token is held in
// memory for the length of one request and never stored.
//
// DEPLOY: Edge Functions -> Deploy new function -> name: analytics-sync
//   -> paste this file -> Deploy -> JWT verification ON.
//
// SECRETS: TOKEN_ENC_KEY, GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET,
//          GA4_PROPERTY_ID=544199512
//          SEARCH_CONSOLE_SITE_URL=sc-domain:jabranandco.com   (only if used)
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
function iso(d) {
  return d.toISOString().slice(0, 10);
}
function ga4date(s) {
  return s.slice(0, 4) + "-" + s.slice(4, 6) + "-" + s.slice(6, 8);
}
async function decrypt(ciphertextB64, ivB64) {
  const raw = Deno.env.get("TOKEN_ENC_KEY");
  if (!raw) throw new Error("TOKEN_ENC_KEY is not configured.");
  const keyBytes = Uint8Array.from(atob(raw), (c)=>c.charCodeAt(0));
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, [
    "decrypt"
  ]);
  const iv = Uint8Array.from(atob(ivB64), (c)=>c.charCodeAt(0));
  const ct = Uint8Array.from(atob(ciphertextB64), (c)=>c.charCodeAt(0));
  const plain = await crypto.subtle.decrypt({
    name: "AES-GCM",
    iv
  }, key, ct);
  return new TextDecoder().decode(plain);
}
async function googleAccessToken(refreshToken) {
  const form = new URLSearchParams({
    client_id: Deno.env.get("GOOGLE_OAUTH_CLIENT_ID") ?? "",
    client_secret: Deno.env.get("GOOGLE_OAUTH_CLIENT_SECRET") ?? "",
    refresh_token: refreshToken,
    grant_type: "refresh_token"
  });
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded"
    },
    body: form.toString()
  });
  const j = await r.json().catch(()=>({}));
  if (!r.ok || !j.access_token) {
    throw new Error("Google refused the refresh token: " + String(j.error_description || j.error || r.status) + ". If this says invalid_grant, the app is in Testing mode and the 7-day token has expired — reconnect the source.");
  }
  return j.access_token;
}
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
  const admin = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  let jobId = null;
  let provider = "";
  async function fail(msg, status = 400) {
    console.error("REJECT " + status + ": " + msg.slice(0, 200));
    if (jobId) {
      await admin.from("analytics_sync_jobs").update({
        status: "failed",
        finished_at: new Date().toISOString(),
        error: msg.slice(0, 400)
      }).eq("id", jobId);
    }
    if (provider) {
      await admin.from("analytics_connections").update({
        status: "sync_failed",
        last_error: msg.slice(0, 300)
      }).eq("platform", provider);
      await admin.from("analytics_data_quality_events").insert({
        source: provider,
        event: "sync_failed",
        detail: msg.slice(0, 300)
      });
    }
    return new Response(JSON.stringify({
      error: msg
    }), {
      status,
      headers: cors
    });
  }
  try {
    // ---- 1 · caller ----
    const auth = req.headers.get("Authorization") ?? "";
    const user = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_ANON_KEY"), {
      global: {
        headers: {
          Authorization: auth
        }
      }
    });
    // v2 2026-08-06: scheduled-sync lane. A caller presenting the CRON_SECRET
    // header may sync without analytics permissions (used by the VPS timer).
    const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
    const cronHdr = req.headers.get("x-cron-secret") ?? "";
    const cronMode = cronSecret.length > 0 && cronHdr === cronSecret;
    if (!cronMode) {
      const { data: me } = await user.auth.getUser();
      const uid = me?.user?.id ?? null;
      if (!uid) return new Response(JSON.stringify({
        error: "Sign in first."
      }), {
        status: 401,
        headers: cors
      });
      const { data: perms } = await user.rpc("analytics_my_permissions");
      const ok = Array.isArray(perms) && (perms.includes("analytics.manage_connections") || perms.includes("analytics.connect_sources") || perms.includes("analytics.admin"));
      if (!ok) return new Response(JSON.stringify({
        error: "You need analytics.manage_connections to sync a source."
      }), {
        status: 403,
        headers: cors
      });
    }
    const body = await req.json();
    provider = String(body?.provider ?? "");
    const days = Math.min(Math.max(Number(body?.days ?? 90), 1), 365);
    if (![
      "ga4",
      "search_console"
    ].includes(provider)) {
      return await fail("Only ga4 and search_console have a connector implemented so far. " + "Google Ads, Meta and LinkedIn connectors are not built yet — they are still blocked on platform approval.", 400);
    }
    // ---- 2 · vault ----
    const { data: vault } = await admin.from("analytics_oauth_tokens").select("ciphertext, iv").eq("provider", provider).maybeSingle();
    if (!vault) return await fail("That source is not connected. Connect it in Data Sources first.", 400);
    // ---- start job ----
    const { data: conn } = await admin.from("analytics_connections").select("id").eq("platform", provider).maybeSingle();
    const { data: job } = await admin.from("analytics_sync_jobs").insert({
      connection_id: conn?.id,
      status: "running"
    }).select("id").single();
    jobId = job?.id ?? null;
    await admin.from("analytics_connections").update({
      status: "syncing",
      last_error: null
    }).eq("platform", provider);
    // ---- 3 · access token ----
    const refresh = await decrypt(vault.ciphertext, vault.iv);
    const accessToken = await googleAccessToken(refresh);
    await admin.from("analytics_oauth_tokens").update({
      rotated_at: new Date().toISOString()
    }).eq("provider", provider);
    const to = new Date();
    const from = new Date();
    from.setDate(from.getDate() - (days - 1));
    let rowsWritten = 0;
    // ======================== GA4 ========================
    if (provider === "ga4") {
      const propertyId = Deno.env.get("GA4_PROPERTY_ID");
      if (!propertyId) return await fail("GA4_PROPERTY_ID secret is not set. Add it in Edge Function Secrets (value: 544199512).", 400);
      // GA4 renamed "conversions" to "keyEvents". Try the modern name, then the
      // legacy one, then drop it — rather than guess which your property accepts.
      const metricSets = [
        [
          "totalUsers",
          "sessions",
          "engagedSessions",
          "keyEvents"
        ],
        [
          "totalUsers",
          "sessions",
          "engagedSessions",
          "conversions"
        ],
        [
          "totalUsers",
          "sessions",
          "engagedSessions"
        ]
      ];
      let report = null;
      let used = [];
      let lastErr = "";
      for (const metrics of metricSets){
        const r = await fetch("https://analyticsdata.googleapis.com/v1beta/properties/" + propertyId + ":runReport", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: "Bearer " + accessToken
          },
          body: JSON.stringify({
            dateRanges: [
              {
                startDate: iso(from),
                endDate: iso(to)
              }
            ],
            dimensions: [
              {
                name: "date"
              },
              {
                name: "sessionDefaultChannelGroup"
              }
            ],
            metrics: metrics.map((m)=>({
                name: m
              })),
            limit: 10000
          })
        });
        const j = await r.json().catch(()=>({}));
        if (r.ok) {
          report = j;
          used = metrics;
          break;
        }
        lastErr = String(j?.error?.message || r.status);
        if (r.status === 401 || r.status === 403) {
          return await fail("Google rejected the request (" + r.status + "): " + lastErr + ". Usually the GA4 property ID is wrong, or the connected account has no access to property " + propertyId + ".", 403);
        }
      }
      if (!report) return await fail("GA4 report failed: " + lastErr, 502);
      // Idempotent: clear this window for this source, then insert fresh.
      await admin.from("analytics_daily_metrics").delete().eq("source", "ga4").gte("metric_date", iso(from)).lte("metric_date", iso(to));
      const rows = (report.rows || []).map((row)=>{
        const d = row.dimensionValues?.[0]?.value ?? "";
        const channel = row.dimensionValues?.[1]?.value ?? "(other)";
        const m = row.metricValues || [];
        const rec = {
          source: "ga4",
          metric_date: ga4date(d),
          dimension: {
            channel
          },
          users: Number(m[0]?.value ?? 0),
          sessions: Number(m[1]?.value ?? 0),
          engaged_sessions: Number(m[2]?.value ?? 0)
        };
        if (used.length === 4) rec.conversions = Number(m[3]?.value ?? 0);
        return rec;
      }).filter((r)=>/^\d{4}-\d{2}-\d{2}$/.test(String(r.metric_date)));
      for(let i = 0; i < rows.length; i += 500){
        const { error } = await admin.from("analytics_daily_metrics").insert(rows.slice(i, i + 500));
        if (error) return await fail("Could not store GA4 rows: " + error.message, 500);
      }
      rowsWritten = rows.length;
      if (used.length === 3) {
        await admin.from("analytics_data_quality_events").insert({
          source: "ga4",
          event: "metric_unavailable",
          detail: "Your property accepted neither keyEvents nor conversions; users/sessions/engagedSessions were stored, conversions were not — they are recorded as unavailable rather than estimated."
        });
      }
    }
    // =================== SEARCH CONSOLE ===================
    if (provider === "search_console") {
      const site = Deno.env.get("SEARCH_CONSOLE_SITE_URL");
      if (!site) return await fail("SEARCH_CONSOLE_SITE_URL secret is not set (value: sc-domain:jabranandco.com).", 400);
      const r = await fetch("https://searchconsole.googleapis.com/webmasters/v3/sites/" + encodeURIComponent(site) + "/searchAnalytics/query", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: "Bearer " + accessToken
        },
        body: JSON.stringify({
          startDate: iso(from),
          endDate: iso(to),
          dimensions: [
            "date",
            "query"
          ],
          rowLimit: 5000,
          type: "web"
        })
      });
      const j = await r.json().catch(()=>({}));
      if (!r.ok) {
        return await fail("Search Console rejected the request (" + r.status + "): " + String(j?.error?.message || r.status) + ". Usually the property is not verified, or SEARCH_CONSOLE_SITE_URL does not match the property exactly.", 502);
      }
      await admin.from("analytics_content_metrics").delete().eq("source", "search_console").gte("metric_date", iso(from)).lte("metric_date", iso(to));
      const rows = (j.rows || []).map((row)=>({
          source: "search_console",
          metric_date: row.keys?.[0],
          search_query: row.keys?.[1] ?? null,
          clicks: Number(row.clicks ?? 0),
          impressions: Number(row.impressions ?? 0),
          ctr: Number(row.ctr ?? 0),
          avg_position: Number(row.position ?? 0)
        })).filter((r)=>/^\d{4}-\d{2}-\d{2}$/.test(String(r.metric_date)));
      for(let i = 0; i < rows.length; i += 500){
        const { error } = await admin.from("analytics_content_metrics").insert(rows.slice(i, i + 500));
        if (error) return await fail("Could not store Search Console rows: " + error.message, 500);
      }
      rowsWritten = rows.length;
    }
    // ---- 6 · finish ----
    const now = new Date().toISOString();
    if (jobId) {
      await admin.from("analytics_sync_jobs").update({
        status: "success",
        finished_at: now,
        rows_ingested: rowsWritten
      }).eq("id", jobId);
    }
    await admin.from("analytics_connections").update({
      status: "connected",
      last_sync_at: now,
      next_sync_at: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      last_error: null
    }).eq("platform", provider);
    return new Response(JSON.stringify({
      ok: true,
      provider,
      rows: rowsWritten,
      period: {
        from: iso(from),
        to: iso(to)
      }
    }), {
      status: 200,
      headers: cors
    });
  } catch (e) {
    return await fail(String(e && e.message ? e.message : e), 500);
  }
});
