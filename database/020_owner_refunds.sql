create table public.pos_refund_requests (
 id uuid primary key default gen_random_uuid(),business_id uuid not null references public.pos_businesses(id),order_id uuid not null,
 request_id uuid not null,requested_by uuid not null references auth.users(id),requested_by_name text not null,
 reason text not null check(length(trim(reason)) between 3 and 300),items jsonb not null,amount bigint not null check(amount>=0),
 net_amount bigint not null,tax_amount bigint not null,service_amount bigint not null,restock boolean not null default false,
 status text not null default 'pending' check(status in ('pending','approved','rejected','completed')),
 created_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid references auth.users(id),reviewed_by_name text,review_note text,
 completed_at timestamptz,completed_by uuid references auth.users(id),completed_by_name text,method text,reference text,
 foreign key(business_id,order_id) references public.pos_orders(business_id,id),unique(business_id,request_id)
);
create unique index pos_refund_pending_order_idx on public.pos_refund_requests(business_id,order_id) where status='pending';
create index pos_refund_business_created_idx on public.pos_refund_requests(business_id,created_at desc);
create index pos_refund_order_idx on public.pos_refund_requests(order_id);
create index pos_refund_requester_idx on public.pos_refund_requests(requested_by);
create index pos_refund_reviewer_idx on public.pos_refund_requests(reviewed_by);
create index pos_refund_completer_idx on public.pos_refund_requests(completed_by);
alter table public.pos_refund_requests enable row level security;
revoke all on public.pos_refund_requests from public,anon,authenticated;
grant select on public.pos_refund_requests to authenticated;
create policy refund_read on public.pos_refund_requests for select to authenticated using(pos_private.allowed(business_id,'pay') or pos_private.allowed(business_id,'reports'));
create trigger pos_workspace_change after insert or update on public.pos_refund_requests for each row execute function pos_private.emit_workspace_change();
create function pos_private.request_refund(b uuid,p_order uuid,p_request uuid,p_lines uuid[],p_reason text,p_restock boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;r uuid;items jsonb;net bigint;tax bigint;service bigint;begin
 perform pos_private.require_access(b,'pay');
 if p_request is null or p_restock is null or length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Isi alasan refund 3–300 karakter';end if;
 select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found or o.status<>'paid' then raise exception 'Refund hanya untuk pesanan Complete';end if;
 select id into r from public.pos_refund_requests where business_id=b and request_id=p_request;if found then return r;end if;
 if coalesce(cardinality(p_lines),0)=0 or cardinality(p_lines)<>(select count(distinct x) from unnest(p_lines) x) or exists(select 1 from unnest(p_lines) x where x is null or not exists(select 1 from public.pos_order_lines l where l.business_id=b and l.order_id=o.id and l.id=x)) then raise exception 'Pilih item refund yang valid';end if;
 if exists(select 1 from public.pos_refund_requests where business_id=b and order_id=o.id and status='pending') then raise exception 'Pesanan masih memiliki pengajuan pending';end if;
 if exists(select 1 from public.pos_refund_requests r,jsonb_array_elements(r.items) x where r.business_id=b and r.order_id=o.id and r.status in ('approved','completed') and (x->>'line_id')::uuid=any(p_lines)) then raise exception 'Item sudah diajukan atau direfund';end if;
 -- Allocate the original fee snapshots exactly once across full lines, including rounding remainders.
 with lines as (select l.*,l.price*l.qty-l.discount_amount n,sum(l.price*l.qty-l.discount_amount) over(order by l.id) cumulative from public.pos_order_lines l where l.order_id=o.id),alloc as (
 select *,case when o.subtotal-o.discount_amount=0 then 0 else floor(o.service_amount::numeric*cumulative/(o.subtotal-o.discount_amount))-floor(o.service_amount::numeric*(cumulative-n)/(o.subtotal-o.discount_amount)) end s,
 case when o.subtotal-o.discount_amount=0 then 0 else floor(o.tax_amount::numeric*cumulative/(o.subtotal-o.discount_amount))-floor(o.tax_amount::numeric*(cumulative-n)/(o.subtotal-o.discount_amount)) end t from lines)
 select jsonb_agg(jsonb_build_object('line_id',id,'product_id',product_id,'name',name,'qty',qty,'net',n,'service',s,'tax',t,'amount',n+s+t) order by id),sum(n),sum(s),sum(t) into items,net,service,tax from alloc where id=any(p_lines);
 insert into public.pos_refund_requests(business_id,order_id,request_id,requested_by,requested_by_name,reason,items,amount,net_amount,tax_amount,service_amount,restock) values(b,o.id,p_request,auth.uid(),pos_private.actor_label(auth.uid()),trim(p_reason),items,net+tax+service,net,tax,service,p_restock) returning id into r;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'refund.requested',r);return r;
