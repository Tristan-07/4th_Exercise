// Centralized Supabase Configuration
const SUPABASE_URL = 'https://kfbolysjloxvauqrxtye.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_QRRGM5APc7vR1tU4i_LZQA_VblMrHgV';

if (typeof supabase === 'undefined') {
  console.error('Supabase SDK client script not found. Make sure @supabase/supabase-js CDN is included.');
}

const supabaseClient = (typeof supabase !== 'undefined') 
  ? supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) 
  : null;
