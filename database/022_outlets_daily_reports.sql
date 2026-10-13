create extension if not exists pg_net;
create extension if not exists pg_cron;
alter table public.pos_businesses add column parent_business_id uuid references public.pos_businesses(id),add column outlet_address text not null default '' check(length(outlet_address)<=300);
create index pos_business_parent_idx on public.pos_businesses(parent_business_id);
create unique index pos_outlet_name_idx on public.pos_businesses(parent_business_id,lower(name)) where parent_business_id is not null;
create function pos_private.create_outlet(b uuid,p_name text,p_address text) returns uuid language plpgsql security definer set search_path='' as $$declare root public.pos_businesses;o uuid;begin
 perform pos_private.require_owner(b);select * into root from public.pos_businesses where id=b;
 if root.parent_business_id is not null then select * into root from public.pos_businesses where id=root.parent_business_id;perform pos_private.require_owner(root.id);end if;
 perform pg_advisory_xact_lock(hashtextextended(root.id::text,23));
 if length(trim(coalesce(p_name,''))) not between 1 and 80 or length(coalesce(p_address,''))>300 then raise exception 'Isi nama dan alamat outlet yang valid';end if;
 if (select count(*) from public.pos_businesses where parent_business_id=root.id)>=19 then raise exception 'Batas 20 outlet tercapai';end if;
 insert into public.pos_businesses(name,category,accent,timezone,parent_business_id,outlet_address,logo_data,receipt_width,restaurant_mode,waiter_enabled,tax_bps,service_bps,tax_on_service)
 values(trim(p_name),root.category,root.accent,root.timezone,root.id,trim(coalesce(p_address,'')),root.logo_data,root.receipt_width,root.restaurant_mode,root.waiter_enabled,root.tax_bps,root.service_bps,root.tax_on_service) returning id into o;
 insert into public.pos_memberships(business_id,user_id,role,permissions) select o,user_id,'owner',array['dashboard','pos','orders','products','reports','settings','pay','cancel','staff'] from public.pos_memberships where business_id=root.id and role='owner' and active;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(root.id,auth.uid(),'outlet.created',o);return o;
