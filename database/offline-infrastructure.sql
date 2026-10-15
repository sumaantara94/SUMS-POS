-- Additive offline infrastructure. POS project only. Run in one transaction.
begin;
create table pos_private.device_commands (
 business_id uuid not null references public.pos_businesses(id),request_id uuid not null,
 actor_id uuid not null references auth.users(id),device_id uuid not null,kind text not null check(kind in ('order','cash')),
 payload jsonb not null,order_id uuid not null references public.pos_orders(id),client_created_at timestamptz not null,
 received_at timestamptz not null default now(),primary key(business_id,request_id)
);
alter table pos_private.device_commands enable row level security;
revoke all on pos_private.device_commands from public,anon,authenticated;
create index pos_device_commands_order_idx on pos_private.device_commands(order_id);
create index pos_device_commands_actor_idx on pos_private.device_commands(actor_id);
alter table public.pos_orders add column client_created_at timestamptz,add column offline_device_id uuid;
create function pos_private.sync_device_command(b uuid,p_request uuid,p_device uuid,p_kind text,p_payload jsonb,p_created timestamptz) returns jsonb language plpgsql security definer set search_path='' as $$
declare prev pos_private.device_commands;cfg public.pos_businesses;entry jsonb;product public.pos_products;o uuid;bill public.pos_orders;
begin
 perform pos_private.require_access(b,'pos');
 if p_kind='cash' then perform pos_private.require_access(b,'pay');end if;
 if p_request is null or p_device is null or p_kind is null or p_kind not in ('order','cash') or p_payload is null or jsonb_typeof(p_payload)<>'object' or p_created is null or p_created>now()+interval '5 minutes' then raise exception 'Invalid device command';end if;
 perform pg_advisory_xact_lock(hashtextextended('device:'||b::text||p_request::text,0));
 select * into prev from pos_private.device_commands where business_id=b and request_id=p_request;
 if found then
  if prev.actor_id<>auth.uid() or prev.device_id<>p_device or prev.kind<>p_kind or prev.payload<>p_payload or prev.client_created_at<>p_created then raise exception 'Request does not match original transaction';end if;
  return jsonb_build_object('order_id',prev.order_id,'duplicate',true);
 end if;
 if p_kind='order' then
  if p_payload->>'request' is distinct from p_request::text then raise exception 'Request ID mismatch';end if;
  -- Serialize catalog checks with stock reservation; order prices are always server-owned.
  perform 1 from public.pos_businesses where id=b for share;
  select * into cfg from public.pos_businesses where id=b;
  if (p_payload->>'tax_bps')::integer is distinct from cfg.tax_bps or (p_payload->>'service_bps')::integer is distinct from cfg.service_bps or (p_payload->>'tax_on_service')::boolean is distinct from cfg.tax_on_service then raise exception 'Tax/service changed. Owner review required';end if;
  if p_payload->'lines' is null or jsonb_typeof(p_payload->'lines')<>'array' or jsonb_array_length(p_payload->'lines') not between 1 and 100 then raise exception 'Invalid items';end if;
  -- Lock all products in stable order so concurrent devices cannot overwrite or oversell stock.
  perform 1 from public.pos_products where business_id=b and id in(select (x->>'id')::uuid from jsonb_array_elements(p_payload->'lines') x) order by id for update;
  for entry in select value from jsonb_array_elements(p_payload->'lines') loop
   select * into product from public.pos_products where business_id=b and id=(entry->>'id')::uuid and active and deleted_at is null;
   if not found or product.price is distinct from (entry->>'price')::bigint then raise exception 'Product/price changed. Owner review required';end if;
  end loop;
  -- Refuse adoption of orders created through another endpoint under a reused ID.
  if exists(select 1 from public.pos_orders where business_id=b and request_id=p_request) then raise exception 'Request ID already used outside device sync';end if;
  o:=pos_private.place_order_v4(b,p_request,p_payload->'lines',p_payload->>'type',(p_payload->>'table')::uuid,coalesce(p_payload->>'guest',''),coalesce(p_payload->>'note',''),(p_payload->>'reservation')::timestamptz);
  select * into bill from public.pos_orders where id=o;
  if bill.total is distinct from (p_payload->>'expected_total')::bigint then raise exception 'Order total changed. Owner review required';end if;
  update public.pos_orders set client_created_at=p_created,offline_device_id=p_device where id=o;
 else
  select order_id into o from pos_private.device_commands where business_id=b and request_id=(p_payload->>'order_request')::uuid and kind='order' and actor_id=auth.uid() and device_id=p_device;
  if o is null then raise exception 'Original device order must sync first';end if;
  select * into bill from public.pos_orders where business_id=b and id=o for update;
  if bill.status<>'open' or bill.total is distinct from (p_payload->>'expected_total')::bigint then raise exception 'Bill changed or already paid. Owner review required';end if;
  perform pos_private.pay_order_v3(b,o,null,jsonb_build_array(jsonb_build_object('method','cash','amount',bill.total,'tendered',p_payload->'tendered','reference','Device cash '||p_request::text)));
 end if;
 insert into pos_private.device_commands(business_id,request_id,actor_id,device_id,kind,payload,order_id,client_created_at) values(b,p_request,auth.uid(),p_device,p_kind,p_payload,o,p_created);
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'device.'||p_kind||'.synced',o);
 return jsonb_build_object('order_id',o,'duplicate',false);
end$$;
create function public.pos_sync_device_command(b uuid,p_request uuid,p_device uuid,p_kind text,p_payload jsonb,p_created timestamptz) returns jsonb language sql security invoker set search_path='' as $$select pos_private.sync_device_command(b,p_request,p_device,p_kind,p_payload,p_created)$$;
revoke all on function pos_private.sync_device_command(uuid,uuid,uuid,text,jsonb,timestamptz),public.pos_sync_device_command(uuid,uuid,uuid,text,jsonb,timestamptz) from public,anon;
grant execute on function pos_private.sync_device_command(uuid,uuid,uuid,text,jsonb,timestamptz),public.pos_sync_device_command(uuid,uuid,uuid,text,jsonb,timestamptz) to authenticated;
commit;
