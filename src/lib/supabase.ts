import { createClient } from '@supabase/supabase-js';
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;
export const configured = Boolean(url && key);
export const supabase = configured ? createClient(url!, key!) : null;
export function requireSupabase() { if (!supabase) throw new Error('Configura VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY para conectar Supabase.'); return supabase; }