end$$;
create function public.pos_create_outlet(b uuid,p_name text,p_address text) returns uuid language sql security invoker set search_path='' as $$select pos_private.create_outlet(b,p_name,p_address)$$;
revoke all on function pos_private.create_outlet(uuid,text,text),public.pos_create_outlet(uuid,text,text) from public,anon;
grant execute on function pos_private.create_outlet(uuid,text,text),public.pos_create_outlet(uuid,text,text) to authenticated;
create table public.pos_report_settings(business_id uuid primary key references public.pos_businesses(id),enabled boolean not null default false,owner_email text not null,configured_by uuid not null references auth.users(id),extra_emails text[] not null default '{}',send_time time not null default '08:00',updated_at timestamptz not null default now());
create index pos_report_configurer_idx on public.pos_report_settings(configured_by);
create table public.pos_report_mail_jobs(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.pos_businesses(id),report_day date not null,recipient text not null,payload jsonb not null,status text not null default 'pending' check(status in ('pending','sending','sent','failed','cancelled')),attempts integer not null default 0,next_attempt_at timestamptz not null default now(),http_request_id bigint,provider_id text,error text,created_at timestamptz not null default now(),attempted_at timestamptz,sent_at timestamptz,unique(business_id,report_day,recipient));
create index pos_report_mail_business_idx on public.pos_report_mail_jobs(business_id,created_at desc);
create index pos_report_mail_due_idx on public.pos_report_mail_jobs(status,next_attempt_at);
alter table public.pos_report_settings enable row level security;
alter table public.pos_report_mail_jobs enable row level security;
revoke all on public.pos_report_settings,public.pos_report_mail_jobs from public,anon,authenticated;
grant select on public.pos_report_settings,public.pos_report_mail_jobs to authenticated;
create policy report_settings_owner_read on public.pos_report_settings for select to authenticated using(exists(select 1 from public.pos_memberships where business_id=pos_report_settings.business_id and user_id=(select auth.uid()) and role='owner' and active));
create policy report_jobs_owner_read on public.pos_report_mail_jobs for select to authenticated using(exists(select 1 from public.pos_memberships where business_id=pos_report_mail_jobs.business_id and user_id=(select auth.uid()) and role='owner' and active));
create trigger pos_workspace_change after insert or update on public.pos_report_settings for each row execute function pos_private.emit_workspace_change();
create trigger pos_workspace_change after insert or update on public.pos_report_mail_jobs for each row execute function pos_private.emit_workspace_change();
create function pos_private.save_report_settings(b uuid,p_enabled boolean,p_emails text[],p_time time) returns void language plpgsql security definer set search_path='' as $$declare mail text;emails text[];begin
 perform pos_private.require_owner(b);select lower(email) into mail from auth.users where id=auth.uid();
 if mail is null or p_enabled is null or p_time is null or extract(second from p_time)<>0 or coalesce(cardinality(p_emails),0)>5 then raise exception 'Pengaturan email tidak valid';end if;
 if exists(select 1 from unnest(p_emails) x where x is null or length(trim(x))>254 or trim(x)!~ '^[A-Za-z0-9.!#$%&*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') then raise exception 'Alamat email penerima tidak valid';end if;
 select coalesce(array_agg(distinct lower(trim(x))),array[]::text[]) into emails from unnest(p_emails) x where lower(trim(x))<>mail;
 insert into public.pos_report_settings(business_id,enabled,owner_email,configured_by,extra_emails,send_time) values(b,p_enabled,mail,auth.uid(),emails,p_time) on conflict(business_id) do update set enabled=excluded.enabled,owner_email=excluded.owner_email,configured_by=excluded.configured_by,extra_emails=excluded.extra_emails,send_time=excluded.send_time,updated_at=now();
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'report.email.configured',b);
end$$;
create function public.pos_save_report_settings(b uuid,p_enabled boolean,p_emails text[],p_time time) returns void language sql security invoker set search_path='' as $$select pos_private.save_report_settings(b,p_enabled,p_emails,p_time)$$;
revoke all on function pos_private.save_report_settings(uuid,boolean,text[],time),public.pos_save_report_settings(uuid,boolean,text[],time) from public,anon;
grant execute on function pos_private.save_report_settings(uuid,boolean,text[],time),public.pos_save_report_settings(uuid,boolean,text[],time) to authenticated;
create function pos_private.daily_metrics(b uuid,d date) returns jsonb language plpgsql security definer set search_path='' as $$declare cfg public.pos_businesses;lo timestamptz;hi timestamptz;paid record;lines record;refunds record;cancelled integer;voids integer;methods jsonb;begin
 select * into cfg from public.pos_businesses where id=b;if not found then raise exception 'Outlet tidak ditemukan';end if;
 lo:=d::timestamp at time zone cfg.timezone;hi:=(d+1)::timestamp at time zone cfg.timezone;
 select count(*) bills,coalesce(sum(total),0) collections,coalesce(sum(subtotal),0) gross,coalesce(sum(discount_amount),0) discount,coalesce(sum(service_amount),0) service,coalesce(sum(tax_amount),0) tax into paid from public.pos_orders where business_id=b and status='paid' and paid_at>=lo and paid_at<hi;
 select coalesce(sum(l.purchase_cost*l.qty),0) cost,count(*) filter(where l.purchase_cost is null) missing into lines from public.pos_order_lines l join public.pos_orders o on o.id=l.order_id where o.business_id=b and o.status='paid' and o.paid_at>=lo and o.paid_at<hi and l.voided_at is null;
 select coalesce(sum(amount),0) amount,coalesce(sum(net_amount),0) net into refunds from public.pos_refund_requests where business_id=b and status='completed' and completed_at>=lo and completed_at<hi;
 select count(*) into cancelled from public.pos_orders where business_id=b and status='cancelled' and cancelled_at>=lo and cancelled_at<hi;
 select count(*) into voids from public.pos_order_lines where business_id=b and voided_at>=lo and voided_at<hi;
 select coalesce(jsonb_object_agg(method,amount),'{}') into methods from (select method,sum(amount) amount from public.pos_payments where business_id=b and created_at>=lo and created_at<hi group by method) x;
 return jsonb_build_object('outlet',cfg.name,'day',d,'timezone',cfg.timezone,'bills',paid.bills,'collections',paid.collections,'gross',paid.gross,'discount',paid.discount,'net_sales_before_refunds',paid.gross-paid.discount,'tax',paid.tax,'service',paid.service,'recorded_cogs',lines.cost,'missing_cost_lines',lines.missing,'refunds',refunds.amount,'net_collections',paid.collections-refunds.amount,'cancelled_bills',cancelled,'voided_items',voids,'methods',methods);
