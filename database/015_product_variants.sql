alter table public.pos_products add column parent_product_id uuid,add column variant_label text check(variant_label is null or length(trim(variant_label)) between 1 and 40),add foreign key(business_id,parent_product_id) references public.pos_products(business_id,id),add constraint pos_variant_not_self check(parent_product_id is distinct from id),add constraint pos_variant_label_required check((parent_product_id is null)=(variant_label is null)),add constraint pos_variant_unique unique(parent_product_id,variant_label);
create index pos_products_parent_idx on public.pos_products(business_id,parent_product_id);
create function pos_private.save_variants(b uuid,p_product uuid,p_variants jsonb) returns void language plpgsql security definer set search_path='' as $$declare root public.pos_products;e jsonb;v uuid;kept uuid[]:='{}';begin
 perform pos_private.require_access(b,'products');select * into root from public.pos_products where business_id=b and id=p_product for update;
 if not found or root.parent_product_id is not null then raise exception 'Pilih produk utama';end if;
 if p_variants is null or jsonb_typeof(p_variants)<>'array' or jsonb_array_length(p_variants)>30 then raise exception 'Maksimal 30 varian per produk';end if;
 for e in select value from jsonb_array_elements(p_variants) loop
  v:=nullif(e->>'id','')::uuid;
  if v is not null then
   perform 1 from public.pos_products where business_id=b and parent_product_id=root.id and id=v for update;if not found then raise exception 'Varian tidak sesuai produk';end if;
   perform pos_private.save_product(b,v,left(root.name,37)||' / '||trim(e->>'name'),root.category,(e->>'price')::bigint,(e->>'stock')::integer,(e->>'active')::boolean);
   update public.pos_products set variant_label=trim(e->>'name'),category_id=root.category_id,purchase_cost=root.purchase_cost where business_id=b and id=v;
  else
   v:=pos_private.save_product(b,null,left(root.name,37)||' / '||trim(e->>'name'),root.category,(e->>'price')::bigint,(e->>'stock')::integer,(e->>'active')::boolean);
   update public.pos_products set parent_product_id=root.id,variant_label=trim(e->>'name'),category_id=root.category_id,purchase_cost=root.purchase_cost where business_id=b and id=v;
  end if;kept:=array_append(kept,v);
 end loop;
 update public.pos_products set active=false where business_id=b and parent_product_id=root.id and not(id=any(kept));
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'variants.configured',root.id);
end$$;
create function pos_private.variant_line_guard() returns trigger language plpgsql security definer set search_path='' as $$declare p public.pos_products;begin
 select * into p from public.pos_products where business_id=new.business_id and id=new.product_id;
 if p.parent_product_id is null and exists(select 1 from public.pos_products where business_id=p.business_id and parent_product_id=p.id and active) then raise exception 'Pilih varian produk';end if;
 if p.parent_product_id is not null and not exists(select 1 from public.pos_products where business_id=p.business_id and id=p.parent_product_id and active) then raise exception 'Produk utama tidak aktif';end if;
 return new;
end$$;
create trigger pos_variant_order_guard before insert on public.pos_order_lines for each row execute function pos_private.variant_line_guard();
create function public.pos_save_variants(b uuid,p_product uuid,p_variants jsonb) returns void language sql security invoker set search_path='' as $$select pos_private.save_variants(b,p_product,p_variants)$$;
revoke all on function pos_private.save_variants(uuid,uuid,jsonb),pos_private.variant_line_guard(),public.pos_save_variants(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function pos_private.save_variants(uuid,uuid,jsonb),public.pos_save_variants(uuid,uuid,jsonb) to authenticated;
