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
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product'),'qty',1),jsonb_build_object('id',p,'qty',2)),'dinein',current_setting('test.table')::uuid,'Refund guest','',null);perform set_config('test.order',o::text,true);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.order')::uuid;q jsonb;r uuid;k uuid:=gen_random_uuid();l uuid;begin
 q:=public.pos_checkout_quote(b,o,current_setting('test.discount')::uuid);
 perform public.pos_pay_order_v3(b,o,current_setting('test.discount')::uuid,jsonb_build_array(jsonb_build_object('method','cash','amount',(q->>'total')::bigint,'tendered',(q->>'total')::bigint)));
 select id into l from public.pos_order_lines where order_id=o and product_id=current_setting('test.product')::uuid;perform set_config('test.line',l::text,true);
 r:=public.pos_request_refund(b,o,k,array[l],'Customer cancelled meal',true);perform set_config('test.refund',r::text,true);
 if public.pos_request_refund(b,o,k,array[l],'Retry request',true)<>r then raise exception 'request not idempotent';end if;
 begin perform public.pos_request_refund(b,o,gen_random_uuid(),array[l],'Duplicate pending',true);raise exception 'pending duplicate accepted';exception when others then if sqlerrm not like 'Pesanan masih%' then raise;end if;end;
 begin perform public.pos_complete_refund(b,r,'cash','');raise exception 'unapproved completion';exception when others then if sqlerrm not like 'Refund memerlukan%' then raise;end if;end;
 begin perform public.pos_review_refund(b,r,true,'');raise exception 'cashier self approved';exception when insufficient_privilege then null;end;
 begin update public.pos_refund_requests set status='approved' where id=r;raise exception 'direct update allowed';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);
do $$begin
 if exists(select 1 from public.pos_refund_requests where business_id=current_setting('test.biz')::uuid) then raise exception 'waiter read refund';end if;
 begin perform public.pos_request_refund(current_setting('test.biz')::uuid,current_setting('test.order')::uuid,gen_random_uuid(),array[current_setting('test.line')::uuid],'Waiter bypass',false);raise exception 'waiter requested refund';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
select public.pos_review_refund(current_setting('test.biz')::uuid,current_setting('test.refund')::uuid,true,'Approved');
select public.pos_review_refund(current_setting('test.biz')::uuid,current_setting('test.refund')::uuid,true,'Retry');
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.order')::uuid;r uuid:=current_setting('test.refund')::uuid;l uuid;next uuid;begin
 begin perform public.pos_request_refund(b,o,gen_random_uuid(),array[current_setting('test.line')::uuid],'Overlap approved',true);raise exception 'overlap accepted';exception when others then if sqlerrm not like 'Item sudah%' then raise;end if;end;
 perform public.pos_complete_refund(b,r,'cash','');perform public.pos_complete_refund(b,r,'cash','');
 if (select stock from public.pos_products where id=current_setting('test.product')::uuid)<>10 then raise exception 'duplicate restock';end if;
 select id into l from public.pos_order_lines where order_id=o and product_id=current_setting('test.product2')::uuid;perform set_config('test.line2',l::text,true);
 next:=public.pos_request_refund(b,o,gen_random_uuid(),array[l],'Coffee unavailable',false);perform set_config('test.next',next::text,true);
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
do $$begin
 begin perform public.pos_review_refund(current_setting('test.biz')::uuid,current_setting('test.next')::uuid,false,'');raise exception 'empty rejection accepted';exception when others then if sqlerrm not like 'Isi catatan penolakan%' then raise;end if;end;
 perform public.pos_review_refund(current_setting('test.biz')::uuid,current_setting('test.next')::uuid,false,'Incorrect selection');
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
select set_config('test.final',public.pos_request_refund(current_setting('test.biz')::uuid,current_setting('test.order')::uuid,gen_random_uuid(),array[current_setting('test.line2')::uuid],'Coffee unavailable',false)::text,true);
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
select public.pos_review_refund(current_setting('test.biz')::uuid,current_setting('test.final')::uuid,true,'Confirmed');
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.order')::uuid;r uuid:=current_setting('test.final')::uuid;begin
 begin perform public.pos_complete_refund(b,r,'qr','');raise exception 'empty reference accepted';exception when others then if sqlerrm not like 'Isi metode%' then raise;end if;end;
 perform public.pos_complete_refund(b,r,'qr','REFUND-TEST');
 if (select sum(amount) from public.pos_refund_requests where order_id=o and status='completed')<>(select total from public.pos_orders where id=o) then raise exception 'allocated total mismatch';end if;
 if (select sum(net_amount) from public.pos_refund_requests where order_id=o and status='completed')<>(select subtotal-discount_amount from public.pos_orders where id=o) then raise exception 'discount allocation mismatch';end if;
 if (select stock from public.pos_products where id=current_setting('test.product2')::uuid)<>8 then raise exception 'unrequested restock';end if;
 if not exists(select 1 from public.pos_orders where id=o and status='paid') then raise exception 'original invoice changed';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);
do $$begin
 if exists(select 1 from public.pos_refund_requests where business_id=current_setting('test.biz')::uuid) then raise exception 'tenant leak';end if;
 begin perform public.pos_review_refund(current_setting('test.biz')::uuid,current_setting('test.refund')::uuid,true,'Intrusion');raise exception 'outsider approved';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.pos_request_refund(uuid,uuid,uuid,uuid[],text,boolean)','execute') then raise exception 'anonymous request';end if;
end$$;
select 'PASS: tenant/role restrictions, owner decisions, required reasons, retry/overlap protection, partial-to-full exact fee allocations, refund recording and optional exactly-once stock return' result;
rollback;
