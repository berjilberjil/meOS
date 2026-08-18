import postgres from 'postgres';
import { env } from '$env/dynamic/private';

const url = env.DATABASE_URL ?? 'postgresql://localhost:5432/myos';
const isSupabase = url.includes('supabase') || url.includes('pooler');

// Single shared Postgres pool for the whole server. Supabase's transaction
// pooler (:6543) needs TLS and no prepared statements — `prepare: false` keeps
// it compatible with both poolers and serverless (Netlify) invocations.
export const sql = postgres(url, {
  onnotice: () => {},
  prepare: false,
  ssl: isSupabase ? 'require' : false
});
