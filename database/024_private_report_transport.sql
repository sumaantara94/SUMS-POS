create extension if not exists http with schema extensions;
create or replace function pos_private.report_worker() returns void language plpgsql security definer set search_path='' as $$declare cfg record;j public.pos_report_mail_jobs;response record;secret text;used integer;begin
 perform pg_advisory_xact_lock(2489031);
 for cfg in select s.*,b.timezone,(now() at time zone b.timezone)::date today from public.pos_report_settings s join public.pos_businesses b on b.id=s.business_id where s.enabled and (now() at time zone b.timezone)::time>=s.send_time and exists(select 1 from public.pos_memberships m where m.business_id=s.business_id and m.user_id=s.configured_by and m.role='owner' and m.active) loop
  perform pos_private.queue_report_internal(cfg.business_id,cfg.today-1);
 end loop;
 for j in select * from public.pos_report_mail_jobs where status='sending' for update loop
  select * into response from net._http_response where id=j.http_request_id;
  if found then
   if response.status_code between 200 and 299 then
    update public.pos_report_mail_jobs set status='sent',sent_at=now(),provider_id=(response.content::jsonb)->>'id',error=null where id=j.id;
   elsif (response.status_code=429 or response.status_code>=500 or response.error_msg is not null or response.timed_out) and j.attempts<3 and j.created_at>now()-interval '23 hours' then
    update public.pos_report_mail_jobs set status='pending',next_attempt_at=now()+interval '15 minutes',error=left(coalesce(response.error_msg,response.content,'Delivery timeout'),200) where id=j.id;
   else update public.pos_report_mail_jobs set status='failed',error=left(coalesce(response.error_msg,response.content,'Delivery failed'),200) where id=j.id;end if;
  elsif j.attempted_at<now()-interval '15 minutes' then
   update public.pos_report_mail_jobs set status=case when j.attempts<3 and j.created_at>now()-interval '23 hours' then 'pending' else 'failed' end,next_attempt_at=now()+interval '15 minutes',error='No delivery response; retry uses the same idempotency key' where id=j.id;
  end if;
 end loop;
 select decrypted_secret into secret from vault.decrypted_secrets where name='sums_pos_reports_resend';if secret is null then return;end if;
 select count(*) into used from public.pos_report_mail_jobs where attempted_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 for j in select * from public.pos_report_mail_jobs where status='pending' and next_attempt_at<=now() and attempts<3 order by created_at limit 6 for update skip locked loop
  if used>=80 then exit;end if;
  if not exists(select 1 from public.pos_report_settings s join public.pos_memberships m on m.business_id=s.business_id and m.user_id=s.configured_by and m.role='owner' and m.active where s.business_id=j.business_id and j.recipient=any(array_prepend(s.owner_email,s.extra_emails))) then update public.pos_report_mail_jobs set status='cancelled',error='Recipient or owner access changed' where id=j.id;continue;end if;
  -- Keep the sender credential in local memory, never in pg_net's managed request queue.
  if j.created_at<now()-interval '23 hours' then update public.pos_report_mail_jobs set status='failed',error='Report expired; review delivery before creating another report' where id=j.id;continue;end if;
  begin
   select * into response from extensions.http(('POST','https://api.resend.com/emails',array[extensions.http_header('Authorization','Bearer '||secret),extensions.http_header('Idempotency-Key','pos-daily-'||j.id::text)],'application/json',j.payload::text)::extensions.http_request);
   if response.status between 200 and 299 then
    update public.pos_report_mail_jobs set status='sent',attempts=attempts+1,attempted_at=now(),sent_at=now(),provider_id=response.content::jsonb->>'id',error=null where id=j.id;
   else
    update public.pos_report_mail_jobs set status=case when (response.status=429 or response.status>=500) and attempts<2 then 'pending' else 'failed' end,attempts=attempts+1,attempted_at=now(),next_attempt_at=now()+interval '15 minutes',error=left(response.content,200) where id=j.id;
   end if;
  exception when others then
   update public.pos_report_mail_jobs set status=case when attempts<2 then 'pending' else 'failed' end,attempts=attempts+1,attempted_at=now(),next_attempt_at=now()+interval '15 minutes',error='Provider connection failed; retry uses the same idempotency key' where id=j.id;
  end;used:=used+1;
 end loop;
end$$;
