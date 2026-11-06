create extension if not exists pgcrypto;
create table public.events (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 name text not null, title text not null, welcome_message text not null default 'Tenemos una sorpresa preparada para ti.',
 exchange_date date, deadline timestamptz, budget numeric(10,2), status text not null default 'setup' check (status in ('setup','registered','drawn','in_progress','completed','closed')),
 pin_length integer not null default 6 check(pin_length between 6 and 12), invite_expiry timestamptz,
 draw_at timestamptz, created_at timestamptz not null default now()
);
create table public.participants (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
 name text not null, normalized_name text not null, created_at timestamptz not null default now(),
 unique(event_id, normalized_name), unique(id,event_id)
);
create table public.invitations (
 id uuid primary key default gen_random_uuid(), event_id uuid not null, participant_id uuid not null,
 token_hash text not null unique, pin_hash text not null, token_prefix text not null,
 attempts integer not null default 0, locked_until timestamptz, used_at timestamptz, revealed_at timestamptz,
 created_at timestamptz not null default now(), foreign key(participant_id,event_id) references public.participants(id,event_id) on delete cascade,
 unique(participant_id)
);
create table public.exclusions (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
 giver_id uuid not null, receiver_id uuid not null, check(giver_id <> receiver_id),
 foreign key(giver_id,event_id) references public.participants(id,event_id) on delete cascade,
 foreign key(receiver_id,event_id) references public.participants(id,event_id) on delete cascade,
 unique(event_id,giver_id,receiver_id)
);
create table public.assignments (
 event_id uuid not null references public.events(id) on delete cascade, giver_id uuid not null, receiver_id uuid not null,
 created_at timestamptz not null default now(), primary key(event_id,giver_id), unique(event_id,receiver_id), check(giver_id <> receiver_id),
 foreign key(giver_id,event_id) references public.participants(id,event_id) on delete cascade,
 foreign key(receiver_id,event_id) references public.participants(id,event_id) on delete cascade
);
create table public.reveal_events (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
 participant_id uuid not null, revealed_at timestamptz not null default now(),
 foreign key(participant_id,event_id) references public.participants(id,event_id) on delete cascade, unique(event_id,participant_id)
);
create index invitations_event_idx on public.invitations(event_id);
create index exclusions_event_idx on public.exclusions(event_id);
create index reveal_event_idx on public.reveal_events(event_id);
create or replace function public.secure_random_int(p_max int) returns int language plpgsql volatile security definer set search_path=public,extensions as $$
declare v bigint; v_limit bigint; b bytea;
begin
 if p_max<1 then raise exception 'invalid_range'; end if;
 v_limit:=4294967296-(4294967296 % p_max);
 loop
  b:=gen_random_bytes(4);
  v:=get_byte(b,0)::bigint*16777216+get_byte(b,1)::bigint*65536+get_byte(b,2)::bigint*256+get_byte(b,3)::bigint;
  if v<v_limit then return (v % p_max)::int+1; end if;
 end loop;
end $$;
revoke all on function public.secure_random_int(int) from public,anon,authenticated;
alter table public.events enable row level security;
alter table public.participants enable row level security;
alter table public.invitations enable row level security;
alter table public.exclusions enable row level security;
alter table public.assignments enable row level security;
alter table public.reveal_events enable row level security;
create policy "owners manage own events" on public.events for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy "owners read participants" on public.participants for select to authenticated using(exists(select 1 from public.events e where e.id=event_id and e.owner_id=auth.uid()));
create policy "owners edit participants before draw" on public.participants for all to authenticated using(exists(select 1 from public.events e where e.id=event_id and e.owner_id=auth.uid() and e.status in ('setup','registered'))) with check(exists(select 1 from public.events e where e.id=event_id and e.owner_id=auth.uid() and e.status in ('setup','registered')));
create policy "owners read exclusions" on public.exclusions for select to authenticated using(exists(select 1 from public.events e where e.id=event_id and e.owner_id=auth.uid()));
create policy "owners edit exclusions before draw" on public.exclusions for all to authenticated using(exists(select 1 from public.events e where e.id=event_id and e.owner_id=auth.uid() and e.status in ('setup','registered'))) with check(exists(select 1 from public.events e where e.id=event_id and e.owner_id=auth.uid() and e.status in ('setup','registered')));
create policy "owners read reveal status" on public.reveal_events for select to authenticated using(exists(select 1 from public.events e where e.id=event_id and e.owner_id=auth.uid()));
-- No browser role can select assignments or invitation secrets. The service role is used only inside Edge Functions.
revoke all on public.assignments, public.invitations, public.reveal_events from anon, authenticated;
create view public.invitation_status with (security_barrier=true) as
 select i.id,i.event_id,i.participant_id,i.used_at,coalesce(i.revealed_at,r.revealed_at) as revealed_at,i.created_at
 from public.invitations i join public.events e on e.id=i.event_id
 left join public.reveal_events r on r.event_id=i.event_id and r.participant_id=i.participant_id
 where e.owner_id=auth.uid();
