import {test} from 'node:test';
import assert from 'node:assert/strict';
import {discountAmount,validDiscount} from '../src/restaurant.mjs';
test('discount rounding, minimum and expiry boundaries match checkout',()=>{const d={active:true,kind:'percent',value:15,min_spend:100,max_amount:null,starts_at:'2026-10-12T00:00:00Z',ends_at:'2026-10-13T00:00:00Z'};assert.equal(discountAmount(d,101),15);assert.equal(validDiscount(d,100,Date.parse(d.starts_at)),true);assert.equal(validDiscount(d,99,Date.parse(d.starts_at)),false);assert.equal(validDiscount(d,100,Date.parse(d.ends_at)),false);assert.equal(validDiscount({...d,active:false},100,Date.parse(d.starts_at)),false)});
test('fixed discounts never exceed subtotal and percentage caps apply',()=>{assert.equal(discountAmount({kind:'fixed',value:100000,max_amount:null},40000),40000);assert.equal(discountAmount({kind:'percent',value:50,max_amount:12000},60000),12000);assert.equal(discountAmount(null,500),0)});
