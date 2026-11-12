# Security

## Reporting

Email **ceo@jabranandco.com** with "SECURITY" in the subject. Please don't open
a public issue for anything that could expose client or staff data.

## Model in one paragraph

Every page ships the Supabase **publishable** key; that is normal and safe only
because **Row-Level Security (RLS) is the real boundary**. All 181 tables have
RLS enabled. Anything a signed-out visitor or a client-portal account must not
see has to be blocked by RLS, by `security_invoker` views, or by a
`SECURITY DEFINER` function that checks the caller. Client-side role checks in
`crm-auth.js` decide what the CRM *shows*; they are not security. Operations
needing elevated rights (inviting staff, setting passwords, sending client
email, AI calls with provider keys) run in Edge Functions that verify the
caller's role with `crm_has_role` before using the service-role key.

## Secrets

| Secret | Lives in | Never in |
|---|---|---|
| Supabase service-role key | Injected into Edge Functions by Supabase | Git, browser, docs, chat |
| Resend, Gmail relay, AI provider, OAuth client secrets, webhook secret | Supabase → Edge Functions → Secrets | Git, browser, docs, chat |
| Database password | Supabase dashboard / owner's password manager | Anywhere else |

`npm run check` fails if it finds a service-role JWT, a `sb_secret_` key, a
private key, or common provider API key formats in the repo.

If a secret leaks: rotate it at the provider first, update the Supabase
secret, redeploy the functions that read it, then clean the history.

## Account hygiene (owner checklist)

- Supabase → Authentication → enable **Leaked password protection**
  (flagged by the security advisor 2026-11-12).
- GitHub → protect `main` and `develop` (see CONTRIBUTING.md).
- Vercel and Supabase accounts: two-factor authentication on.
- Review `crm_staff_roles` when someone leaves; use `admin-set-password` /
  deactivate the profile.

Open findings and their status: [docs/AUDIT-2026-11-12.md](docs/AUDIT-2026-11-12.md).
