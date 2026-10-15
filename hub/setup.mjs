import {mkdir,writeFile,chmod,access} from 'node:fs/promises';import {resolve} from 'node:path';import {spawnSync} from 'node:child_process';import {isIP} from 'node:net';
const args=process.argv.slice(2),read=k=>args[args.indexOf(k)+1];
if(args.includes('--help')){console.log('node hub/setup.mjs --dir <private-directory> --host <fixed-LAN-IP-or-hostname>\nCreates a private local CA and signed HTTPS certificate; trust hub-ca.crt on each POS device. Requires OpenSSL. Existing certificates are never overwritten.');process.exit(0)}
const host=args.includes('--host')?read('--host'):null,dir=args.includes('--dir')?resolve(read('--dir')):null;
if(!host||!dir||!(/^[a-zA-Z0-9.-]{1,253}$/.test(host))){console.error('Tentukan --dir dan --host (IP LAN tetap atau hostname).');process.exit(1)}
process.umask(0o077);await mkdir(dir,{recursive:true,mode:0o700});await chmod(dir,0o700);try{await access(resolve(dir,'hub.key'));throw Error('Sertifikat sudah tersedia. Gunakan direktori baru untuk mengganti identitas Hub.')}catch(e){if(e.code!=='ENOENT')throw e;}
const run=a=>{const r=spawnSync('openssl',a,{cwd:dir,encoding:'utf8'});if(r.status!==0)throw Error(r.error?.message||'OpenSSL gagal: '+r.stderr);};
run(['req','-x509','-newkey','rsa:3072','-sha256','-nodes','-keyout','hub-ca.key','-out','hub-ca.crt','-days','3650','-subj','/CN=SUMS POS Local Hub CA','-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign']);
run(['req','-newkey','rsa:2048','-nodes','-keyout','hub.key','-out','hub.csr','-subj','/CN='+host]);
await writeFile(resolve(dir,'hub.ext'),'subjectAltName='+ (isIP(host)?'IP:':'DNS:')+host+'\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n');
run(['x509','-req','-in','hub.csr','-CA','hub-ca.crt','-CAkey','hub-ca.key','-CAcreateserial','-out','hub.crt','-days','365','-sha256','-extfile','hub.ext']);
console.log('Sertifikat Hub dibuat. Pasang dan percayai hub-ca.crt pada setiap perangkat POS. Simpan hub-ca.key dan hub.key hanya di perangkat Hub.\nJalankan: node hub/server.mjs --dir '+dir+' --host '+host+'\nAlamat: https://'+host+':7443/?app=pos');
