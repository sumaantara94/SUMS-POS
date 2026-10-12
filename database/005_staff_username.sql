create table public.pos_staff_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 business_id uuid not null references public.pos_businesses(id),
 created_by uuid not null references auth.users(id),
 name text not null check(length(trim(name)) between 1 and 80),
 username text not null unique check(username ~ '^[a-z0-9_.-]{3,32}$'),
 created_at timestamptz not null default now()
);
create index pos_staff_business_idx on public.pos_staff_accounts(business_id);
create index pos_staff_creator_idx on public.pos_staff_accounts(created_by);
alter table public.pos_staff_accounts enable row level security;
revoke all on public.pos_staff_accounts from anon,authenticated;
grant select on public.pos_staff_accounts to authenticated;
grant all on public.pos_staff_accounts to service_role;
create policy staff_account_read on public.pos_staff_accounts for select to authenticated using(user_id=(select auth.uid()) or pos_private.allowed(business_id,'staff'));
create table pos_private.login_attempts (key text not null,bucket bigint not null,attempts integer not null,primary key(key,bucket));
revoke all on pos_private.login_attempts from public,anon,authenticated;
grant usage on schema pos_private to service_role;
grant all on pos_private.login_attempts to service_role;
create function public.pos_login_attempt(p_key text,p_limit integer) returns boolean language plpgsql security invoker set search_path='' as $$
declare n integer;b bigint:=floor(extract(epoch from now())/900);begin
 delete from pos_private.login_attempts where bucket<b-4;
 insert into pos_private.login_attempts(key,bucket,attempts) values(p_key,b,1) on conflict(key,bucket) do update set attempts=pos_private.login_attempts.attempts+1 returning attempts into n;
 return n<=p_limit;end;$$;
revoke all on function public.pos_login_attempt(text,integer) from public,anon,authenticated;grant execute on function public.pos_login_attempt(text,integer) to service_role;
