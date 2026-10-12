const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const reply=(status,data)=>new Response(JSON.stringify(data),{status,headers:cors});
export async function handle(req,env,fetcher=fetch){
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply(405,{message:'Metode tidak didukung'});
 if(Number(req.headers.get('content-length'))>8000)return reply(413,{message:'Permintaan terlalu besar'});
 let input;try{const text=await req.text();if(text.length>8000)return reply(413,{message:'Permintaan terlalu besar'});input=JSON.parse(text)}catch{return reply(400,{message:'Permintaan tidak valid'})}
 const url=env('SUPABASE_URL'),secret=env('SUPABASE_SERVICE_ROLE_KEY'),anon=env('SUPABASE_ANON_KEY');
 if(!url||!secret||!anon)return reply(503,{message:'Layanan staf belum siap'});
 const api=async(path,method='GET',body,token=secret)=>{const r=await fetcher(url+path,{method,headers:{apikey:secret,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});const text=await r.text();let data;try{data=JSON.parse(text)}catch{data={}}if(!r.ok)throw new Error(data.msg||data.message||'Request failed');return data};
 const username=String(input.username||'').trim().toLowerCase();
 if(input.action==='login'){
  if(!/^[a-z0-9_.-]{3,32}$/.test(username)||typeof input.password!=='string'||input.password.length>128)return reply(401,{message:'Username atau password tidak benar'});
  try{
   const ip=req.headers.get('x-forwarded-for')||'unknown';const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(ip)))).map(x=>x.toString(16).padStart(2,'0')).join('');
   const [userOk,ipOk]=await Promise.all([api('/rest/v1/rpc/pos_login_attempt','POST',{p_key:'user:'+username,p_limit:10}),api('/rest/v1/rpc/pos_login_attempt','POST',{p_key:'ip:'+hash,p_limit:50})]);
   if(!userOk||!ipOk)return reply(429,{message:'Terlalu banyak percobaan. Coba lagi dalam 15 menit.'});
   const accounts=await api('/rest/v1/pos_staff_accounts?select=user_id,business_id&username=eq.'+encodeURIComponent(username));
   const staff=accounts[0];if(!staff)return reply(401,{message:'Username atau password tidak benar'});
   const memberships=await api('/rest/v1/pos_memberships?select=active&business_id=eq.'+staff.business_id+'&user_id=eq.'+staff.user_id);
   if(!memberships[0]?.active)return reply(401,{message:'Username atau password tidak benar'});
   const identity=await api('/auth/v1/admin/users/'+staff.user_id);const authEmail=identity.email||identity.user?.email;
   const r=await fetcher(url+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:anon,'Content-Type':'application/json'},body:JSON.stringify({email:authEmail,password:input.password})});
   if(!r.ok)return reply(401,{message:'Username atau password tidak benar'});return reply(200,await r.json());
  }catch{return reply(503,{message:'Login staf belum dapat diproses. Coba lagi.'})}
 }
 if(input.action!=='create')return reply(400,{message:'Aksi tidak valid'});
 const bearer=req.headers.get('authorization')||'';if(!bearer.startsWith('Bearer '))return reply(401,{message:'Login owner diperlukan'});
 const b=String(input.business_id||'');if(!/^[0-9a-f-]{36}$/i.test(b))return reply(400,{message:'Bisnis tidak valid'});
 let owner;try{owner=await api('/auth/v1/user','GET',undefined,bearer.slice(7));const membership=await api('/rest/v1/pos_memberships?select=role,active&business_id=eq.'+b+'&user_id=eq.'+owner.id);if(!membership[0]?.active||membership[0].role!=='owner')return reply(403,{message:'Hanya owner dapat membuat staf'})}catch{return reply(401,{message:'Login owner diperlukan'})}
 const name=String(input.name||'').trim();if(name.length<1||name.length>80||!/^[a-z0-9_.-]{3,32}$/.test(username)||typeof input.password!=='string'||input.password.length<10||input.password.length>128||!['cashier','waiter'].includes(input.role))return reply(400,{message:'Isi nama, username 3–32 karakter, password 10–128 karakter, dan peran Kasir/Waiter'});
 let createdId;
 try{
  if((await api('/rest/v1/pos_staff_accounts?select=user_id&username=eq.'+encodeURIComponent(username))).length)return reply(409,{message:'Username sudah digunakan'});
  const id=crypto.randomUUID();const user=await api('/auth/v1/admin/users','POST',{id,email:'staff-'+id+'@pos.internal.invalid',password:input.password,email_confirm:true});createdId=user.id||user.user?.id;if(!createdId)throw new Error('Auth creation failed');
  await api('/rest/v1/rpc/pos_finalize_staff','POST',{p_owner:owner.id,b,p_user:createdId,p_name:name,p_username:username,p_role:input.role});
  return reply(201,{user_id:createdId,name,username,role:input.role});
 }catch{
  // Compensate only the just-created Auth user if atomic membership creation failed.
  if(createdId)await api('/auth/v1/admin/users/'+createdId,'DELETE').catch(()=>{});
  return reply(400,{message:'Akun belum dapat dibuat. Username mungkin sudah digunakan; coba lagi.'});
 }
}
if(typeof Deno!=='undefined')Deno.serve(req=>handle(req,k=>Deno.env.get(k)));
