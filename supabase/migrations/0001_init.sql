-- Mahjong SG Tracker: Supabase schema. Replaces Firestore + firestore.rules.
-- Run in Supabase Dashboard -> SQL Editor (or `supabase db push`).
-- Also enable: Authentication -> Providers -> "Allow anonymous sign-ins".
-- Then set the app password once:  insert into app_config(key, value) values ('access_password', 'your password');

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- app password
-- Nobody can read app_config through the API (RLS on, no policies). The phone proves the password via unlock_app().
create table app_config (key text primary key, value text not null);
alter table app_config enable row level security;

create table access (
  uid uuid primary key default auth.uid(),
  at bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table access enable row level security;
create policy access_self_read on access for select to authenticated using (uid = auth.uid());

create function has_access() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from access where uid = auth.uid()) $$;

create function unlock_app(pw text) returns boolean
language plpgsql security definer set search_path = public as
$$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if exists (select 1 from app_config where key = 'access_password' and value = pw) then
    insert into access(uid) values (auth.uid()) on conflict do nothing;
    return true;
  end if;
  return false;
end $$;

-- ---------------------------------------------------------------- players
create table players (
  id text primary key,
  name text not null check (char_length(name) between 1 and 30),
  handle text not null default '',
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  updated_at bigint not null default (extract(epoch from now()) * 1000)::bigint
);
alter table players enable row level security;
create policy players_read on players for select to authenticated using (has_access());
create policy players_insert on players for insert to authenticated with check (has_access());
create policy players_update on players for update to authenticated using (has_access()) with check (has_access());
-- no delete policy: players are never deleted

-- ---------------------------------------------------------------- rooms (games)
create table rooms (
  code text primary key,
  name text not null default '' check (char_length(name) <= 60),
  players text[] not null check (array_length(players, 1) = 4),
  player_ids text[] not null default '{"","","",""}',
  handles text[] not null default '{"","","",""}',
  settings jsonb not null default '{}'::jsonb check ((settings->>'taiCap') is null or (settings->>'taiCap')::int between 1 and 13),
  status text not null default 'active' check (status in ('lobby', 'active', 'completed', 'cancelled')),
  location text not null default '',
  notes text not null default '',
  scorekeeper text not null default '',
  starting_score int not null default 0,
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  created_by uuid not null default auth.uid(),
  host_uid uuid not null default auth.uid(),
  host_name text not null default '',
  has_pin boolean not null default false,
  started_at bigint,
  finished_at bigint,
  continues_from text
);
alter table rooms enable row level security;

create function is_host(code text) returns boolean
language sql stable security definer set search_path = public as
$$ select has_access() and exists (select 1 from rooms r where r.code = is_host.code and r.host_uid = auth.uid()) $$;

create policy rooms_read on rooms for select to authenticated using (has_access());
create policy rooms_insert on rooms for insert to authenticated with check (has_access() and host_uid = auth.uid() and created_by = auth.uid());
create policy rooms_update_host on rooms for update to authenticated using (is_host(code)) with check (is_host(code));
-- Host-only columns the host may change; host_uid moves only through give_host()/claim_host(). Games are never deleted.
revoke update on rooms from authenticated, anon;
grant update (settings, status, finished_at, location, notes, scorekeeper, host_name, started_at, has_pin) on rooms to authenticated;

-- ---------------------------------------------------------------- host PIN / hand over
create table room_secrets (room_code text primary key references rooms(code) on delete cascade, pin text not null);
alter table room_secrets enable row level security; -- no policies: unreadable through the API

create function set_host_pin(code text, pin text) returns void
language plpgsql security definer set search_path = public as
$$
#variable_conflict use_variable
begin
  if not is_host(code) then raise exception 'only the host can set the PIN'; end if;
  insert into room_secrets(room_code, pin) values (code, pin) on conflict (room_code) do update set pin = excluded.pin;
  update rooms set has_pin = true where rooms.code = set_host_pin.code;
end $$;

