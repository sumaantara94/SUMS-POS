create table public.pos_order_adjustments(
 id uuid primary key default gen_random_uuid(),business_id uuid not null references public.pos_businesses(id),order_id uuid not null,line_id uuid not null,request_id uuid not null,
 actor_id uuid not null references auth.users(id),actor_name text not null,item_name text not null,qty_before integer not null,qty_removed integer not null check(qty_removed>0),qty_after integer not null check(qty_after>=0),amount bigint not null check(amount>=0),reason text not null check(length(trim(reason)) between 3 and 300),created_at timestamptz not null default now(),
 foreign key(business_id,order_id) references public.pos_orders(business_id,id),foreign key(line_id) references public.pos_order_lines(id),unique(business_id,request_id));
create index pos_adjustments_business_created_idx on public.pos_order_adjustments(business_id,created_at desc);
create index pos_adjustments_order_idx on public.pos_order_adjustments(order_id);
create index pos_adjustments_line_idx on public.pos_order_adjustments(line_id);
create index pos_adjustments_actor_idx on public.pos_order_adjustments(actor_id);
alter table public.pos_order_adjustments enable row level security;
revoke all on public.pos_order_adjustments from public,anon,authenticated;grant select on public.pos_order_adjustments to authenticated;
create policy adjustment_read on public.pos_order_adjustments for select to authenticated using(pos_private.allowed(business_id,'pay') or pos_private.allowed(business_id,'reports'));
create trigger pos_workspace_change after insert on public.pos_order_adjustments for each row execute function pos_private.emit_workspace_change();
create function pos_private.check_adjustment_pin(b uuid,p_pin text) returns text language plpgsql security definer set search_path='' as $$
declare hash text;n integer;bucket timestamptz:=to_timestamp(floor(extract(epoch from now())/900)*900);begin
 perform pos_private.require_access(b,'pay');select pin_hash into hash from pos_private.cancel_config where business_id=b;
 if hash is null then return 'Owner perlu mengatur PIN pembatalan';end if;
 insert into pos_private.cancel_attempts values(b,auth.uid(),bucket,1) on conflict(business_id,user_id) do update set attempts=case when cancel_attempts.bucket=excluded.bucket then cancel_attempts.attempts+1 else 1 end,bucket=excluded.bucket returning attempts into n;
 if n>5 then return 'Batas percobaan PIN tercapai. Coba kembali setelah 15 menit';end if;
 if p_pin is null or p_pin !~ '^[0-9]{6}$' or extensions.crypt(p_pin,hash)<>hash then
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'adjustment.pin.denied',b);return 'PIN tidak benar';end if;
 update pos_private.cancel_attempts set attempts=0 where business_id=b and user_id=auth.uid();return null;
