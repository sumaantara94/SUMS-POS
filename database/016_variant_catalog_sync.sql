create function pos_private.sync_variant_catalog() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.parent_product_id is null then update public.pos_products set name=left(new.name,37)||' / '||variant_label,category=new.category,category_id=new.category_id,purchase_cost=new.purchase_cost where business_id=new.business_id and parent_product_id=new.id;end if;return new;
end$$;
create trigger pos_sync_variant_catalog after update of name,category,category_id,purchase_cost on public.pos_products for each row execute function pos_private.sync_variant_catalog();
revoke all on function pos_private.sync_variant_catalog() from public,anon,authenticated;
