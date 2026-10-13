create or replace function pos_private.queue_report_internal(b uuid,d date) returns integer language plpgsql security definer set search_path='' as $$declare cfg public.pos_report_settings;m jsonb;recipient_address text;payload jsonb;html text;plain text;k text;v text;n integer:=0;row_count integer;begin
 select * into cfg from public.pos_report_settings where business_id=b;if not found then raise exception 'Configure report email first';end if;
 if not exists(select 1 from public.pos_memberships where business_id=b and user_id=cfg.configured_by and role='owner' and active) then raise exception 'Report owner access is inactive';end if;
 if not exists(select 1 from unnest(array_prepend(cfg.owner_email,cfg.extra_emails)) x where not exists(select 1 from public.pos_report_mail_jobs j where j.business_id=b and j.report_day=d and j.recipient=x)) then return 0;end if;
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
 for recipient_address in select unnest(array_prepend(cfg.owner_email,cfg.extra_emails)) loop
  payload:=jsonb_build_object('from','SUMS POS <reports@mail.sumsstudio.id>','to',jsonb_build_array(recipient_address),'subject','Daily sales · '||(m->>'outlet')||' · '||d::text,'html',html,'text',plain);
  insert into public.pos_report_mail_jobs(business_id,report_day,recipient,payload) values(b,d,recipient_address,payload) on conflict(business_id,report_day,recipient) do nothing;get diagnostics row_count=row_count;n:=n+row_count;
 end loop;return n;
end$$;
