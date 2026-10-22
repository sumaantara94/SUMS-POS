-- One-click cash refund: approval, optional restock, audit and shift linkage are atomic.
-- Cash is attributed to the active shift of the staff member who raised the request.
create or replace function pos_private.review_refund(b uuid,p_refund uuid,p_approve boolean,p_note text)
returns void
language plpgsql security definer set search_path=''
as $$
declare
 r public.pos_refund_requests;
 s public.pos_shifts;
 l record;
begin
 perform pos_private.require_owner(b);
 select * into r from public.pos_refund_requests where business_id=b and id=p_refund;
 if not found then raise exception 'Pengajuan refund tidak ditemukan'; end if;
 perform 1 from public.pos_orders where business_id=b and id=r.order_id for update;
 select * into r from public.pos_refund_requests where business_id=b and id=p_refund for update;
 if p_approve is null or length(coalesce(p_note,''))>300 or (not p_approve and length(trim(coalesce(p_note,'')))<3) then
   raise exception 'Isi catatan penolakan 3–300 karakter';
 end if;
 if (p_approve and r.status='completed') or (not p_approve and r.status='rejected') then return; end if;
 if r.status<>'pending' then raise exception 'Pengajuan sudah diproses'; end if;

 if not p_approve then
   update public.pos_refund_requests
   set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),
       reviewed_by_name=pos_private.actor_label(auth.uid()),review_note=trim(coalesce(p_note,''))
   where id=r.id;
   insert into public.pos_audit_events(business_id,actor_id,action,record_id)
   values(b,auth.uid(),'refund.rejected',r.id);
   return;
 end if;

 -- Cash must be attributable to the cashier drawer that raised the request.
 select * into s from public.pos_shifts
 where business_id=b and actor_id=r.requested_by and closed_at is null
 order by opened_at desc limit 1 for update;
 if not found then
   raise exception 'Kasir pemohon tidak memiliki shift terbuka. Buka atau pilih shift kasir yang benar sebelum refund.';
 end if;

 if r.restock then
   for l in
     select (x->>'product_id')::uuid product_id,sum((x->>'qty')::integer)::integer qty
     from jsonb_array_elements(r.items) x
     where nullif(x->>'product_id','') is not null
     group by (x->>'product_id')::uuid
     order by (x->>'product_id')::uuid
   loop
     perform 1 from public.pos_products where business_id=b and id=l.product_id for update;
     if not found then raise exception 'Produk untuk restock tidak ditemukan'; end if;
     update public.pos_products set stock=stock+l.qty where business_id=b and id=l.product_id;
     insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id)
     values(b,l.product_id,r.order_id,l.qty,'cash refund restock',auth.uid());
   end loop;
 end if;

 update public.pos_refund_requests
 set status='completed',reviewed_at=now(),reviewed_by=auth.uid(),
     reviewed_by_name=pos_private.actor_label(auth.uid()),review_note=trim(coalesce(p_note,'')),
     completed_at=now(),completed_by=auth.uid(),completed_by_name=pos_private.actor_label(auth.uid()),
     method='cash',reference='',shift_id=s.id
 where id=r.id;

 insert into public.pos_audit_events(business_id,actor_id,action,record_id)
 values(b,auth.uid(),'refund.approved.cash.completed',r.id);
end
$$;

create or replace function pos_private.operations_summary(b uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare owner boolean;
begin
 perform pos_private.require_access(b,'pay');
 select role='owner' into owner from public.pos_memberships
 where business_id=b and user_id=auth.uid() and active;

 return jsonb_build_object(
   'current_shift',(
     select to_jsonb(s)
       || jsonb_build_object('expected_now',pos_private.shift_expected(s.id))
       || jsonb_build_object(
         'refund_count',coalesce((select count(*) from public.pos_refund_requests r where r.business_id=b and r.shift_id=s.id and r.status='completed' and r.method='cash'),0),
         'refund_total',coalesce((select sum(r.amount) from public.pos_refund_requests r where r.business_id=b and r.shift_id=s.id and r.status='completed' and r.method='cash'),0)
       )
     from public.pos_shifts s
     where s.business_id=b and s.actor_id=auth.uid() and s.closed_at is null
   ),
   'shifts',coalesce((
     select jsonb_agg(to_jsonb(s) || jsonb_build_object(
       'refund_count',coalesce((select count(*) from public.pos_refund_requests r where r.business_id=b and r.shift_id=s.id and r.status='completed' and r.method='cash'),0),
       'refund_total',coalesce((select sum(r.amount) from public.pos_refund_requests r where r.business_id=b and r.shift_id=s.id and r.status='completed' and r.method='cash'),0)
     ))
     from (select * from public.pos_shifts where business_id=b and (owner or actor_id=auth.uid()) order by opened_at desc limit 30) s
   ),'[]'::jsonb),
   'entries',coalesce((
     select jsonb_agg(to_jsonb(s))
     from (select * from public.pos_cash_entries where business_id=b and (owner or actor_id=auth.uid()) order by created_at desc limit 50) s
   ),'[]'::jsonb)
 );
end
$$;
