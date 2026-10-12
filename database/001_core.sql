create schema if not exists pos_private;
revoke all on schema pos_private from public, anon;
grant usage on schema pos_private to authenticated;

create table public.pos_businesses (
 id uuid primary key default gen_random_uuid(), name text not null check (length(trim(name)) between 1 and 80),
 category text not null default 'Other', accent text not null default '#087f6c' check(accent ~ '^#[0-9a-fA-F]{6}$'),
 timezone text not null default 'Asia/Makassar', created_at timestamptz not null default now()
);
create table public.pos_memberships (
 business_id uuid not null references public.pos_businesses(id), user_id uuid not null references auth.users(id),
 role text not null check(role in ('owner','cashier','waiter','custom')),
 permissions text[] not null default '{}', active boolean not null default true,
 primary key(business_id,user_id), check(permissions <@ array['dashboard','pos','orders','products','reports','settings','pay','cancel','staff']::text[])
);
create index pos_memberships_user_idx on public.pos_memberships(user_id,business_id);
create table public.pos_products (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.pos_businesses(id),
 name text not null check(length(trim(name)) between 1 and 80), category text not null check(length(trim(category)) between 1 and 40),
 price bigint not null check(price between 1 and 100000000), stock integer not null default 0 check(stock between 0 and 1000000),
 icon text not null default '◇', active boolean not null default true, unique(business_id,id)
);
create index pos_products_business_idx on public.pos_products(business_id);
create table public.pos_orders (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.pos_businesses(id),
 request_id uuid not null, number bigint generated always as identity,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 status text not null default 'open' check(status in ('open','paid','cancelled')),
 order_type text not null check(order_type in ('dinein','takeaway')), table_ref text not null default '' check(length(table_ref)<=40),
 note text not null default '' check(length(note)<=300), total bigint not null default 0 check(total>=0),
 paid_at timestamptz, unique(business_id,request_id), unique(business_id,id)
);
create index pos_orders_business_created_idx on public.pos_orders(business_id,created_at desc);
create index pos_orders_business_paid_idx on public.pos_orders(business_id,paid_at) where status='paid';
create table public.pos_order_lines (
 id uuid primary key default gen_random_uuid(), business_id uuid not null, order_id uuid not null, product_id uuid not null,
 name text not null, price bigint not null check(price>0), qty integer not null check(qty between 1 and 1000000),
 foreign key(business_id,order_id) references public.pos_orders(business_id,id),
 foreign key(business_id,product_id) references public.pos_products(business_id,id), unique(order_id,product_id)
);
create index pos_lines_business_order_idx on public.pos_order_lines(business_id,order_id);
create table public.pos_payments (
 id uuid primary key default gen_random_uuid(), business_id uuid not null, order_id uuid not null unique,
 paid_by uuid not null references auth.users(id), amount bigint not null check(amount>=0), tendered bigint not null,
 change bigint not null check(change>=0), method text not null check(method='cash'), created_at timestamptz not null default now(),
 foreign key(business_id,order_id) references public.pos_orders(business_id,id), check(tendered=amount+change)
);
create index pos_payments_business_idx on public.pos_payments(business_id);
create table public.pos_stock_movements (
 id uuid primary key default gen_random_uuid(), business_id uuid not null, product_id uuid not null, order_id uuid,
 delta integer not null, reason text not null, actor_id uuid not null references auth.users(id), created_at timestamptz not null default now(),
 foreign key(business_id,product_id) references public.pos_products(business_id,id),
 foreign key(business_id,order_id) references public.pos_orders(business_id,id)
);
create index pos_stock_business_created_idx on public.pos_stock_movements(business_id,created_at desc);
create index pos_stock_product_idx on public.pos_stock_movements(product_id);
create index pos_stock_order_idx on public.pos_stock_movements(order_id);
create table public.pos_audit_events (
 id uuid primary key default gen_random_uuid(), business_id uuid not null references public.pos_businesses(id),
 actor_id uuid not null references auth.users(id), action text not null, record_id uuid, created_at timestamptz not null default now()
);
create index pos_audit_business_created_idx on public.pos_audit_events(business_id,created_at desc);

