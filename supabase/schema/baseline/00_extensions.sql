-- Baseline 00: extensions (non-default) as installed on production.
-- Captured from pg_extension. plpgsql (pg_catalog) is built in and omitted.
-- Versions on production: pg_net 0.20.4, uuid-ossp 1.1, pgcrypto 1.3,
-- pg_stat_statements 1.11, supabase_vault 0.3.1.

create schema if not exists extensions;

create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists "pg_stat_statements" with schema extensions;
create extension if not exists "pg_net" with schema extensions;
create extension if not exists "supabase_vault" with schema vault;
