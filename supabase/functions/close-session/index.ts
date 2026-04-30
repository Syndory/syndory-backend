// Edge Function: close-session
// Permet à un professeur de fermer une session de présence

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface CloseSessionRequest {
  session_id: string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getSupabaseClient(req);
    
    // Get current user
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Non authentifié' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const { session_id }: CloseSessionRequest = await req.json();

    // Validation
    if (!session_id) {
      return new Response(
        JSON.stringify({ error: 'Paramètre manquant: session_id requis' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Call the database function to close session
    const { data, error } = await supabase.rpc('close_session', {
      p_session_id: session_id,
      p_professor_id: user.id
    });

    if (error) {
      console.error('Error closing session:', error);
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la fermeture de la session', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const result = data as { success: boolean; error?: string; absents_marked?: number; session_closed?: boolean };

    if (!result.success) {
      return new Response(
        JSON.stringify({ error: result.error }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Session fermée avec succès',
        absents_marked: result.absents_marked,
        session_closed: result.session_closed
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error: any) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Erreur serveur', details: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
