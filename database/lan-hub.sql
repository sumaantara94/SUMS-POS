begin;
create table pos_private.lan_hubs(id uuid primary key,business_id uuid not null references public.pos_businesses(id),owner_id uuid not null references auth.users(id),name text not null,secret text not null check(secret~'^[0-9a-f]{64}$'),active boolean not null default true,created_at timestamptz not null default now());
create index pos_lan_hubs_business_idx on pos_private.lan_hubs(business_id);create index pos_lan_hubs_owner_idx on pos_private.lan_hubs(owner_id);
create table pos_private.lan_commands(business_id uuid not null references public.pos_businesses(id),request_id uuid not null,hub_id uuid not null references pos_private.lan_hubs(id),actor_id uuid not null references auth.users(id),kind text not null,document text not null,order_id uuid not null references public.pos_orders(id),received_at timestamptz not null default now(),primary key(business_id,request_id));
create index pos_lan_commands_hub_idx on pos_private.lan_commands(hub_id);create index pos_lan_commands_actor_idx on pos_private.lan_commands(actor_id);create index pos_lan_commands_order_idx on pos_private.lan_commands(order_id);
alter table pos_private.lan_hubs enable row level security;alter table pos_private.lan_commands enable row level security;
revoke all on pos_private.lan_hubs,pos_private.lan_commands from public,anon,authenticated;
create function pos_private.register_lan_hub(b uuid,p_hub uuid,p_name text) returns jsonb language plpgsql security definer set search_path='' as $$declare h pos_private.lan_hubs;begin
 perform pos_private.require_owner(b);if p_hub is null or length(trim(coalesce(p_name,''))) not between 1 and 80 then raise exception 'Hub tidak valid';end if;
 perform pg_advisory_xact_lock(hashtextextended('lanhub:'||p_hub::text,0));select * into h from pos_private.lan_hubs where id=p_hub;
 if found then if h.business_id<>b or h.owner_id<>auth.uid() or not h.active then raise exception 'Hub tidak tersedia';end if;
 else insert into pos_private.lan_hubs(id,business_id,owner_id,name,secret) values(p_hub,b,auth.uid(),trim(p_name),encode(extensions.gen_random_bytes(32),'hex')) returning * into h;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'lan.hub.registered',h.id);end if;
 return jsonb_build_object('hub_id',h.id,'secret',h.secret);
end$$;
create function pos_private.disable_lan_hub(b uuid,p_hub uuid) returns void language plpgsql security definer set search_path='' as $$begin
 perform pos_private.require_owner(b);update pos_private.lan_hubs set active=false where business_id=b and id=p_hub;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'lan.hub.disabled',p_hub);
