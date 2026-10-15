const DB='sums-pos-device-v1';let flight;
function open(){if(!globalThis.indexedDB)return Promise.reject(Error('Penyimpanan offline tidak tersedia di browser ini.'));if(!flight)flight=new Promise((resolve,reject)=>{const r=indexedDB.open(DB,1);r.onupgradeneeded=()=>{r.result.createObjectStore('snapshots',{keyPath:'key'});r.result.createObjectStore('commands',{keyPath:['user','business','id']});};r.onerror=()=>{flight=null;reject(r.error)};r.onblocked=()=>{flight=null;reject(Error('Tutup tab POS lama lalu coba lagi.'))};r.onsuccess=()=>{const db=r.result;db.onversionchange=()=>{db.close();flight=null};resolve(db)}});return flight;}
async function transact(name,mode,fn){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction(name,mode),s=tx.objectStore(name);let result;try{const request=fn(s);request.onsuccess=()=>result=request.result;request.onerror=()=>reject(request.error);}catch(e){tx.abort();reject(e)}tx.oncomplete=()=>resolve(result);tx.onabort=()=>reject(tx.error||Error('Data belum tersimpan.'));tx.onerror=()=>reject(tx.error);});}
const all=name=>transact(name,'readonly',s=>s.getAll());
export const offlineStore={
 async snapshot(user,business){if(business)return transact('snapshots','readonly',s=>s.get(user+':'+business));return (await all('snapshots')).filter(s=>s.user===user).sort((a,b)=>b.savedAt-a.savedAt)[0]||null;},
 saveSnapshot:s=>transact('snapshots','readwrite',store=>store.put(s)),
 async list(user,business){return (await all('commands')).filter(c=>c.user===user&&(!business||c.business===business)).sort((a,b)=>a.createdAt.localeCompare(b.createdAt)||(a.kind==='order'?-1:1));},
 put:c=>transact('commands','readwrite',s=>s.put(c)),
 // add prevents an uncertain retry from overwriting an immutable request.
 add:c=>transact('commands','readwrite',s=>s.add(c)),
 async forgetSnapshots(user){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction('snapshots','readwrite'),s=tx.objectStore('snapshots'),r=s.openCursor();r.onsuccess=()=>{const c=r.result;if(c){if(c.value.user===user)c.delete();c.continue()}};tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);});}
};
export function deviceId(){let id=localStorage.getItem('sums-pos-device');if(!id){id=crypto.randomUUID();localStorage.setItem('sums-pos-device',id)}return id;}
export async function withOutboxLock(user,business,fn){if(!navigator.locks?.request)throw Error('Browser ini belum mendukung kunci transaksi offline. Gunakan Chrome/Safari terbaru.');return navigator.locks.request('sums-pos-outbox:'+user+':'+business,fn);}
