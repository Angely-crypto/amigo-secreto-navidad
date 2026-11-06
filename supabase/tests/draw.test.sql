begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
select plan(10);
insert into auth.users(id,aud,role,email,encrypted_password,created_at,updated_at)
values ('10000000-0000-4000-8000-000000000001','authenticated','authenticated','draw-test@example.invalid','',now(),now());
insert into public.events(id,owner_id,name,title,welcome_message,status)
values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Test','Test','Test','registered');
insert into public.participants(id,event_id,name,normalized_name) values
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Ana','ana'),
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','Beto','beto'),
 ('30000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','Cami','cami'),
 ('30000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000001','Dani','dani');
insert into public.exclusions(event_id,giver_id,receiver_id) values
 ('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002'),
 ('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.perform_draw('20000000-0000-4000-8000-000000000001');
reset role;
select is((select count(*)::int from public.assignments where event_id='20000000-0000-4000-8000-000000000001'),4,'crea una asignación por persona');
select is((select count(*)::int from public.assignments where event_id='20000000-0000-4000-8000-000000000001' and giver_id=receiver_id),0,'nadie queda asignado a sí mismo');
select is((select count(distinct receiver_id)::int from public.assignments where event_id='20000000-0000-4000-8000-000000000001'),4,'cada persona recibe exactamente una vez');
select is((select count(*)::int from public.assignments a join public.exclusions x on x.event_id=a.event_id and x.giver_id=a.giver_id and x.receiver_id=a.receiver_id where a.event_id='20000000-0000-4000-8000-000000000001'),0,'respeta las exclusiones');
insert into public.invitations(event_id,participant_id,token_hash,pin_hash,token_prefix)
values ('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',repeat('a',64),repeat('b',64),'aaaaaaaaaaaa');
insert into public.reveal_events(event_id,participant_id)
values ('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select throws_ok($$select public.perform_draw('20000000-0000-4000-8000-000000000001')$$,'P0001','draw_already_performed','un evento no admite un segundo sorteo');
select public.reset_event('20000000-0000-4000-8000-000000000001');
reset role;
select is((select count(*)::int from public.assignments where event_id='20000000-0000-4000-8000-000000000001'),0,'reiniciar borra las asignaciones');
select is((select count(*)::int from public.invitations where event_id='20000000-0000-4000-8000-000000000001'),0,'reiniciar invalida las invitaciones');
select is((select count(*)::int from public.reveal_events where event_id='20000000-0000-4000-8000-000000000001'),0,'reiniciar borra las revelaciones');
select is((select status from public.events where id='20000000-0000-4000-8000-000000000001'),'registered','reiniciar conserva el evento y participantes');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.perform_draw('20000000-0000-4000-8000-000000000001');
reset role;
select is((select count(*)::int from public.assignments where event_id='20000000-0000-4000-8000-000000000001'),4,'se puede volver a sortear tras reiniciar');
select * from finish();
rollback;
