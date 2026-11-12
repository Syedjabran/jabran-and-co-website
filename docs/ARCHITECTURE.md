# Architecture

Last verified against production: **2026-11-12** (Vercel deployment
`dpl_AQNnYekryRCKmKS374ELKwNAkHC3` = commit `655ff86`; Supabase
`dvsaqjvcxqlzgpbvexnu`).

## 1 · The big picture

```
                    ┌──────────────────────────── Vercel (static) ─────────────────────────────┐
 visitor / client → │ public pages   index, services, insights, contact, careers, legal …     │
 staff            → │ CRM            crm.html + 25 crm-*.html modules                         │
                    │ client portal  my-account.html, *-view.html documents                   │
                    │ shared JS      supabase-client.js · crm-auth.js · crm-*.js · chat-widget │
                    └──────────────┬───────────────────────────────────────┬──────────────────┘
                                   │ supabase-js 2.119.0 (publishable key) │ fetch / functions.invoke
                                   ▼                                       ▼
          ┌────────────────────── Supabase dvsaqjvcxqlzgpbvexnu ───────────────────────────────┐
          │ Auth (email+password, invites)                                                     │
          │ Postgres 17: 181 tables (all RLS) · 78 views · 153 functions (139 SECURITY DEFINER)│
          │              134 triggers · 347 RLS policies                                       │
          │ Storage: crm-private, finance-docs (both private)                                  │
          │ Edge Functions (12) ─────────────┬─────────────┬─────────────┬───────────────────  │
          │ DB webhook crm_enquiries INSERT ─┘             │             │                     │
          └──────────────────────────────────────────────── │ ─────────── │ ──────────────────  ┘
                     Resend (CEO alert)   Gmail relay (Apps Script)   Gemini / Anthropic   Google / Meta / LinkedIn APIs
```

There is no application server. Browsers talk to Supabase directly; **RLS
and database functions enforce every permission**. Edge Functions exist only
for work that needs a secret (service-role key, provider API keys).

## 2 · Front end

- **Pages** are hand-written HTML at the repo root. Page logic is inline
  `<script>`; shared logic is in root `*.js` files loaded with `<script src>`
  in a fixed order:

  ```html
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.119.0"></script>
  <script src="supabase-client.js"></script>   <!-- creates global `sb`, `jco` -->
  <script src="crm-auth.js"></script>          <!-- CRM only -->
  <script src="crm-activity.js"></script>      <!-- CRM only: activity/print log -->
  <script src="crm-forms.js"></script> …       <!-- module helpers as needed -->
  ```

- **Public pages** load `animations.js` (UI motion + injects `chat-widget.js`),
  Google Tag Manager / GA4 (`G-7S5MKLLT8B`), Meta Pixel and LinkedIn Insight.
  `utm-capture.js` keeps campaign parameters for the enquiry form.
- **Styling** is `style.css` plus page-level `<style>` blocks.
- **Third-party libraries** come from CDNs with exact versions
  (supabase-js 2.119.0, Chart.js 4.4.1, qrcodejs 1.0.0).

### Shared scripts

| File | Role |
|---|---|
| `supabase-client.js` | Creates `sb`. §1 session-context cache: one `crm_session_context()` RPC per session (5-min TTL in `sessionStorage`) → `jco.context()`, `jco.isStaff()`, `jco.hasRole()`, `jco.can()`. §2 **login gateway**: wraps `sb.auth.signInWithPassword` so only a real, validated tap/click/Enter on the Login button can sign in (blocks password-manager auto-submit). §3 `?authdebug=1` overlay. §4 traceability watermark on CRM/portal/document pages. |
| `crm-auth.js` | CRM login screen, page guard (staff only; client accounts are ejected), sidebar/nav, account menu, sign-out (local and global). |
| `crm-nav.js`, `crm-links.js` | Navigation helpers and cross-module record links. |
| `crm-forms.js`, `crm-select.js`, `crm-extras.js`, `crm-intl.js` | Form building, searchable selects, shared CRM widgets, countries/currencies/phone formats. |
| `crm-activity.js`, `crm-tracking.js`, `crm-alerts.js`, `crm-rm.js`, `crm-ai-kpis.js` | Activity + print logging, order tracking, alerts, relationship-manager tools, AI KPI tiles. |
| `portal-documents.js`, `portal-tracking.js` | Client-portal documents and order tracking. |
| `chat-widget.js` | Public website chat → `advisory-agent`. |
| `client-ai-agent.js` | Client-portal assistant → `ai-client-agent` (**not loaded by any page today**). |

## 3 · Authentication and authorisation

