create table public.pos_realtime_events(id bigint generated always as identity primary key,business_id uuid not null references public.pos_businesses(id),transaction_key text not null,created_at timestamptz not null default now(),unique(business_id,transaction_key));
create index pos_realtime_business_id_idx on public.pos_realtime_events(business_id,id desc);
alter table public.pos_realtime_events enable row level security;
revoke all on public.pos_realtime_events from public,anon,authenticated;
grant select on public.pos_realtime_events to authenticated;
create policy event_tenant_read on public.pos_realtime_events for select to authenticated using(exists(select 1 from public.pos_memberships m where m.business_id=pos_realtime_events.business_id and m.user_id=(select auth.uid()) and m.active));
create function pos_private.emit_workspace_change() returns trigger language plpgsql security definer set search_path='' as $$declare b uuid;begin
 if tg_table_name='pos_businesses' then b:=new.id;else b:=new.business_id;end if;
 insert into public.pos_realtime_events(business_id,transaction_key) values(b,pg_current_xact_id()::text) on conflict(business_id,transaction_key) do nothing;
 -- One compact signal per business/transaction, bounded history per workspace.
 delete from public.pos_realtime_events where business_id=b and id<(select id from public.pos_realtime_events where business_id=b order by id desc offset 199 limit 1);
 return new;
end$$;
revoke all on function pos_private.emit_workspace_change() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['pos_businesses','pos_products','pos_orders','pos_order_lines','pos_payments','pos_tables','pos_areas','pos_categories','pos_discounts','pos_memberships','pos_print_jobs'] loop
 execute format('create trigger pos_workspace_change after insert or update on public.%I for each row execute function pos_private.emit_workspace_change()',t);
 end loop;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pos_realtime_events') then alter publication supabase_realtime add table public.pos_realtime_events;end if;
end$$;
