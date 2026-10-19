export const permissions={owner:['dashboard','pos','orders','products','reports','settings'],admin:['products'],cashier:['pos','orders'],waiter:['pos','orders']};
export function money(n){return new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(n)}
export function total(lines){return lines.reduce((s,l)=>s+l.price*l.qty,0)}
export function placeOrder(business,cart,details,role){
 if(!permissions[role]?.includes('pos'))throw Error('Akses ditolak');
 if(!cart.length)throw Error('Pilih produk terlebih dahulu');
 const counts=new Map();
 for(const l of cart){if(!Number.isSafeInteger(l.qty)||l.qty<=0)throw Error('Jumlah tidak valid');counts.set(l.id,(counts.get(l.id)||0)+l.qty)}
 const lines=[...counts].map(([id,qty])=>{const p=business.products.find(p=>p.id===id);if(!p||!p.active)throw Error('Produk tidak tersedia');if(p.stock<qty)throw Error(`Stok ${p.name} tidak cukup`);return {id,name:p.name,price:p.price,qty,purchase_cost:p.purchase_cost??null,category_id:p.category_id,category_name:p.category}});
 const order={id:crypto.randomUUID(),number:`POS-${String(business.orders.length+1).padStart(4,'0')}`,createdAt:new Date().toISOString(),lines,total:total(lines),status:'open',table:details.table.trim(),note:details.note.trim(),type:details.type};
 for(const l of lines)business.products.find(p=>p.id===l.id).stock-=l.qty;
 business.orders.unshift(order);return order;
}
export function payOrder(business,id,method,tendered,role){
 if(!['owner','cashier'].includes(role))throw Error('Pembayaran hanya untuk kasir atau owner');
 const order=business.orders.find(o=>o.id===id);if(!order||order.status!=='open')throw Error('Pesanan sudah ditutup atau tidak ditemukan');
 if(method!=='cash')throw Error('Versi demo hanya mencatat pembayaran tunai');
 if(!Number.isSafeInteger(tendered)||tendered<order.total)throw Error('Uang diterima kurang dari total');
 Object.assign(order,{status:'paid',method,tendered,change:tendered-order.total,paidAt:new Date().toISOString()});return order;
}
export function cancelOrder(business,id,role){if(role!=='owner')throw Error('Pembatalan hanya untuk owner');const o=business.orders.find(o=>o.id===id);if(!o||o.status!=='open')throw Error('Pesanan tidak dapat dibatalkan');for(const l of o.lines){const p=business.products.find(p=>p.id===l.id);if(p)p.stock+=l.qty}o.status='cancelled';return o}
export function sales(business,days,now=new Date()) {const start=new Date(now);start.setHours(0,0,0,0);start.setDate(start.getDate()-(days-1));return business.orders.filter(o=>o.status==='paid'&&new Date(o.paidAt)>=start&&new Date(o.paidAt)<=now)}
