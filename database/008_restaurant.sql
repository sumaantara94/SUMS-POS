-- Restaurant operations: all writes use tenant-checked RPCs.
alter table public.pos_businesses add column restaurant_mode boolean not null default false, add column waiter_enabled boolean not null default false, add constraint waiter_requires_restaurant check(not waiter_enabled or restaurant_mode);
create table public.pos_areas(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.pos_businesses(id),name text not null check(length(trim(name)) between 1 and 40),active boolean not null default true,unique(business_id,id),unique(business_id,name));
create table public.pos_tables(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.pos_businesses(id),area_id uuid not null,name text not null check(length(trim(name)) between 1 and 40),capacity integer not null check(capacity between 1 and 100),x integer not null check(x between 1 and 12),y integer not null check(y between 1 and 12),active boolean not null default true,foreign key(business_id,area_id) references public.pos_areas(business_id,id),unique(business_id,id),unique(area_id,name));
create index pos_tables_area_idx on public.pos_tables(business_id,area_id);
alter table public.pos_orders add column table_id uuid,add column guest_name text not null default '' check(length(guest_name)<=80),add column subtotal bigint,add column discount_amount bigint not null default 0 check(discount_amount>=0),add column discount_name text,add column cancel_reason text,add column cancelled_by uuid references auth.users(id),add column cancelled_at timestamptz,add foreign key(business_id,table_id) references public.pos_tables(business_id,id);
update public.pos_orders set subtotal=total;
alter table public.pos_orders alter column subtotal set not null;
create index pos_orders_table_open_idx on public.pos_orders(business_id,table_id) where status='open';
alter table public.pos_order_lines add column item_note text not null default '' check(length(item_note)<=300),add column discount_amount bigint not null default 0 check(discount_amount>=0 and discount_amount<=price*qty);
create table public.pos_discounts(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.pos_businesses(id),name text not null check(length(trim(name)) between 1 and 80),kind text not null check(kind in ('percent','fixed')),value bigint not null check(value>0),min_spend bigint not null default 0 check(min_spend>=0),max_amount bigint check(max_amount>0),starts_at timestamptz not null,ends_at timestamptz not null,active boolean not null default true,check(ends_at>starts_at),check(kind<>'percent' or value<=100),unique(business_id,id));
alter table public.pos_orders add column discount_id uuid,add foreign key(business_id,discount_id) references public.pos_discounts(business_id,id);
create index pos_discounts_business_idx on public.pos_discounts(business_id);
create table public.pos_print_jobs(id uuid primary key default gen_random_uuid(),business_id uuid not null,order_id uuid not null,section text not null,payload jsonb not null,status text not null default 'queued' check(status in ('queued','printed','cancelled')),created_at timestamptz not null default now(),acknowledged_by uuid references auth.users(id),acknowledged_at timestamptz,foreign key(business_id,order_id) references public.pos_orders(business_id,id),unique(order_id,section));
create index pos_print_jobs_business_idx on public.pos_print_jobs(business_id,created_at desc);
create table pos_private.cancel_config(business_id uuid primary key references public.pos_businesses(id),pin_hash text not null);
create table pos_private.cancel_attempts(business_id uuid not null,user_id uuid not null,bucket timestamptz not null,attempts integer not null,primary key(business_id,user_id));
revoke all on pos_private.cancel_config,pos_private.cancel_attempts from public,anon,authenticated;
alter table pos_private.cancel_config enable row level security;
alter table pos_private.cancel_attempts enable row level security;
alter table public.pos_areas enable row level security;
alter table public.pos_tables enable row level security;
alter table public.pos_discounts enable row level security;
alter table public.pos_print_jobs enable row level security;
revoke all on public.pos_areas,public.pos_tables,public.pos_discounts,public.pos_print_jobs from public,anon,authenticated;
grant select on public.pos_areas,public.pos_tables,public.pos_discounts,public.pos_print_jobs to authenticated;
create policy area_read on public.pos_areas for select to authenticated using(pos_private.allowed(business_id,'pos') or pos_private.allowed(business_id,'settings'));
create policy table_read on public.pos_tables for select to authenticated using(pos_private.allowed(business_id,'pos') or pos_private.allowed(business_id,'settings'));
create policy discount_read on public.pos_discounts for select to authenticated using(pos_private.allowed(business_id,'pay') or pos_private.allowed(business_id,'settings'));
create policy job_read on public.pos_print_jobs for select to authenticated using(pos_private.allowed(business_id,'orders'));
create function pos_private.require_owner(b uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.pos_memberships where business_id=b and user_id=auth.uid() and active and role='owner') then raise exception 'Hanya owner dapat mengatur operasional' using errcode='42501';end if;
end$$;
create function pos_private.restaurant_settings(b uuid,p_mode boolean,p_waiter boolean,p_pin text) returns void language plpgsql security definer set search_path='' as $$begin
 perform pos_private.require_owner(b);
 if p_mode is null or p_waiter is null then raise exception 'Pengaturan tidak valid';end if;
 if p_pin is not null and p_pin<>'' then
  if p_pin !~ '^[0-9]{6}$' then raise exception 'PIN harus 6 angka';end if;
  insert into pos_private.cancel_config values(b,extensions.crypt(p_pin,extensions.gen_salt('bf',10))) on conflict(business_id) do update set pin_hash=excluded.pin_hash;
 end if;
 update public.pos_businesses set restaurant_mode=p_mode,waiter_enabled=p_mode and p_waiter where id=b;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'restaurant.configured',b);
