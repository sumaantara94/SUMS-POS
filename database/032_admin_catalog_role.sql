-- Add a narrowly scoped Back Office Admin role without granting sales visibility.
-- Existing Owner/Cashier/Waiter memberships and permissions remain unchanged.
alter table public.pos_memberships drop constraint if exists pos_memberships_role_check;
alter table public.pos_memberships add constraint pos_memberships_role_check
 check(role in ('owner','admin','cashier','waiter','custom'));

create or replace function public.pos_finalize_staff(p_owner uuid,b uuid,p_user uuid,p_name text,p_username text,p_role text)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.pos_memberships where business_id=b and user_id=p_owner and role='owner' and active) then
  raise exception 'Hanya owner dapat membuat staf' using errcode='42501';
 end if;
 if p_role not in ('admin','cashier','waiter') then raise exception 'Peran tidak valid';end if;
 insert into public.pos_staff_accounts(user_id,business_id,created_by,name,username)
 values(p_user,b,p_owner,trim(p_name),p_username);
 insert into public.pos_memberships(business_id,user_id,role,permissions)
 values(b,p_user,p_role,case
  when p_role='cashier' then array['pos','orders','pay']
  when p_role='waiter' then array['pos','orders']
  else array['products']
 end);
 insert into public.pos_audit_events(business_id,actor_id,action,record_id)
 values(b,p_owner,'staff.created',p_user);
end;$$;
revoke all on function public.pos_finalize_staff(uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.pos_finalize_staff(uuid,uuid,uuid,text,text,text) to service_role;
