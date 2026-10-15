create or replace function pos_private.request_refund_v2(b uuid,p_order uuid,p_request uuid,p_items jsonb,p_pin text,p_reason text,p_restock boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;r public.pos_refund_requests;err text;entry jsonb;l record;previous integer;q integer;items jsonb:='[]';net bigint:=0;service bigint:=0;tax bigint:=0;n bigint;s bigint;t bigint;begin
 perform pos_private.require_access(b,'pay');
 if p_request is null or p_restock is null or length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Isi alasan refund 3–300 karakter';end if;
 select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found or o.status<>'paid' then raise exception 'Refund hanya untuk pesanan Complete';end if;
 select * into r from public.pos_refund_requests where business_id=b and request_id=p_request;
 if found then if r.order_id<>p_order then raise exception 'Request does not match original order';end if;return jsonb_build_object('ok',true,'id',r.id);end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 or jsonb_array_length(p_items)<>(select count(distinct x->>'line_id') from jsonb_array_elements(p_items) x) then raise exception 'Select valid item quantities';end if;
 if exists(select 1 from public.pos_refund_requests where business_id=b and order_id=o.id and status='pending') then raise exception 'Pesanan masih memiliki pengajuan pending';end if;
 for entry in select value from jsonb_array_elements(p_items) loop
 if coalesce(entry->>'line_id','') !~ '^[0-9a-fA-F-]{36}$' or coalesce(entry->>'qty','') !~ '^[0-9]+$' or (entry->>'qty')::numeric not between 1 and 1000000 then raise exception 'Select valid item quantities';end if;
 q:=(entry->>'qty')::integer;
 with lines as(select x.*,x.price*x.qty-x.discount_amount n,sum(x.price*x.qty-x.discount_amount) over(order by x.id) cumulative from public.pos_order_lines x where x.order_id=o.id and x.voided_at is null)
 select lines.*,case when o.subtotal-o.discount_amount=0 then 0 else floor(o.service_amount::numeric*lines.cumulative/(o.subtotal-o.discount_amount))-floor(o.service_amount::numeric*(lines.cumulative-lines.n)/(o.subtotal-o.discount_amount)) end s,
 case when o.subtotal-o.discount_amount=0 then 0 else floor(o.tax_amount::numeric*lines.cumulative/(o.subtotal-o.discount_amount))-floor(o.tax_amount::numeric*(lines.cumulative-lines.n)/(o.subtotal-o.discount_amount)) end t into l from lines where lines.id=(entry->>'line_id')::uuid;
 if not found then raise exception 'Item tidak ditemukan';end if;
 select coalesce(sum((x->>'qty')::integer),0)::integer into previous from public.pos_refund_requests rr,jsonb_array_elements(rr.items) x where rr.business_id=b and rr.order_id=o.id and rr.status in ('approved','completed') and x->>'line_id'=l.id::text;
 if q>l.qty-previous then raise exception 'Quantity exceeds remaining items';end if;
 n:=floor(l.n::numeric*(previous+q)/l.qty)-floor(l.n::numeric*previous/l.qty);s:=floor(l.s::numeric*(previous+q)/l.qty)-floor(l.s::numeric*previous/l.qty);t:=floor(l.t::numeric*(previous+q)/l.qty)-floor(l.t::numeric*previous/l.qty);
 items:=items||jsonb_build_array(jsonb_build_object('line_id',l.id,'product_id',l.product_id,'name',l.name,'qty',q,'net',n,'service',s,'tax',t,'amount',n+s+t));net:=net+n;service:=service+s;tax:=tax+t;
 end loop;
 err:=pos_private.check_adjustment_pin(b,p_pin);if err is not null then return jsonb_build_object('ok',false,'error',err);end if;
 insert into public.pos_refund_requests(business_id,order_id,request_id,requested_by,requested_by_name,reason,items,amount,net_amount,tax_amount,service_amount,restock) values(b,o.id,p_request,auth.uid(),pos_private.actor_label(auth.uid()),trim(p_reason),items,net+service+tax,net,tax,service,p_restock) returning * into r;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'refund.requested.pin',r.id);
 return jsonb_build_object('ok',true,'id',r.id);
end$$;
