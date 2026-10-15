begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.cashier',gen_random_uuid()::text,true),set_config('test.waiter',gen_random_uuid()::text,true),set_config('test.outside',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'reduce-owner@example.invalid'),(current_setting('test.cashier')::uuid,'reduce-cashier@example.invalid'),(current_setting('test.waiter')::uuid,'reduce-waiter@example.invalid'),(current_setting('test.outside')::uuid,'reduce-outside@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;c uuid;p uuid;o uuid;l uuid;j jsonb;req uuid:=gen_random_uuid();r uuid;begin
 b:=public.pos_create_business('Reduction integration','Retail','#087f6c');perform set_config('test.biz',b::text,true);
 perform public.pos_restaurant_settings(b,false,false,'123456');c:=public.pos_save_category(b,null,'Drinks',true);p:=public.pos_save_product_v2(b,null,'Coffee',c,1001,500,30,true);perform set_config('test.product',p::text,true);
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',3)),'takeaway',null,'','',null);perform set_config('test.order',o::text,true);select id into l from public.pos_order_lines where order_id=o;perform set_config('test.line',l::text,true);
 j:=public.pos_reduce_order_line(b,o,l,1,req,'000000','Customer changed quantity');if (j->>'ok')::boolean then raise exception 'wrong PIN accepted';end if;
 if (select qty from public.pos_order_lines where id=l)<>3 or exists(select 1 from public.pos_order_adjustments where order_id=o) then raise exception 'wrong PIN mutated bill';end if;
 j:=public.pos_reduce_order_line(b,o,l,1,req,'123456','Customer changed quantity');if not (j->>'ok')::boolean then raise exception 'valid reduce failed %',j;end if;
 if (select qty from public.pos_order_lines where id=l)<>2 or (select total from public.pos_orders where id=o)<>2002 or (select stock from public.pos_products where id=p)<>28 then raise exception 'quantity/totals/stock incorrect';end if;
 j:=public.pos_reduce_order_line(b,o,l,1,req,'123456','Customer changed quantity');if (select count(*) from public.pos_order_adjustments where order_id=o)<>1 or (select stock from public.pos_products where id=p)<>28 then raise exception 'reduction retry duplicated';end if;
 perform public.pos_pay_order_v3(b,o,null,'[{"method":"cash","amount":2002,"tendered":2002,"reference":""}]');
 j:=public.pos_request_refund_v2(b,o,gen_random_uuid(),jsonb_build_array(jsonb_build_object('line_id',l,'qty',1)),'000000','One coffee unavailable',true);if (j->>'ok')::boolean then raise exception 'paid wrong PIN accepted';end if;
 j:=public.pos_request_refund_v2(b,o,gen_random_uuid(),jsonb_build_array(jsonb_build_object('line_id',l,'qty',1)),'123456','One coffee unavailable',true);r:=(j->>'id')::uuid;perform set_config('test.refund',r::text,true);
 if (select amount from public.pos_refund_requests where id=r)<>1001 or (select total from public.pos_orders where id=o)<>2002 or (select qty from public.pos_order_lines where id=l)<>2 then raise exception 'original invoice altered';end if;
 begin perform public.pos_complete_refund(b,r,'cash','');raise exception 'refund completed without approval';exception when others then if sqlerrm<>'Refund memerlukan approval owner' then raise;end if;end;
 begin perform public.pos_request_refund(b,o,gen_random_uuid(),array[l],'PIN bypass',false);raise exception 'legacy PIN bypass';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.cashier')::uuid,'cashier',array['pos','orders','pay']),(current_setting('test.biz')::uuid,current_setting('test.waiter')::uuid,'waiter',array['pos','orders']);
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);set local role authenticated;
do $$begin
 begin perform public.pos_review_refund(current_setting('test.biz')::uuid,current_setting('test.refund')::uuid,true,'');raise exception 'cashier self-approved';exception when insufficient_privilege then null;end;
 if not exists(select 1 from public.pos_order_adjustments where business_id=current_setting('test.biz')::uuid) then raise exception 'cashier log hidden';end if;
 begin update public.pos_order_adjustments set qty_removed=9;raise exception 'log tampered';exception when insufficient_privilege then null;end;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid:=current_setting('test.biz')::uuid;o uuid:=current_setting('test.order')::uuid;l uuid:=current_setting('test.line')::uuid;r uuid:=current_setting('test.refund')::uuid;j jsonb;begin
 perform public.pos_review_refund(b,r,true,'Approved unavailable item');perform public.pos_complete_refund(b,r,'cash','');perform public.pos_complete_refund(b,r,'cash','');
 if (select stock from public.pos_products where id=current_setting('test.product')::uuid)<>29 then raise exception 'refund restock repeated';end if;
 j:=public.pos_request_refund_v2(b,o,gen_random_uuid(),jsonb_build_array(jsonb_build_object('line_id',l,'qty',1)),'123456','Last coffee unavailable',false);r:=(j->>'id')::uuid;perform public.pos_review_refund(b,r,true,'');perform public.pos_complete_refund(b,r,'cash','');
 if (select sum(amount) from public.pos_refund_requests where order_id=o and status='completed')<>2002 then raise exception 'partial refunds do not conserve total';end if;
 begin perform public.pos_request_refund_v2(b,o,gen_random_uuid(),jsonb_build_array(jsonb_build_object('line_id',l,'qty',1)),'123456','Over refund attempt',false);raise exception 'over-refund accepted';exception when others then if sqlerrm<>'Quantity exceeds remaining items' then raise;end if;end;
 -- Full open removal is also represented by one immutable zero-remaining event.
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',current_setting('test.product')::uuid,'qty',1)),'takeaway',null,'','',null);select id into l from public.pos_order_lines where order_id=o;
 j:=public.pos_reduce_order_line(b,o,l,1,gen_random_uuid(),'123456','Customer cancelled item');if not (j->>'ok')::boolean or not exists(select 1 from public.pos_order_adjustments where order_id=o and qty_after=0) then raise exception 'full reduction missing';end if;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);set local role authenticated;
