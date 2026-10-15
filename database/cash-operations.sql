begin;
create table public.pos_shifts(
 id uuid primary key,business_id uuid not null references public.pos_businesses(id),actor_id uuid not null references auth.users(id),actor_name text not null,
 opened_at timestamptz not null default now(),opening_cash bigint not null check(opening_cash between 0 and 1000000000000),
 closed_at timestamptz,counted_cash bigint check(counted_cash between 0 and 1000000000000),expected_cash bigint,difference bigint,note text not null default '' check(length(note)<=300),unique(business_id,id)
);
create unique index pos_shifts_one_open on public.pos_shifts(business_id,actor_id) where closed_at is null;
create index pos_shifts_actor_idx on public.pos_shifts(actor_id);
create table public.pos_cash_entries(
 id uuid primary key,business_id uuid not null references public.pos_businesses(id),shift_id uuid,actor_id uuid not null references auth.users(id),actor_name text not null,
 kind text not null check(kind in ('cash_in','cash_out','expense')),account text not null check(account in ('cash','bank')),
 amount bigint not null check(amount between 1 and 1000000000000),reason text not null check(length(trim(reason)) between 3 and 300),created_at timestamptz not null default now(),
 foreign key(business_id,shift_id) references public.pos_shifts(business_id,id),check(kind='expense' or account='cash')
);
create index pos_cash_entries_business_idx on public.pos_cash_entries(business_id,created_at desc);
create index pos_cash_entries_shift_idx on public.pos_cash_entries(shift_id);
create index pos_cash_entries_actor_idx on public.pos_cash_entries(actor_id);
alter table public.pos_shifts enable row level security;alter table public.pos_cash_entries enable row level security;
revoke all on public.pos_shifts,public.pos_cash_entries from public,anon,authenticated;
grant select on public.pos_shifts,public.pos_cash_entries to authenticated;
create policy shift_read on public.pos_shifts for select to authenticated using(pos_private.allowed(business_id,'pay') and actor_id=(select auth.uid()) or pos_private.allowed(business_id,'settings'));
create policy cash_read on public.pos_cash_entries for select to authenticated using(pos_private.allowed(business_id,'pay') and actor_id=(select auth.uid()) or pos_private.allowed(business_id,'settings'));
alter table public.pos_payments add column shift_id uuid references public.pos_shifts(id);
alter table public.pos_refund_requests add column shift_id uuid references public.pos_shifts(id);
create index pos_payments_shift_idx on public.pos_payments(shift_id);
create index pos_refunds_shift_idx on public.pos_refund_requests(shift_id);
create function pos_private.attach_shift() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_table_name='pos_payments' then
 select id into new.shift_id from public.pos_shifts where business_id=new.business_id and actor_id=new.paid_by and closed_at is null for update;
 elsif new.status='completed' and old.status is distinct from 'completed' and new.method='cash' then
 select id into new.shift_id from public.pos_shifts where business_id=new.business_id and actor_id=new.completed_by and closed_at is null for update;
 end if;return new;
end$$;
revoke all on function pos_private.attach_shift() from public,anon,authenticated;
create trigger pos_payment_shift before insert on public.pos_payments for each row execute function pos_private.attach_shift();
create trigger pos_refund_shift before update on public.pos_refund_requests for each row execute function pos_private.attach_shift();
create function pos_private.shift_expected(s uuid) returns bigint language sql volatile security definer set search_path='' as $$
 select opening_cash+coalesce((select sum(amount) from public.pos_payments where shift_id=s and method='cash'),0)-coalesce((select sum(amount) from public.pos_refund_requests where shift_id=s and status='completed' and method='cash'),0)+coalesce((select sum(case when kind='cash_in' then amount else -amount end) from public.pos_cash_entries where shift_id=s and account='cash'),0) from public.pos_shifts where id=s;
