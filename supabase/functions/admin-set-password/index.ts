// ============================================================================
// JABRAN & CO. CRM — EDGE FUNCTION: admin-set-password
//
// Lets the OWNER / SUPER ADMIN set any staff member's password directly from
// the CRM — no reset email involved. Same pattern as admin-invite:
//   • caller is verified with THEIR OWN session (owner/super_admin only),
//   • only then does the service-role client perform the admin update,
//   • every use is written to crm_audit_logs (who changed whose password,
//     never the password itself).
//
// DEPLOY: Edge Functions → Deploy new function → name: admin-set-password
// → paste this file → Deploy → JWT toggle **ON** (like admin-invite).
// No new secrets: SUPABASE_SERVICE_ROLE_KEY is injected automatically.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    // 1 · verify the CALLER with their own session — owner/super_admin only
    const auth = req.headers.get("Authorization") ?? "";
    const caller = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: auth } } },
    );
    const { data: allowed, error: roleErr } = await caller.rpc("crm_has_role", {
      roles: ["owner", "super_admin"],
    });
    if (roleErr || allowed !== true) {
      console.error("REJECT 403: caller is not owner/super_admin");
      return new Response(JSON.stringify({ error: "Only the Owner or Super Admin can set passwords." }), { status: 403, headers: cors });
    }
    const { data: me } = await caller.auth.getUser();
    const callerId = me?.user?.id ?? null;

    // 2 · validate input
    const body = await req.json();
    const userId = String(body?.user_id ?? "");
    const password = String(body?.password ?? "");
    if (!userId || userId.length < 30) {
      return new Response(JSON.stringify({ error: "No employee selected." }), { status: 400, headers: cors });
    }
    if (password.length < 8) {
      return new Response(JSON.stringify({ error: "Password must be at least 8 characters." }), { status: 400, headers: cors });
    }

    // 3 · perform the admin update with the service role
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { error: updErr } = await admin.auth.admin.updateUserById(userId, { password });
    if (updErr) {
      console.error("REJECT 500: admin update failed:", String(updErr.message).slice(0, 200));
      return new Response(JSON.stringify({ error: "Update failed: " + updErr.message }), { status: 500, headers: cors });
    }

    // 4 · audit — who changed whose password (never the password)
    try {
      await admin.from("crm_audit_logs").insert({
        action: "password_set_by_admin",
        entity: "auth.users",
        entity_id: userId,
        after_value: { changed_by: callerId, at: new Date().toISOString() },
      });
    } catch (_e) { /* audit is best-effort; the change itself succeeded */ }

    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: cors });
  } catch (e) {
    console.error("REJECT 500: unexpected:", String(e).slice(0, 200));
    return new Response(JSON.stringify({ error: "Unexpected error: " + String(e).slice(0, 200) }), { status: 500, headers: cors });
  }
});
