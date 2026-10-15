begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.cashier',gen_random_uuid()::text,true),set_config('test.outside',gen_random_uuid()::text,true),set_config('test.waiter',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'offline-owner@example.invalid'),(current_setting('test.cashier')::uuid,'offline-cashier@example.invalid'),(current_setting('test.outside')::uuid,'offline-outside@example.invalid'),(current_setting('test.waiter')::uuid,'offline-waiter@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;c uuid;p uuid;j jsonb;d uuid:=gen_random_uuid();r uuid:=gen_random_uuid();pay uuid:=gen_random_uuid();payload jsonb;created timestamptz:=now()-interval '1 hour';o uuid;begin
 b:=public.pos_create_business('Offline integration','Retail','#087f6c');perform set_config('test.biz',b::text,true);
 perform public.pos_save_charges(b,0,0,false);c:=public.pos_save_category(b,null,'Drinks',true);p:=public.pos_save_product_v2(b,null,'Coffee',c,1000,500,10,true);
 perform set_config('test.product',p::text,true);perform set_config('test.device',d::text,true);perform set_config('test.request',r::text,true);
 payload:=jsonb_build_object('request',r,'lines',jsonb_build_array(jsonb_build_object('id',p,'qty',2,'price',1000)),'type','takeaway','tax_bps',0,'service_bps',0,'tax_on_service',false,'expected_total',2000);perform set_config('test.payload',payload::text,true);
 j:=public.pos_sync_device_command(b,r,d,'order',payload,created);o:=(j->>'order_id')::uuid;perform set_config('test.order',o::text,true);
 j:=public.pos_sync_device_command(b,r,d,'order',payload,created);
 if not (j->>'duplicate')::boolean or (select stock from public.pos_products where id=p)<>8 or (select count(*) from public.pos_orders where business_id=b)<>1 then raise exception 'retry duplicated stock/order';end if;
 begin perform public.pos_sync_device_command(b,r,d,'order',jsonb_set(payload,'{expected_total}','1000'),created);raise exception 'changed retry accepted';exception when others then if sqlerrm<>'Request does not match original transaction' then raise;end if;end;
 payload:=jsonb_build_object('order_request',r,'expected_total',2000,'tendered',2500);
 j:=public.pos_sync_device_command(b,pay,d,'cash',payload,created);j:=public.pos_sync_device_command(b,pay,d,'cash',payload,created);
 if (select count(*) from public.pos_payments where order_id=o)<>1 or (select change from public.pos_payments where order_id=o)<>500 then raise exception 'cash retry duplicated';end if;
 if not exists(select 1 from public.pos_orders where id=o and offline_device_id=d and client_created_at=created and status='paid') then raise exception 'offline trace missing';end if;
 begin perform public.pos_sync_device_command(b,gen_random_uuid(),d,'cash',payload,created);raise exception 'second cash accepted';exception when others then if sqlerrm<>'Bill changed or already paid. Owner review required' then raise;end if;end;
 -- Rejected price/total/stock commands must leave no partial orders, tickets or reservations.
 r:=gen_random_uuid();payload:=jsonb_build_object('request',r,'lines',jsonb_build_array(jsonb_build_object('id',p,'qty',1,'price',999)),'type','takeaway','tax_bps',0,'service_bps',0,'tax_on_service',false,'expected_total',999);
 begin perform public.pos_sync_device_command(b,r,d,'order',payload,created);raise exception 'price changed accepted';exception when others then if sqlerrm<>'Product/price changed. Owner review required' then raise;end if;end;
 payload:=jsonb_set(jsonb_set(payload,'{lines,0,price}','1000'),'{expected_total}','999');
 begin perform public.pos_sync_device_command(b,r,d,'order',payload,created);raise exception 'bad total accepted';exception when others then if sqlerrm<>'Order total changed. Owner review required' then raise;end if;end;
 if (select stock from public.pos_products where id=p)<>8 or exists(select 1 from public.pos_orders where business_id=b and request_id=r) then raise exception 'rejected total changed stock';end if;
 payload:=jsonb_set(jsonb_set(payload,'{lines,0,qty}','99'),'{expected_total}','99000');
 begin perform public.pos_sync_device_command(b,r,d,'order',payload,created);raise exception 'oversell accepted';exception when others then if sqlerrm='oversell accepted' then raise;end if;end;
 if (select stock from public.pos_products where id=p)<>8 then raise exception 'stock conflict mutated stock';end if;
end$$;
reset role;
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.cashier')::uuid,'cashier',array['pos','orders','pay']),(current_setting('test.biz')::uuid,current_setting('test.waiter')::uuid,'waiter',array['pos','orders']);
select set_config('request.jwt.claim.sub',current_setting('test.outside'),true);set local role authenticated;
do $$begin
 begin perform public.pos_sync_device_command(current_setting('test.biz')::uuid,gen_random_uuid(),gen_random_uuid(),'order','{}',now());raise exception 'outsider accepted';exception when insufficient_privilege then null;end;
 begin perform count(*) from pos_private.device_commands;raise exception 'private ledger exposed';exception when insufficient_privilege then null;end;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);set local role authenticated;
do $$begin
 begin perform public.pos_sync_device_command(current_setting('test.biz')::uuid,gen_random_uuid(),gen_random_uuid(),'cash','{}',now());raise exception 'waiter cash accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);set local role authenticated;
do $$begin
 begin perform public.pos_sync_device_command(current_setting('test.biz')::uuid,current_setting('test.request')::uuid,current_setting('test.device')::uuid,'order',current_setting('test.payload')::jsonb,now()-interval '1 hour');raise exception 'another actor adopted request';exception when others then if sqlerrm<>'Request does not match original transaction' then raise;end if;end;
end$$;
reset role;
update public.pos_memberships set active=false where business_id=current_setting('test.biz')::uuid and user_id=current_setting('test.cashier')::uuid;
set local role authenticated;
do $$begin
 begin perform public.pos_sync_device_command(current_setting('test.biz')::uuid,gen_random_uuid(),gen_random_uuid(),'order','{}',now());raise exception 'revoked actor accepted';exception when insufficient_privilege then null;end;
end$$;
rollback;
