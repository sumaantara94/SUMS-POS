import https from 'node:https';import http from 'node:http';
import {readFile,stat,mkdir,chmod} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';import {fileURLToPath} from 'node:url';import {randomUUID} from 'node:crypto';
import {HubStore,may} from './store.mjs';import {cloudRequest,verifyMember,refreshCatalog} from './cloud.mjs';
const MIME={'.html':'text/html; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css','.json':'application/json','.webmanifest':'application/manifest+json','.png':'image/png','.svg':'image/svg+xml'};
export function hubHandler({store,root,origin,verify=verifyMember,refresh=refreshCatalog,cloud=cloudRequest}){const address=new URL(origin);
 return async(req,res)=>{const json=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data));};try{
  if(req.headers.host!==address.host) return json(403,{error:'Alamat Hub tidak cocok'});
  if(req.headers.origin&&req.headers.origin!==origin)return json(403,{error:'Origin ditolak'});
  res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');res.setHeader('Content-Security-Policy',"frame-ancestors 'none'");
  const url=new URL(req.url,origin),path=url.pathname;
  if(path.startsWith('/hub/')){
   if(!['GET','POST'].includes(req.method))return json(405,{error:'Method ditolak'});
   if(path==='/hub/health'&&req.method==='GET')return json(200,{protocol:'sums-pos-lan-v1',configured:Boolean(store.get('config')),origin});
   if(req.method==='POST'&&!req.headers['content-type']?.startsWith('application/json'))return json(415,{error:'JSON diperlukan'});
   let body={};if(req.method==='POST'){let bytes=0,parts=[];for await(const part of req){bytes+=part.length;if(bytes>120000)return json(413,{error:'Request terlalu besar'});parts.push(part)}body=JSON.parse(Buffer.concat(parts).toString());}
   const bearer=req.headers.authorization?.replace(/^Bearer /,'');
   if(path==='/hub/setup'&&req.method==='POST'){
    const member=await verify(bearer,body.business);if(member.role!=='owner')return json(403,{error:'Owner diperlukan'});
    const existing=store.get('config');if(existing&&existing.business!==body.business)return json(409,{error:'Hub sudah digunakan outlet lain'});
    if(!existing){const hub=randomUUID(),cfg=await cloud('/rest/v1/rpc/pos_register_lan_hub',bearer,{b:body.business,p_hub:hub,p_name:'SUMS Outlet Hub'});store.configure({business:body.business,hub,secret:cfg.secret});}
    await refresh(store,bearer);return json(200,{ready:true,business:body.business});
   }
   if(path==='/hub/enroll'&&req.method==='POST'){
    const cfg=store.get('config');if(!cfg||cfg.business!==body.business)return json(409,{error:'Owner perlu mengaktifkan outlet di Hub'});
    const member=await verify(bearer,body.business);if(member.role==='owner'||member.permissions.includes('pay'))await refresh(store,bearer);
    return json(200,store.enroll({...member,device:body.device}));
   }
   let session;try{session=store.session(bearer)}catch(e){return json(401,{error:e.message})}
   if(path==='/hub/logout'&&req.method==='POST'){store.revoke(bearer);return json(200,{ok:true});}
   if(path==='/hub/state'&&req.method==='GET')return json(200,store.view(session));
   if(path==='/hub/commands'&&req.method==='POST')return json(200,store.submit(session,body));
   if(path==='/hub/ack'&&req.method==='POST'){store.acknowledge(body.id,body.result);return json(200,{ok:true});}
   if(path==='/hub/review'&&req.method==='POST'){store.review(session,body.id,body.error);return json(200,{ok:true});}
   if(path==='/hub/retry'&&req.method==='POST'){store.retry(session);return json(200,{ok:true});}
   return json(404,{error:'Endpoint tidak tersedia'});
  }
  if(req.method!=='GET')return json(405,{error:'Method ditolak'});
  let target=resolve(root,'.'+decodeURIComponent(path==='/'?'/index.html':path));if(!target.startsWith(root+sep))return json(403,{error:'Path ditolak'});
  if(!(await stat(target)).isFile())return json(404,{error:'File tidak ditemukan'});
  let data=await readFile(target);if(target===resolve(root,'index.html'))data=Buffer.from(data.toString().replace('<head>','<head><meta name="sums-lan-hub" content="v1">'));res.writeHead(200,{'Content-Type':MIME[extname(target)]||'application/octet-stream','Cache-Control':'no-cache'});res.end(data);
 }catch(e){json(e.code==='ENOENT'?404:400,{error:e.message||'Hub tidak tersedia'});}};
}
export async function startHub({dir,host='127.0.0.1',port=7443,insecure=false,root=resolve(fileURLToPath(new URL('../dist',import.meta.url)))}={}){
 if(!dir)throw Error('Tentukan --dir untuk data dan sertifikat Hub');
 if(insecure&&host!=='127.0.0.1')throw Error('HTTP hanya diizinkan untuk uji loopback');
 process.umask(0o077);dir=resolve(dir);await mkdir(dir,{recursive:true,mode:0o700});await chmod(dir,0o700);const store=new HubStore(resolve(dir,'hub.sqlite'));await chmod(resolve(dir,'hub.sqlite'),0o600);
 const protocol=insecure?'http':'https',origin=protocol+'://'+host+':'+port,handler=hubHandler({store,root,origin});
 const server=insecure?http.createServer(handler):https.createServer({key:await readFile(resolve(dir,'hub.key')),cert:await readFile(resolve(dir,'hub.crt')),minVersion:'TLSv1.2'},handler);
 server.requestTimeout=20000;server.headersTimeout=10000;await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,insecure?'127.0.0.1':'0.0.0.0',resolve)});return {server,store,origin};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const args=process.argv.slice(2),read=k=>args[args.indexOf(k)+1];if(args.includes('--help')){console.log('node hub/server.mjs --dir <private-data-directory> --host <fixed-LAN-IP-or-hostname> [--port 7443]\nRequires trusted hub.crt and hub.key in the private data directory. Node.js 24+ required.');process.exit(0)}
 try{const hub=await startHub({dir:args.includes('--dir')?read('--dir'):null,host:args.includes('--host')?read('--host'):'127.0.0.1',port:args.includes('--port')?Number(read('--port')):7443});console.log('SUMS POS Hub: '+hub.origin+'/?app=pos');for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>hub.server.close(()=>{hub.store.close();process.exit(0)}));}catch(e){console.error(e.message);process.exitCode=1;}
}
