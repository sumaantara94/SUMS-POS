begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.waiter',gen_random_uuid()::text,true),set_config('test.cashier',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'trace-owner@example.invalid'),(current_setting('test.waiter')::uuid,'trace-waiter@example.invalid'),(current_setting('test.cashier')::uuid,'trace-cashier@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;a uuid;t uuid;c uuid;p uuid;begin
 b:=public.pos_create_business('Trace test','Restaurant','#087f6c');perform set_config('test.biz',b::text,true);a:=public.pos_save_area(b,null,'Front',true);t:=public.pos_save_table(b,null,a,'1',2,1,1,true);perform set_config('test.table',t::text,true);
 c:=public.pos_save_category(b,null,'Meals',true);p:=public.pos_save_product_v3(b,null,'Test meal',c,10000,5000,5,true,'data:image/jpeg;base64,YWJj');perform set_config('test.product',p::text,true);
 if not exists(select 1 from public.pos_products where id=p and photo_data<>'' and photo_updated_at is not null) then raise exception 'photo not stored';end if;
 begin perform public.pos_save_product_v3(b,p,'Unsafe',c,10000,5000,5,true,'data:image/svg+xml;base64,YWJj');raise exception 'unsafe photo accepted';exception when others then if sqlerrm='unsafe photo accepted' then raise;end if;end;
 if not exists(select 1 from public.pos_products where id=p and name='Test meal') then raise exception 'bad photo partially saved';end if;
 perform public.pos_restaurant_settings(b,true,true,'246810');
end$$;
reset role;
insert into public.pos_staff_accounts(user_id,business_id,created_by,name,username) values(current_setting('test.waiter')::uuid,current_setting('test.biz')::uuid,current_setting('test.owner')::uuid,'Waiter Test','trace.waiter'),(current_setting('test.cashier')::uuid,current_setting('test.biz')::uuid,current_setting('test.owner')::uuid,'Cashier Test','trace.cashier');
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.waiter')::uuid,'waiter',array['pos','orders']),(current_setting('test.biz')::uuid,current_setting('test.cashier')::uuid,'cashier',array['pos','orders','pay']);
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);set local role authenticated;
do $$declare o uuid;begin
 o:=public.pos_place_order_v3(current_setting('test.biz')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1,'note','Less spicy')),'dinein',current_setting('test.table')::uuid,'Guest','');perform set_config('test.order',o::text,true);
 if not exists(select 1 from public.pos_orders where id=o and created_by_name='Waiter Test' and created_role='waiter') then raise exception 'waiter snapshot wrong';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
select public.pos_pay_order_v3(current_setting('test.biz')::uuid,current_setting('test.order')::uuid,null,jsonb_build_array(jsonb_build_object('method','cash','amount',10000,'tendered',10000)));
do $$begin if not exists(select 1 from public.pos_payments where order_id=current_setting('test.order')::uuid and paid_by_name='Cashier Test') then raise exception 'cashier snapshot wrong';end if;end$$;
reset role;
update public.pos_staff_accounts set name='Renamed waiter' where user_id=current_setting('test.waiter')::uuid;
set local role authenticated;
do $$declare o uuid;r jsonb;begin
 if not exists(select 1 from public.pos_orders where id=current_setting('test.order')::uuid and created_by_name='Waiter Test') then raise exception 'historical name changed';end if;
 o:=public.pos_place_order_v3(current_setting('test.biz')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',current_setting('test.table')::uuid,'Next','');r:=public.pos_cancel_order_v2(current_setting('test.biz')::uuid,o,'246810','Guest cancelled');
 if not (r->>'ok')::boolean or not exists(select 1 from public.pos_orders where id=o and cancelled_by_name='Cashier Test' and cancelled_at is not null and cancel_reason='Guest cancelled') then raise exception 'cancel actor trace failed';end if;
end$$;
select 'PASS: photo persistence and safe types, atomic rejection, waiter/cashier/cancel actor snapshots and rename stability' result;
rollback;
