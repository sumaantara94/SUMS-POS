create or replace function pos_private.queue_report(b uuid,p_day date) returns integer language plpgsql security definer set search_path='' as $$declare today date;begin
 perform pos_private.require_owner(b);select (now() at time zone timezone)::date into today from public.pos_businesses where id=b;
 if p_day is null or p_day>=today or p_day<today-365 then raise exception 'Select a completed report day within the last year';end if;
 return pos_private.queue_report_internal(b,p_day);
end$$;
