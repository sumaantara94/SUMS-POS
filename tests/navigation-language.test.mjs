import {test} from 'node:test';
import assert from 'node:assert/strict';
import {posHome,posPages,posEntry} from '../src/navigation.mjs';
import {getLanguage,setLanguage,locale,translate,localize,protectUserText} from '../src/i18n.mjs';

test('POS homes and available pages follow role and restaurant mode',()=>{
 const restaurant={restaurant_mode:true,waiter_enabled:true};
 assert.equal(posHome('cashier',restaurant),'orders');
 assert.equal(posHome('owner',restaurant),'orders');
 assert.equal(posHome('waiter',restaurant),'tables');
 assert.equal(posPages('cashier',restaurant)[0],'orders');
 assert.equal(posPages('waiter',restaurant)[0],'tables');
 const retail={restaurant_mode:false,waiter_enabled:true};
 assert.equal(posHome('cashier',retail),'pos');
 assert.equal(posPages('cashier',retail)[0],'pos');
 assert.ok(!posPages('cashier',retail).includes('tables'));
 assert.deepEqual(posPages('waiter',retail),['pos','possettings']);
 assert.deepEqual(posPages('waiter',{...restaurant,waiter_enabled:false}),['pos','possettings']);
});
test('English default translates navigation, payment labels and dynamic totals',()=>{
 assert.equal(getLanguage(),'en');
 assert.equal(locale(),'en-GB');
 assert.equal(translate('Pesanan'),'Orders');
 assert.equal(translate('PESANAN'),'ORDER');
 assert.equal(translate('Pengaturan'),'Settings');
 assert.equal(translate('Bahasa aplikasi'),'App language');
 assert.equal(translate('Pembayaran 2'),'Payment 2');
 assert.equal(translate('Dialokasikan Rp 20.000 · sisa Rp 30.000'),'Allocated Rp 20.000 · remaining Rp 30.000');
 assert.equal(translate('3 item · Tekan untuk submit pesanan'),'3 items · Tap to submit order');
 setLanguage('id');
 assert.equal(locale(),'id-ID');
 assert.equal(translate('Pesanan'),'Pesanan');
 setLanguage('en');
});
test('localization preserves user content and form values',()=>{
 globalThis.document={documentElement:{lang:''}};
 const text=(value,protectedNode=false)=>({nodeType:3,textContent:value,parentElement:{closest:()=>protectedNode?{}:null}});
 const name=text('Pesanan'),note=text('Pilih produk terlebih dahulu',true),label=text('Meja');
 const attrs={placeholder:'Cari produk...',value:'Nama bisnis'};
 const root={nodeType:1,childNodes:[name,note,label],hasAttribute:key=>key in attrs,getAttribute:key=>attrs[key],setAttribute:(key,value)=>attrs[key]=value};
 protectUserText(['Pesanan']);localize(root);
 assert.equal(name.textContent,'Pesanan');
 assert.equal(note.textContent,'Pilih produk terlebih dahulu');
 assert.equal(label.textContent,'Tables');
 assert.equal(attrs.placeholder,'Search products...');
 assert.equal(attrs.value,'Nama bisnis');
 delete globalThis.document;protectUserText([]);
});

test('Products opens the cashier catalogue while waiter seating remains first',()=>{
 const b={restaurant_mode:true,waiter_enabled:true};
 assert.equal(posEntry('cashier',b,null,false),'products');
 assert.equal(posEntry('owner',b,null,false),'products');
 assert.equal(posEntry('waiter',b,null,false),'tables');
 assert.equal(posEntry('waiter',b,{id:'reserved'},true),'products');
 assert.equal(posEntry('waiter',b,{id:'free'},false),'guest');
 assert.equal(posEntry('cashier',b,{id:'free'},false),'guest');
 assert.equal(posEntry('cashier',{restaurant_mode:false},null,false),'products');
});
