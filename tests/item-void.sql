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

select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid:=current_setting('test.biz')::uuid;p uuid;o uuid;begin
 p:=public.pos_save_product_v2(b,null,'Coffee',(select category_id from public.pos_products where id=current_setting('test.product')::uuid),30001,10000,10,true);perform set_config('test.product2',p::text,true);
 perform public.pos_save_print_config(b,'',58,jsonb_build_array(jsonb_build_object('name','Kitchen','width',58,'categories',jsonb_build_array((select category_id from public.pos_products where id=p)))));
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1),jsonb_build_object('id',p,'qty',2)),'dinein',current_setting('test.table')::uuid,'Guest','',null);perform set_config('test.order',o::text,true);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.order')::uuid;l uuid;r jsonb;beforetotal bigint;begin
 select id into l from public.pos_order_lines where order_id=o and product_id=current_setting('test.product')::uuid;perform set_config('test.line',l::text,true);select total into beforetotal from public.pos_orders where id=o;
 r:=public.pos_void_line(b,o,l,'111111','Ingredient unavailable');if (r->>'ok')::boolean then raise exception 'wrong PIN accepted';end if;
 if (select total from public.pos_orders where id=o)<>beforetotal then raise exception 'wrong PIN changed total';end if;
 r:=public.pos_void_line(b,o,l,'246810','Ingredient unavailable');if not (r->>'ok')::boolean then raise exception 'valid PIN denied';end if;
 perform public.pos_void_line(b,o,l,'246810','Retry operation');
 if (select stock from public.pos_products where id=current_setting('test.product')::uuid)<>10 then raise exception 'duplicate restock';end if;
 if (select total from public.pos_orders where id=o)<>69302 or (select subtotal from public.pos_orders where id=o)<>60002 then raise exception 'fee recalculation failed';end if;
 if exists(select 1 from public.pos_print_jobs j,jsonb_array_elements(j.payload->'items') x where j.order_id=o and j.status='queued' and x->>'product_id'=current_setting('test.product')) then raise exception 'void remains on pending kitchen ticket';end if;
 perform public.pos_cancel_order_v2(b,o,'246810','Whole bill cancelled');
 if (select stock from public.pos_products where id=current_setting('test.product')::uuid)<>10 or (select stock from public.pos_products where id=current_setting('test.product2')::uuid)<>10 then raise exception 'whole cancel double restored line';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
do $$declare o uuid;begin
 o:=public.pos_place_order_v4(current_setting('test.biz')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1),jsonb_build_object('id',current_setting('test.product2'),'qty',2)),'dinein',current_setting('test.table')::uuid,'Guest 2','',null);perform set_config('test.next',o::text,true);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.next')::uuid;l uuid;q jsonb;good uuid;begin
 select id into l from public.pos_order_lines where order_id=o and product_id=current_setting('test.product')::uuid;
 perform public.pos_ack_print(b,(select id from public.pos_print_jobs where order_id=o limit 1));
 perform public.pos_void_line(b,o,l,'246810','Customer cancelled item');
 if not exists(select 1 from public.pos_print_jobs where order_id=o and status='queued' and payload->>'kind'='void') then raise exception 'printed ticket correction missing';end if;
 q:=public.pos_checkout_quote(b,o,current_setting('test.discount')::uuid);perform public.pos_pay_order_v3(b,o,current_setting('test.discount')::uuid,jsonb_build_array(jsonb_build_object('method','qr','amount',(q->>'total')::bigint)));
 if (select sum(discount_amount) from public.pos_order_lines where order_id=o and voided_at is null)<>6000 then raise exception 'discount allocated to voided line';end if;
 begin perform public.pos_request_refund(b,o,gen_random_uuid(),array[l],'Refund voided line',false);raise exception 'voided line refund accepted';exception when others then if sqlerrm not like 'Pilih item refund%' then raise;end if;end;
 select id into good from public.pos_order_lines where order_id=o and voided_at is null;
 perform public.pos_request_refund(b,o,gen_random_uuid(),array[good],'Refund remaining item',false);
 if (select amount from public.pos_refund_requests where order_id=o)<>(select total from public.pos_orders where id=o) then raise exception 'refund allocation after void wrong';end if;
 begin perform public.pos_void_line(b,o,good,'246810','Paid line void');raise exception 'paid line directly voided';exception when others then if sqlerrm not like 'Item Complete%' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid;l record;begin
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1),jsonb_build_object('id',current_setting('test.product2'),'qty',1)),'dinein',current_setting('test.table')::uuid,'All void','',null);
 for l in select id from public.pos_order_lines where order_id=o loop perform public.pos_void_line(b,o,l.id,'246810','All items cancelled');end loop;
 if not exists(select 1 from public.pos_orders where id=o and status='cancelled') then raise exception 'last item did not release bill';end if;
 perform public.pos_cancel_order_v2(b,o,'246810','Retry cancel');
 if (select stock from public.pos_products where id=current_setting('test.product')::uuid)<>10 or (select stock from public.pos_products where id=current_setting('test.product2')::uuid)<>8 then raise exception 'all item restore incorrect';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$begin
 begin perform public.pos_void_line(current_setting('test.biz')::uuid,current_setting('test.next')::uuid,current_setting('test.line')::uuid,'246810','Waiter void');raise exception 'waiter void';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);
do $$begin
 begin perform public.pos_void_line(current_setting('test.biz')::uuid,current_setting('test.next')::uuid,current_setting('test.line')::uuid,'246810','Outsider void');raise exception 'tenant void';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.pos_void_line(uuid,uuid,uuid,text,text)','execute') then raise exception 'anonymous line void';end if;
end$$;
select 'PASS: line PIN/role/tenant checks, exactly-once stock return, fee/discount recalculation, kitchen pending/correction tickets, whole-cancel skip and paid-refund boundaries' result;
rollback;
