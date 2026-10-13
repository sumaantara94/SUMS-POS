alter table public.pos_order_lines add column voided_at timestamptz,add column voided_by uuid references auth.users(id),add column voided_by_name text,add column void_reason text,add column void_amount bigint;
create index pos_lines_voided_by_idx on public.pos_order_lines(voided_by) where voided_by is not null;
create or replace function pos_private.cancel_order_v2(b uuid,p_order uuid,p_pin text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;l record;hash text;n integer;bucket timestamptz:=to_timestamp(floor(extract(epoch from now())/900)*900);begin
 perform pos_private.require_access(b,'orders');
 if not pos_private.allowed(b,'pay') then raise exception 'Hanya kasir atau owner dapat membatalkan';end if;
 if length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Alasan pembatalan wajib 3–300 karakter';end if;
 select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;
 if o.status='cancelled' then return jsonb_build_object('ok',true,'id',o.id);end if;
 if o.status<>'open' then raise exception 'Pesanan lunas tidak dapat dibatalkan';end if;
 select pin_hash into hash from pos_private.cancel_config where business_id=b;
 if hash is null then return jsonb_build_object('ok',false,'error','Owner perlu mengatur PIN pembatalan');end if;
 insert into pos_private.cancel_attempts values(b,auth.uid(),bucket,1) on conflict(business_id,user_id) do update set attempts=case when cancel_attempts.bucket=excluded.bucket then cancel_attempts.attempts+1 else 1 end,bucket=excluded.bucket returning attempts into n;
 if n>5 then return jsonb_build_object('ok',false,'error','Batas percobaan PIN tercapai. Coba kembali setelah 15 menit');end if;
 if p_pin is null or p_pin !~ '^[0-9]{6}$' or extensions.crypt(p_pin,hash)<>hash then return jsonb_build_object('ok',false,'error','PIN tidak benar');end if;
 for l in select * from public.pos_order_lines where order_id=o.id and voided_at is null order by product_id loop
  update public.pos_products set stock=stock+l.qty where business_id=b and id=l.product_id;
  insert into public.pos_stock_movements(business_id,product_id,order_id,delta,reason,actor_id) values(b,l.product_id,o.id,l.qty,'order.release',auth.uid());
 end loop;
 update public.pos_orders set status='cancelled',cancel_reason=trim(p_reason),cancelled_by=auth.uid(),cancelled_at=now() where id=o.id;
 update public.pos_print_jobs set status='cancelled' where order_id=o.id and status='queued';
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'order.cancelled.pin',o.id);
 return jsonb_build_object('ok',true,'id',o.id);
end$$;
create or replace function pos_private.pay_order_v3(b uuid,p_order uuid,p_discount uuid,p_payments jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;q jsonb;entry jsonb;paid bigint:=0;amount bigint;tendered bigint;assigned bigint:=0;share bigint;l record;begin
 perform pos_private.require_access(b,'pay');select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found then raise exception 'Pesanan tidak ditemukan';end if;
 if o.status='paid' then return o.id;end if;
 q:=pos_private.checkout_quote(b,p_order,p_discount);
 if p_payments is null or jsonb_typeof(p_payments)<>'array' or jsonb_array_length(p_payments) not between 1 and 10 then raise exception 'Isi 1–10 bagian pembayaran';end if;
 for entry in select value from jsonb_array_elements(p_payments) loop
  if coalesce(entry->>'method','') not in ('cash','credit_card','debit_card','qr','bank_transfer','other') or coalesce(entry->>'amount','') !~ '^[0-9]+$' or (entry->>'amount')::numeric>1000000000000 then raise exception 'Metode atau nominal pembayaran tidak valid';end if;
  amount:=(entry->>'amount')::bigint;
  if amount=0 and (q->>'total')::bigint<>0 then raise exception 'Nominal setiap pembayaran harus positif';end if;
  if entry->>'method'='cash' then
   if coalesce(entry->>'tendered','') !~ '^[0-9]+$' or (entry->>'tendered')::numeric>1000000000000 then raise exception 'Uang tunai diterima tidak valid';end if;
   tendered:=(entry->>'tendered')::bigint;if tendered<amount then raise exception 'Tunai diterima kurang dari alokasi cash';end if;
  else tendered:=amount;end if;
  paid:=paid+amount;
  insert into public.pos_payments(business_id,order_id,paid_by,amount,tendered,change,method,reference) values(b,o.id,auth.uid(),amount,tendered,tendered-amount,entry->>'method',coalesce(entry->>'reference',''));
 end loop;
 if paid<>(q->>'total')::bigint then raise exception 'Total bagian pembayaran harus sama dengan tagihan';end if;
 for l in select id,sum(price*qty) over(order by id) cumulative from public.pos_order_lines where order_id=o.id and voided_at is null order by id loop
  share:=case when o.subtotal=0 then 0 else floor((q->>'discount')::numeric*l.cumulative/o.subtotal)::bigint-assigned end;
  assigned:=assigned+share;update public.pos_order_lines set discount_amount=share where id=l.id;
 end loop;
 update public.pos_orders set total=(q->>'total')::bigint,discount_amount=(q->>'discount')::bigint,discount_id=p_discount,discount_name=q->>'discount_name',service_amount=(q->>'service')::bigint,tax_amount=(q->>'tax')::bigint,status='paid',paid_at=now() where id=o.id;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'order.paid',o.id);return o.id;
