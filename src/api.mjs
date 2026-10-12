import {supabaseUrl,publishableKey} from './config.mjs';
const storageKey='sums-pos-session';
let session=null,refreshing=null;
try{session=JSON.parse(sessionStorage.getItem(storageKey))}catch{}
export const getSession=()=>session;
function keep(value){session=value?.access_token?{...value,expires_at:Date.now()/1000+value.expires_in}:null;if(session)sessionStorage.setItem(storageKey,JSON.stringify(session));else sessionStorage.removeItem(storageKey)}
async function request(path,{method='GET',body,auth=true}={}){
 if(auth&&!session?.access_token)throw Error('Silakan login');
 if(auth&&session.expires_at<Date.now()/1000+45){if(!refreshing)refreshing=request('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:session.refresh_token},auth:false}).then(keep).catch(e=>{keep(null);throw e}).finally(()=>refreshing=null);await refreshing}
 const response=await fetch(supabaseUrl+path,{method,headers:{apikey:publishableKey,...(auth?{Authorization:'Bearer '+session.access_token}:{}),'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 const data=await response.text();let value;try{value=JSON.parse(data)}catch{value=data}
 if(!response.ok)throw Error(value?.msg||value?.message||value?.error_description||'Koneksi gagal. Coba lagi.');return value;
}
export async function login(email,password){keep(await request(email.includes('@')?'/auth/v1/token?grant_type=password':'/functions/v1/staff-access',{method:'POST',body:email.includes('@')?{email,password}:{action:'login',username:email,password},auth:false}));return session}
export async function signup(email,password){const data=await request('/auth/v1/signup',{method:'POST',body:{email,password},auth:false});if(data.access_token)keep(data);return data}
export async function logout(){try{await request('/auth/v1/logout',{method:'POST'})}finally{keep(null)}}
export async function verifySession(){if(!session)return null;const user=await request('/auth/v1/user');session.user=user;return session}
export const rpc=(name,args)=>request('/rest/v1/rpc/'+name,{method:'POST',body:args});
export async function loadBusinesses(){const [businesses,memberships]=await Promise.all([request('/rest/v1/pos_businesses?select=*&order=created_at.asc'),request('/rest/v1/pos_memberships?select=*&user_id=eq.'+session.user.id)]);return businesses.map(b=>({...b,products:[],orders:[],membership:memberships.find(m=>m.business_id===b.id)})).filter(b=>b.membership?.active)}
export async function loadBusiness(id){const filter='business_id=eq.'+encodeURIComponent(id);const [products,orders,members,categories,staffAccounts,areas,tables,discounts,printJobs,config,openOrders]=await Promise.all([request('/rest/v1/pos_products?select=*&'+filter+'&order=name.asc'),request('/rest/v1/pos_orders?select=*,pos_order_lines(*),pos_payments(*)&'+filter+'&order=created_at.desc&limit=1000'),request('/rest/v1/pos_memberships?select=*&'+filter),request('/rest/v1/pos_categories?select=*&'+filter+'&order=name.asc'),request('/rest/v1/pos_staff_accounts?select=*&'+filter+'&order=name.asc'),request('/rest/v1/pos_areas?select=*&'+filter+'&order=name.asc'),request('/rest/v1/pos_tables?select=*&'+filter+'&order=name.asc'),request('/rest/v1/pos_discounts?select=*&'+filter+'&order=starts_at.desc'),request('/rest/v1/pos_print_jobs?select=*&'+filter+'&status=eq.queued&order=created_at.asc'),request('/rest/v1/pos_businesses?select=*&id=eq.'+encodeURIComponent(id)),request('/rest/v1/pos_orders?select=*&'+filter+'&status=eq.open')]);return {...config[0],products,orders:orders.map(o=>({...o,number:'POS-'+String(o.number).padStart(4,'0'),createdAt:o.created_at,paidAt:o.paid_at,type:o.order_type,table:o.table_ref,lines:o.pos_order_lines.map(l=>({...l,id:l.product_id})),payments:o.pos_payments,tendered:o.pos_payments.filter(p=>p.method==='cash').reduce((s,p)=>s+p.tendered,0),change:o.pos_payments.reduce((s,p)=>s+p.change,0),method:o.pos_payments.length>1?'split':o.pos_payments[0]?.method})),members,categories,staffAccounts,areas,tables,discounts,printJobs,openOrders}}

export const createStaff=args=>request('/functions/v1/staff-access',{method:'POST',body:{action:'create',...args}});
