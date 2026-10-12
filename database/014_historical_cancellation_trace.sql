-- Recover historical cancellation timestamps/actors only from existing audit evidence.
update public.pos_orders o set cancelled_at=a.created_at,cancelled_by=a.actor_id
from (select distinct on (business_id,record_id) business_id,record_id,actor_id,created_at from public.pos_audit_events where action in ('order.cancelled','order.cancelled.pin') order by business_id,record_id,created_at desc) a
where o.business_id=a.business_id and o.id=a.record_id and o.status='cancelled' and o.cancelled_at is null;