end$$;
create function pos_private.save_area(b uuid,p_id uuid,p_name text,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 perform pos_private.require_owner(b);
 if p_id is null then insert into public.pos_areas(business_id,name,active) values(b,trim(p_name),p_active) returning id into result;
 else update public.pos_areas set name=trim(p_name),active=p_active where business_id=b and id=p_id returning id into result;if result is null then raise exception 'Area tidak ditemukan';end if;end if;
 return result;
end$$;
create function pos_private.save_table(b uuid,p_id uuid,p_area uuid,p_name text,p_capacity integer,p_x integer,p_y integer,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 perform pos_private.require_owner(b);
 if p_id is null then insert into public.pos_tables(business_id,area_id,name,capacity,x,y,active) values(b,p_area,trim(p_name),p_capacity,p_x,p_y,p_active) returning id into result;
 else update public.pos_tables set area_id=p_area,name=trim(p_name),capacity=p_capacity,x=p_x,y=p_y,active=p_active where business_id=b and id=p_id returning id into result;if result is null then raise exception 'Meja tidak ditemukan';end if;end if;
 return result;
end$$;
create function pos_private.save_discount(b uuid,p_id uuid,p_name text,p_kind text,p_value bigint,p_min bigint,p_max bigint,p_start timestamptz,p_end timestamptz,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 perform pos_private.require_owner(b);
 if p_id is null then insert into public.pos_discounts(business_id,name,kind,value,min_spend,max_amount,starts_at,ends_at,active) values(b,trim(p_name),p_kind,p_value,p_min,p_max,p_start,p_end,p_active) returning id into result;
 else update public.pos_discounts set name=trim(p_name),kind=p_kind,value=p_value,min_spend=p_min,max_amount=p_max,starts_at=p_start,ends_at=p_end,active=p_active where business_id=b and id=p_id returning id into result;if result is null then raise exception 'Diskon tidak ditemukan';end if;end if;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'discount.saved',result);return result;
end$$;
-- Retire old entrypoints; old private cores cannot be invoked by authenticated clients.
alter function pos_private.place_order(uuid,uuid,jsonb,text,text,text) rename to place_order_core;
alter function pos_private.pay_order(uuid,uuid,bigint) rename to pay_order_core;
revoke execute on function pos_private.place_order_core(uuid,uuid,jsonb,text,text,text),pos_private.pay_order_core(uuid,uuid,bigint),pos_private.cancel_order(uuid,uuid),public.pos_place_order(uuid,uuid,jsonb,text,text,text),public.pos_pay_order(uuid,uuid,bigint),public.pos_cancel_order(uuid,uuid) from public,anon,authenticated;
-- Core INSERT requires new subtotal default until server recomputes it.
alter table public.pos_orders alter column subtotal set default 0;
create function pos_private.place_order_v3(b uuid,p_request uuid,p_lines jsonb,p_type text,p_table uuid,p_guest text,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
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
  if exists(select 1 from public.pos_orders where business_id=b and table_id=t.id and status='open') then raise exception 'Meja sedang digunakan. Muat ulang ketersediaan meja';end if;
 end if;
 if p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Isi pesanan tidak valid';end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x where length(coalesce(x->>'note',''))>300) or exists(select 1 from jsonb_array_elements(p_lines) x group by x->>'id' having count(*)>1) then raise exception 'Item duplikat atau catatan terlalu panjang';end if;
 o:=pos_private.place_order_core(b,p_request,p_lines,p_type,coalesce(t.name,''),coalesce(p_note,''));
 update public.pos_orders set table_id=p_table,guest_name=trim(coalesce(p_guest,'')),subtotal=total where id=o;
 update public.pos_order_lines l set item_note=coalesce(x->>'note','') from jsonb_array_elements(p_lines) x where l.order_id=o and l.product_id=(x->>'id')::uuid;
 if cfg.restaurant_mode then
  for section in select value from jsonb_array_elements(cfg.print_sections) loop
   select jsonb_agg(jsonb_build_object('product_id',l.product_id,'name',l.name,'qty',l.qty,'note',l.item_note) order by l.name) into items from public.pos_order_lines l where l.order_id=o and section->'categories' ? l.category_id::text;
   if items is not null then insert into public.pos_print_jobs(business_id,order_id,section,payload) values(b,o,section->>'name',jsonb_build_object('section',section,'table',t.name,'guest',trim(coalesce(p_guest,'')),'note',p_note,'items',items,'order_id',o)) on conflict on constraint pos_print_jobs_order_id_section_key do nothing;end if;
  end loop;
 end if;
 return o;
end$$;
create function pos_private.pay_order_v2(b uuid,p_order uuid,p_tendered bigint,p_discount uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;d public.pos_discounts;amount bigint:=0;assigned bigint:=0;l record;share bigint;begin
 perform pos_private.require_access(b,'pay');select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;
 if o.status='paid' then return o.id;end if;
 if o.status<>'open' then raise exception 'Pesanan tidak aktif';end if;
 if p_discount is not null then
  select * into d from public.pos_discounts where business_id=b and id=p_discount for share;
  if not found or not d.active or now()<d.starts_at or now()>=d.ends_at or o.subtotal<d.min_spend then raise exception 'Diskon tidak berlaku untuk transaksi ini';end if;
  amount:=case when d.kind='percent' then floor(o.subtotal::numeric*d.value/100)::bigint else d.value end;
  amount:=least(amount,o.subtotal,coalesce(d.max_amount,amount));
 end if;
 -- Cumulative proportional allocation preserves exact rupiah totals in category reports.
 for l in select id,price*qty gross,sum(price*qty) over(order by id) cumulative from public.pos_order_lines where order_id=o.id order by id loop
  share:=case when o.subtotal=0 then 0 else floor(amount::numeric*l.cumulative/o.subtotal)::bigint-assigned end;
  assigned:=assigned+share;update public.pos_order_lines set discount_amount=share where id=l.id;
 end loop;
 update public.pos_orders set total=subtotal-amount,discount_amount=amount,discount_id=p_discount,discount_name=d.name where id=o.id;
 return pos_private.pay_order_core(b,o.id,p_tendered);
end$$;
create function pos_private.cancel_order_v2(b uuid,p_order uuid,p_pin text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;l record;hash text;n integer;bucket timestamptz:=to_timestamp(floor(extract(epoch from now())/900)*900);begin
 perform pos_private.require_access(b,'orders');
 if not pos_private.allowed(b,'pay') then raise exception 'Hanya kasir atau owner dapat membatalkan';end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Alasan pembatalan wajib 3–300 karakter';end if;
 select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;
 if o.status='cancelled' then return jsonb_build_object('ok',true,'id',o.id);end if;
 if o.status<>'open' then raise exception 'Pesanan lunas tidak dapat dibatalkan';end if;
 select pin_hash into hash from pos_private.cancel_config where business_id=b;
 if hash is null then return jsonb_build_object('ok',false,'error','Owner perlu mengatur PIN pembatalan');end if;
 insert into pos_private.cancel_attempts values(b,auth.uid(),bucket,1) on conflict(business_id,user_id) do update set attempts=case when cancel_attempts.bucket=excluded.bucket then cancel_attempts.attempts+1 else 1 end,bucket=excluded.bucket returning attempts into n;
 if n>5 then return jsonb_build_object('ok',false,'error','Batas percobaan PIN tercapai. Coba kembali setelah 15 menit');end if;
 if p_pin is null or p_pin !~ '^[0-9]{6}$' or extensions.crypt(p_pin,hash)<>hash then return jsonb_build_object('ok',false,'error','PIN tidak benar');end if;
 for l in select * from public.pos_order_lines where order_id=o.id order by product_id loop
  update public.pos_products set stock=stock+l.qty where business_id=b and id=l.product_id;
  insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id) values(b,l.product_id,o.id,l.qty,'order.release',auth.uid());
 end loop;
 update public.pos_orders set status='cancelled',cancel_reason=trim(p_reason),cancelled_by=auth.uid(),cancelled_at=now() where id=o.id;
 update public.pos_print_jobs set status='cancelled' where order_id=o.id and status='queued';
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'order.cancelled.pin',o.id);
 return jsonb_build_object('ok',true,'id',o.id);
end$$;
create function pos_private.ack_print(b uuid,p_job uuid) returns void language plpgsql security definer set search_path='' as $$begin
 perform pos_private.require_access(b,'orders');
 update public.pos_print_jobs set status='printed',acknowledged_by=auth.uid(),acknowledged_at=now() where business_id=b and id=p_job and status='queued';
 if not found then raise exception 'Antrean tidak aktif';end if;
end$$;
create function public.pos_restaurant_settings(b uuid,p_mode boolean,p_waiter boolean,p_pin text) returns void language sql security invoker set search_path='' as $$select pos_private.restaurant_settings(b,p_mode,p_waiter,p_pin)$$;
create function public.pos_save_area(b uuid,p_id uuid,p_name text,p_active boolean) returns uuid language sql security invoker set search_path='' as $$select pos_private.save_area(b,p_id,p_name,p_active)$$;
create function public.pos_save_table(b uuid,p_id uuid,p_area uuid,p_name text,p_capacity integer,p_x integer,p_y integer,p_active boolean) returns uuid language sql security invoker set search_path='' as $$select pos_private.save_table(b,p_id,p_area,p_name,p_capacity,p_x,p_y,p_active)$$;
create function public.pos_save_discount(b uuid,p_id uuid,p_name text,p_kind text,p_value bigint,p_min bigint,p_max bigint,p_start timestamptz,p_end timestamptz,p_active boolean) returns uuid language sql security invoker set search_path='' as $$select pos_private.save_discount(b,p_id,p_name,p_kind,p_value,p_min,p_max,p_start,p_end,p_active)$$;
create function public.pos_place_order_v3(b uuid,p_request uuid,p_lines jsonb,p_type text,p_table uuid,p_guest text,p_note text) returns uuid language sql security invoker set search_path='' as $$select pos_private.place_order_v3(b,p_request,p_lines,p_type,p_table,p_guest,p_note)$$;
create function public.pos_pay_order_v2(b uuid,p_order uuid,p_tendered bigint,p_discount uuid) returns uuid language sql security invoker set search_path='' as $$select pos_private.pay_order_v2(b,p_order,p_tendered,p_discount)$$;
create function public.pos_cancel_order_v2(b uuid,p_order uuid,p_pin text,p_reason text) returns jsonb language sql security invoker set search_path='' as $$select pos_private.cancel_order_v2(b,p_order,p_pin,p_reason)$$;
create function public.pos_ack_print(b uuid,p_job uuid) returns void language sql security invoker set search_path='' as $$select pos_private.ack_print(b,p_job)$$;
-- Explicit grants: no blanket grants to retired core functions.
do $$declare f record;begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='pos_private' and p.proname in ('require_owner','restaurant_settings','save_area','save_table','save_discount','place_order_v3','pay_order_v2','cancel_order_v2','ack_print')) or (n.nspname='public' and p.proname in ('pos_restaurant_settings','pos_save_area','pos_save_table','pos_save_discount','pos_place_order_v3','pos_pay_order_v2','pos_cancel_order_v2','pos_ack_print')) loop
 execute format('revoke all on function %s from public,anon',f.sig);execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end$$;
