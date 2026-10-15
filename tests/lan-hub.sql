begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.waiter',gen_random_uuid()::text,true),set_config('test.cashier',gen_random_uuid()::text,true),set_config('test.outside',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'lan-owner@example.invalid'),(current_setting('test.waiter')::uuid,'lan-waiter@example.invalid'),(current_setting('test.cashier')::uuid,'lan-cashier@example.invalid'),(current_setting('test.outside')::uuid,'lan-outside@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;a uuid;t uuid;c uuid;p uuid;h uuid:=gen_random_uuid();j jsonb;d jsonb;begin
 b:=public.pos_create_business('LAN Hub integration','Restaurant','#087f6c');perform set_config('test.biz',b::text,true);
 perform public.pos_save_charges(b,0,0,false);perform public.pos_restaurant_settings(b,true,true,'123456');
 a:=public.pos_save_area(b,null,'Ground',true);t:=public.pos_save_table(b,null,a,'T1',4,1,1,true);c:=public.pos_save_category(b,null,'Drinks',true);p:=public.pos_save_product_v2(b,null,'Coffee',c,1000,400,10,true);
 j:=public.pos_register_lan_hub(b,h,'Integration Hub');perform set_config('test.hub',h::text,true);perform set_config('test.secret',j->>'secret',true);
 d:=jsonb_build_object('hub',h,'business',b,'id',gen_random_uuid(),'actor',current_setting('test.waiter'),'device',gen_random_uuid(),'kind','order','createdAt',now()-interval '1 hour','payload',jsonb_build_object('type','dinein','table',t,'guest','LAN Guest','note','Offline WiFi order','reservation',null,'tax_bps',0,'service_bps',0,'tax_on_service',false,'expected_total',2000,'lines',jsonb_build_array(jsonb_build_object('id',p,'qty',2,'price',1000,'note','No sugar'))));
 d:=jsonb_set(d,'{payload,request}',d->'id');perform set_config('test.document',d::text,true);perform set_config('test.product',p::text,true);
end$$;
reset role;
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.waiter')::uuid,'waiter',array['pos','orders']),(current_setting('test.biz')::uuid,current_setting('test.cashier')::uuid,'cashier',array['pos','orders','pay']);
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);set local role authenticated;
do $$declare doc text:=current_setting('test.document');sig text;result jsonb;o uuid;begin
 perform set_config('test.shift',public.pos_open_shift(current_setting('test.biz')::uuid,gen_random_uuid(),50000)::text,true);
 sig:=encode(extensions.hmac(convert_to(doc,'UTF8'),decode(current_setting('test.secret'),'hex'),'sha256'),'hex');
 begin perform public.pos_sync_lan_command(doc,repeat('0',64));raise exception 'fake signature accepted';exception when insufficient_privilege then null;end;
 result:=public.pos_sync_lan_command(doc,sig);o:=(result->>'order_id')::uuid;perform set_config('test.order',o::text,true);
 if result->>'proof'<>encode(extensions.hmac(convert_to('ack:'||doc||':'||o::text,'UTF8'),decode(current_setting('test.secret'),'hex'),'sha256'),'hex') then raise exception 'ack proof mismatch';end if;
 perform public.pos_sync_lan_command(doc,sig);
 if (select count(*) from public.pos_orders where business_id=current_setting('test.biz')::uuid)<>1 or (select stock from public.pos_products where id=current_setting('test.product')::uuid)<>8 then raise exception 'LAN retry duplicated stock/order';end if;
 if not exists(select 1 from public.pos_orders where id=o and created_by=current_setting('test.waiter')::uuid and created_role='waiter' and client_created_at is not null) then raise exception 'waiter identity lost';end if;
 begin perform public.pos_register_lan_hub(current_setting('test.biz')::uuid,gen_random_uuid(),'Unauthorized Hub');raise exception 'cashier registered Hub';exception when insufficient_privilege then null;end;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare d jsonb;doc text;sig text;j jsonb;o uuid:=current_setting('test.order')::uuid;begin
 d:=jsonb_build_object('hub',current_setting('test.hub'),'business',current_setting('test.biz'),'id',gen_random_uuid(),'actor',current_setting('test.cashier'),'device',gen_random_uuid(),'kind','cash','createdAt',now()-interval '45 minutes','payload',jsonb_build_object('order_request',current_setting('test.document')::jsonb->>'id','expected_total',2000,'tendered',2500));
 doc:=d::text;sig:=encode(extensions.hmac(convert_to(doc,'UTF8'),decode(current_setting('test.secret'),'hex'),'sha256'),'hex');perform public.pos_sync_lan_command(doc,sig);perform public.pos_sync_lan_command(doc,sig);
 if not exists(select 1 from public.pos_payments where order_id=o and paid_by=current_setting('test.cashier')::uuid and shift_id=current_setting('test.shift')::uuid and change=500) or (select count(*) from public.pos_payments where order_id=o)<>1 then raise exception 'cashier attribution/shift/dedup failed';end if;
 d:=jsonb_set(d,'{id}',to_jsonb(gen_random_uuid()::text));doc:=d::text;sig:=encode(extensions.hmac(convert_to(doc,'UTF8'),decode(current_setting('test.secret'),'hex'),'sha256'),'hex');
 begin perform public.pos_sync_lan_command(doc,sig);raise exception 'second payment accepted';exception when others then if sqlerrm<>'Bill berubah atau sudah dibayar. Periksa kas Hub' then raise;end if;end;
 perform public.pos_disable_lan_hub(current_setting('test.biz')::uuid,current_setting('test.hub')::uuid);
 begin perform public.pos_sync_lan_command(current_setting('test.document'),encode(extensions.hmac(convert_to(current_setting('test.document'),'UTF8'),decode(current_setting('test.secret'),'hex'),'sha256'),'hex'));raise exception 'disabled Hub accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.outside'),true);set local role authenticated;
do $$begin
 begin perform public.pos_sync_lan_command(current_setting('test.document'),repeat('0',64));raise exception 'outsider accepted';exception when insufficient_privilege then null;end;
 begin perform count(*) from pos_private.lan_hubs;raise exception 'Hub secret exposed';exception when insufficient_privilege then null;end;
end$$;
rollback;
