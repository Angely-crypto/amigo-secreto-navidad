import { requireSupabase } from './supabase';
export async function invoke<T>(action: string, body: Record<string, unknown>): Promise<T> {
 const { data, error } = await requireSupabase().functions.invoke('api', { body: { action, ...body } });
 if (error) throw new Error(error.message || 'No se pudo completar la operación.');
 if (data?.error) throw new Error(data.error);
 return data as T;
}
export const hashToken = async (token: string) => {
 const bytes = new TextEncoder().encode(token);
 const digest = await crypto.subtle.digest('SHA-256', bytes);
 return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
};
