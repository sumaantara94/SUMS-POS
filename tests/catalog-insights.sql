begin;
select set_config('test.owner',gen_random_uuid()::text,true),set_config('test.outsider',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('test.owner')::uuid,'catalog-owner@example.invalid'),(current_setting('test.outsider')::uuid,'catalog-outside@example.invalid');
select set_config('request.jwt.claim.sub',current_setting('test.owner'),true);set local role authenticated;
do $$declare b uuid;c uuid;p uuid;v uuid;u uuid;o uuid;insights jsonb;begin
 b:=public.pos_create_business('Catalogue integration','Retail','#087f6c');perform set_config('test.biz',b::text,true);
 c:=public.pos_save_category(b,null,'Coffee',true);perform set_config('test.cat',c::text,true);
 p:=public.pos_save_product_v2(b,null,'Coffee',c,28000,10000,30,true);
 u:=public.pos_save_product_v2(b,null,'Unordered',c,10000,null,0,true);
 perform public.pos_save_variants(b,p,'[{"name":"Large","price":34000,"stock":20,"active":true}]');
 select id into v from public.pos_products where parent_product_id=p;
 begin perform public.pos_delete_category(b,c);raise exception 'nonempty category deleted';exception when others then if sqlerrm<>'Category must be empty' then raise;end if;end;
 o:=public.pos_place_order_v4(b,gen_random_uuid(),jsonb_build_array(jsonb_build_object('id',v,'qty',2)),'takeaway',null,'','',null);
 perform public.pos_pay_order_v3(b,o,null,'[{"method":"cash","amount":68000,"tendered":68000,"reference":""}]');
 insights:=public.pos_product_performance(b,current_date,current_date,c);
 if jsonb_array_length(insights->'top')<>1 or (insights->'top'->0->>'id')::uuid<>p or (insights->'top'->0->>'qty')::integer<>2 or (insights->'top'->0->>'revenue')::bigint<>68000 then raise exception 'variant aggregation incorrect';end if;
 if jsonb_array_length(insights->'unsold')<>1 or (insights->'unsold'->0->>'id')::uuid<>u then raise exception 'unsold incorrect';end if;
 if jsonb_array_length(public.pos_product_performance(b,current_date-3,current_date-2,c)->'top')<>0 then raise exception 'range ignored';end if;
 perform public.pos_delete_product(b,p);
 if exists(select 1 from public.pos_products where (id=p or parent_product_id=p) and (active or deleted_at is null or category_id is not null)) then raise exception 'archive incomplete';end if;
 if not exists(select 1 from public.pos_order_lines where order_id=o and name='Coffee / Large' and qty=2) then raise exception 'history lost';end if;
 if (public.pos_product_performance(b,current_date,current_date,null)->'top'->0->>'qty')::integer<>2 then raise exception 'historical ranking lost';end if;
 begin perform public.pos_save_product_v2(b,p,'Restored',c,1,null,5,true);raise exception 'archived product revived';exception when others then if sqlerrm<>'Deleted product cannot be edited' then raise;end if;end;
 perform public.pos_delete_product(b,u);perform public.pos_delete_category(b,c);
 if exists(select 1 from public.pos_categories where id=c) then raise exception 'empty category retained';end if;
 if not exists(select 1 from public.pos_order_lines where order_id=o and category_name='Coffee') then raise exception 'category history lost';end if;
 -- Even after catalogue deletion, restocking a paid item keeps its original foreign key valid.
 perform set_config('test.variant',v::text,true);
end$$;
reset role;
update public.pos_products set stock=stock+1 where id=current_setting('test.variant')::uuid;
select set_config('request.jwt.claim.sub',current_setting('test.outsider'),true);set local role authenticated;
do $$begin
 begin perform public.pos_product_performance(current_setting('test.biz')::uuid,current_date,current_date,null);raise exception 'outsider report';exception when insufficient_privilege then null;end;
 begin perform public.pos_delete_category(current_setting('test.biz')::uuid,current_setting('test.cat')::uuid);raise exception 'outsider delete';exception when insufficient_privilege then null;end;
 begin perform public.pos_delete_product(current_setting('test.biz')::uuid,current_setting('test.variant')::uuid);raise exception 'outsider delete';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$declare h text;m jsonb;begin
 m:='{"outlet":"<script>Test</script>","day":"2026-10-12","timezone":"Asia/Makassar","bills":2,"collections":79000,"net_collections":79000,"net_sales_before_refunds":79000,"discount":5000,"service":0,"tax":0,"refunds":0,"cancelled_bills":0,"voided_items":0,"missing_cost_lines":2,"methods":{"cash":79000}}';h:=pos_private.sales_email_html(m);
 if h not like '%width="600"%' or h not like '%align="center"%' or h not like '%Rp 79.000%' or h like '%<script>%' or h not like '%Rp 39.500%' then raise exception 'email format/escaping regression';end if;
 if length(h)>20000 or h like '%<main%' then raise exception 'email became full width technical dump';end if;
end$$;
rollback;
