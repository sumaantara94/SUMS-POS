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
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;t uuid:=current_setting('test.table')::uuid;begin
 begin perform public.pos_reserve_table(b,t,'Waiter',null,true);raise exception 'waiter released reservation';exception when insufficient_privilege then null;end;
 begin perform public.pos_place_order_v3(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',t,'Guest','');raise exception 'reserved table seated';exception when others then if sqlerrm='reserved table seated' or sqlerrm not like 'Meja masih direservasi%' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
select public.pos_reserve_table(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,null,null,true);
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$declare o uuid;begin
 o:=public.pos_place_order_v3(current_setting('test.biz')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',current_setting('test.table')::uuid,'Guest','');perform set_config('test.order',o::text,true);
 if not exists(select 1 from public.pos_orders where id=o and total=115500 and tax_amount=10500 and service_amount=5000) then raise exception 'order charge snapshot failed';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
select public.pos_save_charges(current_setting('test.biz')::uuid,0,0,false);
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.order')::uuid;d uuid:=current_setting('test.discount')::uuid;q jsonb;begin
 q:=public.pos_checkout_quote(b,o,d);if (q->>'total')::bigint<>103950 or (q->>'tax')::bigint<>9450 then raise exception 'quote wrong or changed historical rate';end if;
 begin perform public.pos_reserve_table(b,current_setting('test.table')::uuid,'Other',null,false);raise exception 'reserved occupied table';exception when others then if sqlerrm='reserved occupied table' or sqlerrm not like 'Meja masih memiliki open bill%' then raise;end if;end;
 begin perform public.pos_pay_order_v3(b,o,d,jsonb_build_array(jsonb_build_object('method','cash','amount',40000,'tendered',50000)));raise exception 'incomplete split accepted';exception when others then if sqlerrm='incomplete split accepted' then raise;end if;end;
 if exists(select 1 from public.pos_payments where order_id=o) then raise exception 'partial payment committed';end if;
 perform public.pos_pay_order_v3(b,o,d,jsonb_build_array(jsonb_build_object('method','cash','amount',40000,'tendered',50000),jsonb_build_object('method','credit_card','amount',63950,'reference','TEST-REFERENCE')));
 perform public.pos_pay_order_v3(b,o,null,'[]');
 if (select count(*) from public.pos_payments where order_id=o)<>2 or (select sum(amount) from public.pos_payments where order_id=o)<>103950 or (select sum(change) from public.pos_payments where order_id=o)<>10000 then raise exception 'split duplicate or totals wrong';end if;
 if not exists(select 1 from public.pos_orders where id=o and status='paid' and total=103950 and service_amount=4500 and discount_amount=10000) then raise exception 'paid totals wrong';end if;
 if not pos_private.allowed(b,'reports') then raise exception 'cashier reports denied';end if;
 if has_function_privilege('authenticated','public.pos_pay_order_v2(uuid,uuid,bigint,uuid)','execute') then raise exception 'legacy tax bypass';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$declare o uuid;begin
 o:=public.pos_place_order_v3(current_setting('test.biz')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',current_setting('test.table')::uuid,'Next guest','');perform set_config('test.next',o::text,true);
 if pos_private.allowed(current_setting('test.biz')::uuid,'reports') then raise exception 'waiter reports granted';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$begin perform public.pos_pay_order_v3(current_setting('test.biz')::uuid,current_setting('test.next')::uuid,null,jsonb_build_array(jsonb_build_object('method','qr','amount',100000,'reference','QR-TEST')));end$$;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);
do $$begin
 begin perform public.pos_reserve_table(current_setting('test.biz')::uuid,current_setting('test.table')::uuid,'Intrusion',null,false);raise exception 'outsider reservation accepted';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pos_payments where business_id=current_setting('test.biz')::uuid) then raise exception 'payment tenant leak';end if;
end$$;
select 'PASS: cashier reservation, waiter block, open bill block, release/reseat, immutable fee rates, discounted tax/service, atomic split/cash change, QR, report access and tenant isolation' result;
rollback;
