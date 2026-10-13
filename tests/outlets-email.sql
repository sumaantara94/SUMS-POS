begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.staff',gen_random_uuid()::text,true),set_config('test.outsider',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'owner-report@example.invalid'),(current_setting('test.staff')::uuid,'staff-report@example.invalid'),(current_setting('test.outsider')::uuid,'outside-report@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;o uuid;n integer;r record;begin
 b:=public.pos_create_business('Outlet integration','Retail','#087f6c');perform set_config('test.biz',b::text,true);
 o:=public.pos_create_outlet(b,'Second outlet','Test address');perform set_config('test.outlet',o::text,true);
 if not exists(select 1 from public.pos_businesses where id=o and parent_business_id=b and outlet_address='Test address') then raise exception 'outlet metadata missing';end if;
 if not exists(select 1 from public.pos_memberships where business_id=o and user_id=auth.uid() and role='owner') then raise exception 'outlet owner not assigned';end if;
 if exists(select 1 from public.pos_products where business_id=o) then raise exception 'stock copied into outlet';end if;
 begin perform public.pos_create_business('Extra workspace','Retail','#087f6c');raise exception 'workspace gate bypassed';exception when others then if sqlerrm not like 'Workspace tambahan%' then raise;end if;end;
 begin perform public.pos_save_report_settings(b,true,array['invalid'],'08:00');raise exception 'invalid email accepted';exception when others then if sqlerrm not like 'Alamat email%' then raise;end if;end;
 perform public.pos_save_report_settings(b,false,array['Extra@example.invalid','extra@example.invalid'],'08:00');
 if (select cardinality(extra_emails) from public.pos_report_settings where business_id=b)<>1 then raise exception 'recipient dedup failed';end if;
 n:=public.pos_queue_report(b,current_date-1);if n<>2 then raise exception 'queue recipient count';end if;
 if public.pos_queue_report(b,current_date-1)<>0 then raise exception 'queue not idempotent';end if;
 if exists(select 1 from public.pos_report_mail_jobs where business_id=b and payload::text ~ 're_[A-Za-z0-9_-]{16,}') then raise exception 'secret in client-visible payload';end if;
 begin update public.pos_report_settings set enabled=true where business_id=b;raise exception 'direct config write';exception when insufficient_privilege then null;end;
 begin perform pos_private.report_worker();raise exception 'client ran global sender';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into public.pos_memberships(business_id,user_id,role,permissions) values(current_setting('test.biz')::uuid,current_setting('test.staff')::uuid,'cashier',array['pos','orders','pay']);
select set_config('request.jwt.claim.sub',current_setting('test.staff'),true);set local role authenticated;
do $$begin
 if exists(select 1 from public.pos_businesses where id=current_setting('test.outlet')::uuid) or exists(select 1 from public.pos_report_settings where business_id=current_setting('test.biz')::uuid) or exists(select 1 from public.pos_report_mail_jobs where business_id=current_setting('test.biz')::uuid) then raise exception 'outlet/email leak';end if;
 begin perform public.pos_create_outlet(current_setting('test.biz')::uuid,'Unauthorized','');raise exception 'staff created outlet';exception when insufficient_privilege then null;end;
 begin perform public.pos_save_report_settings(current_setting('test.biz')::uuid,true,'{}','08:00');raise exception 'staff configured email';exception when insufficient_privilege then null;end;
 begin perform public.pos_queue_report(current_setting('test.biz')::uuid,current_date);raise exception 'staff queued mail';exception when insufficient_privilege then null;end;
 begin perform decrypted_secret from vault.decrypted_secrets where name='sums_pos_reports_resend';raise exception 'mail credential exposed';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);
do $$begin
 if exists(select 1 from public.pos_businesses where id=current_setting('test.biz')::uuid) then raise exception 'tenant leak';end if;
 begin perform public.pos_queue_report(current_setting('test.biz')::uuid,current_date);raise exception 'outsider queued mail';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.pos_create_outlet(uuid,text,text)','execute') then raise exception 'anonymous outlet creation';end if;
end$$;
select 'PASS: outlet membership/stock isolation, workspace gate, owner-only recipients/configuration, deduped scoped email queue, global sender/credentials denied to clients' result;
rollback;
