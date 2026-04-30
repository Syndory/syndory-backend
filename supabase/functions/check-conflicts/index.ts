// Edge Function: check-conflicts
// Vérifie les conflits d'emploi du temps (salle, prof, classe)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface CheckConflictsRequest {
  seance_id?: string; // Optionnel pour nouvelle séance
  matiere_id: string;
  professor_id: string;
  class_id: string;
  salle_id: string;
  date: string; // YYYY-MM-DD
  start_time: string; // HH:MM
  end_time: string; // HH:MM
}

interface Conflict {
  conflict_type: string;
  conflict_details: {
    seance_id: string;
    [key: string]: any;
  };
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

    // Check if user is admin
    const { data: userData } = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single();

    if (userData?.role !== 'admin') {
      return new Response(
        JSON.stringify({ error: 'Accès réservé aux administrateurs' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const {
      seance_id,
      matiere_id,
      professor_id,
      class_id,
      salle_id,
      date,
      start_time,
      end_time
    }: CheckConflictsRequest = await req.json();

    // Validation
    if (!matiere_id || !professor_id || !class_id || !salle_id || !date || !start_time || !end_time) {
      return new Response(
        JSON.stringify({ error: 'Tous les paramètres sont requis' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Call the database function to check conflicts
    const { data, error } = await supabase.rpc('check_schedule_conflicts', {
      p_seance_id: seance_id || null,
      p_matiere_id: matiere_id,
      p_professor_id: professor_id,
      p_class_id: class_id,
      p_salle_id: salle_id,
      p_date: date,
      p_start_time: start_time,
      p_end_time: end_time
    });

    if (error) {
      console.error('Error checking conflicts:', error);
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la vérification des conflits', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const conflicts = (data as Conflict[]) || [];
    const hasConflicts = conflicts.length > 0;

    return new Response(
      JSON.stringify({
        has_conflicts: hasConflicts,
        conflicts: conflicts,
        can_create: !hasConflicts
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