end$$;
create function pos_private.reduce_line(b uuid,p_order uuid,p_line uuid,p_qty integer,p_request uuid,p_pin text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;l public.pos_order_lines;v public.pos_order_adjustments;err text;result jsonb;subtotal_value bigint;service bigint;tax bigint;newtotal bigint;j public.pos_print_jobs;items jsonb;begin
 perform pos_private.require_access(b,'orders');perform pos_private.require_access(b,'pay');
 if p_request is null or p_qty is null or p_qty<1 or length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Enter quantity and reason (3–300 characters)';end if;
 select * into o from public.pos_orders where business_id=b and id=p_order for update;if not found then raise exception 'Pesanan tidak ditemukan';end if;
 select * into v from public.pos_order_adjustments where business_id=b and request_id=p_request;
 if found then if v.order_id<>p_order or v.line_id<>p_line or v.qty_removed<>p_qty then raise exception 'Request does not match original adjustment';end if;return jsonb_build_object('ok',true,'id',v.id);end if;
 select * into l from public.pos_order_lines where business_id=b and order_id=o.id and id=p_line for update;
 if not found or l.voided_at is not null or o.status<>'open' then raise exception 'Only open order items can be reduced';end if;
 if p_qty>l.qty then raise exception 'Quantity exceeds remaining items';end if;
 err:=pos_private.check_adjustment_pin(b,p_pin);if err is not null then return jsonb_build_object('ok',false,'error',err);end if;
 if p_qty=l.qty then
 result:=pos_private.void_line(b,o.id,l.id,p_pin,p_reason);if not (result->>'ok')::boolean then return result;end if;
 select void_amount into newtotal from public.pos_order_lines where id=l.id;
 else
 update public.pos_order_lines set qty=qty-p_qty where id=l.id;
 select coalesce(sum(price*qty),0) into subtotal_value from public.pos_order_lines where order_id=o.id and voided_at is null;
 service:=round(subtotal_value::numeric*o.service_bps/10000)::bigint;tax:=round((subtotal_value+case when o.tax_on_service then service else 0 end)::numeric*o.tax_bps/10000)::bigint;newtotal:=subtotal_value+service+tax;
 update public.pos_orders set subtotal=subtotal_value,total=newtotal,service_amount=service,tax_amount=tax where id=o.id;
 update public.pos_products set stock=stock+p_qty where business_id=b and id=l.product_id;
 insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id) values(b,l.product_id,o.id,p_qty,'item.quantity.reduce',auth.uid());
 -- Update tickets still in queue, or enqueue a quantity-only correction for printed tickets.
 for j in select * from public.pos_print_jobs where business_id=b and order_id=o.id and status in ('queued','printed') and coalesce(payload->>'kind','') not in ('void','reduce') loop
 if exists(select 1 from jsonb_array_elements(j.payload->'items') x where x->>'product_id'=l.product_id::text) then
 if j.status='queued' then
 select jsonb_agg(case when x->>'product_id'=l.product_id::text then jsonb_set(x,'{qty}',to_jsonb(l.qty-p_qty)) else x end) into items from jsonb_array_elements(j.payload->'items') x;
 update public.pos_print_jobs set payload=jsonb_set(payload,'{items}',items) where id=j.id;
 else
 insert into public.pos_print_jobs(business_id,order_id,section,payload) values(b,o.id,left(j.section,24)||' · REDUCE '||left(p_request::text,8),jsonb_build_object('kind','reduce','section',j.payload->'section','table',o.table_ref,'guest',o.guest_name,'items',jsonb_build_array(jsonb_build_object('product_id',l.product_id,'category_id',l.category_id,'name',l.name,'qty',p_qty,'note',trim(p_reason))))) on conflict on constraint pos_print_jobs_order_id_section_key do nothing;
 end if;end if;end loop;
 newtotal:=o.total-newtotal;
 end if;
 insert into public.pos_order_adjustments(business_id,order_id,line_id,request_id,actor_id,actor_name,item_name,qty_before,qty_removed,qty_after,amount,reason) values(b,o.id,l.id,p_request,auth.uid(),pos_private.actor_label(auth.uid()),l.name,l.qty,p_qty,l.qty-p_qty,newtotal,trim(p_reason)) returning * into v;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'item.quantity.reduced',v.id);
 return jsonb_build_object('ok',true,'id',v.id);
end$$;
create function pos_private.request_refund_v2(b uuid,p_order uuid,p_request uuid,p_items jsonb,p_pin text,p_reason text,p_restock boolean) returns jsonb language plpgsql security definer set search_path='' as $$
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
 select *,case when o.subtotal-o.discount_amount=0 then 0 else floor(o.service_amount::numeric*cumulative/(o.subtotal-o.discount_amount))-floor(o.service_amount::numeric*(cumulative-n)/(o.subtotal-o.discount_amount)) end s,
 case when o.subtotal-o.discount_amount=0 then 0 else floor(o.tax_amount::numeric*cumulative/(o.subtotal-o.discount_amount))-floor(o.tax_amount::numeric*(cumulative-n)/(o.subtotal-o.discount_amount)) end t into l from lines where id=(entry->>'line_id')::uuid;
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
create function public.pos_reduce_order_line(b uuid,p_order uuid,p_line uuid,p_qty integer,p_request uuid,p_pin text,p_reason text) returns jsonb language sql security invoker set search_path='' as $$select pos_private.reduce_line(b,p_order,p_line,p_qty,p_request,p_pin,p_reason)$$;
create function public.pos_request_refund_v2(b uuid,p_order uuid,p_request uuid,p_items jsonb,p_pin text,p_reason text,p_restock boolean) returns jsonb language sql security invoker set search_path='' as $$select pos_private.request_refund_v2(b,p_order,p_request,p_items,p_pin,p_reason,p_restock)$$;
-- Retire the legacy PIN-free entry points so clients cannot bypass the new requirement.
revoke execute on function public.pos_request_refund(uuid,uuid,uuid,uuid[],text,boolean),pos_private.request_refund(uuid,uuid,uuid,uuid[],text,boolean) from public,anon,authenticated;
revoke all on function pos_private.check_adjustment_pin(uuid,text),pos_private.reduce_line(uuid,uuid,uuid,integer,uuid,text,text),pos_private.request_refund_v2(uuid,uuid,uuid,jsonb,text,text,boolean),public.pos_reduce_order_line(uuid,uuid,uuid,integer,uuid,text,text),public.pos_request_refund_v2(uuid,uuid,uuid,jsonb,text,text,boolean) from public,anon,authenticated;
grant execute on function pos_private.reduce_line(uuid,uuid,uuid,integer,uuid,text,text),pos_private.request_refund_v2(uuid,uuid,uuid,jsonb,text,text,boolean),public.pos_reduce_order_line(uuid,uuid,uuid,integer,uuid,text,text),public.pos_request_refund_v2(uuid,uuid,uuid,jsonb,text,text,boolean) to authenticated;

