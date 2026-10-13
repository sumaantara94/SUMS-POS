import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {refundLines} from '../src/refunds.mjs';
test('loading a completed refunded bill renders the original total, actor and request action',async()=>{
 const src=await readFile('src/app.mjs','utf8'),body=src.split('\n').find(l=>l.startsWith('function orderDetails('));
 const o={id:'o',number:'POS-1',status:'paid',table:'Table 1',createdAt:new Date().toISOString(),created_by_name:'Waiter',lines:[{id:'p',line_id:'l',name:'Coffee',qty:1,price:1000}],total:1000,payments:[{paid_by_name:'Cashier'}]};
 const b={orders:[o],refunds:[{order_id:'o',status:'completed',items:[{line_id:'l'}],amount:1000}]};let html='';
 const node={addEventListener(){},onclick:null},modal=value=>{html=value;return {querySelector:()=>node}};
 const factory=new Function('business','refundLines','toast','modal','esc','money','locale','surface','can','refunds','paymentForm','cancelForm','printOrder','const cloud=true;'+body+';return orderDetails');
 factory(()=>b,refundLines,()=>{},modal,String,String,()=> 'en-GB','pos',()=>true,{order:()=>'<section>Refund requests</section>',bind(){}},()=>{},()=>{},()=>{})('o');
 assert.ok(html.includes('id="loaded-refund"'));assert.ok(html.includes('refunded-line'));assert.ok(html.includes('Total bill awal'));assert.ok(html.includes('Sisa pembayaran setelah refund'));assert.ok(html.includes('Cashier'));assert.ok(!html.includes('id="loaded-cancel"'));
});
