// Durable device outbox. Credentials and PINs never belong in these records.
import {chargeTotals} from './payments.mjs';
export const OFFLINE_LEASE_MS=12*60*60*1000;
export function leaseValid(snapshot,now=Date.now()) {return Boolean(snapshot&&Number.isFinite(snapshot.savedAt)&&now>=snapshot.savedAt&&now-snapshot.savedAt<OFFLINE_LEASE_MS&&snapshot.business.membership?.active);}
export function offlineSnapshot(user,business,now=Date.now()) {
 const fields=['id','name','category','accent','timezone','logo_data','receipt_width','restaurant_mode','waiter_enabled','tax_bps','service_bps','tax_on_service','membership','categories','areas','tables','print_sections'];
 const b=Object.fromEntries(fields.filter(k=>business[k]!==undefined).map(k=>[k,structuredClone(business[k])]));
 b.products=business.products.map(({purchase_cost,...p})=>structuredClone(p));
 Object.assign(b,{orders:business.orders.filter(o=>o.status==='open'&&!o.local).map(o=>({...structuredClone(o),lines:o.lines.map(({purchase_cost,...l})=>structuredClone(l))})),members:[],staffAccounts:[],discounts:[],printJobs:[],openOrders:[],refunds:[],mailJobs:[],adjustments:[]});
 return {key:user+':'+business.id,user,business:b,savedAt:now};
}
export function makeOrder(snapshot,cart,{request,device,type='takeaway',table=null,guest='',reservation=null,note=''},now=Date.now()) {
 if(!leaseValid(snapshot,now))throw Error('Hubungkan internet untuk memperbarui izin offline (berlaku 12 jam).');
 const b=snapshot.business,m=b.membership;
 if(!(m.role==='owner'||m.permissions?.includes('pos')))throw Error('Akses pesanan ditolak');
 if(!cart.length||cart.length>100)throw Error('Isi 1–100 produk');
 const lines=cart.map(l=>{const p=b.products.find(p=>p.id===l.id);if(!p?.active||!Number.isSafeInteger(l.qty)||l.qty<1||l.qty>p.stock)throw Error('Produk atau stok lokal tidak cukup');return {id:p.id,name:p.name,price:p.price,qty:l.qty,note:l.item_note||''};});
 if(new Set(lines.map(l=>l.id)).size!==lines.length)throw Error('Produk duplikat');
 const subtotal=lines.reduce((s,l)=>s+l.price*l.qty,0),q=chargeTotals({...b,subtotal});
 return {id:request,user:snapshot.user,business:b.id,device,kind:'order',status:'pending',createdAt:new Date(now).toISOString(),payload:{request,lines,type,table,guest,reservation,note,tax_bps:b.tax_bps||0,service_bps:b.service_bps||0,tax_on_service:Boolean(b.tax_on_service),expected_total:q.total},local:{id:request,request_id:request,number:'LOCAL-'+request.slice(0,8).toUpperCase(),createdAt:new Date(now).toISOString(),type,table:b.tables?.find(t=>t.id===table)?.name||'',table_id:table,guest_name:guest,note,lines:lines.map(l=>({...l,line_id:l.id,item_note:l.note})),subtotal,total:q.total,service_amount:q.service,tax_amount:q.tax,tax_bps:b.tax_bps||0,service_bps:b.service_bps||0,tax_on_service:Boolean(b.tax_on_service),status:'open',payments:[],local:true}};
}
export function makeCash(snapshot,order,tendered,{request,device},now=Date.now()) {
 if(!leaseValid(snapshot,now))throw Error('Hubungkan internet untuk memperbarui izin offline.');
 const m=snapshot.business.membership;if(!(m.role==='owner'||m.permissions?.includes('pay')))throw Error('Akses pembayaran ditolak');
 if(!order.local||order.status!=='open')throw Error('Offline hanya untuk pesanan lokal baru yang belum dibayar.');
 if(!Number.isSafeInteger(tendered)||tendered<order.total||tendered>1e12)throw Error('Uang tunai diterima tidak valid');
 return {id:request,user:snapshot.user,business:snapshot.business.id,device,kind:'cash',status:'pending',createdAt:new Date(now).toISOString(),payload:{order_request:order.request_id,expected_total:order.total,tendered}};
}
export function overlayOutbox(business,commands) {
 const b=structuredClone(business),existing=new Set(b.orders.map(o=>o.request_id));
 for(const c of commands.filter(c=>c.kind==='order')){
  if(existing.has(c.id))continue;
  const o={...structuredClone(c.local),syncStatus:c.status,syncError:c.error||'',serverId:c.result?.order_id};
  const cash=commands.find(p=>p.kind==='cash'&&p.payload.order_request===c.id);
  if(cash){o.status='paid';o.paidAt=cash.createdAt;o.method='cash';o.tendered=cash.payload.tendered;o.change=o.tendered-o.total;o.payments=[{method:'cash',amount:o.total,tendered:o.tendered,change:o.change}];o.syncStatus=cash.status==='synced'?c.status:cash.status;o.syncError=cash.error||o.syncError;}
  b.orders.unshift(o);
  for(const l of o.lines){const p=b.products.find(p=>p.id===l.id);if(p)p.stock=Math.max(0,p.stock-l.qty);}
 }
 // A synced order may be visible before its queued cash settlement arrives.
 for(const c of commands.filter(c=>c.kind==='cash')){const o=b.orders.find(o=>o.request_id===c.payload.order_request);if(o&&!o.local&&(c.status!=='synced'||o.status!=='paid')){o.localPaymentPending=true;o.syncStatus=c.status;o.syncError=c.error||'';if(o.status==='open'){o.status='paid';o.paidAt=c.createdAt;o.method='cash';o.payments=[{method:'cash',amount:c.payload.expected_total,tendered:c.payload.tendered,change:c.payload.tendered-c.payload.expected_total}];}}}
 return b;
}
export const retryable=e=>e?.retryable===true||e instanceof TypeError||['TimeoutError','AbortError'].includes(e?.name);
export async function drainOutbox({store,user,business,send,onChange=()=>{}}) {
 const commands=await store.list(user,business);
 for(const c of commands.filter(c=>c.status==='pending')){
  if(c.kind==='cash'&&!commands.some(o=>o.id===c.payload.order_request&&o.status==='synced'))continue;
  try {c.result=await send(c);c.status='synced';c.error='';await store.put(c);await onChange(c);}
  catch(e){c.error=String(e.message||e);if(!retryable(e))c.status='review';await store.put(c);await onChange(c);if(retryable(e)||e.status===401||e.status===403)break;}
 }
}