create function pos_private.allowed(b uuid, p text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pos_memberships m where m.business_id=b and m.user_id=auth.uid() and m.active and (m.role='owner' or p=any(m.permissions)));
$$;
create function pos_private.require_access(b uuid,p text) returns void language plpgsql security definer set search_path='' as $$
begin if not pos_private.allowed(b,p) then raise exception 'Akses bisnis atau izin ditolak' using errcode='42501'; end if; end; $$;

alter table public.pos_businesses enable row level security;
alter table public.pos_memberships enable row level security;
alter table public.pos_products enable row level security;
alter table public.pos_orders enable row level security;
alter table public.pos_order_lines enable row level security;
alter table public.pos_payments enable row level security;
alter table public.pos_stock_movements enable row level security;
alter table public.pos_audit_events enable row level security;
revoke all on public.pos_businesses,public.pos_memberships,public.pos_products,public.pos_orders,public.pos_order_lines,public.pos_payments,public.pos_stock_movements,public.pos_audit_events from anon,authenticated;
grant select on public.pos_businesses,public.pos_memberships,public.pos_products,public.pos_orders,public.pos_order_lines,public.pos_payments,public.pos_stock_movements,public.pos_audit_events to authenticated;
create policy business_read on public.pos_businesses for select to authenticated using(exists(select 1 from public.pos_memberships where business_id=id and user_id=(select auth.uid()) and active));
create policy membership_read on public.pos_memberships for select to authenticated using(user_id=(select auth.uid()) or pos_private.allowed(business_id,'staff'));
create policy product_read on public.pos_products for select to authenticated using(pos_private.allowed(business_id,'pos') or pos_private.allowed(business_id,'products'));
create policy order_read on public.pos_orders for select to authenticated using(pos_private.allowed(business_id,'orders') or pos_private.allowed(business_id,'reports') or pos_private.allowed(business_id,'dashboard'));
create policy line_read on public.pos_order_lines for select to authenticated using(pos_private.allowed(business_id,'orders') or pos_private.allowed(business_id,'reports') or pos_private.allowed(business_id,'dashboard'));
create policy payment_read on public.pos_payments for select to authenticated using(pos_private.allowed(business_id,'pay') or pos_private.allowed(business_id,'reports') or pos_private.allowed(business_id,'dashboard'));
create policy stock_read on public.pos_stock_movements for select to authenticated using(pos_private.allowed(business_id,'products'));
create policy audit_read on public.pos_audit_events for select to authenticated using(pos_private.allowed(business_id,'staff'));

create function pos_private.create_business(p_name text,p_category text,p_accent text) returns uuid language plpgsql security definer set search_path='' as $$
declare b uuid;begin
 if auth.uid() is null then raise exception 'Login diperlukan' using errcode='42501';end if;
 insert into public.pos_businesses(name,category,accent) values(trim(p_name),p_category,p_accent) returning id into b;
 insert into public.pos_memberships(business_id,user_id,role,permissions) values(b,auth.uid(),'owner',array['dashboard','pos','orders','products','reports','settings','pay','cancel','staff']);
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'business.created',b);return b;
end;$$;
create function pos_private.save_business(b uuid,p_name text,p_category text,p_accent text) returns void language plpgsql security definer set search_path='' as $$
begin perform pos_private.require_access(b,'settings');update public.pos_businesses set name=trim(p_name),category=p_category,accent=p_accent where id=b;insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'business.updated',b);end;$$;
create function pos_private.save_product(b uuid,p_id uuid,p_name text,p_category text,p_price bigint,p_stock integer,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;old_stock integer;begin
 perform pos_private.require_access(b,'products');
 if p_id is null then insert into public.pos_products(business_id,name,category,price,stock,active) values(b,trim(p_name),trim(p_category),p_price,p_stock,p_active) returning id into result;old_stock:=0;
 else select stock into old_stock from public.pos_products where business_id=b and id=p_id for update;if not found then raise exception 'Produk tidak ditemukan';end if;update public.pos_products set name=trim(p_name),category=trim(p_category),price=p_price,stock=p_stock,active=p_active where business_id=b and id=p_id;result:=p_id;end if;
 if p_stock<>old_stock then insert into public.pos_stock_movements(business_id,product_id,delta,reason,actor_id) values(b,result,p_stock-old_stock,'adjustment',auth.uid());end if;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'product.saved',result);return result;
