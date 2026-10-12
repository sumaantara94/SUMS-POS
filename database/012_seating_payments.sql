alter table public.pos_tables add column reservation_guest text,add column reserved_at timestamptz,add column reserved_for timestamptz,add column reserved_by uuid references auth.users(id);
alter table public.pos_businesses add column tax_bps integer not null default 0 check(tax_bps between 0 and 10000),add column service_bps integer not null default 0 check(service_bps between 0 and 10000),add column tax_on_service boolean not null default true;
alter table public.pos_orders add column tax_bps integer not null default 0,add column service_bps integer not null default 0,add column tax_on_service boolean not null default true,add column tax_amount bigint not null default 0 check(tax_amount>=0),add column service_amount bigint not null default 0 check(service_amount>=0);
alter table public.pos_payments drop constraint pos_payments_order_id_key,drop constraint pos_payments_method_check;
alter table public.pos_payments add constraint pos_payments_method_check check(method in ('cash','credit_card','debit_card','qr','bank_transfer','other')),add column reference text not null default '' check(length(reference)<=100);
create index pos_payments_order_idx on public.pos_payments(order_id);
create index pos_tables_reserved_by_idx on public.pos_tables(reserved_by) where reserved_by is not null;
create or replace function pos_private.allowed(b uuid,p text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pos_memberships m where m.business_id=b and m.user_id=auth.uid() and m.active and (m.role='owner' or p=any(m.permissions) or (m.role='cashier' and p='reports')));
$$;
create function pos_private.reserve_table(b uuid,p_table uuid,p_guest text,p_time timestamptz,p_release boolean) returns void language plpgsql security definer set search_path='' as $$declare t public.pos_tables;begin
 perform pos_private.require_access(b,'pay');select * into t from public.pos_tables where business_id=b and id=p_table for update;
 if not found then raise exception 'Meja tidak ditemukan';end if;
 if p_release then update public.pos_tables set reservation_guest=null,reserved_at=null,reserved_for=null,reserved_by=null where business_id=b and id=t.id;
 else
  if not t.active or not exists(select 1 from public.pos_areas where business_id=b and id=t.area_id and active) then raise exception 'Meja tidak aktif';end if;
  if exists(select 1 from public.pos_orders where business_id=b and table_id=t.id and status='open') then raise exception 'Meja masih memiliki open bill';end if;
  if t.reserved_at is not null then raise exception 'Meja sudah direservasi';end if;
  if length(trim(coalesce(p_guest,''))) not between 1 and 80 then raise exception 'Isi nama tamu reservasi';end if;
  update public.pos_tables set reservation_guest=trim(p_guest),reserved_at=now(),reserved_for=p_time,reserved_by=auth.uid() where business_id=b and id=t.id;
 end if;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),case when p_release then 'table.reservation.released' else 'table.reserved' end,t.id);
end$$;
create function pos_private.save_charges(b uuid,p_tax integer,p_service integer,p_tax_service boolean) returns void language plpgsql security definer set search_path='' as $$begin
 perform pos_private.require_owner(b);
 if p_tax is null or p_service is null or p_tax_service is null then raise exception 'Pengaturan tax/service tidak valid';end if;
 update public.pos_businesses set tax_bps=p_tax,service_bps=p_service,tax_on_service=p_tax_service where id=b;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'charges.configured',b);
