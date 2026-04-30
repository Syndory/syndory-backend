// Edge Function: open-session
// Permet à un professeur d'ouvrir une session de présence avec vérification GPS

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface OpenSessionRequest {
  seance_id: string;
  gps_lat: number;
  gps_long: number;
  marking_window_duration: number; // en minutes
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getSupabaseClient(req);

    // Get current user
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Non authentifié' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Parse request body
    const {
      seance_id,
      gps_lat,
      gps_long,
      marking_window_duration,
    }: OpenSessionRequest = await req.json();

    // Validation
    if (!seance_id || gps_lat === undefined || gps_long === undefined) {
      return new Response(
        JSON.stringify({
          error: 'Paramètres manquants: seance_id, gps_lat, gps_long requis',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Validate GPS coordinates
    if (gps_lat < -90 || gps_lat > 90 || gps_long < -180 || gps_long > 180) {
      return new Response(
        JSON.stringify({ error: 'Coordonnées GPS invalides' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Validate marking window duration
    const duration = marking_window_duration || 15;
    if (duration < 5 || duration > 120) {
      return new Response(
        JSON.stringify({
          error: 'Durée de fenêtre invalide (min: 5, max: 120 minutes)',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Vérifier que le professeur est bien assigné à cette séance
    const { data: seance, error: seanceError } = await supabase
      .from('seances_view')
      .select('*')
      .eq('id', seance_id)
      .eq('professor_id', user.id)
      .single();

    if (seanceError || !seance) {
      return new Response(
        JSON.stringify({ error: 'Séance non trouvée ou non autorisée' }),
        {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Vérifier que la séance est aujourd'hui ou dans la plage horaire
    const seanceDate = new Date(seance.date);
    const today = new Date();
    if (seanceDate.toDateString() !== today.toDateString()) {
      return new Response(
        JSON.stringify({
          error: 'La session ne peut être ouverte que le jour de la séance',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Vérifier que l'ouverture se fait dans le créneau exact de la séance
    const tz = 'Africa/Porto-Novo';
    const now = new Date();
    const startTime = String(
      seance.start_time || seance.seance_start || '',
    ).slice(0, 5);
    const endTime = String(seance.end_time || seance.seance_end || '').slice(
      0,
      5,
    );
    if (
      !startTime ||
      !endTime ||
      startTime.length !== 5 ||
      endTime.length !== 5
    ) {
      return new Response(
        JSON.stringify({ error: 'Heures de séance invalides' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const getNowInTzIsoDate = (d: Date) => {
      const parts = new Intl.DateTimeFormat('en-CA', {
        timeZone: tz,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      }).formatToParts(d);
      const get = (type: string) => parts.find((p) => p.type === type)?.value;
      const y = get('year');
      const m = get('month');
      const day = get('day');
      if (!y || !m || !day) return null;
      return `${y}-${m}-${day}`;
    };

    const toTzComparableNumber = (isoDate: string, hhmm: string) => {
      // Crée un nombre comparable (YYYYMMDDHHMM) dans la timezone cible
      const [hh, mm] = hhmm.split(':');
      return Number(`${isoDate.replaceAll('-', '')}${hh}${mm}`);
    };

    const nowIsoDateInTz = getNowInTzIsoDate(now);
    if (!nowIsoDateInTz) {
      return new Response(
        JSON.stringify({
          error: 'Impossible de déterminer la date courante (timezone)',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const nowTimeParts = new Intl.DateTimeFormat('en-GB', {
      timeZone: tz,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(now);
    const getNow = (type: string) =>
      nowTimeParts.find((p) => p.type === type)?.value;
    const nowHH = getNow('hour');
    const nowMM = getNow('minute');
    if (!nowHH || !nowMM) {
      return new Response(
        JSON.stringify({
          error: "Impossible de déterminer l'heure courante (timezone)",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const nowComparable = toTzComparableNumber(
      nowIsoDateInTz,
      `${nowHH}:${nowMM}`,
    );
    const startComparable = toTzComparableNumber(
      String(seance.date),
      startTime,
    );
    const endComparable = toTzComparableNumber(String(seance.date), endTime);

    if (nowComparable < startComparable || nowComparable > endComparable) {
      return new Response(
        JSON.stringify({
          error:
            'La session ne peut être ouverte que pendant le créneau horaire de la séance',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Vérifier la position GPS du professeur
    const { data: isWithinRadius, error: radiusError } = await supabase.rpc(
      'is_within_salle_radius',
      {
        p_user_lat: gps_lat,
        p_user_long: gps_long,
        p_salle_id: seance.salle_id,
      },
    );

    if (radiusError) {
      console.error('Error checking radius:', radiusError);
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la vérification GPS' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    if (!isWithinRadius) {
      // Calculer la distance pour info
      const { data: distance } = await supabase.rpc('calculate_distance', {
        lat1: gps_lat,
        lon1: gps_long,
        lat2: seance.salle_gps_lat,
        lon2: seance.salle_gps_long,
      });

      return new Response(
        JSON.stringify({
          error: "Vous n'êtes pas dans la salle. Rapprochez-vous.",
          distance: distance,
          required_radius: seance.salle_tolerance,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Vérifier qu'une session n'est pas déjà ouverte pour ce prof
    const { data: existingSession, error: existingError } = await supabase
      .from('sessions')
      .select('id')
      .eq('professor_id', user.id)
      .eq('status', 'ouverte')
      .maybeSingle();

    if (existingError) {
      console.error('Error checking existing session:', existingError);
      return new Response(
        JSON.stringify({
          error: 'Erreur lors de la vérification des sessions',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    if (existingSession) {
      return new Response(
        JSON.stringify({
          error: "Vous avez déjà une session ouverte. Fermez-la d'abord.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Créer la session
    const { data: session, error: createError } = await supabase
      .from('sessions')
      .insert({
        seance_id: seance_id,
        professor_id: user.id,
        marking_window_duration: duration,
        professor_gps_lat: gps_lat,
        professor_gps_long: gps_long,
        status: 'ouverte',
      })
      .select()
      .single();

    if (createError) {
      console.error('Error creating session:', createError);
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la création de la session' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Notifier les étudiants de la classe
    await supabase.rpc('notify_class', {
      p_class_id: seance.class_id,
      p_type: 'session_opened',
      p_title: 'Session de présence ouverte',
      p_message: `La session de présence pour ${seance.matiere_name} est ouverte. Marquez votre présence !`,
      p_data: { session_id: session.id, seance_id: seance_id },
    });

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Session ouverte avec succès',
        session: session,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (error: unknown) {
    console.error('Unexpected error:', error);
    const details = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: 'Erreur serveur', details }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