1. **Sign-in:** email + password through Supabase Auth, only via the gesture
   gateway in `supabase-client.js`. Staff are invited by `admin-invite`
   (Supabase invite email → `crm.html`). Password reset: `reset-password.html`.
   The owner/super admin can set a password directly with
   `admin-set-password`.
2. **Who is staff:** `crm_staff_roles(user_id, role)`. Roles: `owner`,
   `super_admin`, `ceo`, `finance_manager`, `trade_sourcing_manager`,
   `customs_manager`, `consultancy_manager`, `operations_manager`,
   `business_development`, `account_manager`, `project_manager`,
   `document_controller`, `read_only_auditor`. Profiles in
   `crm_employee_profiles`.
3. **Who is a client:** `crm_portal_members` links an auth user to a
   `crm_organizations` row. Clients see their own organisation's data through
   RLS and the `crm_client_*` / `crm_my_*` views.
4. **Checks in the database:** `crm_has_role(roles[])`, `crm_is_staff()`,
   `analytics_can(permission)` / `analytics_my_permissions()` (permission
   matrix `analytics_role_permissions`), `pharma_my_permissions()`
   (`pharma_role_permissions`). RLS policies and SECURITY DEFINER RPCs call
   these.
5. **Session context:** `crm_session_context()` returns roles, staff flag,
   analytics permissions and email in one call; the browser caches it. The
   cache only decides what to *show*; RLS decides what is *returned*.

## 4 · Data flows

**Website enquiry → CRM → CEO email**
`contact.html` inserts into `crm_enquiries` (anon insert allowed by RLS) →
triggers assign the number, owner and activity → Database Webhook
`enquiry-email` calls `notify-enquiry` with `x-webhook-secret` → Resend emails
`NOTIFY_EMAIL`.

**Sales pipeline** `crm_enquiries` → `crm_opportunities` → `crm_quotations`
(+ items, approvals, versions) → `crm_orders` (+ items, milestones, tracking,
shipments, customs) → `crm_invoices` (+ items) → `crm_payments` +
`crm_payment_allocations` → `crm_receipts`. Totals are recalculated by
triggers (`crm_quotation_recalc`, `crm_invoice_recalc`,
`crm_apply_allocation_totals`). Document numbers come from `crm_counters`.

**Costing & finance** cost sheets, cost lines/centres/categories, employee
costs, timesheets, fixed expenses, subscriptions, budgets → reporting views
(`crm_pl_actual_monthly`, `crm_order_ebitda`, `crm_cashflow_monthly`,
`crm_receivables_ageing` …).

**Client email** `crm-email.html` → `send-client-email` (role-checked) →
renders the letterhead → Google Apps Script relay sends from
ceo@jabranandco.com → logged in `crm_email_log`. Attachments come from the
browser or the private `crm-private` bucket.

**Documents** `invoice-view`, `quotation-view`, `receipt-view`,
`report-view`, `certificate-view` render a record for print/PDF; printing is
logged by `crm-activity.js`.

**AI analytics** `crm-analytics.html` → `analytics-agent` (plans the question
→ allowlisted analytics RPCs as the caller → narrates). Connectors:
`analytics-oauth` / `analytics-oauth-callback` (encrypted tokens in
`analytics_oauth_tokens`), `analytics-sync` (GA4, Search Console → daily
metric tables), triggered from the CRM or by a VPS timer with
`x-cron-secret`.

## 5 · Database domains

| Prefix | Tables | Views | What |
|---|---|---|---|
| `crm_` | 82 | 56 | Sales pipeline, orders, finance, costing, HR costs, settings, audit, attachments |
| `pharma_` | 48 | 17 | Pharma distribution master (products, doctors, pharmacies, distributors, stock, tenders, toll manufacturing, campaigns) |
| `analytics_` | 17 | 5 | AI analytics: connections, OAuth, sync jobs, metrics, prompts, permissions |
| `ai_` | 8 | – | Website/portal AI agents: configs, prompt versions, conversations, messages, handoffs, usage |
| `social_` | 8 | – | Social media planner (brand voice, calendar, posts, engagement) |
| `training_`, `client_`, misc | 19 | – | Training academy, early client-portal tables, blog/case studies, profiles |

Details and the change process: [DATABASE.md](DATABASE.md).

## 6 · Edge functions

