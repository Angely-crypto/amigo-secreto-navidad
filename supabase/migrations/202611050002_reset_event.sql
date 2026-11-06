create or replace function public.prevent_event_edits_after_draw() returns trigger language plpgsql set search_path=public as $$
begin
 if current_setting('app.reset_event',true)='true' then return new; end if;
 if old.status in ('drawn','in_progress','completed','closed') and
   (case new.status when 'setup' then 1 when 'registered' then 2 when 'drawn' then 3 when 'in_progress' then 4 when 'completed' then 5 when 'closed' then 6 end) <
   (case old.status when 'setup' then 1 when 'registered' then 2 when 'drawn' then 3 when 'in_progress' then 4 when 'completed' then 5 when 'closed' then 6 end) then
  raise exception 'event_status_cannot_revert';
 end if;
 if old.status in ('drawn','in_progress','completed','closed') and
   row(new.name,new.title,new.welcome_message,new.exchange_date,new.deadline,new.budget,new.pin_length,new.invite_expiry)
   is distinct from row(old.name,old.title,old.welcome_message,old.exchange_date,old.deadline,old.budget,old.pin_length,old.invite_expiry) then
  raise exception 'event_locked_after_draw';
 end if;
 return new;
end $$;

create or replace function public.reset_event(p_event_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare v_owner uuid; v_has_participants boolean;
begin
 select owner_id into v_owner from public.events where id=p_event_id for update;
 if not found then raise exception 'event_not_found'; end if;
 if v_owner is distinct from auth.uid() then raise exception 'not_authorized'; end if;
 delete from public.assignments where event_id=p_event_id;
 delete from public.invitations where event_id=p_event_id;
 delete from public.reveal_events where event_id=p_event_id;
 select exists(select 1 from public.participants where event_id=p_event_id) into v_has_participants;
 perform set_config('app.reset_event','true',true);
 update public.events set status=case when v_has_participants then 'registered' else 'setup' end,draw_at=null where id=p_event_id;
end $$;
revoke all on function public.reset_event(uuid) from public,anon;
grant execute on function public.reset_event(uuid) to authenticated;
