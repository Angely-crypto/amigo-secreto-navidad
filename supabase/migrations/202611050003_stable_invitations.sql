alter table public.events add column invitation_epoch uuid not null default gen_random_uuid();

create table public.invitation_credential_history (
 id uuid primary key default gen_random_uuid(), invitation_id uuid not null references public.invitations(id) on delete cascade,
 token_hash text not null unique, pin_hash text not null, created_at timestamptz not null default now()
);
alter table public.invitation_credential_history enable row level security;
revoke all on public.invitation_credential_history from anon,authenticated;

create or replace function public.check_invitation(p_token_hash text,p_pin_hash text)
returns table(participant_id uuid,event_id uuid,valid boolean)
language plpgsql security definer set search_path=public as $$
declare v_invitation public.invitations%rowtype; v_expected_pin text;
begin
 select * into v_invitation from public.invitations i where i.token_hash=p_token_hash for update;
 if found then
  v_expected_pin:=v_invitation.pin_hash;
 else
  select i.* into v_invitation from public.invitation_credential_history h
   join public.invitations i on i.id=h.invitation_id where h.token_hash=p_token_hash for update of i;
  if not found then return query select null::uuid,null::uuid,false; return; end if;
  select h.pin_hash into v_expected_pin from public.invitation_credential_history h where h.invitation_id=v_invitation.id and h.token_hash=p_token_hash;
 end if;
 if v_invitation.locked_until is not null and v_invitation.locked_until>now() then return query select null::uuid,null::uuid,false; return; end if;
 if v_expected_pin<>p_pin_hash then
  update public.invitations set attempts=attempts+1,locked_until=case when attempts+1>=5 then now()+interval '15 minutes' else null end where id=v_invitation.id;
  return query select null::uuid,null::uuid,false; return;
 end if;
 update public.invitations set attempts=0,locked_until=null,used_at=coalesce(used_at,now()) where id=v_invitation.id;
 return query select v_invitation.participant_id,v_invitation.event_id,true;
end $$;
revoke all on function public.check_invitation(text,text) from public,anon,authenticated;
grant execute on function public.check_invitation(text,text) to service_role;

create or replace function public.create_invitations(p_event_id uuid,p_rows jsonb) returns void language plpgsql security definer set search_path=public as $$
declare v_owner uuid; v_status text; v_row jsonb; v_old public.invitations%rowtype;
begin
 select owner_id,status into v_owner,v_status from public.events where id=p_event_id for update;
 if not found then raise exception 'event_not_found'; end if;
 if v_owner is distinct from auth.uid() and auth.role() <> 'service_role' then raise exception 'not_authorized'; end if;
 if v_status not in ('setup','registered','drawn','in_progress') then raise exception 'event_closed'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<2 then raise exception 'minimum_two_invitations'; end if;
 for v_row in select jsonb_array_elements(p_rows) loop
  select * into v_old from public.invitations where event_id=p_event_id and participant_id=(v_row->>'participant_id')::uuid for update;
  if found and v_old.token_hash<>(v_row->>'token_hash') then
   insert into public.invitation_credential_history(invitation_id,token_hash,pin_hash)
   values(v_old.id,v_old.token_hash,v_old.pin_hash) on conflict(token_hash) do nothing;
  end if;
 end loop;
 insert into public.invitations(event_id,participant_id,token_hash,pin_hash,token_prefix)
 select p_event_id,(r->>'participant_id')::uuid,r->>'token_hash',r->>'pin_hash',r->>'token_prefix' from jsonb_array_elements(p_rows) r
 on conflict(participant_id) do update set token_hash=excluded.token_hash,pin_hash=excluded.pin_hash,token_prefix=excluded.token_prefix,attempts=0,locked_until=null;
end $$;
revoke all on function public.create_invitations(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.create_invitations(uuid,jsonb) to service_role;

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
 update public.events set status=case when v_has_participants then 'registered' else 'setup' end,draw_at=null,invitation_epoch=gen_random_uuid() where id=p_event_id;
end $$;
revoke all on function public.reset_event(uuid) from public,anon;
grant execute on function public.reset_event(uuid) to authenticated;