end$$;
create function pos_private.review_refund(b uuid,p_refund uuid,p_approve boolean,p_note text) returns void language plpgsql security definer set search_path='' as $$declare r public.pos_refund_requests;begin
 perform pos_private.require_owner(b);select * into r from public.pos_refund_requests where business_id=b and id=p_refund;
 if not found then raise exception 'Pengajuan refund tidak ditemukan';end if;
 perform 1 from public.pos_orders where business_id=b and id=r.order_id for update;
 select * into r from public.pos_refund_requests where business_id=b and id=p_refund for update;
 if p_approve is null or length(coalesce(p_note,''))>300 or (not p_approve and length(trim(coalesce(p_note,'')))<3) then raise exception 'Isi catatan penolakan 3–300 karakter';end if;
 if (p_approve and r.status in ('approved','completed')) or (not p_approve and r.status='rejected') then return;end if;
 if r.status<>'pending' then raise exception 'Pengajuan sudah diproses';end if;
 update public.pos_refund_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid(),reviewed_by_name=pos_private.actor_label(auth.uid()),review_note=trim(coalesce(p_note,'')) where id=r.id;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),case when p_approve then 'refund.approved' else 'refund.rejected' end,r.id);
end$$;
create function pos_private.complete_refund(b uuid,p_refund uuid,p_method text,p_reference text) returns void language plpgsql security definer set search_path='' as $$declare r public.pos_refund_requests;l record;begin
 perform pos_private.require_access(b,'pay');select * into r from public.pos_refund_requests where business_id=b and id=p_refund;
 if not found then raise exception 'Pengajuan refund tidak ditemukan';end if;
 perform 1 from public.pos_orders where business_id=b and id=r.order_id for update;
 select * into r from public.pos_refund_requests where business_id=b and id=p_refund for update;
 if r.status='completed' then return;end if;
 if r.status<>'approved' then raise exception 'Refund memerlukan approval owner';end if;
 if coalesce(p_method,'') not in ('cash','credit_card','debit_card','qr','bank_transfer','other') or length(coalesce(p_reference,''))>100 or (p_method<>'cash' and length(trim(coalesce(p_reference,'')))<1) then raise exception 'Isi metode dan referensi refund';end if;
 if r.restock then
  for l in select (x->>'product_id')::uuid product_id,(x->>'qty')::integer qty from jsonb_array_elements(r.items) x order by x->>'product_id' loop
   perform 1 from public.pos_products where business_id=b and id=l.product_id for update;
   update public.pos_products set stock=stock+l.qty where business_id=b and id=l.product_id;
   insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id) values(b,l.product_id,r.order_id,l.qty,'approved refund restock',auth.uid());
  end loop;
 end if;
 update public.pos_refund_requests set status='completed',completed_at=now(),completed_by=auth.uid(),completed_by_name=pos_private.actor_label(auth.uid()),method=p_method,reference=trim(coalesce(p_reference,'')) where id=r.id;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'refund.completed',r.id);
end$$;
create function public.pos_request_refund(b uuid,p_order uuid,p_request uuid,p_lines uuid[],p_reason text,p_restock boolean) returns uuid language sql security invoker set search_path='' as $$select pos_private.request_refund(b,p_order,p_request,p_lines,p_reason,p_restock)$$;
create function public.pos_review_refund(b uuid,p_refund uuid,p_approve boolean,p_note text) returns void language sql security invoker set search_path='' as $$select pos_private.review_refund(b,p_refund,p_approve,p_note)$$;
create function public.pos_complete_refund(b uuid,p_refund uuid,p_method text,p_reference text) returns void language sql security invoker set search_path='' as $$select pos_private.complete_refund(b,p_refund,p_method,p_reference)$$;
revoke all on function pos_private.request_refund(uuid,uuid,uuid,uuid[],text,boolean),public.pos_request_refund(uuid,uuid,uuid,uuid[],text,boolean),pos_private.review_refund(uuid,uuid,boolean,text),public.pos_review_refund(uuid,uuid,boolean,text),pos_private.complete_refund(uuid,uuid,text,text),public.pos_complete_refund(uuid,uuid,text,text) from public,anon;
grant execute on function pos_private.request_refund(uuid,uuid,uuid,uuid[],text,boolean),public.pos_request_refund(uuid,uuid,uuid,uuid[],text,boolean),pos_private.review_refund(uuid,uuid,boolean,text),public.pos_review_refund(uuid,uuid,boolean,text),pos_private.complete_refund(uuid,uuid,text,text),public.pos_complete_refund(uuid,uuid,text,text) to authenticated;
