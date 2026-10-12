begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.outsider',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'tables-owner@example.invalid'),(current_setting('test.outsider')::uuid,'tables-outsider@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;a uuid;payload jsonb;t1 public.pos_tables;t2 public.pos_tables;t3 uuid;c uuid;p uuid;o uuid;n integer;begin
 b:=public.pos_create_business('Simple table test','Restaurant','#087f6c');a:=public.pos_save_area(b,null,'Front',true);perform set_config('test.biz',b::text,true);perform set_config('test.area',a::text,true);
 select jsonb_agg(jsonb_build_object('id',null,'name','Meja '||i,'capacity',case when i between 3 and 5 then 4 else 2 end) order by i) into payload from generate_series(1,10) i;
 perform public.pos_configure_tables(b,a,payload);perform public.pos_configure_tables(b,a,payload);
 select count(*) into n from public.pos_tables where business_id=b and active;if n<>10 then raise exception 'quantity or retry wrong';end if;
 if (select sum(capacity) from public.pos_tables where business_id=b and active)<>26 then raise exception 'capacity range wrong';end if;
 select * into t1 from public.pos_tables where business_id=b and name='Meja 1';select * into t2 from public.pos_tables where business_id=b and name='Meja 2';
 perform public.pos_move_table(b,t1.id,t2.x,t2.y);
 if not exists(select 1 from public.pos_tables where id=t2.id and x=t1.x and y=t1.y) then raise exception 'swap did not persist';end if;
 perform public.pos_move_table(b,t1.id,8,6);if not exists(select 1 from public.pos_tables where id=t1.id and x=8 and y=6 and capacity=2) then raise exception 'move failed';end if;
 select id into t3 from public.pos_tables where business_id=b and name='Meja 3';
 payload:=jsonb_build_array(jsonb_build_object('id',t1.id,'name',t1.name,'capacity',2),jsonb_build_object('id',t2.id,'name',t2.name,'capacity',2));
 perform public.pos_configure_tables(b,a,payload);
 if (select count(*) from public.pos_tables where business_id=b and active)<>2 or (select count(*) from public.pos_tables where business_id=b)<>10 then raise exception 'reduction lost records or wrong count';end if;
 payload:=payload||jsonb_build_array(jsonb_build_object('id',t3,'name','Meja 3','capacity',4));perform public.pos_configure_tables(b,a,payload);
 perform public.pos_restaurant_settings(b,true,true,'246810');c:=public.pos_save_category(b,null,'Drinks',true);p:=public.pos_save_product_v2(b,null,'Water',c,1000,500,10,true);
 o:=public.pos_place_order_v3(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',1)),'dinein',t3,'Guest','');
 -- Explicit smaller payload must fail without partial deactivation.
 begin perform public.pos_configure_tables(b,a,jsonb_build_array(jsonb_build_object('id',t1.id,'name',t1.name,'capacity',2)));raise exception 'occupied table removed';exception when others then if sqlerrm='occupied table removed' or sqlerrm not like 'Meja dengan pesanan%' then raise;end if;end;
 if not exists(select 1 from public.pos_tables where id=t3 and active) then raise exception 'failed save changed table';end if;
 perform public.pos_move_table(b,t3,9,6);if not exists(select 1 from public.pos_orders where id=o and table_id=t3 and status='open') then raise exception 'layout move changed order';end if;
 perform set_config('test.table',t3::text,true);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);
do $$begin
 begin perform public.pos_configure_tables(current_setting('test.biz')::uuid,current_setting('test.area')::uuid,'[]');raise exception 'outsider batch accepted';exception when insufficient_privilege then null;end;
 begin perform public.pos_move_table(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,1,1);raise exception 'outsider move accepted';exception when insufficient_privilege then null;end;
end$$;
select 'PASS: 10-table batch, per-table capacities, save retries, layout move/swap, IDs preserved, occupied reduction blocked, tenant write denial' result;
rollback;
