create table public.pos_categories (
 id uuid primary key default gen_random_uuid(),business_id uuid not null references public.pos_businesses(id),
 name text not null check(length(trim(name)) between 1 and 40),active boolean not null default true,
 unique(business_id,id),unique(business_id,name)
);
create index pos_categories_business_idx on public.pos_categories(business_id);
alter table public.pos_categories enable row level security;
revoke all on public.pos_categories from anon,authenticated;grant select on public.pos_categories to authenticated;
create policy category_read on public.pos_categories for select to authenticated using(pos_private.allowed(business_id,'pos') or pos_private.allowed(business_id,'products'));
insert into public.pos_categories(business_id,name) select distinct business_id,category from public.pos_products;
alter table public.pos_products add column category_id uuid,add column purchase_cost bigint check(purchase_cost between 0 and 100000000);
update public.pos_products p set category_id=c.id from public.pos_categories c where c.business_id=p.business_id and c.name=p.category;
alter table public.pos_products add foreign key(business_id,category_id) references public.pos_categories(business_id,id);
create index pos_products_category_idx on public.pos_products(business_id,category_id);
alter table public.pos_order_lines add column purchase_cost bigint,add column category_id uuid,add column category_name text;
alter table public.pos_businesses add column logo_data text not null default '',add column receipt_width integer not null default 80 check(receipt_width in (58,80)),add column print_sections jsonb not null default '[]';
create function pos_private.snapshot_line() returns trigger language plpgsql security invoker set search_path='' as $$
declare p public.pos_products;begin select * into p from public.pos_products where business_id=new.business_id and id=new.product_id;new.purchase_cost:=p.purchase_cost;new.category_id:=p.category_id;new.category_name:=p.category;return new;end;$$;
create trigger pos_line_snapshot before insert on public.pos_order_lines for each row execute function pos_private.snapshot_line();
create function pos_private.save_category(b uuid,p_id uuid,p_name text,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare c uuid;begin perform pos_private.require_access(b,'products');
 if p_id is null then insert into public.pos_categories(business_id,name,active) values(b,trim(p_name),p_active) returning id into c;
 else update public.pos_categories set name=trim(p_name),active=p_active where business_id=b and id=p_id returning id into c;if c is null then raise exception 'Kategori tidak ditemukan';end if;
 update public.pos_products set category=trim(p_name) where business_id=b and category_id=c;end if;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'category.saved',c);return c;end;$$;
create function pos_private.save_product_v2(b uuid,p_id uuid,p_name text,p_category_id uuid,p_price bigint,p_cost bigint,p_stock integer,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.pos_categories;p uuid;begin perform pos_private.require_access(b,'products');select * into c from public.pos_categories where business_id=b and id=p_category_id;
 if not found or not c.active then raise exception 'Pilih kategori aktif';end if;
 p:=pos_private.save_product(b,p_id,p_name,c.name,p_price,p_stock,p_active);
 update public.pos_products set category_id=c.id,purchase_cost=p_cost where business_id=b and id=p;return p;end;$$;
create function pos_private.save_print_config(b uuid,p_logo text,p_width integer,p_sections jsonb) returns void language plpgsql security definer set search_path='' as $$
declare item jsonb;cat text;begin perform pos_private.require_access(b,'settings');
 if p_logo is null or length(p_logo)>280000 or (p_logo<>'' and p_logo!~'^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$') then raise exception 'Logo harus PNG/JPEG/WebP maksimal 200 KB';end if;
 if p_sections is null or jsonb_typeof(p_sections)<>'array' or jsonb_array_length(p_sections)>20 then raise exception 'Section printer tidak valid';end if;
 for item in select * from jsonb_array_elements(p_sections) loop
 if length(trim(item->>'name')) not between 1 and 40 or (item->>'width')::integer not in (58,80) or jsonb_typeof(item->'categories')<>'array' then raise exception 'Isi section tidak valid';end if;
 for cat in select jsonb_array_elements_text(item->'categories') loop
 if not exists(select 1 from public.pos_categories where business_id=b and id=cat::uuid) then raise exception 'Kategori section tidak sesuai bisnis';end if;
 end loop;end loop;
 update public.pos_businesses set logo_data=p_logo,receipt_width=p_width,print_sections=p_sections where id=b;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'print.config.updated',b);end;$$;
create function public.pos_save_category(b uuid,p_id uuid,p_name text,p_active boolean) returns uuid language sql security invoker set search_path='' as $$select pos_private.save_category(b,p_id,p_name,p_active)$$;
create function public.pos_save_product_v2(b uuid,p_id uuid,p_name text,p_category_id uuid,p_price bigint,p_cost bigint,p_stock integer,p_active boolean) returns uuid language sql security invoker set search_path='' as $$select pos_private.save_product_v2(b,p_id,p_name,p_category_id,p_price,p_cost,p_stock,p_active)$$;
create function public.pos_save_print_config(b uuid,p_logo text,p_width integer,p_sections jsonb) returns void language sql security invoker set search_path='' as $$select pos_private.save_print_config(b,p_logo,p_width,p_sections)$$;
revoke all on function pos_private.snapshot_line(),pos_private.save_category(uuid,uuid,text,boolean),pos_private.save_product_v2(uuid,uuid,text,uuid,bigint,bigint,integer,boolean),pos_private.save_print_config(uuid,text,integer,jsonb) from public,anon;
grant execute on function pos_private.save_category(uuid,uuid,text,boolean),pos_private.save_product_v2(uuid,uuid,text,uuid,bigint,bigint,integer,boolean),pos_private.save_print_config(uuid,text,integer,jsonb) to authenticated;
revoke all on function public.pos_save_category(uuid,uuid,text,boolean),public.pos_save_product_v2(uuid,uuid,text,uuid,bigint,bigint,integer,boolean),public.pos_save_print_config(uuid,text,integer,jsonb) from public,anon;
grant execute on function public.pos_save_category(uuid,uuid,text,boolean),public.pos_save_product_v2(uuid,uuid,text,uuid,bigint,bigint,integer,boolean),public.pos_save_print_config(uuid,text,integer,jsonb) to authenticated;