end$$;
create or replace function pos_private.request_refund(b uuid,p_order uuid,p_request uuid,p_lines uuid[],p_reason text,p_restock boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.pos_orders;r uuid;items jsonb;net bigint;tax bigint;service bigint;begin
 perform pos_private.require_access(b,'pay');
 if p_request is null or p_restock is null or length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Isi alasan refund 3–300 karakter';end if;
 select * into o from public.pos_orders where business_id=b and id=p_order for update;
 if not found or o.status<>'paid' then raise exception 'Refund hanya untuk pesanan Complete';end if;
 select id into r from public.pos_refund_requests where business_id=b and request_id=p_request;if found then return r;end if;
 if coalesce(cardinality(p_lines),0)=0 or cardinality(p_lines)<>(select count(distinct x) from unnest(p_lines) x) or exists(select 1 from unnest(p_lines) x where x is null or not exists(select 1 from public.pos_order_lines l where l.business_id=b and l.order_id=o.id and l.id=x and l.voided_at is null)) then raise exception 'Pilih item refund yang valid';end if;
 if exists(select 1 from public.pos_refund_requests where business_id=b and order_id=o.id and status='pending') then raise exception 'Pesanan masih memiliki pengajuan pending';end if;
 if exists(select 1 from public.pos_refund_requests r,jsonb_array_elements(r.items) x where r.business_id=b and r.order_id=o.id and r.status in ('approved','completed') and (x->>'line_id')::uuid=any(p_lines)) then raise exception 'Item sudah diajukan atau direfund';end if;
 -- Allocate the original fee snapshots exactly once across full lines, including rounding remainders.
 with lines as (select l.*,l.price*l.qty-l.discount_amount n,sum(l.price*l.qty-l.discount_amount) over(order by l.id) cumulative from public.pos_order_lines l where l.order_id=o.id and l.voided_at is null),alloc as (
 select *,case when o.subtotal-o.discount_amount=0 then 0 else floor(o.service_amount::numeric*cumulative/(o.subtotal-o.discount_amount))-floor(o.service_amount::numeric*(cumulative-n)/(o.subtotal-o.discount_amount)) end s,
 case when o.subtotal-o.discount_amount=0 then 0 else floor(o.tax_amount::numeric*cumulative/(o.subtotal-o.discount_amount))-floor(o.tax_amount::numeric*(cumulative-n)/(o.subtotal-o.discount_amount)) end t from lines)
 select jsonb_agg(jsonb_build_object('line_id',id,'product_id',product_id,'name',name,'qty',qty,'net',n,'service',s,'tax',t,'amount',n+s+t) order by id),sum(n),sum(s),sum(t) into items,net,service,tax from alloc where id=any(p_lines);
 insert into public.pos_refund_requests(business_id,order_id,request_id,requested_by,requested_by_name,reason,items,amount,net_amount,tax_amount,service_amount,restock) values(b,o.id,p_request,auth.uid(),pos_private.actor_label(auth.uid()),trim(p_reason),items,net+tax+service,net,tax,service,p_restock) returning id into r;
 insert into public.pos_audit_events(business_id,actor_id,action,record_id) values(b,auth.uid(),'refund.requested',r);return r;
end$$;
create function pos_private.void_line(b uuid,p_order uuid,p_line uuid,p_pin text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
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
 for j in select * from public.pos_print_jobs where business_id=b and order_id=o.id and status in ('queued','printed') and coalesce(payload->>'kind','')<>'void' loop
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
create function public.pos_void_line(b uuid,p_order uuid,p_line uuid,p_pin text,p_reason text) returns jsonb language sql security invoker set search_path='' as $$select pos_private.void_line(b,p_order,p_line,p_pin,p_reason)$$;
revoke all on function pos_private.void_line(uuid,uuid,uuid,text,text),public.pos_void_line(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function pos_private.void_line(uuid,uuid,uuid,text,text),public.pos_void_line(uuid,uuid,uuid,text,text) to authenticated;