$$;
revoke all on function pos_private.shift_expected(uuid) from public,anon,authenticated;
create function pos_private.open_shift(b uuid,p_request uuid,p_opening bigint) returns uuid language plpgsql security definer set search_path='' as $$declare s public.pos_shifts;begin
 perform pos_private.require_access(b,'pay');
 if p_request is null or p_opening is null then raise exception 'Isi modal kas awal';end if;
 perform pg_advisory_xact_lock(hashtextextended('shift:'||b::text||auth.uid()::text,0));
 select * into s from public.pos_shifts where id=p_request;
 if found then if s.business_id<>b or s.actor_id<>auth.uid() or s.opening_cash<>p_opening then raise exception 'Shift request mismatch';end if;return s.id;end if;
 if exists(select 1 from public.pos_shifts where business_id=b and actor_id=auth.uid() and closed_at is null) then raise exception 'Masih ada shift terbuka';end if;
 insert into public.pos_shifts(id,business_id,actor_id,actor_name,opening_cash) values(p_request,b,auth.uid(),pos_private.actor_label(auth.uid()),p_opening);
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'shift.opened',p_request);return p_request;
end$$;
create function pos_private.cash_entry(b uuid,p_request uuid,p_kind text,p_account text,p_amount bigint,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$declare s uuid;old public.pos_cash_entries;begin
 perform pos_private.require_access(b,'pay');
 if p_request is null then raise exception 'Request ID wajib';end if;
 perform pg_advisory_xact_lock(hashtextextended('cash-entry:'||p_request::text,0));
 select * into old from public.pos_cash_entries where id=p_request;
 if found then if old.business_id<>b or old.actor_id<>auth.uid() or old.kind is distinct from p_kind or old.account is distinct from p_account or old.amount is distinct from p_amount or old.reason is distinct from trim(p_reason) then raise exception 'Cash entry request mismatch';end if;return old.id;end if;
 select id into s from public.pos_shifts where business_id=b and actor_id=auth.uid() and closed_at is null for update;
 if p_account='cash' and s is null then raise exception 'Buka shift sebelum mencatat uang tunai';end if;
 insert into public.pos_cash_entries(id,business_id,shift_id,actor_id,actor_name,kind,account,amount,reason) values(p_request,b,s,auth.uid(),pos_private.actor_label(auth.uid()),p_kind,p_account,p_amount,trim(p_reason));
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'cash.'||p_kind,p_request);return p_request;
end$$;
create function pos_private.close_shift(b uuid,p_shift uuid,p_counted bigint,p_note text) returns jsonb language plpgsql security definer set search_path='' as $$declare s public.pos_shifts;e bigint;begin
 perform pos_private.require_access(b,'pay');select * into s from public.pos_shifts where business_id=b and id=p_shift and actor_id=auth.uid() for update;
 if not found then raise exception 'Shift tidak ditemukan';end if;
 if s.closed_at is not null then if s.counted_cash is distinct from p_counted or s.note is distinct from trim(coalesce(p_note,'')) then raise exception 'Shift sudah ditutup dengan angka berbeda';end if;return to_jsonb(s);end if;
 if p_counted is null or p_counted<0 or p_counted>1000000000000 or length(coalesce(p_note,''))>300 then raise exception 'Isi kas aktual yang valid';end if;
 e:=pos_private.shift_expected(s.id);
 if p_counted<>e and length(trim(coalesce(p_note,'')))<3 then raise exception 'Isi alasan selisih kas (minimal 3 karakter)';end if;
 update public.pos_shifts set closed_at=now(),counted_cash=p_counted,expected_cash=e,difference=p_counted-e,note=trim(coalesce(p_note,'')) where id=s.id returning * into s;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'shift.closed',s.id);return to_jsonb(s);
end$$;
create function pos_private.operations_summary(b uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare owner boolean;begin
 perform pos_private.require_access(b,'pay');select role='owner' into owner from public.pos_memberships where business_id=b and user_id=auth.uid() and active;
 return jsonb_build_object('current_shift',(select to_jsonb(s)||jsonb_build_object('expected_now',pos_private.shift_expected(s.id)) from public.pos_shifts s where business_id=b and actor_id=auth.uid() and closed_at is null),'shifts',coalesce((select jsonb_agg(to_jsonb(s)) from (select * from public.pos_shifts where business_id=b and (owner or actor_id=auth.uid()) order by opened_at desc limit 30) s),'[]'::jsonb),'entries',coalesce((select jsonb_agg(to_jsonb(s)) from (select * from public.pos_cash_entries where business_id=b and (owner or actor_id=auth.uid()) order by created_at desc limit 50) s),'[]'::jsonb));
end$$;
create function public.pos_open_shift(b uuid,p_request uuid,p_opening bigint) returns uuid language sql security invoker set search_path='' as $$select pos_private.open_shift(b,p_request,p_opening)$$;
create function public.pos_cash_entry(b uuid,p_request uuid,p_kind text,p_account text,p_amount bigint,p_reason text) returns uuid language sql security invoker set search_path='' as $$select pos_private.cash_entry(b,p_request,p_kind,p_account,p_amount,p_reason)$$;
create function public.pos_close_shift(b uuid,p_shift uuid,p_counted bigint,p_note text) returns jsonb language sql security invoker set search_path='' as $$select pos_private.close_shift(b,p_shift,p_counted,p_note)$$;
create function public.pos_operations_summary(b uuid) returns jsonb language sql security invoker set search_path='' as $$select pos_private.operations_summary(b)$$;
revoke all on function pos_private.open_shift(uuid,uuid,bigint),pos_private.cash_entry(uuid,uuid,text,text,bigint,text),pos_private.close_shift(uuid,uuid,bigint,text),pos_private.operations_summary(uuid),public.pos_open_shift(uuid,uuid,bigint),public.pos_cash_entry(uuid,uuid,text,text,bigint,text),public.pos_close_shift(uuid,uuid,bigint,text),public.pos_operations_summary(uuid) from public,anon;
grant execute on function pos_private.open_shift(uuid,uuid,bigint),pos_private.cash_entry(uuid,uuid,text,text,bigint,text),pos_private.close_shift(uuid,uuid,bigint,text),pos_private.operations_summary(uuid),public.pos_open_shift(uuid,uuid,bigint),public.pos_cash_entry(uuid,uuid,text,text,bigint,text),public.pos_close_shift(uuid,uuid,bigint,text),public.pos_operations_summary(uuid) to authenticated;
commit;