end$$;
create function pos_private.html_escape(t text) returns text language sql immutable set search_path='' as $$select replace(replace(replace(coalesce(t,''),'&','&amp;'),'<','&lt;'),'>','&gt;')$$;
create function pos_private.queue_report_internal(b uuid,d date) returns integer language plpgsql security definer set search_path='' as $$declare cfg public.pos_report_settings;m jsonb;recipient text;payload jsonb;html text;plain text;k text;v text;n integer:=0;row_count integer;begin
 select * into cfg from public.pos_report_settings where business_id=b;if not found then raise exception 'Configure report email first';end if;
 if not exists(select 1 from public.pos_memberships where business_id=b and user_id=cfg.configured_by and role='owner' and active) then raise exception 'Report owner access is inactive';end if;
 m:=pos_private.daily_metrics(b,d);
 html:='<html lang="en"><head><meta charset="utf-8"><title>Daily sales report</title></head><body style="margin:0;background:#f4f7f6;font-family:Arial,sans-serif;color:#182d32"><main style="max-width:600px;margin:24px auto;background:white;padding:28px;border-radius:14px"><p style="color:#087f6c;font-weight:bold">SUMS POS · Daily Sales</p><h1 style="font-size:24px">'||pos_private.html_escape(m->>'outlet')||'</h1><p>'||pos_private.html_escape(d::text)||' · '||pos_private.html_escape(m->>'timezone')||'</p><table role="presentation" style="border-collapse:collapse;width:100%">';
 plain:='SUMS POS — Daily sales'||chr(10)||(m->>'outlet')||' · '||d::text||' · '||(m->>'timezone')||chr(10);
 for k,v in select key,value from jsonb_each_text(m) where key not in ('outlet','day','timezone','methods') order by key loop
  html:=html||'<tr><td style="padding:10px;border-bottom:1px solid #e2eae8">'||initcap(replace(k,'_',' '))||'</td><td style="padding:10px;text-align:right;border-bottom:1px solid #e2eae8">'||pos_private.html_escape(v)||'</td></tr>';
  plain:=plain||initcap(replace(k,'_',' '))||': '||v||chr(10);
 end loop;
 html:=html||'</table><p>Amounts are in IDR. COGS includes only recorded costs. Invoice totals remain auditable; completed refunds reduce net collections.</p><h2 style="font-size:16px">Payment methods</h2>';
 for k,v in select key,value from jsonb_each_text(m->'methods') loop html:=html||'<p>'||pos_private.html_escape(initcap(replace(k,'_',' ')))||': IDR '||pos_private.html_escape(v)||'</p>';plain:=plain||k||': IDR '||v||chr(10);end loop;
 html:=html||'<p style="font-size:12px;color:#73868a">Daily operational report. Manage recipients and delivery time in Back Office → Sales reports → Email reports.</p><p style="font-size:12px">Powered by SUMS POS</p></main></body></html>';
 for recipient in select unnest(array_prepend(cfg.owner_email,cfg.extra_emails)) loop
  payload:=jsonb_build_object('from','SUMS POS <reports@mail.sumsstudio.id>','to',jsonb_build_array(recipient),'subject','Daily sales · '||(m->>'outlet')||' · '||d::text,'html',html,'text',plain);
  insert into public.pos_report_mail_jobs(business_id,report_day,recipient,payload) values(b,d,recipient,payload) on conflict(business_id,report_day,recipient) do nothing;get diagnostics row_count=row_count;n:=n+row_count;
 end loop;return n;
end$$;
create function pos_private.queue_report(b uuid,p_day date) returns integer language plpgsql security definer set search_path='' as $$declare today date;begin
 perform pos_private.require_owner(b);select (now() at time zone timezone)::date into today from public.pos_businesses where id=b;
 if p_day is null or p_day>today or p_day<today-365 then raise exception 'Select a report date within the last year';end if;
 return pos_private.queue_report_internal(b,p_day);
end$$;
create function public.pos_queue_report(b uuid,p_day date) returns integer language sql security invoker set search_path='' as $$select pos_private.queue_report(b,p_day)$$;
revoke all on function pos_private.daily_metrics(uuid,date),pos_private.html_escape(text),pos_private.queue_report_internal(uuid,date),pos_private.queue_report(uuid,date),public.pos_queue_report(uuid,date) from public,anon,authenticated;
grant execute on function pos_private.queue_report(uuid,date),public.pos_queue_report(uuid,date) to authenticated;
-- The scheduler owns delivery. Clients cannot access credentials or execute the sender.
create function pos_private.report_worker() returns void language plpgsql security definer set search_path='' as $$declare cfg record;j public.pos_report_mail_jobs;response record;secret text;used integer;begin
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
  update public.pos_report_mail_jobs set status='sending',attempts=attempts+1,attempted_at=now(),http_request_id=net.http_post(url:='https://api.resend.com/emails',headers:=jsonb_build_object('Authorization','Bearer '||secret,'Content-Type','application/json','Idempotency-Key','pos-daily-'||j.id::text),body:=j.payload,timeout_milliseconds:=15000) where id=j.id;used:=used+1;
 end loop;
end$$;
revoke all on function pos_private.report_worker() from public,anon,authenticated;
revoke all on net.http_request_queue,net._http_response from public,anon,authenticated;
select cron.schedule('sums-pos-daily-sales','*/5 * * * *','select pos_private.report_worker()');