end$$;
create function pos_private.sync_lan_command(p_document text,p_signature text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;h pos_private.lan_hubs;m public.pos_memberships;cfg public.pos_businesses;prev pos_private.lan_commands;b uuid;r uuid;a uuid;device uuid;kind text;p jsonb;created timestamptz;o uuid;bill public.pos_orders;entry jsonb;product public.pos_products;actor_shift uuid;begin
 if auth.uid() is null then raise exception 'Login diperlukan' using errcode='42501';end if;
 if p_document is null or length(p_document)>100000 or p_signature is null then raise exception 'Dokumen Hub tidak valid';end if;
 d:=p_document::jsonb;b:=(d->>'business')::uuid;r:=(d->>'id')::uuid;a:=(d->>'actor')::uuid;device:=(d->>'device')::uuid;kind:=d->>'kind';p:=d->'payload';created:=(d->>'createdAt')::timestamptz;
 perform pos_private.require_access(b,'pos');if kind='cash' then perform pos_private.require_access(b,'pay');end if;
 select * into h from pos_private.lan_hubs where id=(d->>'hub')::uuid and business_id=b and active;
 if not found or not exists(select 1 from public.pos_memberships where business_id=b and user_id=h.owner_id and role='owner' and active) then raise exception 'Hub tidak aktif' using errcode='42501';end if;
 if encode(extensions.hmac(convert_to(p_document,'UTF8'),decode(h.secret,'hex'),'sha256'),'hex')<>p_signature then raise exception 'Tanda tangan Hub tidak valid' using errcode='42501';end if;
 select * into m from public.pos_memberships where business_id=b and user_id=a and active;
 if not found or (m.role<>'owner' and not ('pos'=any(m.permissions))) or (kind='cash' and m.role<>'owner' and not ('pay'=any(m.permissions))) then raise exception 'Izin pengirim telah dicabut' using errcode='42501';end if;
 if r is null or a is null or device is null or created is null or created>now()+interval '5 minutes' or kind is null or kind not in ('order','cash') or p is null or jsonb_typeof(p)<>'object' then raise exception 'Isi transaksi Hub tidak valid';end if;
 perform pg_advisory_xact_lock(hashtextextended('lan-command:'||b::text||r::text,0));
 select * into prev from pos_private.lan_commands where business_id=b and request_id=r;
 if found then if prev.document<>p_document or prev.hub_id<>h.id then raise exception 'Request Hub berbeda dari transaksi asal';end if;o:=prev.order_id;
 else
  if kind='order' then
   if p->>'request' is distinct from r::text then raise exception 'Request ID berbeda';end if;
   perform 1 from public.pos_businesses where id=b for share;select * into cfg from public.pos_businesses where id=b;
   if m.role='waiter' and (not cfg.restaurant_mode or not cfg.waiter_enabled or p->>'type'<>'dinein' or p->>'table' is null or length(trim(coalesce(p->>'guest','')))=0) then raise exception 'Mode waiter atau meja tidak tersedia';end if;
   if (p->>'tax_bps')::integer is distinct from cfg.tax_bps or (p->>'service_bps')::integer is distinct from cfg.service_bps or (p->>'tax_on_service')::boolean is distinct from cfg.tax_on_service then raise exception 'Tax/service berubah. Periksa transaksi Hub';end if;
   if p->'lines' is null or jsonb_typeof(p->'lines')<>'array' or jsonb_array_length(p->'lines') not between 1 and 100 then raise exception 'Item Hub tidak valid';end if;
   perform 1 from public.pos_products where business_id=b and id in(select (x->>'id')::uuid from jsonb_array_elements(p->'lines') x) order by id for update;
   for entry in select value from jsonb_array_elements(p->'lines') loop
    select * into product from public.pos_products where business_id=b and id=(entry->>'id')::uuid and active and deleted_at is null;
    if not found or product.price is distinct from (entry->>'price')::bigint then raise exception 'Harga/produk berubah. Periksa transaksi Hub';end if;
   end loop;
   if exists(select 1 from public.pos_orders where business_id=b and request_id=r) then raise exception 'ID transaksi sudah dipakai di luar Hub';end if;
   o:=pos_private.place_order_v4(b,r,p->'lines',p->>'type',(p->>'table')::uuid,coalesce(p->>'guest',''),coalesce(p->>'note',''),(p->>'reservation')::timestamptz);
   select * into bill from public.pos_orders where id=o;
   if bill.total is distinct from (p->>'expected_total')::bigint then raise exception 'Total Hub berubah';end if;
   update public.pos_orders set created_by=a,created_by_name=pos_private.actor_label(a),created_role=m.role,client_created_at=created,offline_device_id=device where id=o;
   update public.pos_stock_movements set actor_id=a where business_id=b and order_id=o;
  else
   select lc.order_id into o from pos_private.lan_commands lc where lc.business_id=b and lc.hub_id=h.id and lc.request_id=(p->>'order_request')::uuid and lc.kind='order';
   if o is null then raise exception 'Pesanan Hub harus disinkron lebih dahulu';end if;
   select * into bill from public.pos_orders where business_id=b and id=o for update;
   if bill.status<>'open' or bill.total is distinct from (p->>'expected_total')::bigint then raise exception 'Bill berubah atau sudah dibayar. Periksa kas Hub';end if;
   select id into actor_shift from public.pos_shifts where business_id=b and actor_id=a and closed_at is null for update;
   perform pos_private.pay_order_v3(b,o,null,jsonb_build_array(jsonb_build_object('method','cash','amount',bill.total,'tendered',p->'tendered','reference','LAN cash '||r::text)));
   update public.pos_payments set paid_by=a,paid_by_name=pos_private.actor_label(a),shift_id=actor_shift where business_id=b and order_id=o;
  end if;
  insert into pos_private.lan_commands(business_id,request_id,hub_id,actor_id,kind,document,order_id) values(b,r,h.id,a,kind,p_document,o);
  insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,a,'lan.'||kind||'.synced',o);
 end if;
 return jsonb_build_object('order_id',o,'proof',encode(extensions.hmac(convert_to('ack:'||p_document||':'||o::text,'UTF8'),decode(h.secret,'hex'),'sha256'),'hex'));
end$$;
create function public.pos_register_lan_hub(b uuid,p_hub uuid,p_name text) returns jsonb language sql security invoker set search_path='' as $$select pos_private.register_lan_hub(b,p_hub,p_name)$$;
create function public.pos_disable_lan_hub(b uuid,p_hub uuid) returns void language sql security invoker set search_path='' as $$select pos_private.disable_lan_hub(b,p_hub)$$;
create function public.pos_sync_lan_command(p_document text,p_signature text) returns jsonb language sql security invoker set search_path='' as $$select pos_private.sync_lan_command(p_document,p_signature)$$;
revoke all on function pos_private.register_lan_hub(uuid,uuid,text),pos_private.disable_lan_hub(uuid,uuid),pos_private.sync_lan_command(text,text),public.pos_register_lan_hub(uuid,uuid,text),public.pos_disable_lan_hub(uuid,uuid),public.pos_sync_lan_command(text,text) from public,anon;
grant execute on function pos_private.register_lan_hub(uuid,uuid,text),pos_private.disable_lan_hub(uuid,uuid),pos_private.sync_lan_command(text,text),public.pos_register_lan_hub(uuid,uuid,text),public.pos_disable_lan_hub(uuid,uuid),public.pos_sync_lan_command(text,text) to authenticated;
commit;