end;$$;
create function pos_private.place_order(b uuid,p_request uuid,p_lines jsonb,p_type text,p_table text,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare o uuid;item record;product public.pos_products;qty integer;amount bigint:=0;begin
 perform pos_private.require_access(b,'pos');
 if p_request is null then raise exception 'Request ID wajib';end if;
 perform pg_advisory_xact_lock(hashtextextended(b::text||p_request::text,0));
 select id into o from public.pos_orders where business_id=b and request_id=p_request;if found then return o;end if;
 if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'Isi pesanan tidak valid';end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x where (x->>'qty') is null or (x->>'qty')::numeric<>trunc((x->>'qty')::numeric) or (x->>'qty')::numeric not between 1 and 1000000) then raise exception 'Jumlah item tidak valid';end if;
 insert into public.pos_orders(business_id,request_id,created_by,order_type,table_ref,note) values(b,p_request,auth.uid(),p_type,p_table,p_note) returning id into o;
 -- Lock catalog rows in UUID order to avoid deadlock between concurrent checkouts.
 for item in select (x->>'id')::uuid as id,sum((x->>'qty')::numeric) as qty from jsonb_array_elements(p_lines) x group by (x->>'id')::uuid order by (x->>'id')::uuid loop
  if item.qty is null or item.qty<>trunc(item.qty) or item.qty not between 1 and 1000000 then raise exception 'Jumlah tidak valid';end if;qty:=item.qty::integer;
  select * into product from public.pos_products where business_id=b and id=item.id for update;
  if not found or not product.active then raise exception 'Produk tidak tersedia';end if;
  if product.stock<qty then raise exception 'Stok % tidak cukup',product.name;end if;
  update public.pos_products set stock=stock-qty where business_id=b and id=product.id;
  insert into public.pos_order_lines(business_id,order_id,product_id,name,price,qty) values(b,o,product.id,product.name,product.price,qty);
  insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id) values(b,product.id,o,-qty,'order.reserve',auth.uid());amount:=amount+product.price*qty;
 end loop;
 update public.pos_orders set total=amount where id=o;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'order.created',o);return o;
end;$$;
create function pos_private.pay_order(b uuid,p_order uuid,p_tendered bigint) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;begin
 perform pos_private.require_access(b,'pay');select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;
 if o.status='paid' then return o.id;end if;
 if o.status<>'open' then raise exception 'Pesanan tidak aktif';end if;
 if p_tendered is null or p_tendered<o.total or p_tendered>1000000000000 then raise exception 'Uang diterima tidak valid';end if;
 insert into public.pos_payments(business_id,order_id,paid_by,amount,tendered,change,method) values(b,o.id,auth.uid(),o.total,p_tendered,p_tendered-o.total,'cash');
 update public.pos_orders set status='paid',paid_at=now() where id=o.id;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'order.paid',o.id);return o.id;
end;$$;
create function pos_private.cancel_order(b uuid,p_order uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;l record;begin
 perform pos_private.require_access(b,'cancel');select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;if o.status='cancelled' then return o.id;end if;if o.status<>'open' then raise exception 'Pesanan lunas tidak dapat dibatalkan';end if;
 for l in select * from public.pos_order_lines where order_id=o.id order by product_id loop
  update public.pos_products set stock=stock+l.qty where business_id=b and id=l.product_id;
  insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id) values(b,l.product_id,o.id,l.qty,'order.release',auth.uid());
 end loop;update public.pos_orders set status='cancelled' where id=o.id;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'order.cancelled',o.id);return o.id;