grant select on public.invitation_status to authenticated;
grant select on public.reveal_events to authenticated;
grant select,insert,update on public.events to authenticated;
grant select,insert,update,delete on public.participants,public.exclusions to authenticated;
create or replace function public.prevent_event_edits_after_draw() returns trigger language plpgsql set search_path=public as $$
begin
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
create trigger event_config_locked before update on public.events for each row execute function public.prevent_event_edits_after_draw();
create or replace function public.perform_draw(p_event uuid) returns void language plpgsql security definer set search_path=public as $$
declare v_owner uuid; v_status text; v_ids uuid[]; v_perm uuid[]; v_ok boolean; v_i int; v_j int; v_tmp uuid; v_try int:=0; v_n int;
begin
 select owner_id,status into v_owner,v_status from events where id=p_event for update;
 if v_owner is distinct from auth.uid() then raise exception 'not_authorized'; end if;
 if v_status not in ('setup','registered') or exists(select 1 from assignments where event_id=p_event) then raise exception 'draw_already_performed'; end if;
 select array_agg(id order by id) into v_ids from participants where event_id=p_event;
 v_n:=coalesce(array_length(v_ids,1),0); if v_n<2 then raise exception 'minimum_two_participants'; end if;
 -- Secure Fisher-Yates permutations, rejecting invalid cycles uniformly from the set of valid permutations.
 loop
  v_try:=v_try+1; v_perm:=v_ids;
  for v_i in reverse v_n..2 loop
   v_j:=public.secure_random_int(v_i);
   v_tmp:=v_perm[v_i]; v_perm[v_i]:=v_perm[v_j]; v_perm[v_j]:=v_tmp;
  end loop;
  v_ok:=true;
  for v_i in 1..v_n loop
   if v_perm[v_i]=v_ids[v_i] or exists(select 1 from exclusions x where x.event_id=p_event and x.giver_id=v_ids[v_i] and x.receiver_id=v_perm[v_i]) then v_ok:=false; exit; end if;
  end loop;
  if v_ok then exit; end if;
  if v_try>=10000 then raise exception 'no_valid_draw_found'; end if;
 end loop;
 for v_i in 1..v_n loop insert into assignments(event_id,giver_id,receiver_id) values(p_event,v_ids[v_i],v_perm[v_i]); end loop;
 update events set status='drawn',draw_at=now() where id=p_event;
end $$;
create or replace function public.check_invitation(p_token_hash text,p_pin_hash text) returns table(participant_id uuid,event_id uuid,valid boolean) language plpgsql security definer set search_path=public as $$
declare r public.invitations%rowtype;
begin
 select * into r from public.invitations i where i.token_hash=p_token_hash for update;
 if not found then return query select null::uuid,null::uuid,false; return; end if;
 if r.locked_until is not null and r.locked_until>now() then return query select null::uuid,null::uuid,false; return; end if;
 if r.pin_hash<>p_pin_hash then
  update public.invitations set attempts=attempts+1,locked_until=case when attempts+1>=5 then now()+interval '15 minutes' else null end where id=r.id;
  return query select null::uuid,null::uuid,false; return;
 end if;
 update public.invitations set attempts=0,locked_until=null,used_at=coalesce(used_at,now()) where id=r.id;
 return query select r.participant_id,r.event_id,true;
end $$;
revoke all on function public.check_invitation(text,text) from public,anon,authenticated;
grant execute on function public.check_invitation(text,text) to service_role;
create or replace function public.create_invitations(p_event_id uuid,p_rows jsonb) returns void language plpgsql security definer set search_path=public as $$
declare v_owner uuid; v_status text;
begin
 select owner_id,status into v_owner,v_status from public.events where id=p_event_id for update;
 if not found then raise exception 'event_not_found'; end if;
 if v_owner is distinct from auth.uid() and auth.role() <> 'service_role' then raise exception 'not_authorized'; end if;
 if v_status not in ('setup','registered','drawn','in_progress') then raise exception 'event_closed'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<2 then raise exception 'minimum_two_invitations'; end if;
 insert into public.invitations(event_id,participant_id,token_hash,pin_hash,token_prefix)
 select p_event_id,(r->>'participant_id')::uuid,r->>'token_hash',r->>'pin_hash',r->>'token_prefix' from jsonb_array_elements(p_rows) r
 on conflict(participant_id) do update set token_hash=excluded.token_hash,pin_hash=excluded.pin_hash,token_prefix=excluded.token_prefix,attempts=0,locked_until=null;
end $$;
revoke all on function public.create_invitations(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.create_invitations(uuid,jsonb) to service_role;
revoke all on function public.perform_draw(uuid) from public,anon;
grant execute on function public.perform_draw(uuid) to authenticated;
