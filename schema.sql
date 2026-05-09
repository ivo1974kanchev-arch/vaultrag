-- =============================================================
-- vaultrag — Supabase Schema
-- Scope: SaaS license server only.
-- On-device tables (documents, chunks, vector_indexes,
-- chat_sessions, messages, license) live in SQLite on the device.
-- =============================================================

-- ---------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------
-- ENUM types
-- ---------------------------------------------------------------
create type license_tier as enum ('early_bird', 'team');
create type license_status as enum ('active', 'revoked', 'expired');

-- ---------------------------------------------------------------
-- waitlist
-- ---------------------------------------------------------------
create table if not exists waitlist (
  id              uuid primary key default gen_random_uuid(),
  email           text not null unique,
  name            text,
  referral_source text,
  created_at      timestamptz not null default now()
);

alter table waitlist enable row level security;

-- Allow anonymous inserts (sign-up form); no reads via anon key
create policy "Anyone can join waitlist"
  on waitlist for insert
  with check (true);

create policy "Service role reads waitlist"
  on waitlist for select
  using (auth.role() = 'service_role');

-- ---------------------------------------------------------------
-- license_keys
-- Managed server-side; app validates locally after first check.
-- ---------------------------------------------------------------
create table if not exists license_keys (
  id                  uuid primary key default gen_random_uuid(),
  license_key         text not null unique,              -- HMAC-signed token
  tier                license_tier not null default 'early_bird',
  status              license_status not null default 'active',
  seat_count          smallint not null default 1,       -- 1 = Early Bird, ≤10 = Team
  seats_used          smallint not null default 0,
  purchaser_email     text not null,
  google_order_id     text unique,                       -- Play Billing order reference
  play_purchase_token text,                              -- raw receipt token
  activated_at        timestamptz,
  expires_at          timestamptz,                       -- null = lifetime
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint seat_count_positive check (seat_count >= 1),
  constraint seats_not_exceeded  check (seats_used <= seat_count),
  constraint team_seat_cap       check (tier <> 'team' or seat_count <= 10)
);

alter table license_keys enable row level security;

-- Only the service role (Hono worker with service key) can read/write
create policy "Service role full access to license_keys"
  on license_keys for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- ---------------------------------------------------------------
-- license_activations
-- One row per device seat activation.
-- ---------------------------------------------------------------
create table if not exists license_activations (
  id              uuid primary key default gen_random_uuid(),
  license_key_id  uuid not null references license_keys(id) on delete cascade,
  device_fingerprint text not null,                     -- hashed Android device ID
  activated_at    timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  revoked         boolean not null default false,

  unique (license_key_id, device_fingerprint)
);

alter table license_activations enable row level security;

create policy "Service role full access to license_activations"
  on license_activations for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- ---------------------------------------------------------------
-- pricing_tiers  (read-only product catalogue; anon-readable)
-- ---------------------------------------------------------------
create table if not exists pricing_tiers (
  id          serial primary key,
  name        text not null unique,
  slug        text not null unique,
  price_usd   numeric(10,2) not null,
  period      text not null default 'one-time',
  features    jsonb not null default '[]',
  active      boolean not null default true,
  sort_order  smallint not null default 0,
  created_at  timestamptz not null default now()
);

alter table pricing_tiers enable row level security;

create policy "Anyone can read active pricing tiers"
  on pricing_tiers for select
  using (active = true);

create policy "Service role manages pricing tiers"
  on pricing_tiers for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- Seed pricing tiers
insert into pricing_tiers (name, slug, price_usd, period, features, sort_order)
values
  (
    'Early Bird',
    'early-bird',
    29.00,
    'one-time',
    '["Unlimited PDF imports","Offline Q&A with Gemma 4","Source-cited answers","Lifetime updates for v1.x","Priority email support"]'::jsonb,
    1
  ),
  (
    'Team License',
    'team-license',
    199.00,
    'one-time',
    '["Everything in Early Bird","Up to 10 seats (APK sideload or managed Play distribution)","Volume license key management","Dedicated onboarding call","Invoice/PO payment accepted"]'::jsonb,
    2
  )
on conflict (slug) do nothing;

-- ---------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_license_keys_updated_at
  before update on license_keys
  for each row execute procedure set_updated_at();

-- ---------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------
create index if not exists idx_license_keys_key        on license_keys(license_key);
create index if not exists idx_license_keys_email      on license_keys(purchaser_email);
create index if not exists idx_license_keys_order      on license_keys(google_order_id);
create index if not exists idx_activations_license     on license_activations(license_key_id);
create index if not exists idx_activations_fingerprint on license_activations(device_fingerprint);
create index if not exists idx_waitlist_email          on waitlist(email);