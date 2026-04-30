import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.0';

export const getSupabaseClient = (req: Request) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  
  // Extract auth header for user context
  const authHeader = req.headers.get('Authorization');
  
  return createClient(supabaseUrl, supabaseKey, {
    global: {
      headers: authHeader ? { Authorization: authHeader } : undefined,
    },
  });
};

export const getSupabaseAdmin = () => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  
  return createClient(supabaseUrl, supabaseKey);
};