create or replace function pos_private.void_line(b uuid,p_order uuid,p_line uuid,p_pin text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;l public.pos_order_lines;hash text;n integer;bucket timestamptz:=to_timestamp(floor(extract(epoch from now())/900)*900);remaining_subtotal bigint;service bigint;tax bigint;newtotal bigint;j public.pos_print_jobs;items jsonb;begin
 perform pos_private.require_access(b,'orders');perform pos_private.require_access(b,'pay');
 if length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Alasan pembatalan wajib 3–300 karakter';end if;
 select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;
 select * into l from public.pos_order_lines where business_id=b and order_id=o.id and id=p_line for update;
 if not found then raise exception 'Item tidak ditemukan';end if;
 if l.voided_at is not null then return jsonb_build_object('ok',true);end if;
 if o.status<>'open' then raise exception 'Item Complete memerlukan approval refund owner';end if;
 select pin_hash into hash from pos_private.cancel_config where business_id=b;
 if hash is null then return jsonb_build_object('ok',false,'error','Owner perlu mengatur PIN pembatalan');end if;
 insert into pos_private.cancel_attempts values(b,auth.uid(),bucket,1) on conflict(business_id,user_id) do update set attempts=case when cancel_attempts.bucket=excluded.bucket then cancel_attempts.attempts+1 else 1 end,bucket=excluded.bucket returning attempts into n;
 if n>5 then return jsonb_build_object('ok',false,'error','Batas percobaan PIN tercapai. Coba kembali setelah 15 menit');end if;
 if p_pin is null or p_pin !~ '^[0-9]{6}$' or extensions.crypt(p_pin,hash)<>hash then return jsonb_build_object('ok',false,'error','PIN tidak benar');end if;

 select coalesce(sum(price*qty),0) into remaining_subtotal from public.pos_order_lines where order_id=o.id and voided_at is null and id<>l.id;
 service:=round(remaining_subtotal::numeric*o.service_bps/10000)::bigint;tax:=round((remaining_subtotal+case when o.tax_on_service then service else 0 end)::numeric*o.tax_bps/10000)::bigint;newtotal:=remaining_subtotal+service+tax;
 update public.pos_order_lines set voided_at=now(),voided_by=auth.uid(),voided_by_name=pos_private.actor_label(auth.uid()),void_reason=trim(p_reason),void_amount=o.total-newtotal where id=l.id;
 update public.pos_products set stock=stock+l.qty where business_id=b and id=l.product_id;
 insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id) values(b,l.product_id,o.id,l.qty,'item.void',auth.uid());
 if not exists(select 1 from public.pos_order_lines where order_id=o.id and voided_at is null) then
  update public.pos_orders set status='cancelled',cancel_reason=trim(p_reason),cancelled_by=auth.uid(),cancelled_at=now() where id=o.id;
 else
  update public.pos_orders set subtotal=remaining_subtotal,total=newtotal,service_amount=service,tax_amount=tax where id=o.id;
 end if;
 -- Pending kitchen tickets contain only active items; send a separate correction ticket if already printed.
 for j in select * from public.pos_print_jobs where business_id=b and order_id=o.id and status in ('queued','printed') and coalesce(payload->>'kind','') not in ('void','reduce') loop
  if exists(select 1 from jsonb_array_elements(j.payload->'items') x where x->>'product_id'=l.product_id::text) then
   if j.status='queued' then
    select coalesce(jsonb_agg(x),'[]'::jsonb) into items from jsonb_array_elements(j.payload->'items') x where x->>'product_id'<>l.product_id::text;
    update public.pos_print_jobs set payload=jsonb_set(payload,'{items}',items),status=case when jsonb_array_length(items)=0 then 'cancelled' else 'queued' end where id=j.id;
   else
    insert into public.pos_print_jobs(business_id,order_id,section,payload) values(b,o.id,left(j.section,40)||' · VOID '||left(l.id::text,8),jsonb_build_object('kind','void','section',j.payload->'section','table',o.table_ref,'guest',o.guest_name,'items',jsonb_build_array(jsonb_build_object('product_id',l.product_id,'category_id',l.category_id,'name',l.name,'qty',l.qty,'note',trim(p_reason))))) on conflict on constraint pos_print_jobs_order_id_section_key do nothing;
   end if;
  end if;
 end loop;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'item.void',l.id);
 return jsonb_build_object('ok',true);
end$$;