| Function | `verify_jwt` | Called by | Who may call | Secrets it reads (besides the injected Supabase ones) | External |
|---|---|---|---|---|---|
| `notify-enquiry` | off | DB webhook on `crm_enquiries` INSERT | holder of `WEBHOOK_SECRET` | `RESEND_API_KEY`, `NOTIFY_EMAIL`, `FROM_EMAIL`, `SITE_URL`, `WEBHOOK_SECRET` | Resend |
| `admin-invite` | on | `crm-employees.html` | owner, super_admin, ceo | `SITE_URL` | Supabase Auth invite |
| `admin-set-password` | on | `crm-employees.html` | owner, super_admin | – | – |
| `send-client-email` | on | `crm-email.html` | owner, super_admin, ceo, BD, account/consultancy/operations/project managers | `GMAIL_RELAY_URL`, `GMAIL_RELAY_SECRET`, `REPLY_TO`, `SENDER_NAME` | Apps Script Gmail relay |
| `advisory-agent` | off | `chat-widget.js` (all public pages) | browsers on the allowed origins; rate-limited per hashed IP (`ai_public_rate_events`); saves leads to `crm_enquiries` | `ANTHROPIC_API_KEY` (Claude, preferred) or `GEMINI_API_KEY` (fallback); optional `ANTHROPIC_MODEL`, `ANTHROPIC_EFFORT`, `AI_PROVIDER`; optional `RATE_LIMIT_SALT`, `RL_PER_10MIN`, `RL_PER_DAY`, `RL_GLOBAL_PER_DAY` | Claude `claude-haiku-5-5` (default) or Gemini `gemini-3.1-flash-lite`, via `_shared/llm.ts` |
| `ai-agent` | off | **no page** — switched off via `ai_agent_configs.is_enabled` (returns 503) | anyone | `AI_API_KEY`, `AI_PROVIDER`, `AI_MODEL_PUBLIC`, `AI_MAX_TOKENS`, `ALLOWED_ORIGIN` | Anthropic |
| `ai-client-agent` | on | `client-ai-agent.js` (**not loaded by any page**) — switched off via `ai_agent_configs.is_enabled` | signed-in portal users | `AI_API_KEY`, `AI_MODEL_CLIENT`, `AI_MODEL_PUBLIC`, `AI_MAX_TOKENS`, `ALLOWED_ORIGIN` | Anthropic |
| `ai-accountant` | on | `crm-ai-accountant.html` | staff (`crm_is_staff`) | `ANTHROPIC_API_KEY` (Claude, preferred) or `GEMINI_API_KEY` (fallback); optional `ANTHROPIC_MODEL`, `ANTHROPIC_EFFORT`, `AI_PROVIDER` | Claude or Gemini, via `_shared/llm.ts` |
| `analytics-agent` | on | `crm-analytics.html` | `analytics.query` permission | `ANTHROPIC_API_KEY` (Claude, preferred) or `GEMINI_API_KEY` (fallback); optional `ANTHROPIC_MODEL`, `ANTHROPIC_EFFORT`, `AI_PROVIDER` | Claude or Gemini (planner + narrator), via `_shared/llm.ts` |
| `analytics-oauth` | on | `crm-analytics.html`, `analytics-oauth.html` | `connect_sources` / `manage_connections` / admin | `TOKEN_ENC_KEY`, `GOOGLE_OAUTH_CLIENT_ID/SECRET`, `META_APP_ID/SECRET`, `LINKEDIN_CLIENT_ID/SECRET` | Google, Meta, LinkedIn OAuth |
| `analytics-oauth-callback` | off | OAuth provider redirect | holder of a valid single-use state | same as `analytics-oauth` | as above |
| `analytics-sync` | on | `crm-analytics.html`, VPS timer | analytics permission or `x-cron-secret` | `TOKEN_ENC_KEY`, `GOOGLE_OAUTH_CLIENT_ID/SECRET`, `GA4_PROPERTY_ID`, `SEARCH_CONSOLE_SITE_URL`, `CRON_SECRET` | GA4 Data API, Search Console API |

Pattern used by every role-gated function: build a client with the caller's
`Authorization` header → `rpc('crm_has_role' | 'crm_is_staff' | 'analytics_my_permissions')`
→ only then create the service-role client. Keep it that way.

## 7 · Hosting configuration

- `vercel.json` sets HSTS, `X-Content-Type-Options`, `Referrer-Policy`,
  `X-Frame-Options: SAMEORIGIN`, a restrictive `Permissions-Policy`, font
  preconnects, `no-cache` revalidation for HTML/JS/CSS, 7-day caching for
  media, and `noindex` for internal snippet pages.
- `.vercelignore` keeps `supabase/`, `docs/`, `scripts/`, `.github/` and the
  repo Markdown off the public site.
- Domains: `www.jabranandco.com`, `jabranandco.com`, plus Vercel aliases.
  Previews are behind Vercel SSO.

## 8 · Known gaps (tracked in the audit)

No staging database; no schema baseline in git yet; no automated browser
tests; two AI functions deployed but switched off. See [AUDIT-2026-11-12.md](AUDIT-2026-11-12.md).
