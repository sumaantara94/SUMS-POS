begin;
select set_config('pos.test.owner',gen_random_uuid()::text,true),set_config('pos.test.waiter',gen_random_uuid()::text,true),set_config('pos.test.outsider',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('pos.test.owner')::uuid,'pos-test-owner@example.invalid'),(current_setting('pos.test.waiter')::uuid,'pos-test-waiter@example.invalid'),(current_setting('pos.test.outsider')::uuid,'pos-test-outsider@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('pos.test.owner'),true);
set local role authenticated;
do $$declare b uuid;p uuid;o uuid;r uuid;v integer;begin
 b:=public.pos_create_business('Test business','Retail','#087f6c');perform set_config('pos.test.business',b::text,true);
 p:=public.pos_save_product(b,null,'Test product','Retail',28000,3,true);perform set_config('pos.test.product',p::text,true);
 r:=gen_random_uuid();o:=public.pos_place_order(b,r,jsonb_build_array(jsonb_build_object('id',p,'qty',2)),'dinein','04','');
 if public.pos_place_order(b,r,jsonb_build_array(jsonb_build_object('id',p,'qty',2)),'dinein','04','')<>o then raise exception 'idempotency failed';end if;
 select stock into v from public.pos_products where id=p;if v<>1 then raise exception 'stock failed';end if;
 begin perform public.pos_place_order(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',2)),'dinein','','');raise exception 'oversell accepted';exception when others then if sqlerrm='oversell accepted' then raise;end if;end;
 begin perform public.pos_pay_order(b,o,100);raise exception 'underpayment accepted';exception when others then if sqlerrm='underpayment accepted' then raise;end if;end;
 perform public.pos_pay_order(b,o,300000);perform public.pos_pay_order(b,o,300000);
 select count(*) into v from public.pos_payments where order_id=o;if v<>1 then raise exception 'double payment';end if;
 o:=public.pos_place_order(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',1)),'takeaway','','');perform public.pos_cancel_order(b,o);perform public.pos_cancel_order(b,o);
 select stock into v from public.pos_products where id=p;if v<>1 then raise exception 'double release';end if;
 perform public.pos_set_member(b,'pos-test-waiter@example.invalid','waiter','{}',true);
 begin update public.pos_products set price=1 where id=p;raise exception 'direct mutation accepted';exception when insufficient_privilege then null;end;
end;$$;
select set_config('request.jwt.claim.sub',current_setting('pos.test.waiter'),true);
do $$declare b uuid:=current_setting('pos.test.business')::uuid;p uuid:=current_setting('pos.test.product')::uuid;o uuid;begin
 o:=public.pos_place_order(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',1)),'dinein','','');
 begin perform public.pos_pay_order(b,o,28000);raise exception 'waiter paid';exception when insufficient_privilege then null;end;
 begin perform public.pos_set_member(b,'pos-test-outsider@example.invalid','custom',array['pay'],true);raise exception 'waiter added member';exception when insufficient_privilege then null;end;
end;$$;
select set_config('request.jwt.claim.sub',current_setting('pos.test.outsider'),true);
do $$declare b uuid:=current_setting('pos.test.business')::uuid;v integer;begin
 select count(*) into v from public.pos_orders where business_id=b;if v<>0 then raise exception 'tenant leak';end if;
 select count(*) into v from public.pos_products where business_id=b;if v<>0 then raise exception 'catalog leak';end if;
 begin perform public.pos_place_order(b,gen_random_uuid(),'[]','dinein','','');raise exception 'outsider created order';exception when insufficient_privilege then null;end;
end;$$;
select 'PASS: tenant isolation, price snapshots, stock reserve/release, duplicate requests/payments, role enforcement, direct-write denial' as result;
rollback;
