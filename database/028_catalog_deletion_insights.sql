-- Remove products from the catalogue while retaining foreign keys and financial history.
alter table public.pos_products add column deleted_at timestamptz;
create index pos_products_catalog_idx on public.pos_products(business_id,category_id) where deleted_at is null;
create function pos_private.delete_product(b uuid,p_product uuid) returns void language plpgsql security definer set search_path='' as $$
declare root public.pos_products;begin
 perform pos_private.require_access(b,'products');
 select * into root from public.pos_products where business_id=b and id=p_product and deleted_at is null for update;
 if not found then raise exception 'Product not found';end if;
 update public.pos_products set active=false,deleted_at=clock_timestamp(),category_id=null,photo_data='',photo_updated_at=null where business_id=b and (id=root.id or parent_product_id=root.id) and deleted_at is null;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'product.deleted',root.id);
end$$;
create function pos_private.deleted_product_guard() returns trigger language plpgsql set search_path='' as $$begin
 if old.deleted_at is not null and (to_jsonb(new)-'stock') is distinct from (to_jsonb(old)-'stock') then raise exception 'Deleted product cannot be edited';end if;return new;
end$$;
create trigger pos_deleted_product_guard before update on public.pos_products for each row execute function pos_private.deleted_product_guard();
create function pos_private.delete_category(b uuid,p_category uuid) returns void language plpgsql security definer set search_path='' as $$begin
 perform pos_private.require_access(b,'products');
 perform 1 from public.pos_categories where business_id=b and id=p_category for update;if not found then raise exception 'Category not found';end if;
 if exists(select 1 from public.pos_products where business_id=b and category_id=p_category) then raise exception 'Category must be empty';end if;
 delete from public.pos_categories where business_id=b and id=p_category;
 -- Remove obsolete category routing, retaining section/printer configuration.
 update public.pos_businesses set print_sections=(select coalesce(jsonb_agg(jsonb_set(s,'{categories}',(select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(coalesce(s->'categories','[]'::jsonb)) x where x#>>'{}'<>p_category::text))),'[]'::jsonb) from jsonb_array_elements(print_sections) s) where id=b;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'category.deleted',p_category);
end$$;
create function public.pos_delete_product(b uuid,p_product uuid) returns void language sql security invoker set search_path='' as $$select pos_private.delete_product(b,p_product)$$;
create function public.pos_delete_category(b uuid,p_category uuid) returns void language sql security invoker set search_path='' as $$select pos_private.delete_category(b,p_category)$$;
create function pos_private.product_performance(b uuid,p_from date,p_to date,p_category uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tz text;lo timestamptz;hi timestamptz;top_products jsonb;no_sales jsonb;begin
 if not (pos_private.allowed(b,'reports') or pos_private.allowed(b,'dashboard') or pos_private.allowed(b,'pay')) then raise exception 'Report access denied' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 then raise exception 'Choose a valid date range of up to 366 days';end if;
 select timezone into tz from public.pos_businesses where id=b;
 lo:=p_from::timestamp at time zone tz;hi:=(p_to+1)::timestamp at time zone tz;
 with sold as (
 select coalesce(p.parent_product_id,p.id) id,max(coalesce(root.name,p.name,l.name)) name,max(coalesce(root.category_id,p.category_id,l.category_id)::text)::uuid category_id,sum(l.qty) qty,sum(l.price*l.qty-l.discount_amount) revenue
 from public.pos_order_lines l join public.pos_orders o on o.id=l.order_id and o.business_id=b join public.pos_products p on p.id=l.product_id and p.business_id=b left join public.pos_products root on root.id=p.parent_product_id and root.business_id=b
 where o.status='paid' and o.paid_at>=lo and o.paid_at<hi and l.voided_at is null and (p_category is null or l.category_id=p_category)
 group by coalesce(p.parent_product_id,p.id)
 ), ranked as(select * from sold order by qty desc,revenue desc,name,id limit 5)
 select coalesce(jsonb_agg(to_jsonb(r) order by qty desc,revenue desc,name,id),'[]'::jsonb) into top_products from ranked r;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category_id',p.category_id) order by p.name,p.id),'[]'::jsonb) into no_sales from public.pos_products p
 where p.business_id=b and p.active and p.deleted_at is null and p.parent_product_id is null and (p_category is null or p.category_id=p_category)
 and not exists(select 1 from public.pos_order_lines l join public.pos_orders o on o.id=l.order_id join public.pos_products v on v.id=l.product_id and v.business_id=b where o.business_id=b and o.status='paid' and o.paid_at>=lo and o.paid_at<hi and l.voided_at is null and coalesce(v.parent_product_id,v.id)=p.id and (p_category is null or l.category_id=p_category));
 return jsonb_build_object('top',top_products,'unsold',no_sales);
end$$;
create function public.pos_product_performance(b uuid,p_from date,p_to date,p_category uuid default null) returns jsonb language sql security invoker set search_path='' as $$select pos_private.product_performance(b,p_from,p_to,p_category)$$;
revoke all on function pos_private.delete_product(uuid,uuid),pos_private.deleted_product_guard(),pos_private.delete_category(uuid,uuid),pos_private.product_performance(uuid,date,date,uuid),public.pos_delete_product(uuid,uuid),public.pos_delete_category(uuid,uuid),public.pos_product_performance(uuid,date,date,uuid) from public,anon,authenticated;
grant execute on function pos_private.delete_product(uuid,uuid),pos_private.delete_category(uuid,uuid),pos_private.product_performance(uuid,date,date,uuid),public.pos_delete_product(uuid,uuid),public.pos_delete_category(uuid,uuid),public.pos_product_performance(uuid,date,date,uuid) to authenticated;
