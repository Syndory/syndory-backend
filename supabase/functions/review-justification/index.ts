import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface ReviewJustificationRequest {
  justificatif_id: string;
  decision: 'validé' | 'rejeté';
  rejection_reason?: string;
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

    if (userData?.role !== 'professor') {
      return new Response(
        JSON.stringify({ error: 'Acces reserve aux professeurs' }),
        {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const {
      justificatif_id,
      decision,
      rejection_reason,
    }: ReviewJustificationRequest = await req.json();

    if (!justificatif_id || !decision) {
      return new Response(
        JSON.stringify({
          error: 'Parametres requis: justificatif_id, decision',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    if (!['validé', 'rejeté'].includes(decision)) {
      return new Response(JSON.stringify({ error: 'Decision invalide' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (
      decision === 'rejeté' &&
      (!rejection_reason || rejection_reason.trim() === '')
    ) {
      return new Response(
        JSON.stringify({ error: 'rejection_reason requis en cas de rejet' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: justificatif, error: justificatifError } = await supabase
      .from('justificatifs')
      .select(
        'id, status, presence_id, student_id, presence:presence_id (session:session_id (seance:seance_id (id, professor_id)))',
      )
      .eq('id', justificatif_id)
      .single();

    if (justificatifError || !justificatif) {
      return new Response(
        JSON.stringify({ error: 'Justificatif introuvable' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const seanceProfessorId =
      justificatif.presence?.session?.seance?.professor_id;
    if (!seanceProfessorId || seanceProfessorId !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Justificatif non autorise' }),
        {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    if (justificatif.status !== 'en_attente') {
      return new Response(
        JSON.stringify({ error: 'Justificatif deja traite' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: updated, error: updateError } = await supabase
      .from('justificatifs')
      .update({
        status: decision,
        reviewed_at: new Date().toISOString(),
        reviewed_by: user.id,
        rejection_reason: decision === 'rejeté' ? rejection_reason : null,
      })
      .eq('id', justificatif_id)
      .select('id, status')
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

    if (decision === 'validé') {
      const { error: presenceError } = await supabase
        .from('presences')
        .update({ status: 'justified' })
        .eq('id', justificatif.presence_id);

      if (presenceError) {
        return new Response(
          JSON.stringify({
            error: 'Erreur lors de la mise a jour de la presence',
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }
    }

    return new Response(
      JSON.stringify({ success: true, justificatif: updated }),
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
