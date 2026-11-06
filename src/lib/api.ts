import { requireSupabase } from './supabase';
export async function invoke<T>(action: string, body: Record<string, unknown>): Promise<T> {
 const { data, error } = await requireSupabase().functions.invoke('api', { body: { action, ...body } });
 if (error) {
  let message = error.message || 'No se pudo completar la operación.';
  const context = (error as { context?: unknown }).context;
  if (context instanceof Response) {
   try {
    const payload = await context.clone().json() as { error?: unknown };
    if (typeof payload?.error === 'string' && payload.error.trim()) message = payload.error;
   } catch { /* Conserva el mensaje original si la respuesta no contiene JSON. */ }
  }
  throw new Error(message);
 }
 if (data?.error) throw new Error(data.error);
 return data as T;
}
export const hashToken = async (token: string) => {
 const bytes = new TextEncoder().encode(token);
 const digest = await crypto.subtle.digest('SHA-256', bytes);
 return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
};
