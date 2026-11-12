// ============================================================================
// JABRAN & CO. CRM — Supabase Edge Function: admin-invite
// Lets Owner / Super Admin / CEO invite employees from the CRM UI.
// The service-role key exists ONLY as an Edge Function secret — never in the
// browser, never in the repository.
//
// DEPLOY (Supabase Dashboard):
//   1. Edge Functions → Deploy new function → name: admin-invite → paste → Deploy.
//   2. Secrets (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY are
//      injected automatically by Supabase). Add one more:
//        SITE_URL = https://www.jabranandco.com
//   3. No webhook needed — the Employees page calls this function directly
//      with the caller's own login token; the function verifies governance
//      rights in the database before doing anything.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const site = Deno.env.get("SITE_URL") ?? "https://www.jabranandco.com";

    // 1 · Identify the caller from their own JWT and verify governance rights
    //     against the database (role-based, never email-based).
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: allowed, error: roleErr } = await caller.rpc("crm_has_role", {
      roles: ["owner", "super_admin", "ceo"],
    });
    if (roleErr || allowed !== true) {
      return new Response(JSON.stringify({ error: "Not authorized" }),
        { status: 403, headers: { ...cors, "Content-Type": "application/json" } });
    }

    // 2 · Validate input
    const body = await req.json();
    const email = String(body?.email ?? "").trim().toLowerCase();
    const fullName = String(body?.full_name ?? "").trim();
    const department = String(body?.department ?? "").trim() || null;
    const designation = String(body?.designation ?? "").trim() || null;
    const roles: string[] = Array.isArray(body?.roles) ? body.roles : [];
    const validRoles = new Set([
      "super_admin","ceo","finance_manager","trade_sourcing_manager",
      "customs_manager","consultancy_manager","operations_manager",
      "business_development","account_manager","project_manager",
      "document_controller","read_only_auditor",
    ]); // Owner is deliberately NOT invitable via API.
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return new Response(JSON.stringify({ error: "Invalid email" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    }
    const cleanRoles = roles.filter((r) => validRoles.has(r));

    // 3 · Create + invite via the admin API (invite email sent by Supabase)
    const admin = createClient(url, service);
    const { data: invited, error: invErr } = await admin.auth.admin.inviteUserByEmail(
      email, { redirectTo: `${site}/crm.html` });
    if (invErr) {
      return new Response(JSON.stringify({ error: invErr.message }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    }
    const uid = invited.user.id;

    // 4 · Profile + roles
    await admin.from("crm_employee_profiles").upsert({
      user_id: uid, full_name: fullName || null, department, designation, is_active: true,
    });
    if (cleanRoles.length) {
      await admin.from("crm_staff_roles").upsert(
        cleanRoles.map((r) => ({ user_id: uid, role: r })),
        { onConflict: "user_id,role" });
    }

    return new Response(JSON.stringify({ user_id: uid, email }),
      { status: 200, headers: { ...cors, "Content-Type": "application/json" } });
  } catch (e) {
    console.error("admin-invite failure:", e);
    return new Response(JSON.stringify({ error: "Internal error" }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});
