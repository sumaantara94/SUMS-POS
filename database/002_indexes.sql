create index pos_audit_actor_idx on public.pos_audit_events(actor_id);
create index pos_lines_product_idx on public.pos_order_lines(business_id,product_id);
create index pos_orders_creator_idx on public.pos_orders(created_by);
create index pos_payments_business_order_idx on public.pos_payments(business_id,order_id);
create index pos_payments_actor_idx on public.pos_payments(paid_by);
create index pos_stock_actor_idx on public.pos_stock_movements(actor_id);
create index pos_stock_business_order_idx on public.pos_stock_movements(business_id,order_id);
create index pos_stock_business_product_idx on public.pos_stock_movements(business_id,product_id);
