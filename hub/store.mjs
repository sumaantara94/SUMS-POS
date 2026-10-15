import {DatabaseSync} from 'node:sqlite';
import {createHash,createHmac,randomBytes,timingSafeEqual} from 'node:crypto';
import {chargeTotals} from '../src/payments.mjs';
export const digest=s=>createHash('sha256').update(s).digest('hex');
export const sign=(secret,text)=>createHmac('sha256',Buffer.from(secret,'hex')).update(text).digest('hex');
export const equal=(a,b)=>typeof a==='string'&&typeof b==='string'&&a.length===b.length&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
const uuid=s=>typeof s==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
const assert=(v,msg)=>{if(!v)throw Error(msg)};
export const may=(s,p)=>s.role==='owner'||s.permissions.includes(p);
export class HubStore{
 constructor(file){this.db=new DatabaseSync(file,{timeout:5000});this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;
 CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY,user TEXT NOT NULL,device TEXT NOT NULL,role TEXT NOT NULL,permissions TEXT NOT NULL,expires INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS commands(seq INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,user TEXT NOT NULL,device TEXT NOT NULL,kind TEXT NOT NULL,order_ref TEXT NOT NULL,document TEXT NOT NULL,signature TEXT NOT NULL,local_order TEXT,status TEXT NOT NULL DEFAULT 'pending',error TEXT NOT NULL DEFAULT '',result TEXT);
 CREATE UNIQUE INDEX IF NOT EXISTS one_cash_per_order ON commands(order_ref) WHERE kind='cash';`);}
 get(key){const r=this.db.prepare('select value from settings where key=?').get(key);return r?JSON.parse(r.value):null;}
 set(key,value){this.db.prepare('insert into settings values(?,?) on conflict(key) do update set value=excluded.value').run(key,JSON.stringify(value));}
 configure(config){assert(!this.get('config'),'Hub sudah dikonfigurasi');assert(uuid(config.hub)&&uuid(config.business)&&/^[0-9a-f]{64}$/.test(config.secret),'Konfigurasi Hub tidak valid');this.set('config',config);}
 enroll({user,device,role,permissions},now=Date.now()){assert(uuid(user)&&uuid(device)&&Array.isArray(permissions),'Perangkat tidak valid');assert(role==='owner'||permissions.includes('pos'),'Akses POS ditolak');const token=randomBytes(32).toString('base64url'),expires=now+12*3600000;this.db.prepare('delete from sessions where expires<?').run(now);this.db.prepare('insert into sessions values(?,?,?,?,?,?)').run(digest(token),user,device,role,JSON.stringify(permissions),expires);return {token,expires,user,device,business:this.get('config').business};}
 session(token,now=Date.now()){const row=typeof token==='string'&&token.length<200?this.db.prepare('select * from sessions where hash=?').get(digest(token)):null;assert(row&&row.expires>now,'Sesi Hub berakhir. Hubungkan internet dan sambungkan perangkat kembali.');return {...row,permissions:JSON.parse(row.permissions)};}
 beginSnapshot(){return this.rows().filter(c=>c.status==='synced').map(c=>c.id);}
 snapshot(catalog,included){this.set('catalog',{...catalog,included,savedAt:Date.now()});}
 rows(){return this.db.prepare('select * from commands order by seq').all().map(r=>({...r,command:JSON.parse(r.document),local:r.local_order?JSON.parse(r.local_order):null,result:r.result?JSON.parse(r.result):null}));}
 view(session){const catalog=this.get('catalog'),rows=this.rows();const commands=rows.filter(r=>r.kind==='order'||may(session,'pay')).map(r=>({id:r.id,user:r.user,device:r.device,business:r.command.business,kind:r.kind,createdAt:r.command.createdAt,payload:r.command.payload,local:r.local?{...r.local,...(rows.some(c=>c.kind==='cash'&&c.order_ref===r.id)||catalog?.paidRequests.includes(r.id)?{status:'paid',paidAt:rows.find(c=>c.kind==='cash'&&c.order_ref===r.id)?.command.createdAt||r.command.createdAt}:{}),...((catalog?.cancelledRequests||[]).includes(r.id)?{status:'cancelled'}:{})}:null,status:r.status,error:r.error,result:r.result,document:r.document,signature:r.signature}));const paid=rows.filter(r=>r.kind==='cash').map(r=>r.order_ref);const tables=(catalog?.tables||[]).map(t=>({...t,...(t.reserved_at&&rows.some(r=>r.kind==='order'&&r.command.payload.table===t.id&&r.command.payload.reservation===t.reserved_at)?{reserved_at:null,reservation_guest:null}:{})}));return {hub:this.get('config').hub,business:this.get('config').business,catalogAt:catalog?.savedAt||null,tables,commands,paid,version:(catalog?.savedAt||0)+':'+rows.map(r=>r.seq+':'+r.status).join(',')};}
 stock(catalog,rows,id){const p=catalog.products.find(p=>p.id===id);return (p?.stock||0)-rows.filter(r=>r.kind==='order'&&!catalog.included.includes(r.id)).reduce((n,r)=>n+(r.command.payload.lines.find(l=>l.id===id)?.qty||0),0);}
 submit(session,input,now=Date.now()){
  const cfg=this.get('config');assert(cfg,'Owner perlu mengaktifkan Hub');assert(input&&uuid(input.id)&&input.user===session.user&&input.device===session.device&&input.business===cfg.business,'Identitas transaksi/perangkat berbeda');
  assert(['order','cash'].includes(input.kind)&&input.payload&&typeof input.payload==='object','Transaksi tidak valid');
  const document=JSON.stringify({hub:cfg.hub,business:cfg.business,id:input.id,actor:session.user,device:session.device,kind:input.kind,createdAt:input.createdAt,payload:input.payload});assert(document.length<100000,'Transaksi terlalu besar');
  assert(Number.isFinite(Date.parse(input.createdAt))&&Date.parse(input.createdAt)<=now+300000,'Waktu perangkat tidak valid');
  this.db.exec('begin immediate');try{
   const old=this.db.prepare('select * from commands where id=?').get(input.id);if(old){assert(old.document===document,'ID transaksi sudah dipakai untuk isi berbeda');this.db.exec('commit');return {id:old.id,status:old.status,accepted:true};}
   const cat=this.get('catalog');assert(cat&&now>=cat.savedAt&&now-cat.savedAt<12*3600000,'Katalog Hub perlu diperbarui saat online');
   const rows=this.rows();let local=null,ref=input.id;
   if(input.kind==='order'){
    assert(may(session,'pos'),'Izin pesanan ditolak');const p=input.payload;assert(p.request===input.id&&['takeaway','dinein'].includes(p.type)&&Array.isArray(p.lines)&&p.lines.length>0&&p.lines.length<=100,'Isi pesanan tidak valid');
    assert(new Set(p.lines.map(l=>l.id)).size===p.lines.length,'Produk duplikat');
    assert(p.tax_bps===cat.tax_bps&&p.service_bps===cat.service_bps&&p.tax_on_service===cat.tax_on_service,'Tax/service berbeda dari katalog Hub');
    const lines=p.lines.map(l=>{const product=cat.products.find(x=>x.id===l.id);assert(product?.active&&product.price===l.price&&Number.isSafeInteger(l.qty)&&l.qty>0&&l.qty<=this.stock(cat,rows,l.id),'Harga berubah atau stok Hub tidak cukup');assert(typeof l.note==='string'&&l.note.length<=300,'Catatan terlalu panjang');return {id:l.id,line_id:l.id,name:product.name,price:product.price,qty:l.qty,item_note:l.note,category_id:product.category_id};});
    assert(typeof p.guest==='string'&&p.guest.length<=80&&typeof p.note==='string'&&p.note.length<=300,'Nama/catatan tidak valid');
    if(session.role==='waiter')assert(cat.restaurant_mode&&cat.waiter_enabled&&p.type==='dinein'&&p.table&&p.guest.trim(),'Mode waiter perlu meja dan nama tamu');
    if(cat.restaurant_mode&&p.type==='dinein')assert(p.table&&p.guest.trim(),'Pilih meja dan nama tamu');
    if(p.table){const t=cat.tables.find(t=>t.id===p.table);assert(cat.restaurant_mode&&p.type==='dinein'&&t?.active,'Meja tidak aktif');const reservation=t.reserved_at&&rows.some(r=>r.kind==='order'&&r.command.payload.table===t.id&&r.command.payload.reservation===t.reserved_at)?null:t.reserved_at||null;assert(reservation===(p.reservation||null),'Reservasi meja berubah');assert(!cat.openOrders.some(o=>o.table_id===p.table&&!rows.some(c=>c.kind==='cash'&&c.order_ref===o.request_id))&&!rows.some(o=>o.kind==='order'&&o.command.payload.table===p.table&&!rows.some(c=>c.kind==='cash'&&c.order_ref===o.id)&&!cat.paidRequests.includes(o.id)&&!(cat.cancelledRequests||[]).includes(o.id)),'Meja sedang digunakan');}
    const subtotal=lines.reduce((n,l)=>n+l.qty*l.price,0),q=chargeTotals({...cat,subtotal});assert(Number.isSafeInteger(q.total)&&q.total<=1e12&&p.expected_total===q.total,'Total tidak cocok atau terlalu besar');local={id:input.id,request_id:input.id,number:'LAN-'+input.id.slice(0,8).toUpperCase(),createdAt:input.createdAt,type:p.type,table:cat.tables.find(t=>t.id===p.table)?.name||'',table_id:p.table,guest_name:p.guest,note:p.note,created_by_name:session.user,created_role:session.role,lines,subtotal,total:q.total,tax_amount:q.tax,service_amount:q.service,tax_bps:cat.tax_bps,service_bps:cat.service_bps,tax_on_service:cat.tax_on_service,status:'open',payments:[],local:true,lan:true};
   }else{
    assert(may(session,'pay'),'Waiter tidak boleh menerima pembayaran');const p=input.payload;ref=p.order_request;const original=rows.find(r=>r.id===ref&&r.kind==='order');assert(original&&original.status!=='review','Pesanan asal belum diterima Hub/perlu diperiksa');assert(!rows.some(r=>r.kind==='cash'&&r.order_ref===ref)&&!cat.paidRequests.includes(ref),'Pesanan sudah dibayar');assert(Number.isSafeInteger(p.tendered)&&p.tendered>=original.local.total&&p.tendered<=1e12&&p.expected_total===original.local.total,'Nominal tunai tidak sesuai');
   }
   this.db.prepare('insert into commands(id,user,device,kind,order_ref,document,signature,local_order) values(?,?,?,?,?,?,?,?)').run(input.id,session.user,session.device,input.kind,ref,document,sign(cfg.secret,document),local?JSON.stringify(local):null);this.db.exec('commit');return {id:input.id,status:'pending',accepted:true};
  }catch(e){this.db.exec('rollback');throw e;}
 }
 acknowledge(id,result){const row=this.db.prepare('select * from commands where id=?').get(id);assert(row&&uuid(result?.order_id),'Acknowledgement tidak valid');const proof=sign(this.get('config').secret,'ack:'+row.document+':'+result.order_id);assert(equal(proof,result.proof),'Bukti cloud tidak valid');this.db.prepare("update commands set status='synced',result=?,error='' where id=?").run(JSON.stringify(result),id);}
 review(session,id,error){assert(may(session,'pay'),'Izin kasir diperlukan');this.db.prepare("update commands set status='review',error=? where id=? and status<>'synced'").run(String(error).slice(0,300),id);}
 retry(session){assert(may(session,'pay'),'Izin kasir diperlukan');this.db.exec("update commands set status='pending',error='' where status='review'");}
 revoke(token){this.db.prepare('delete from sessions where hash=?').run(digest(token));}
 close(){this.db.close();}
}
