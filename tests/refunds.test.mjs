import {test} from 'node:test';import assert from 'node:assert/strict';
import {refundLines,refundState,refundUI} from '../src/refunds.mjs';
test('only completed refunds determine partial/full state; rejected items can be requested again',()=>{
 const o={id:'o',lines:[{line_id:'a'},{line_id:'b'}]};
 const r=[{order_id:'o',status:'rejected',items:[{line_id:'a'}]},{order_id:'o',status:'approved',items:[{line_id:'b'}]},{order_id:'other',status:'completed',items:[{line_id:'a'}]}];
 assert.deepEqual([...refundLines(r,'o')],['b']);assert.equal(refundState(r,o),'');
 r.push({order_id:'o',status:'completed',items:[{line_id:'a'}]});assert.equal(refundState(r,o),'Partially refunded');
 r[1].status='completed';assert.equal(refundState(r,o),'Refunded');
});
test('owner notification shows pending item/reason/actor and escapes business content',()=>{
 const b={orders:[{id:'o',number:'POS-1'}],refunds:[{id:'r',order_id:'o',status:'pending',items:[{qty:1,name:'<Coffee>'}],reason:'<No stock>',requested_by_name:'<Cashier>',amount:1000}]};
 const esc=v=>String(v).replaceAll('<','&lt;').replaceAll('>','&gt;');
 const ui=refundUI({business:()=>b,esc,money:String});const html=ui.dashboard();
 assert.ok(html.includes('1 pending'));assert.ok(html.includes('&lt;Coffee&gt;'));assert.ok(html.includes('&lt;No stock&gt;'));assert.ok(html.includes('&lt;Cashier&gt;'));assert.ok(html.includes('data-refund-view="r"'));
});
