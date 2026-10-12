begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.other',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'realtime-owner@example.invalid'),(current_setting('test.other')::uuid,'realtime-other@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;p uuid;n integer;begin
 b:=public.pos_create_business('Realtime test','Retail','#087f6c');perform set_config('test.biz',b::text,true);
 p:=public.pos_save_product(b,null,'Test','Retail',1000,5,true);perform public.pos_save_product(b,p,'Test 2','Retail',2000,5,true);
 select count(*) into n from public.pos_realtime_events where business_id=b;if n<>1 then raise exception 'change not deduplicated per transaction';end if;
 begin insert into public.pos_realtime_events(business_id,transaction_key) values(b,'forged');raise exception 'client event injection';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.other'),true);
do $$begin if exists(select 1 from public.pos_realtime_events where business_id=current_setting('test.biz')::uuid) then raise exception 'tenant event leak';end if;end$$;
reset role;
select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pos_realtime_events') as published;
set local role anon;
do $$begin begin perform 1 from public.pos_realtime_events;raise exception 'anonymous event read';exception when insufficient_privilege then null;end;end$$;
select 'PASS: transaction-deduplicated event, tenant read isolation, direct-write/anonymous denial and replication publication' result;
rollback;