do $$begin
 begin perform public.pos_reduce_order_line(current_setting('test.biz')::uuid,current_setting('test.order')::uuid,current_setting('test.line')::uuid,1,gen_random_uuid(),'123456','Waiter denied');raise exception 'waiter reduced';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pos_order_adjustments) then raise exception 'waiter viewed finance logs';end if;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.outside'),true);set local role authenticated;
do $$begin
 begin perform public.pos_request_refund_v2(current_setting('test.biz')::uuid,current_setting('test.order')::uuid,gen_random_uuid(),'[]','123456','Outside attempt',false);raise exception 'outside refund';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pos_order_adjustments) then raise exception 'outside viewed logs';end if;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid:=current_setting('test.biz')::uuid;p uuid:=current_setting('test.product')::uuid;o uuid;l uuid;d uuid;r uuid;j jsonb;q jsonb;total_expected bigint;i integer;begin
 perform public.pos_save_charges(b,721,333,true);
 d:=public.pos_save_discount(b,null,'Rounding discount','fixed',101,0,null,now()-interval '1 day',now()+interval '1 day',true);
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',3)),'takeaway',null,'','',null);select id into l from public.pos_order_lines where order_id=o;
 q:=public.pos_checkout_quote(b,o,d);total_expected:=(q->>'total')::bigint;
 perform public.pos_pay_order_v3(b,o,d,jsonb_build_array(jsonb_build_object('method','cash','amount',total_expected,'tendered',total_expected,'reference','')));
 for i in 1..3 loop
 j:=public.pos_request_refund_v2(b,o,gen_random_uuid(),jsonb_build_array(jsonb_build_object('line_id',l,'qty',1)),'123456','Rounding test refund',false);r:=(j->>'id')::uuid;perform public.pos_review_refund(b,r,true,'');perform public.pos_complete_refund(b,r,'cash','');
 end loop;
 if (select sum(amount) from public.pos_refund_requests where order_id=o and status='completed')<>total_expected then raise exception 'discount fee rounding lost money';end if;
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',3)),'takeaway',null,'','',null);select id into l from public.pos_order_lines where order_id=o;
 total_expected:=(select total from public.pos_orders where id=o);
 j:=public.pos_reduce_order_line(b,o,l,1,gen_random_uuid(),'123456','Fee recalculation test');
 if (select total from public.pos_orders where id=o)+(select amount from public.pos_order_adjustments where order_id=o)<>total_expected then raise exception 'open fee reduction not conserved';end if;
 for i in 1..5 loop j:=public.pos_reduce_order_line(b,o,l,1,gen_random_uuid(),'000000','PIN failure test');if (j->>'ok')::boolean then raise exception 'bad PIN accepted';end if;end loop;
 j:=public.pos_reduce_order_line(b,o,l,1,gen_random_uuid(),'123456','Throttle test');if (j->>'ok')::boolean or j->>'error' not like 'Batas percobaan%' then raise exception 'PIN throttling bypassed';end if;
end$$;
rollback;
