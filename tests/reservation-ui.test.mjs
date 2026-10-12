import {test} from 'node:test';import assert from 'node:assert/strict';
import {restaurantUI} from '../src/restaurant.mjs';
test('reserved table can be selected; an open bill still disables selection',()=>{
 const b={areas:[{id:'area',name:'Front',active:true}],tables:[{id:'reserved',name:'Table 1',area_id:'area',active:true,capacity:2,reserved_at:'2026-10-12T00:00:00Z',reservation_guest:'Suma'},{id:'occupied',name:'Table 2',area_id:'area',active:true,capacity:2}],orders:[{status:'open',table_id:'occupied',createdAt:new Date().toISOString()}]};
 const ui=restaurantUI({business:()=>b,esc:String,can:()=>false});
 const html=ui.map(true),reserved=html.match(/<button[^>]*data-pick-table="reserved"[^>]*>/)[0],occupied=html.match(/<button[^>]*data-pick-table="occupied"[^>]*>/)[0];
 assert.ok(!reserved.includes('disabled'));assert.ok(occupied.includes('disabled'));
 assert.ok(html.includes('Suma'));
});
