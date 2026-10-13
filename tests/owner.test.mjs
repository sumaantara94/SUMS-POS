import {test} from 'node:test';import assert from 'node:assert/strict';
import {outletGroup,ownerUI} from '../src/owner.mjs';
test('outlet group excludes unrelated workspaces even when the current outlet is a child',()=>{
 const root={id:'r'},child={id:'c',parent_business_id:'r'},other={id:'x'},otherChild={id:'y',parent_business_id:'x'};
 assert.deepEqual(outletGroup([root,child,other,otherChild],child),[root,child]);
});
test('owner header has an outlet picker and notification access without logout or POS launch',()=>{
 const b={id:'r',name:'Main',refunds:[{status:'pending'}]};
 const ui=ownerUI({business:()=>b,state:()=>({businesses:[b]}),esc:String,api:{getSession:()=>({user:{email:'owner@example.invalid',user_metadata:{full_name:'Owner'}}})},isOwner:()=>true});
 const html=ui.header();assert.ok(html.includes('id="business"'));assert.ok(html.includes('data-refund-notifications'));assert.ok(html.includes('Add outlet'));assert.ok(!html.includes('logout'));assert.ok(!html.includes('switchsurface'));
 assert.ok(ui.profileButton().includes('id="owner-profile"'));assert.ok(!ui.profileButton().includes('Log out'));
});
test('notification header shows no outlet creation control for non-owner memberships',()=>{
 const b={id:'r',name:'Main',refunds:[]};const ui=ownerUI({business:()=>b,state:()=>({businesses:[b]}),esc:String,isOwner:()=>false});
 assert.ok(!ui.header().includes('owner-add-outlet'));
});
