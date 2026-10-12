// Minimal Phoenix v1 client; only tenant-scoped invalidation signals are subscribed.
export function workspaceJoin(business,token){return {config:{broadcast:{ack:false,self:false},presence:{enabled:false},postgres_changes:[{event:'INSERT',schema:'public',table:'pos_realtime_events',filter:'business_id=eq.'+business}],private:false},access_token:token}}
export function workspaceRealtime({url,key,business,getToken,onChange,onStatus,WebSocketImpl=globalThis.WebSocket,interval=globalThis.setInterval,clearInterval=globalThis.clearInterval,delay=globalThis.setTimeout,clearDelay=globalThis.clearTimeout}){
 let socket,stopped=false,retry,heartbeat,joinTimeout,ref=0,joinRef,ids=[],failures=0,heartRef=null,topic='realtime:pos-'+business;
 const status=value=>onStatus?.(value),send=(event,payload={},target=topic)=>{const id=String(++ref);socket?.send(JSON.stringify({topic:target,event,payload,ref:id,join_ref:target===topic?joinRef:null}));return id};
 function reconnect(){if(stopped||retry)return;status('reconnecting');retry=delay(()=>{retry=null;connect()},Math.min(30000,1000*2**Math.min(failures++,5)))}
 function clear(){clearInterval(heartbeat);clearDelay(joinTimeout);heartRef=null}
 async function connect(){if(stopped)return;status('connecting');let token;try{token=await getToken()}catch{status('authentication');reconnect();return}if(stopped||!token)return;ids=[];const ws=new WebSocketImpl(url.replace(/^http/,'ws')+'/realtime/v1/websocket?apikey='+encodeURIComponent(key)+'&vsn=1.0.0');socket=ws;
 ws.onopen=()=>{if(stopped||socket!==ws)return;joinRef=String(ref+1);send('phx_join',workspaceJoin(business,token));joinTimeout=delay(()=>ws.close(),15000);heartbeat=interval(async()=>{if(socket!==ws||ws.readyState!==1)return;if(heartRef){ws.close();return}try{const fresh=await getToken();if(fresh!==token){token=fresh;send('access_token',{access_token:token})}heartRef=send('heartbeat',{},'phoenix')}catch{ws.close()}},25000)};
 ws.onmessage=event=>{if(stopped||socket!==ws)return;let m;try{m=JSON.parse(event.data)}catch{return}if(m.topic==='phoenix'&&m.ref===heartRef){heartRef=null;return}if(m.topic!==topic)return;
  if(m.event==='phx_reply'&&m.ref===joinRef){if(m.payload?.status!=='ok'){status('degraded');ws.close();return}ids=(m.payload.response?.postgres_changes||[]).map(x=>x.id);clearDelay(joinTimeout);if(ids.length){failures=0;status('live');onChange?.()}else status('connecting')}
  if(m.event==='system'){if(m.payload?.extension==='postgres_changes'&&m.payload.status==='ok'){failures=0;status('live')}else if(m.payload?.status==='error'){status('degraded')}}
  if(m.event==='postgres_changes'){const p=m.payload,data=p?.data;if(data?.schema==='public'&&data.table==='pos_realtime_events'&&data.record?.business_id===business&&p.ids?.some(id=>ids.includes(id)))onChange?.()}
  if(m.event==='phx_error'||m.event==='phx_close')ws.close();
 };
 ws.onerror=()=>status('degraded');ws.onclose=()=>{if(socket!==ws)return;clear();reconnect()};
 }
 connect();return {close(){stopped=true;clearDelay(retry);clear();if(socket?.readyState===1)try{send('phx_leave')}catch{}socket?.close()}};
}