create function claim_host(code text, pin text, name text) returns boolean
language plpgsql security definer set search_path = public as
$$
#variable_conflict use_variable
begin
  if not has_access() then raise exception 'locked'; end if;
  if exists (select 1 from room_secrets s where s.room_code = code and s.pin = claim_host.pin) then
    update rooms set host_uid = auth.uid(), host_name = coalesce(nullif(name, ''), 'Host') where rooms.code = claim_host.code;
    return true;
  end if;
  return false;
end $$;

create function give_host(code text, new_uid uuid, name text) returns void
language plpgsql security definer set search_path = public as
$$
#variable_conflict use_variable
begin
  if not is_host(code) then raise exception 'only the host can hand over'; end if;
  update rooms set host_uid = new_uid, host_name = coalesce(nullif(name, ''), 'Host') where rooms.code = give_host.code;
end $$;

-- ---------------------------------------------------------------- events (append-only ledger)
create table events (
  id text primary key default gen_random_uuid()::text,
  room_code text not null references rooms(code) on delete restrict,
  type text not null check (type in ('win', 'instant', 'draw', 'adjust', 'kong', 'bonus')),
  -- server-side ZERO-SUM: exactly 4 integers summing to 0
  deltas int[] not null check (array_length(deltas, 1) = 4 and deltas[1] + deltas[2] + deltas[3] + deltas[4] = 0),
  voided boolean not null default false,
  void_reason text,
  voided_at bigint,
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  by uuid default auth.uid(),
  data jsonb not null default '{}'::jsonb
);
create index events_room_idx on events (room_code, created_at);
alter table events enable row level security;
create policy events_read on events for select to authenticated using (has_access());
create policy events_insert_host on events for insert to authenticated with check (is_host(room_code));
create policy events_void_host on events for update to authenticated using (is_host(room_code)) with check (is_host(room_code));
revoke update on events from authenticated, anon;
grant update (voided, void_reason, voided_at) on events to authenticated; -- only void / restore; never delete

-- ---------------------------------------------------------------- members + player requests ("I won!", payouts)
create table members (
  room_code text not null references rooms(code) on delete cascade,
  uid uuid not null default auth.uid(),
  seat int check (seat between 0 and 3),
  name text,
  at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  primary key (room_code, uid)
);
alter table members enable row level security;
create policy members_read on members for select to authenticated using (has_access());
create policy members_write on members for all to authenticated using (has_access() and uid = auth.uid()) with check (has_access() and uid = auth.uid());

create table requests (
  id text primary key default gen_random_uuid()::text,
  room_code text not null references rooms(code) on delete cascade,
  type text not null check (type in ('win', 'instant')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  by_uid uuid not null default auth.uid(),
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  decided_at bigint,
  data jsonb not null default '{}'::jsonb
);
alter table requests enable row level security;
create policy requests_read on requests for select to authenticated using (has_access());
create policy requests_insert on requests for insert to authenticated with check (has_access() and by_uid = auth.uid() and status = 'pending');
create policy requests_decide on requests for update to authenticated
  using (is_host(room_code) or (has_access() and by_uid = auth.uid()))
  with check (is_host(room_code) or (by_uid = auth.uid() and status = 'cancelled'));

-- ---------------------------------------------------------------- house rules + extra rule sets
create table house_rules (
  id text primary key default 'house' check (id = 'house'),
  rules jsonb not null default '{}'::jsonb check ((rules->>'taiCap') is null or (rules->>'taiCap')::int between 1 and 13),
  last_change jsonb,
  updated_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  by uuid default auth.uid()
);
alter table house_rules enable row level security;
create policy house_read on house_rules for select to authenticated using (has_access());
create policy house_write on house_rules for all to authenticated using (has_access()) with check (has_access());

create table rule_sets (
  id text primary key default gen_random_uuid()::text,
  name text not null check (char_length(name) between 1 and 30),
  rules jsonb not null check ((rules->>'taiCap')::int between 1 and 13),
  last_change jsonb,
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  updated_at bigint not null default (extract(epoch from now()) * 1000)::bigint,
  by uuid default auth.uid()
);
alter table rule_sets enable row level security;
create policy rule_sets_all on rule_sets for all to authenticated using (has_access()) with check (has_access());

-- ---------------------------------------------------------------- realtime
alter publication supabase_realtime add table rooms, events, members, requests, house_rules, rule_sets, players;
