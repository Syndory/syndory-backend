// Edge Function: validate-progression
// Permet à un professeur de valider définitivement une progression

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface ValidateProgressionRequest {
  progression_id: string;
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
    const { progression_id }: ValidateProgressionRequest = await req.json();

    // Validation
    if (!progression_id) {
      return new Response(
        JSON.stringify({ error: 'Paramètre manquant: progression_id requis' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Vérifier que la progression existe et appartient à une séance du prof
    const { data: progression, error: progError } = await supabase
      .from('progressions')
      .select(`
        *,
        seance:seance_id (
          professor_id,
          class_id,
          matiere_id
        )
      `)
      .eq('id', progression_id)
      .single();

    if (progError || !progression) {
      return new Response(
        JSON.stringify({ error: 'Progression non trouvée' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Vérifier que le professeur est bien celui de la séance
    if (progression.seance.professor_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Non autorisé à valider cette progression' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Vérifier qu'elle n'est pas déjà validée
    if (progression.is_validated) {
      return new Response(
        JSON.stringify({ error: 'Cette progression est déjà validée' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Mettre à jour la progression
    const { data: updated, error: updateError } = await supabase
      .from('progressions')
      .update({
        is_validated: true,
        validated_at: new Date().toISOString(),
        updated_by: user.id,
        updated_by_role: 'professor'
      })
      .eq('id', progression_id)
      .select()
      .single();

    if (updateError) {
      console.error('Error validating progression:', updateError);
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la validation' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Progression validée avec succès',
        progression: updated
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
