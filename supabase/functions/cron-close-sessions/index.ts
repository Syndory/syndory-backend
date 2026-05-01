import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabase = getSupabaseAdmin();
  const errors: string[] = [];

  const { error: closeError } = await supabase.rpc('close_expired_sessions');
  if (closeError) {
    errors.push(`close_expired_sessions: ${closeError.message}`);
  }

  const { error: publishError } = await supabase.rpc(
    'publish_scheduled_annonces',
  );
  if (publishError) {
    errors.push(`publish_scheduled_annonces: ${publishError.message}`);
  }

  const { error: remindersError } = await supabase.rpc('send_exam_reminders');
  if (remindersError) {
    errors.push(`send_exam_reminders: ${remindersError.message}`);
  }

  if (errors.length > 0) {
    return new Response(JSON.stringify({ success: false, errors }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