end$$;
create function pos_private.checkout_quote(b uuid,p_order uuid,p_discount uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;d public.pos_discounts;discount bigint:=0;net bigint;service bigint;tax bigint;begin
 perform pos_private.require_access(b,'pay');select * into o from public.pos_orders where business_id=b and id=p_order;
 if not found or o.status<>'open' then raise exception 'Pesanan tidak aktif';end if;
 if p_discount is not null then
  select * into d from public.pos_discounts where business_id=b and id=p_discount for share;
  if not found or not d.active or now()<d.starts_at or now()>=d.ends_at or o.subtotal<d.min_spend then raise exception 'Diskon tidak berlaku';end if;
  discount:=least(o.subtotal,coalesce(d.max_amount,o.subtotal),case when d.kind='percent' then floor(o.subtotal::numeric*d.value/100)::bigint else d.value end);
 end if;
 net:=o.subtotal-discount;service:=round(net::numeric*o.service_bps/10000)::bigint;tax:=round((net+case when o.tax_on_service then service else 0 end)::numeric*o.tax_bps/10000)::bigint;
 return jsonb_build_object('subtotal',o.subtotal,'discount',discount,'discount_name',d.name,'net',net,'service',service,'tax',tax,'total',net+service+tax);
end$$;
create function pos_private.pay_order_v3(b uuid,p_order uuid,p_discount uuid,p_payments jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;q jsonb;entry jsonb;paid bigint:=0;amount bigint;tendered bigint;assigned bigint:=0;share bigint;l record;begin
 perform pos_private.require_access(b,'pay');select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;
 if o.status='paid' then return o.id;end if;
 q:=pos_private.checkout_quote(b,p_order,p_discount);
 if p_payments is null or jsonb_typeof(p_payments)<>'array' or jsonb_array_length(p_payments) not between 1 and 10 then raise exception 'Isi 1–10 bagian pembayaran';end if;
 for entry in select value from jsonb_array_elements(p_payments) loop
  if coalesce(entry->>'method','') not in ('cash','credit_card','debit_card','qr','bank_transfer','other') or coalesce(entry->>'amount','') !~ '^[0-9]+$' or (entry->>'amount')::numeric>1000000000000 then raise exception 'Metode atau nominal pembayaran tidak valid';end if;
  amount:=(entry->>'amount')::bigint;
  if amount=0 and (q->>'total')::bigint<>0 then raise exception 'Nominal setiap pembayaran harus positif';end if;
  if entry->>'method'='cash' then
   if coalesce(entry->>'tendered','') !~ '^[0-9]+$' or (entry->>'tendered')::numeric>1000000000000 then raise exception 'Uang tunai diterima tidak valid';end if;
   tendered:=(entry->>'tendered')::bigint;if tendered<amount then raise exception 'Tunai diterima kurang dari alokasi cash';end if;
  else tendered:=amount;end if;
  paid:=paid+amount;
  insert into public.pos_payments(business_id,order_id,paid_by,amount,tendered,change,method,reference) values(b,o.id,auth.uid(),amount,tendered,tendered-amount,entry->>'method',coalesce(entry->>'reference',''));
 end loop;
 if paid<>(q->>'total')::bigint then raise exception 'Total bagian pembayaran harus sama dengan tagihan';end if;
 for l in select id,sum(price*qty) over(order by id) cumulative from public.pos_order_lines where order_id=o.id order by id loop
  share:=case when o.subtotal=0 then 0 else floor((q->>'discount')::numeric*l.cumulative/o.subtotal)::bigint-assigned end;
  assigned:=assigned+share;update public.pos_order_lines set discount_amount=share where id=l.id;
 end loop;
 update public.pos_orders set total=(q->>'total')::bigint,discount_amount=(q->>'discount')::bigint,discount_id=p_discount,discount_name=q->>'discount_name',service_amount=(q->>'service')::bigint,tax_amount=(q->>'tax')::bigint,status='paid',paid_at=now() where id=o.id;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'order.paid',o.id);return o.id;
end$$;
-- Retire the cash-only settlement path so tax/split validation cannot be bypassed.
revoke execute on function public.pos_pay_order_v2(uuid,uuid,bigint,uuid),pos_private.pay_order_v2(uuid,uuid,bigint,uuid) from public,anon,authenticated;
create function public.pos_reserve_table(b uuid,p_table uuid,p_guest text,p_time timestamptz,p_release boolean) returns void language sql security invoker set search_path='' as $$select pos_private.reserve_table(b,p_table,p_guest,p_time,p_release)$$;
create function public.pos_save_charges(b uuid,p_tax integer,p_service integer,p_tax_service boolean) returns void language sql security invoker set search_path='' as $$select pos_private.save_charges(b,p_tax,p_service,p_tax_service)$$;
create function public.pos_checkout_quote(b uuid,p_order uuid,p_discount uuid) returns jsonb language sql security invoker set search_path='' as $$select pos_private.checkout_quote(b,p_order,p_discount)$$;
create function public.pos_pay_order_v3(b uuid,p_order uuid,p_discount uuid,p_payments jsonb) returns uuid language sql security invoker set search_path='' as $$select pos_private.pay_order_v3(b,p_order,p_discount,p_payments)$$;
revoke all on function pos_private.reserve_table(uuid,uuid,text,timestamptz,boolean),pos_private.save_charges(uuid,integer,integer,boolean),pos_private.checkout_quote(uuid,uuid,uuid),pos_private.pay_order_v3(uuid,uuid,uuid,jsonb),public.pos_reserve_table(uuid,uuid,text,timestamptz,boolean),public.pos_save_charges(uuid,integer,integer,boolean),public.pos_checkout_quote(uuid,uuid,uuid),public.pos_pay_order_v3(uuid,uuid,uuid,jsonb) from public,anon;
grant execute on function pos_private.reserve_table(uuid,uuid,text,timestamptz,boolean),pos_private.save_charges(uuid,integer,integer,boolean),pos_private.checkout_quote(uuid,uuid,uuid),pos_private.pay_order_v3(uuid,uuid,uuid,jsonb),public.pos_reserve_table(uuid,uuid,text,timestamptz,boolean),public.pos_save_charges(uuid,integer,integer,boolean),public.pos_checkout_quote(uuid,uuid,uuid),public.pos_pay_order_v3(uuid,uuid,uuid,jsonb) to authenticated;

create or replace function pos_private.place_order_v3(b uuid,p_request uuid,p_lines jsonb,p_type text,p_table uuid,p_guest text,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare o uuid;cfg public.pos_businesses;t public.pos_tables;is_waiter boolean;section jsonb;items jsonb;begin
 perform pos_private.require_access(b,'pos');
 if p_request is null then raise exception 'Request ID wajib';end if;
 perform pg_advisory_xact_lock(hashtextextended(b::text||p_request::text,0));
 select id into o from public.pos_orders where business_id=b and request_id=p_request;if found then return o;end if;
 select * into cfg from public.pos_businesses where id=b;
 select role='waiter' into is_waiter from public.pos_memberships where business_id=b and user_id=auth.uid();
 if is_waiter and (not cfg.restaurant_mode or not cfg.waiter_enabled) then raise exception 'Mode waiter belum diaktifkan oleh owner';end if;
 if (is_waiter or (cfg.restaurant_mode and p_type='dinein')) then
  if p_type<>'dinein' or p_table is null or length(trim(coalesce(p_guest,''))) not between 1 and 80 then raise exception 'Pilih meja dan isi nama tamu terlebih dahulu';end if;
 end if;
 if p_table is not null then
  if not cfg.restaurant_mode or p_type<>'dinein' then raise exception 'Meja hanya untuk dine in mode Restaurant';end if;
  select * into t from public.pos_tables where business_id=b and id=p_table for update;
  if not found or not t.active or not exists(select 1 from public.pos_areas where business_id=b and id=t.area_id and active) then raise exception 'Meja tidak tersedia';end if;
  if t.reserved_at is not null then raise exception 'Meja masih direservasi. Kasir harus melepas reservasi dahulu';end if;
  if exists(select 1 from public.pos_orders where business_id=b and table_id=t.id and status='open') then raise exception 'Meja sedang digunakan. Muat ulang ketersediaan meja';end if;
 end if;
 if p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Isi pesanan tidak valid';end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x where length(coalesce(x->>'note',''))>300) or exists(select 1 from jsonb_array_elements(p_lines) x group by x->>'id' having count(*)>1) then raise exception 'Item duplikat atau catatan terlalu panjang';end if;
 o:=pos_private.place_order_core(b,p_request,p_lines,p_type,coalesce(t.name,''),coalesce(p_note,''));
 update public.pos_orders set table_id=p_table,guest_name=trim(coalesce(p_guest,'')),subtotal=total,tax_bps=cfg.tax_bps,service_bps=cfg.service_bps,tax_on_service=cfg.tax_on_service,service_amount=round(total::numeric*cfg.service_bps/10000)::bigint,tax_amount=round((total+case when cfg.tax_on_service then round(total::numeric*cfg.service_bps/10000)::bigint else 0 end)::numeric*cfg.tax_bps/10000)::bigint where id=o;
 update public.pos_orders set total=subtotal+service_amount+tax_amount where id=o;
 update public.pos_order_lines l set item_note=coalesce(x->>'note','') from jsonb_array_elements(p_lines) x where l.order_id=o and l.product_id=(x->>'id')::uuid;
 if cfg.restaurant_mode then
  for section in select value from jsonb_array_elements(cfg.print_sections) loop
   select jsonb_agg(jsonb_build_object('product_id',l.product_id,'name',l.name,'qty',l.qty,'note',l.item_note) order by l.name) into items from public.pos_order_lines l where l.order_id=o and section->'categories' ? l.category_id::text;
   if items is not null then insert into public.pos_print_jobs(business_id,order_id,section,payload) values(b,o,section->>'name',jsonb_build_object('section',section,'table',t.name,'guest',trim(coalesce(p_guest,'')),'note',p_note,'items',items,'order_id',o)) on conflict on constraint pos_print_jobs_order_id_section_key do nothing;end if;
  end loop;
 end if;
 return o;
end$$;
