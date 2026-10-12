begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.cashier',gen_random_uuid()::text,true),set_config('test.waiter',gen_random_uuid()::text,true),set_config('test.outsider',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'newops-owner@example.invalid'),(current_setting('test.cashier')::uuid,'newops-cashier@example.invalid'),(current_setting('test.waiter')::uuid,'newops-waiter@example.invalid'),(current_setting('test.outsider')::uuid,'newops-outsider@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;a uuid;t uuid;c uuid;p uuid;d uuid;begin
 b:=public.pos_create_business('Operations test','Restaurant','#087f6c');perform set_config('test.biz',b::text,true);a:=public.pos_save_area(b,null,'Front',true);t:=public.pos_save_table(b,null,a,'1',4,1,1,true);perform set_config('test.table',t::text,true);
 c:=public.pos_save_category(b,null,'Meals',true);p:=public.pos_save_product_v2(b,null,'Meal',c,100000,30000,10,true);perform set_config('test.product',p::text,true);
 perform public.pos_restaurant_settings(b,true,true,'246810');perform public.pos_save_charges(b,1000,500,true);d:=public.pos_save_discount(b,null,'10%','percent',10,0,null,now()-interval '1 hour',now()+interval '1 hour',true);perform set_config('test.discount',d::text,true);
end$$;
reset role;
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.cashier')::uuid,'cashier',array['pos','orders','pay']),(current_setting('test.biz')::uuid,current_setting('test.waiter')::uuid,'waiter',array['pos','orders']);

select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);set local role authenticated;
select public.pos_reserve_table(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,'Reserved guest',now()+interval '1 hour',false);
select set_config('test.oldstamp',(select reserved_at::text from public.pos_tables where id=current_setting('test.table')::uuid),true);
select public.pos_edit_reservation(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,'Arriving guest',now()+interval '2 hours',current_setting('test.oldstamp')::timestamptz);
select set_config('test.stamp',(select reserved_at::text from public.pos_tables where id=current_setting('test.table')::uuid),true);
do $$begin
 if not exists(select 1 from public.pos_tables where id=current_setting('test.table')::uuid and reservation_guest='Arriving guest' and reserved_for=now()+interval '2 hours') then raise exception 'edit failed';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;t uuid:=current_setting('test.table')::uuid;p uuid:=current_setting('test.product')::uuid;o uuid;r uuid:=gen_random_uuid();begin
 begin perform public.pos_edit_reservation(b,t,'Intrusion',null,current_setting('test.stamp')::timestamptz);raise exception 'waiter edited reservation';exception when insufficient_privilege then null;end;
 begin perform public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',1)),'dinein',t,'Arriving guest','',current_setting('test.oldstamp')::timestamptz);raise exception 'stale reservation claimed';exception when others then if sqlerrm not like 'Reservasi telah berubah%' then raise;end if;end;
 begin perform public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',11)),'dinein',t,'Arriving guest','',current_setting('test.stamp')::timestamptz);raise exception 'oversold';exception when others then if sqlerrm='oversold' then raise;end if;end;
 if not exists(select 1 from public.pos_tables where id=t and reserved_at=current_setting('test.stamp')::timestamptz) then raise exception 'failed order released reservation';end if;
 o:=public.pos_place_order_v4(b,r,jsonb_build_array(jsonb_build_object('id',p,'qty',1,'note','No spice')),'dinein',t,'Arriving guest','',current_setting('test.stamp')::timestamptz);
 if public.pos_place_order_v4(b,r,'[]','dinein',t,'Arriving guest','',current_setting('test.stamp')::timestamptz)<>o then raise exception 'retry duplicated';end if;
 if (select reserved_at from public.pos_tables where id=t) is not null then raise exception 'reservation not consumed';end if;
 if not exists(select 1 from public.pos_orders where id=o and status='open' and table_id=t and guest_name='Arriving guest' and created_role='waiter') then raise exception 'reserved seating order failed';end if;
 if (select stock from public.pos_products where id=p)<>9 then raise exception 'stock or retry wrong';end if;
 begin perform public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',1)),'dinein',t,'Second','',null);raise exception 'occupied table accepted';exception when others then if sqlerrm not like 'Meja sedang digunakan%' then raise;end if;end;
 perform set_config('test.order',o::text,true);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
select public.pos_pay_order_v3(current_setting('test.biz')::uuid,current_setting('test.order')::uuid,null,jsonb_build_array(jsonb_build_object('method','qr','amount',115500)));
select public.pos_reserve_table(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,'Cancel guest',null,false);
select set_config('test.cancelstamp',(select reserved_at::text from public.pos_tables where id=current_setting('test.table')::uuid),true);
select public.pos_reserve_table(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,null,null,true);
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$begin
 begin perform public.pos_place_order_v4(current_setting('test.biz')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',current_setting('test.table')::uuid,'Cancel guest','',current_setting('test.cancelstamp')::timestamptz);raise exception 'cancelled reservation claimed';exception when others then if sqlerrm not like 'Reservasi telah berubah%' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);
do $$begin
 begin perform public.pos_edit_reservation(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,'Intrusion',null,null);raise exception 'outsider edited';exception when insufficient_privilege then null;end;
 begin perform public.pos_place_order_v4(current_setting('test.biz')::uuid,gen_random_uuid(),'[]','dinein',current_setting('test.table')::uuid,'Intrusion','',null);raise exception 'outsider ordered';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.pos_place_order_v4(uuid,uuid,jsonb,text,uuid,text,text,timestamptz)','execute') then raise exception 'anonymous endpoint access';end if;
end$$;
select 'PASS: edit time/name, waiter denial for edits, stale/cancelled reservation rejection, failed order rollback, atomic reserved seating, open bill lock, idempotency and tenant isolation' result;
rollback;
