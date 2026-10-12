-- Keep table IDs/history while making quantity/capacity and layout edits atomic.
alter table public.pos_tables drop constraint pos_tables_map_slot_key;
alter table public.pos_tables add constraint pos_tables_map_slot_key unique(area_id,x,y) deferrable initially immediate;
create function pos_private.configure_tables(b uuid,p_area uuid,p_tables jsonb) returns void language plpgsql security definer set search_path='' as $$
declare entry jsonb;tid uuid;kept uuid[]:='{}';resolved jsonb:='[]';slot integer;begin
 perform pos_private.require_owner(b);
 perform 1 from public.pos_areas where business_id=b and id=p_area for update;
 if not found then raise exception 'Area tidak ditemukan';end if;
 if p_tables is null or jsonb_typeof(p_tables)<>'array' or jsonb_array_length(p_tables)>144 then raise exception 'Jumlah meja maksimal 144 per area';end if;
 if exists(select 1 from jsonb_array_elements(p_tables) e group by trim(e->>'name') having count(*)>1) then raise exception 'Nama meja tidak boleh sama';end if;
 for entry in select value from jsonb_array_elements(p_tables) loop
  if length(trim(coalesce(entry->>'name',''))) not between 1 and 40 or coalesce(entry->>'capacity','') !~ '^[0-9]+$' or (entry->>'capacity')::numeric not between 1 and 100 then raise exception 'Isi nama dan kapasitas meja 1–100';end if;
  tid:=nullif(entry->>'id','')::uuid;
  if tid is not null then
   perform 1 from public.pos_tables where business_id=b and area_id=p_area and id=tid for update;
   if not found then raise exception 'Meja tidak ditemukan di area ini';end if;
  else
   -- Name lookup makes a repeated save after a network timeout reuse new tables.
   select id into tid from public.pos_tables where business_id=b and area_id=p_area and name=trim(entry->>'name') for update;
  end if;
  if tid=any(kept) then raise exception 'Meja duplikat';end if;
  if tid is not null then kept:=array_append(kept,tid);end if;
  resolved:=resolved||jsonb_build_array(entry||jsonb_build_object('id',tid));
 end loop;
 -- Do not remove a table currently serving an open order.
 if exists(select 1 from public.pos_tables t join public.pos_orders o on o.business_id=t.business_id and o.table_id=t.id and o.status='open' where t.business_id=b and t.area_id=p_area and not(t.id=any(kept))) then raise exception 'Meja dengan pesanan aktif tidak bisa dikurangi';end if;
 update public.pos_tables set active=false where business_id=b and area_id=p_area and not(id=any(kept));
 for entry in select value from jsonb_array_elements(resolved) loop
  tid:=nullif(entry->>'id','')::uuid;
  if tid is not null then
   update public.pos_tables set name=trim(entry->>'name'),capacity=(entry->>'capacity')::integer,active=true where business_id=b and id=tid;
  else
   select s into slot from generate_series(0,143) s where not exists(select 1 from public.pos_tables where business_id=b and area_id=p_area and x=(s%12)+1 and y=(s/12)+1) order by s limit 1;
   if slot is null then raise exception 'Area sudah memiliki 144 meja. Aktifkan kembali meja yang nonaktif';end if;
   insert into public.pos_tables(business_id,area_id,name,capacity,x,y,active) values(b,p_area,trim(entry->>'name'),(entry->>'capacity')::integer,(slot%12)+1,(slot/12)+1,true);
  end if;
 end loop;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'tables.configured',p_area);
end$$;
create function pos_private.move_table(b uuid,p_table uuid,p_x integer,p_y integer) returns void language plpgsql security definer set search_path='' as $$
declare t public.pos_tables;other uuid;area uuid;begin
 perform pos_private.require_owner(b);
 if p_x is null or p_y is null or p_x not between 1 and 12 or p_y not between 1 and 12 then raise exception 'Posisi meja tidak valid';end if;
 select area_id into area from public.pos_tables where business_id=b and id=p_table;
 if area is null then raise exception 'Meja tidak ditemukan';end if;
 perform 1 from public.pos_areas where business_id=b and id=area for update;
 select * into t from public.pos_tables where business_id=b and id=p_table for update;
 if t.area_id<>area then raise exception 'Area meja telah berubah. Muat ulang';end if;
 select id into other from public.pos_tables where business_id=b and area_id=area and x=p_x and y=p_y and id<>p_table for update;
 set constraints public.pos_tables_map_slot_key deferred;
 update public.pos_tables set x=p_x,y=p_y where business_id=b and id=t.id;
 if other is not null then update public.pos_tables set x=t.x,y=t.y where business_id=b and id=other;end if;
 set constraints public.pos_tables_map_slot_key immediate;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'table.moved',t.id);
end$$;
create function public.pos_configure_tables(b uuid,p_area uuid,p_tables jsonb) returns void language sql security invoker set search_path='' as $$select pos_private.configure_tables(b,p_area,p_tables)$$;
create function public.pos_move_table(b uuid,p_table uuid,p_x integer,p_y integer) returns void language sql security invoker set search_path='' as $$select pos_private.move_table(b,p_table,p_x,p_y)$$;
revoke all on function pos_private.configure_tables(uuid,uuid,jsonb),pos_private.move_table(uuid,uuid,integer,integer),public.pos_configure_tables(uuid,uuid,jsonb),public.pos_move_table(uuid,uuid,integer,integer) from public,anon;
grant execute on function pos_private.configure_tables(uuid,uuid,jsonb),pos_private.move_table(uuid,uuid,integer,integer),public.pos_configure_tables(uuid,uuid,jsonb),public.pos_move_table(uuid,uuid,integer,integer) to authenticated;
