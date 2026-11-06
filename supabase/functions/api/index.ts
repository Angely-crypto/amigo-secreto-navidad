import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json', 'Cache-Control': 'no-store, private', 'Pragma': 'no-cache' };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: cors });
const encoder = new TextEncoder();
async function macBytes(value: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(value)));
}
const hex = (bytes: Uint8Array) => [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
const digest = async (value: string, secret: string) => hex(await macBytes(value, secret));
async function derivePin(eventId: string, participantId: string, secret: string, length: number) {
  let pin = '';
  for (let counter = 0; pin.length < length; counter++) {
    for (const byte of await macBytes(`invite-pin:v1:${eventId}:${participantId}:${counter}`, secret)) {
      if (byte < 250) pin += String(byte % 10);
      if (pin.length === length) break;
    }
  }
  return pin;
}
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json(405, { error: 'Método no permitido.' });
  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const pepper = Deno.env.get('PIN_PEPPER');
  if (!pepper) return json(500, { error: 'Falta configurar PIN_PEPPER en las funciones.' });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  try {
    const body = await req.json();
    if (body.action === 'create-invitation') {
      const auth = req.headers.get('Authorization');
      if (!auth) return json(401, { error: 'Inicia sesión como administrador.' });
      const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } });
      const { data: { user } } = await userClient.auth.getUser();
      if (!user) return json(401, { error: 'Inicia sesión como administrador.' });
      const { data: event } = await admin.from('events').select('id,owner_id,status,invite_expiry,pin_length,invitation_epoch').eq('id', body.event_id).single();
      if (!event || event.owner_id !== user.id) return json(403, { error: 'No tienes acceso a este evento.' });
      if (!['setup','registered','drawn','in_progress'].includes(event.status)) return json(409, { error: 'El evento no admite invitaciones.' });
      if (typeof body.event_id !== 'string') return json(400, { error: 'Evento no válido.' });
      const { data: participants, error: participantError } = await admin.from('participants').select('id').eq('event_id', event.id);
      if (participantError) throw participantError;
      if (participants.length < 2) return json(400, { error: 'Agrega al menos dos participantes.' });
      let invitationEpoch = event.invitation_epoch;
      if (body.renew === true) {
        invitationEpoch = crypto.randomUUID();
        const { error: epochError } = await admin.from('events').update({ invitation_epoch: invitationEpoch }).eq('id', event.id);
        if (epochError) throw epochError;
      }
      const credentials = await Promise.all(participants.map(async (p: {id:string}) => {
        const token = hex(await macBytes(`invite-token:v1:${event.id}:${invitationEpoch}:${p.id}`, pepper));
        const pin = await derivePin(`${event.id}:${invitationEpoch}`, p.id, pepper, event.pin_length ?? 6);
        const token_hash = hex(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(token))));
        return { participant_id: p.id, token, pin, token_hash, pin_hash: await digest(pin, pepper), token_prefix: token.slice(0, 12) };
      }));
      const rows = credentials.map(({participant_id,token_hash,pin_hash,token_prefix})=>({participant_id,token_hash,pin_hash,token_prefix}));
      const { error } = await admin.rpc('create_invitations', { p_event_id: event.id, p_rows: rows });
      if (error) throw error;
      if (body.renew === true) {
        const { error: statusError } = await admin.from('invitations').update({ used_at: null, attempts: 0, locked_until: null }).eq('event_id', event.id).is('revealed_at', null);
        if (statusError) throw statusError;
      }
      return json(200, { invitations: credentials.map(({participant_id,token,pin})=>({participant_id,token,pin})) });
    }
    if (body.action === 'authenticate-invitation' || body.action === 'reveal-result') {
      if (typeof body.token_hash !== 'string' || typeof body.pin !== 'string') return json(401, { error: 'Invitación o código no válidos.' });
      const { data: rows, error } = await admin.rpc('check_invitation', { p_token_hash: body.token_hash, p_pin_hash: await digest(body.pin, pepper) });
      if (error) throw error;
      const auth = rows?.[0];
      if (!auth?.valid) return json(401, { error: 'Invitación o código incorrectos. Tras cinco intentos, el acceso se bloquea 15 minutos.' });
      const { data: participant, error: pe } = await admin.from('participants').select('id,name').eq('id', auth.participant_id).single();
      if (pe || !participant) return json(404, { error: 'No se encontró esta invitación.' });
      const { data: event, error: ee } = await admin.from('events').select('id,title,welcome_message,status,deadline,budget').eq('id', auth.event_id).single();
      if (ee || !event) return json(404, { error: 'No se encontró el evento.' });
      if (body.action === 'authenticate-invitation' && !['drawn','in_progress','completed'].includes(event.status) && event.deadline && new Date(event.deadline).getTime() < Date.now()) return json(410, { error: 'El plazo para participar ya terminó.' });
      if (body.action === 'authenticate-invitation') {
        const { count } = await admin.from('participants').select('*', { count: 'exact', head: true }).eq('event_id', event.id);
        return json(200, { name: participant.name, title: event.title, welcome_message: event.welcome_message, paper_count: Math.max(4, count || 4), budget: event.budget });
      }
      if (!['drawn','in_progress','completed'].includes(event.status)) return json(409, { error: 'El sorteo todavía no está disponible.' });
      const { data: result, error: re } = await admin.from('assignments').select('receiver_id').eq('event_id', event.id).eq('giver_id', participant.id).single();
      if (re || !result) return json(409, { error: 'El resultado aún no está disponible.' });
      const { data: recipient, error: ne } = await admin.from('participants').select('name,photo_data').eq('id', result.receiver_id).single();
      if (ne || !recipient) throw ne || new Error('No se encontró el resultado.');
      await admin.from('reveal_events').upsert({ event_id: event.id, participant_id: participant.id }, { onConflict: 'event_id,participant_id', ignoreDuplicates: true });
      await admin.from('invitations').update({ revealed_at: new Date().toISOString() }).eq('event_id', event.id).eq('participant_id', participant.id).is('revealed_at', null);
      await admin.from('events').update({ status: 'in_progress' }).eq('id', event.id).eq('status', 'drawn');
      return json(200, { recipient: recipient.name, photo_data: recipient.photo_data ?? null, budget: event.budget });
    }
    return json(400, { error: 'Acción desconocida.' });
  } catch (error) {
    console.error('api error', error instanceof Error ? error.message : 'unknown');
    return json(500, { error: 'Ocurrió un problema al procesar la solicitud.' });
  }
});
