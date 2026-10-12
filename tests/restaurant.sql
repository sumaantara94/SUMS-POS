begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.waiter',gen_random_uuid()::text,true),set_config('test.cashier',gen_random_uuid()::text,true),set_config('test.outsider',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'restaurant-owner@example.invalid'),(current_setting('test.waiter')::uuid,'restaurant-waiter@example.invalid'),(current_setting('test.cashier')::uuid,'restaurant-cashier@example.invalid'),(current_setting('test.outsider')::uuid,'restaurant-outsider@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;a uuid;t uuid;c uuid;p uuid;d uuid;begin
 b:=public.pos_create_business('Restaurant integration','Restaurant','#087f6c');perform set_config('test.biz',b::text,true);
 a:=public.pos_save_area(b,null,'Rooftop',true);t:=public.pos_save_table(b,null,a,'R1',4,1,1,true);perform set_config('test.table',t::text,true);
 c:=public.pos_save_category(b,null,'Drinks',true);p:=public.pos_save_product_v2(b,null,'Latte',c,30001,12000,10,true);perform set_config('test.product',p::text,true);
 perform public.pos_save_print_config(b,'',58,jsonb_build_array(jsonb_build_object('name','Bar','width',58,'categories',jsonb_build_array(c))));
 perform public.pos_restaurant_settings(b,true,true,'246810');
 d:=public.pos_save_discount(b,null,'Today 15%','percent',15,0,null,now()-interval '1 hour',now()+interval '1 hour',true);perform set_config('test.discount',d::text,true);
