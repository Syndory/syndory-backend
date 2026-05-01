import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface UpdateFcmTokenRequest {
  fcm_token: string;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getSupabaseClient(req);

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Non authentifie' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { fcm_token }: UpdateFcmTokenRequest = await req.json();

    if (!fcm_token || typeof fcm_token !== 'string') {
      return new Response(JSON.stringify({ error: 'fcm_token requis' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { error: updateError } = await supabase
      .from('users')
      .update({ fcm_token })
      .eq('id', user.id)
      .select('id')
      .single();

    if (updateError) {
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la mise a jour' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('Unexpected error:', message);
    return new Response(
      JSON.stringify({ error: 'Erreur serveur', details: message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }
});
