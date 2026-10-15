begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.cashier',gen_random_uuid()::text,true),set_config('test.waiter',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'cash-owner@example.invalid'),(current_setting('test.cashier')::uuid,'cashier-cash@example.invalid'),(current_setting('test.waiter')::uuid,'cash-waiter@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;s uuid:=gen_random_uuid();e uuid:=gen_random_uuid();c uuid;p uuid;o uuid;j jsonb;r uuid;l uuid;begin
 b:=public.pos_create_business('Cash operations tests','Retail','#087f6c');perform set_config('test.biz',b::text,true);
 perform public.pos_restaurant_settings(b,false,false,'123456');perform public.pos_save_charges(b,0,0,false);
 c:=public.pos_save_category(b,null,'Drinks',true);p:=public.pos_save_product_v2(b,null,'Coffee',c,1000,500,20,true);
 perform public.pos_open_shift(b,s,100000);perform public.pos_open_shift(b,s,100000);
 begin perform public.pos_open_shift(b,gen_random_uuid(),50000);raise exception 'two shifts accepted';exception when others then if sqlerrm<>'Masih ada shift terbuka' then raise;end if;end;
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',p,'qty',2)),'takeaway',null,'','',null);
 perform public.pos_pay_order_v3(b,o,null,'[{"method":"cash","amount":1000,"tendered":5000},{"method":"qr","amount":1000}]');
 -- Expected uses applied cash, not tendered cash, and excludes QR.
 j:=public.pos_operations_summary(b);if (j->'current_shift'->>'expected_now')::bigint<>101000 then raise exception 'cash/QR/change incorrect';end if;
 perform public.pos_cash_entry(b,e,'expense','cash',10000,'Purchase cleaning materials');perform public.pos_cash_entry(b,e,'expense','cash',10000,'Purchase cleaning materials');
 begin perform public.pos_cash_entry(b,e,'expense','cash',11000,'Purchase cleaning materials');raise exception 'altered retry accepted';exception when others then if sqlerrm<>'Cash entry request mismatch' then raise;end if;end;
 perform public.pos_cash_entry(b,gen_random_uuid(),'expense','bank',25000,'Online electricity payment');
 perform public.pos_cash_entry(b,gen_random_uuid(),'cash_in','cash',50000,'Additional float from owner');
 perform public.pos_cash_entry(b,gen_random_uuid(),'cash_out','cash',5000,'Owner cash withdrawal');
 j:=public.pos_operations_summary(b);if (j->'current_shift'->>'expected_now')::bigint<>136000 then raise exception 'cash movements wrong %',j;end if;
 select id into l from public.pos_order_lines where order_id=o;
 j:=public.pos_request_refund_v2(b,o,gen_random_uuid(),jsonb_build_array(jsonb_build_object('line_id',l,'qty',1)),'123456','Unavailable coffee refund',true);r:=(j->>'id')::uuid;
 perform public.pos_review_refund(b,r,true,'');perform public.pos_complete_refund(b,r,'cash','');
 j:=public.pos_operations_summary(b);if (j->'current_shift'->>'expected_now')::bigint<>135000 then raise exception 'cash refund not subtracted %',j;end if;
 begin perform public.pos_close_shift(b,s,134000,'');raise exception 'variance without reason accepted';exception when others then if sqlerrm<>'Isi alasan selisih kas (minimal 3 karakter)' then raise;end if;end;
 j:=public.pos_close_shift(b,s,134000,'Cash counted short');if (j->>'difference')::bigint<>-1000 then raise exception 'variance wrong';end if;
 perform public.pos_close_shift(b,s,134000,'Cash counted short');
 begin perform public.pos_cash_entry(b,gen_random_uuid(),'expense','cash',1000,'Closed shift expense');raise exception 'closed cash allowed';exception when others then if sqlerrm<>'Buka shift sebelum mencatat uang tunai' then raise;end if;end;
 perform set_config('test.shift',s::text,true);
end$$;
reset role;
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.cashier')::uuid,'cashier',array['pos','orders','pay']),(current_setting('test.biz')::uuid,current_setting('test.waiter')::uuid,'waiter',array['pos','orders']);
select set_config('request.jwt.claim.sub',current_setting('test.cashier'),true);set local role authenticated;
do $$declare j jsonb;begin
 j:=public.pos_operations_summary(current_setting('test.biz')::uuid);if jsonb_array_length(j->'shifts')<>0 or jsonb_array_length(j->'entries')<>0 then raise exception 'cashier read other staff ledger';end if;
 begin perform public.pos_close_shift(current_setting('test.biz')::uuid,current_setting('test.shift')::uuid,0,'other staff');raise exception 'other shift closed';exception when others then if sqlerrm<>'Shift tidak ditemukan' then raise;end if;end;
 begin update public.pos_shifts set opening_cash=0;raise exception 'direct mutation allowed';exception when insufficient_privilege then null;end;
end$$;
reset role;select set_config('request.jwt.claim.sub',current_setting('test.waiter'),true);set local role authenticated;
do $$begin
 begin perform public.pos_open_shift(current_setting('test.biz')::uuid,gen_random_uuid(),0);raise exception 'waiter shift accepted';exception when insufficient_privilege then null;end;
end$$;
rollback;