end$$;
reset role;
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.waiter')::uuid,'waiter',array['pos','orders']),(current_setting('test.biz')::uuid,current_setting('test.cashier')::uuid,'cashier',array['pos','orders','pay']);
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);set local role authenticated;
do $$declare b uuid:=current_setting('test.biz')::uuid;p uuid:=current_setting('test.product')::uuid;t uuid:=current_setting('test.table')::uuid;o uuid;r uuid:=gen_random_uuid();n integer;begin
 begin perform public.pos_place_order_v3(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',1)),'dinein',null,'','');raise exception 'missing table accepted';exception when others then if sqlerrm='missing table accepted' then raise;end if;end;
 o:=public.pos_place_order_v3(b,r,jsonb_build_array(jsonb_build_object('id',p,'qty',2,'note','No sugar')),'dinein',t,'Suma','Serve together');perform set_config('test.order',o::text,true);
 if public.pos_place_order_v3(b,r,jsonb_build_array(jsonb_build_object('id',p,'qty',2)),'dinein',t,'Suma','')<>o then raise exception 'retry duplicated order';end if;
 select count(*) into n from public.pos_print_jobs where order_id=o;if n<>1 then raise exception 'print routing duplicate or missing';end if;
 if not exists(select 1 from public.pos_print_jobs where order_id=o and payload->'items'->0->>'note'='No sugar') then raise exception 'item note missing from print';end if;
 begin perform public.pos_place_order_v3(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',1)),'dinein',t,'Other','');raise exception 'occupied table accepted';exception when others then if sqlerrm='occupied table accepted' then raise;end if;end;
 begin perform public.pos_pay_order_v2(b,o,60002,null);raise exception 'waiter paid';exception when insufficient_privilege then null;end;
 if has_function_privilege('authenticated','public.pos_place_order(uuid,uuid,jsonb,text,text,text)','execute') then raise exception 'legacy bypass enabled';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.order')::uuid;r jsonb;begin
 begin perform public.pos_cancel_order_v2(b,o,'246810','');raise exception 'empty reason accepted';exception when others then if sqlerrm='empty reason accepted' then raise;end if;end;
 r:=public.pos_cancel_order_v2(b,o,'111111','Wrong item');if (r->>'ok')::boolean then raise exception 'wrong PIN cancelled';end if;
 if not exists(select 1 from public.pos_orders where id=o and status='open') then raise exception 'wrong PIN changed status';end if;
 begin perform public.pos_pay_order_v2(b,o,1,current_setting('test.discount')::uuid);raise exception 'discount underpayment accepted';exception when others then if sqlerrm='discount underpayment accepted' then raise;end if;end;
 if exists(select 1 from public.pos_order_lines where order_id=o and discount_amount<>0) then raise exception 'underpayment left partial discount';end if;
 perform public.pos_pay_order_v2(b,o,60002,current_setting('test.discount')::uuid);
 if not exists(select 1 from public.pos_orders where id=o and total=51002 and discount_amount=9000) then raise exception 'net total wrong';end if;
 if (select sum(discount_amount) from public.pos_order_lines where order_id=o)<>9000 then raise exception 'allocation wrong';end if;
 perform public.pos_pay_order_v2(b,o,0,null);
 if (select count(*) from public.pos_payments where order_id=o)<>1 then raise exception 'duplicate payment';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid;begin
 o:=public.pos_place_order_v3(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',current_setting('test.table')::uuid,'Next guest','');perform set_config('test.cancelorder',o::text,true);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.cancelorder')::uuid;r jsonb;begin
 r:=public.pos_cancel_order_v2(b,o,'246810','Guest left');if not (r->>'ok')::boolean then raise exception 'correct PIN failed: %',r;end if;
 if (select stock from public.pos_products where id=current_setting('test.product')::uuid)<>8 then raise exception 'stock not restored';end if;
 if not exists(select 1 from public.pos_orders where id=o and cancel_reason='Guest left' and status='cancelled') then raise exception 'cancel reason missing';end if;
 if exists(select 1 from public.pos_print_jobs where order_id=o and status='queued') then raise exception 'cancelled order still queued';end if;
 if has_table_privilege('authenticated','pos_private.cancel_config','select') then raise exception 'PIN hash exposed';end if;
end$$;

select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;d uuid;o uuid;begin
 d:=public.pos_save_discount(b,null,'Expired','fixed',100,0,null,now()-interval '2 hours',now()-interval '1 hour',true);
 o:=public.pos_place_order_v3(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',current_setting('test.table')::uuid,'Third guest','');perform set_config('test.throttleorder',o::text,true);
 begin perform public.pos_pay_order_v2(b,o,30001,d);raise exception 'expired discount accepted';exception when others then if sqlerrm='expired discount accepted' then raise;end if;end;
 perform public.pos_restaurant_settings(b,true,false,null);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$begin
 begin perform public.pos_place_order_v3(current_setting('test.biz')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1)),'dinein',current_setting('test.table')::uuid,'Blocked','');raise exception 'disabled waiter accepted';exception when others then if sqlerrm='disabled waiter accepted' or sqlerrm not like 'Mode waiter%' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare r jsonb;i integer;begin
 for i in 1..5 loop r:=public.pos_cancel_order_v2(current_setting('test.biz')::uuid,current_setting('test.throttleorder')::uuid,'000000','PIN test');end loop;
 r:=public.pos_cancel_order_v2(current_setting('test.biz')::uuid,current_setting('test.throttleorder')::uuid,'246810','PIN test');
 if (r->>'ok')::boolean or r->>'error' not like 'Batas percobaan%' then raise exception 'PIN throttle failed';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);
do $$begin
 if exists(select 1 from public.pos_tables where business_id=current_setting('test.biz')::uuid) or exists(select 1 from public.pos_print_jobs where business_id=current_setting('test.biz')::uuid) or exists(select 1 from public.pos_discounts where business_id=current_setting('test.biz')::uuid) then raise exception 'tenant leak';end if;
 begin perform public.pos_save_area(current_setting('test.biz')::uuid,null,'Intrusion',true);raise exception 'outsider configured';exception when insufficient_privilege then null;end;
end$$;
select 'PASS: table/guest enforcement, table occupancy/release, idempotent routing, item notes, waiter/payment permissions, PIN denial/cancel, stock restore, discount totals and tenant isolation' result;
rollback;
