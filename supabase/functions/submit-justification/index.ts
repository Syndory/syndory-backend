import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface SubmitJustificationRequest {
  presence_id: string;
  file_url: string;
  reason?: string;
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

    const { data: userData } = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single();

    if (!['student', 'class_representative'].includes(userData?.role || '')) {
      return new Response(
        JSON.stringify({ error: 'Acces reserve aux etudiants' }),
        {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { presence_id, file_url, reason }: SubmitJustificationRequest =
      await req.json();

    if (!presence_id || !file_url) {
      return new Response(
        JSON.stringify({ error: 'Parametres requis: presence_id, file_url' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: presence, error: presenceError } = await supabase
      .from('presences')
      .select(
        'id, status, student_id, session:session_id (seance:seance_id (id, professor_id))',
      )
      .eq('id', presence_id)
      .single();

    if (presenceError || !presence) {
      return new Response(JSON.stringify({ error: 'Presence introuvable' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (presence.student_id !== user.id) {
      return new Response(JSON.stringify({ error: 'Presence non autorisee' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (presence.status !== 'absent') {
      return new Response(
        JSON.stringify({
          error: 'Justificatif autorise uniquement pour absent',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: existing } = await supabase
      .from('justificatifs')
      .select('id')
      .eq('presence_id', presence_id)
      .maybeSingle();

    if (existing?.id) {
      return new Response(
        JSON.stringify({ error: 'Justificatif deja soumis' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: justificatif, error: insertError } = await supabase
      .from('justificatifs')
      .insert({
        presence_id,
        student_id: user.id,
        file_url,
        reason,
      })
      .select()
      .single();

    if (insertError) {
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la creation du justificatif' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const seanceId = presence.session?.seance?.id;
    if (seanceId) {
      const { error: notifyError } = await supabase.rpc(
        'notify_professor_for_seance',
        {
          p_seance_id: seanceId,
          p_type: 'justification_status',
          p_title: 'Justificatif soumis',
          p_message: 'Un justificatif a ete soumis pour une absence.',
          p_data: {
            justificatif_id: justificatif.id,
            presence_id,
          },
        },
      );

      if (notifyError) {
        console.error('Error notifying professor:', notifyError);
      }
    }

    return new Response(
      JSON.stringify({ success: true, justificatif_id: justificatif.id }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
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
