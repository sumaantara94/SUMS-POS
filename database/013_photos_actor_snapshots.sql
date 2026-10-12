alter table public.pos_products add column photo_data text not null default '',add column photo_updated_at timestamptz;
alter table public.pos_orders add column created_by_name text,add column created_role text,add column cancelled_by_name text;
alter table public.pos_payments add column paid_by_name text;
create function pos_private.actor_label(u uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce((select name from public.pos_staff_accounts where user_id=u),nullif(trim(raw_user_meta_data->>'full_name'),''),nullif(trim(raw_user_meta_data->>'name'),''),nullif(split_part(email,'@',1),''),'Staf') from auth.users where id=u;
$$;
create function pos_private.order_actor_snapshot() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' then new.created_by_name:=pos_private.actor_label(new.created_by);select role into new.created_role from public.pos_memberships where business_id=new.business_id and user_id=new.created_by;end if;
 if new.cancelled_by is not null and (tg_op='INSERT' or old.cancelled_by is distinct from new.cancelled_by) then new.cancelled_by_name:=pos_private.actor_label(new.cancelled_by);end if;
 return new;
end$$;
create function pos_private.payment_actor_snapshot() returns trigger language plpgsql security definer set search_path='' as $$begin new.paid_by_name:=pos_private.actor_label(new.paid_by);return new;end$$;
create trigger pos_order_actor before insert or update of cancelled_by on public.pos_orders for each row execute function pos_private.order_actor_snapshot();
create trigger pos_payment_actor before insert on public.pos_payments for each row execute function pos_private.payment_actor_snapshot();
update public.pos_orders o set created_by_name=pos_private.actor_label(created_by),created_role=(select role from public.pos_memberships where business_id=o.business_id and user_id=o.created_by),cancelled_by_name=case when cancelled_by is not null then pos_private.actor_label(cancelled_by) end;
update public.pos_payments set paid_by_name=pos_private.actor_label(paid_by);
create function pos_private.save_product_v3(b uuid,p_id uuid,p_name text,p_category_id uuid,p_price bigint,p_cost bigint,p_stock integer,p_active boolean,p_photo text) returns uuid language plpgsql security definer set search_path='' as $$declare p uuid;begin
 perform pos_private.require_access(b,'products');
 if p_photo is null or length(p_photo)>60000 or (p_photo<>'' and p_photo !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$') then raise exception 'Gunakan thumbnail JPEG maksimal 45 KB';end if;
 p:=pos_private.save_product_v2(b,p_id,p_name,p_category_id,p_price,p_cost,p_stock,p_active);
 update public.pos_products set photo_updated_at=case when photo_data is distinct from p_photo then clock_timestamp() else photo_updated_at end,photo_data=p_photo where business_id=b and id=p;return p;
end$$;
create function public.pos_save_product_v3(b uuid,p_id uuid,p_name text,p_category_id uuid,p_price bigint,p_cost bigint,p_stock integer,p_active boolean,p_photo text) returns uuid language sql security invoker set search_path='' as $$select pos_private.save_product_v3(b,p_id,p_name,p_category_id,p_price,p_cost,p_stock,p_active,p_photo)$$;
revoke all on function pos_private.actor_label(uuid),pos_private.order_actor_snapshot(),pos_private.payment_actor_snapshot(),pos_private.save_product_v3(uuid,uuid,text,uuid,bigint,bigint,integer,boolean,text),public.pos_save_product_v3(uuid,uuid,text,uuid,bigint,bigint,integer,boolean,text) from public,anon,authenticated;
grant execute on function pos_private.save_product_v3(uuid,uuid,text,uuid,bigint,bigint,integer,boolean,text),public.pos_save_product_v3(uuid,uuid,text,uuid,bigint,bigint,integer,boolean,text) to authenticated;
