create unique index pos_one_open_per_table on public.pos_orders(business_id,table_id) where status='open' and table_id is not null;
alter table public.pos_tables add constraint pos_tables_map_slot_key unique(area_id,x,y);
alter table public.pos_discounts add constraint pos_discount_amount_bounds check(value<=1000000000000 and min_spend<=1000000000000 and (max_amount is null or max_amount<=1000000000000));
