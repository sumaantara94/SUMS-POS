import {mkdir} from 'node:fs/promises';import {resolve,dirname} from 'node:path';import {spawnSync} from 'node:child_process';
const target=resolve(process.argv[2]||'artifacts/SUMS_POS_LAN_Hub.tar.gz');await mkdir(dirname(target),{recursive:true});
const build=spawnSync(process.execPath,['scripts/build.mjs'],{stdio:'inherit'});if(build.status!==0)process.exit(1);
const pack=spawnSync('tar',['-czf',target,'hub','src','dist','docs/RELEASE-LAN-HUB.md','docs/RELEASE-OFFLINE-CASH.md','package.json'],{stdio:'inherit'});if(pack.status!==0)process.exit(1);console.log(target);
