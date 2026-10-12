create or replace function pos_private.create_business(p_name text,p_category text,p_accent text) returns uuid language plpgsql security definer set search_path='' as $$
declare b uuid;begin
 if auth.uid() is null then raise exception 'Login diperlukan' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,17));
 if exists(select 1 from public.pos_memberships where user_id=auth.uid() and role='owner') then raise exception 'Workspace tambahan memerlukan upgrade plan; belum tersedia';end if;
 insert into public.pos_businesses(name,category,accent) values(trim(p_name),p_category,p_accent) returning id into b;
 insert into public.pos_memberships(business_id,user_id,role,permissions) values(b,auth.uid(),'owner',array['dashboard','pos','orders','products','reports','settings','pay','cancel','staff']);
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'business.created',b);return b;
end;$$;