end;$$;
create function pos_private.set_member(b uuid,p_email text,p_role text,p_permissions text[],p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare u uuid;begin
 -- Membership management always requires the owner role, even when custom roles have staff visibility.
 if auth.uid() is null or not exists(select 1 from public.pos_memberships where business_id=b and user_id=auth.uid() and role='owner' and active) then raise exception 'Hanya owner dapat mengatur staf' using errcode='42501';end if;
 select id into u from auth.users where lower(email)=lower(trim(p_email));if u is null then raise exception 'Staf harus mendaftar terlebih dahulu';end if;
 if u=auth.uid() then raise exception 'Owner tidak dapat mengubah hak akses sendiri';end if;
 if exists(select 1 from public.pos_memberships where business_id=b and user_id=u and role='owner') then raise exception 'Hak akses owner tidak dapat diubah di sini';end if;
 if p_role not in ('cashier','waiter','custom') then raise exception 'Peran tidak valid';end if;
 insert into public.pos_memberships(business_id,user_id,role,permissions,active) values(b,u,p_role,case when p_role='cashier' then array['pos','orders','pay'] when p_role='waiter' then array['pos','orders'] else coalesce(p_permissions,'{}') end,p_active)
 on conflict(business_id,user_id) do update set role=excluded.role,permissions=excluded.permissions,active=excluded.active;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'member.updated',u);
end;$$;
-- Public entry points are invokers. Privilege is confined to audited private functions.
create function public.pos_create_business(p_name text,p_category text,p_accent text) returns uuid language sql security invoker set search_path='' as $$select pos_private.create_business(p_name,p_category,p_accent)$$;
create function public.pos_save_business(b uuid,p_name text,p_category text,p_accent text) returns void language sql security invoker set search_path='' as $$select pos_private.save_business(b,p_name,p_category,p_accent)$$;
create function public.pos_save_product(b uuid,p_id uuid,p_name text,p_category text,p_price bigint,p_stock integer,p_active boolean) returns uuid language sql security invoker set search_path='' as $$select pos_private.save_product(b,p_id,p_name,p_category,p_price,p_stock,p_active)$$;
create function public.pos_place_order(b uuid,p_request uuid,p_lines jsonb,p_type text,p_table text,p_note text) returns uuid language sql security invoker set search_path='' as $$select pos_private.place_order(b,p_request,p_lines,p_type,p_table,p_note)$$;
create function public.pos_pay_order(b uuid,p_order uuid,p_tendered bigint) returns uuid language sql security invoker set search_path='' as $$select pos_private.pay_order(b,p_order,p_tendered)$$;
create function public.pos_cancel_order(b uuid,p_order uuid) returns uuid language sql security invoker set search_path='' as $$select pos_private.cancel_order(b,p_order)$$;
create function public.pos_set_member(b uuid,p_email text,p_role text,p_permissions text[],p_active boolean) returns void language sql security invoker set search_path='' as $$select pos_private.set_member(b,p_email,p_role,p_permissions,p_active)$$;
revoke all on all functions in schema pos_private from public,anon;
grant execute on all functions in schema pos_private to authenticated;
revoke all on function public.pos_create_business(text,text,text),public.pos_save_business(uuid,text,text,text),public.pos_save_product(uuid,uuid,text,text,bigint,integer,boolean),public.pos_place_order(uuid,uuid,jsonb,text,text,text),public.pos_pay_order(uuid,uuid,bigint),public.pos_cancel_order(uuid,uuid),public.pos_set_member(uuid,text,text,text[],boolean) from public,anon;
grant execute on function public.pos_create_business(text,text,text),public.pos_save_business(uuid,text,text,text),public.pos_save_product(uuid,uuid,text,text,bigint,integer,boolean),public.pos_place_order(uuid,uuid,jsonb,text,text,text),public.pos_pay_order(uuid,uuid,bigint),public.pos_cancel_order(uuid,uuid),public.pos_set_member(uuid,text,text,text[],boolean) to authenticated;
