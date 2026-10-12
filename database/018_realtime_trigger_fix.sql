create or replace function pos_private.emit_workspace_change() returns trigger language plpgsql security definer set search_path='' as $$declare b uuid;begin
 if tg_table_name='pos_businesses' then b:=new.id;else b:=new.business_id;end if;
 insert into public.pos_realtime_events(business_id,transaction_key) values(b,pg_current_xact_id()::text) on conflict(business_id,transaction_key) do nothing;
 -- One compact signal per business/transaction, bounded history per workspace.
 delete from public.pos_realtime_events where business_id=b and id<(select id from public.pos_realtime_events where business_id=b order by id desc offset 199 limit 1);
 return new;
end$$;
