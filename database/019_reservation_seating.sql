create function pos_private.place_order_v4(b uuid,p_request uuid,p_lines jsonb,p_type text,p_table uuid,p_guest text,p_note text,p_reservation_at timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
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
  if t.reserved_at is distinct from p_reservation_at then raise exception 'Reservasi telah berubah. Muat ulang dan pilih meja kembali';end if;
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
 if t.reserved_at is not null then
  update public.pos_tables set reservation_guest=null,reserved_at=null,reserved_for=null,reserved_by=null where business_id=b and id=t.id;
  insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'table.reservation.seated',t.id);
 end if;
 return o;
end$$;

create function public.pos_place_order_v4(b uuid,p_request uuid,p_lines jsonb,p_type text,p_table uuid,p_guest text,p_note text,p_reservation_at timestamptz) returns uuid language sql security invoker set search_path='' as $$select pos_private.place_order_v4(b,p_request,p_lines,p_type,p_table,p_guest,p_note,p_reservation_at)$$;
create function pos_private.edit_reservation(b uuid,p_table uuid,p_guest text,p_time timestamptz,p_expected timestamptz) returns void language plpgsql security definer set search_path='' as $$declare t public.pos_tables;begin
 perform pos_private.require_access(b,'pay');
 select * into t from public.pos_tables where business_id=b and id=p_table for update;
 if not found or t.reserved_at is null then raise exception 'Reservasi tidak ditemukan';end if;
 if p_expected is null or t.reserved_at is distinct from p_expected then raise exception 'Reservasi telah berubah. Muat ulang dan pilih meja kembali';end if;
 if exists(select 1 from public.pos_orders where business_id=b and table_id=t.id and status='open') then raise exception 'Meja masih memiliki open bill';end if;
 if length(trim(coalesce(p_guest,''))) not between 1 and 80 then raise exception 'Isi nama tamu reservasi';end if;
 update public.pos_tables set reservation_guest=trim(p_guest),reserved_for=p_time,reserved_at=clock_timestamp(),reserved_by=auth.uid() where business_id=b and id=t.id;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'table.reservation.updated',t.id);
end$$;
create function public.pos_edit_reservation(b uuid,p_table uuid,p_guest text,p_time timestamptz,p_expected timestamptz) returns void language sql security invoker set search_path='' as $$select pos_private.edit_reservation(b,p_table,p_guest,p_time,p_expected)$$;
revoke all on function pos_private.place_order_v4(uuid,uuid,jsonb,text,uuid,text,text,timestamptz),public.pos_place_order_v4(uuid,uuid,jsonb,text,uuid,text,text,timestamptz),pos_private.edit_reservation(uuid,uuid,text,timestamptz,timestamptz),public.pos_edit_reservation(uuid,uuid,text,timestamptz,timestamptz) from public,anon;
grant execute on function pos_private.place_order_v4(uuid,uuid,jsonb,text,uuid,text,text,timestamptz),public.pos_place_order_v4(uuid,uuid,jsonb,text,uuid,text,text,timestamptz),pos_private.edit_reservation(uuid,uuid,text,timestamptz,timestamptz),public.pos_edit_reservation(uuid,uuid,text,timestamptz,timestamptz) to authenticated;
