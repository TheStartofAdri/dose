-- caregiver_shares: stores a minimized, read-only caregiver snapshot under an unguessable token.
-- Written and read ONLY by the `caregiver-share` edge function via the service role. RLS is enabled
-- with NO policies, so anon/authenticated roles have zero access — the token (a bearer credential in
-- the share URL) is the only way in, and only through the function.

create table if not exists public.caregiver_shares (
    token       text primary key,
    payload     jsonb       not null,
    created_at  timestamptz not null default now(),
    expires_at  timestamptz not null
);

-- Sweep helper: index the expiry so a scheduled cleanup (pg_cron) can purge lapsed rows cheaply.
create index if not exists caregiver_shares_expires_at_idx on public.caregiver_shares (expires_at);

alter table public.caregiver_shares enable row level security;
-- Intentionally no policies → deny all for anon/authenticated. Service role (the edge function) bypasses RLS.

-- Optional hard-delete of expired shares, so revoked/lapsed data doesn't linger. Enable pg_cron in the
-- dashboard to activate; harmless if pg_cron isn't installed (wrapped so the migration still applies).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('purge-expired-caregiver-shares', '0 * * * *',
      $purge$ delete from public.caregiver_shares where expires_at < now() $purge$);
  end if;
end $$;
