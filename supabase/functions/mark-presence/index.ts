// Edge Function: mark-presence
// Permet à un étudiant de marquer sa présence avec vérification GPS

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface MarkPresenceRequest {
  session_id: string;
  gps_lat: number;
  gps_long: number;
}

serve(async (req) => {
  // Handle CORS preflight
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
    const { session_id, gps_lat, gps_long }: MarkPresenceRequest = await req.json();

    // Validation
    if (!session_id || gps_lat === undefined || gps_long === undefined) {
      return new Response(
        JSON.stringify({ error: 'Paramètres manquants: session_id, gps_lat, gps_long requis' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Validate GPS coordinates
    if (gps_lat < -90 || gps_lat > 90 || gps_long < -180 || gps_long > 180) {
      return new Response(
        JSON.stringify({ error: 'Coordonnées GPS invalides' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Call the database function to mark presence
    const { data, error } = await supabase.rpc('mark_presence', {
      p_session_id: session_id,
      p_student_id: user.id,
      p_gps_lat: gps_lat,
      p_gps_long: gps_long
    });

    if (error) {
      console.error('Error marking presence:', error);
      return new Response(
        JSON.stringify({ error: 'Erreur lors du marquage de présence', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const result = data as { success: boolean; error?: string; presence_id?: string; distance?: number };

    if (!result.success) {
      return new Response(
        JSON.stringify({ 
          error: result.error,
          distance: result.distance 
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Présence confirmée',
        presence_id: result.presence_id
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Erreur serveur', details: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
