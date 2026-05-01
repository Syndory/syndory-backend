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

    const { data: result, error: rpcError } = await supabase.rpc(
      'validate_justification',
      {
        p_justificatif_id: justificatif_id,
        p_professor_id: user.id,
        p_decision: decision,
        p_rejection_reason: decision === 'rejeté' ? rejection_reason : null,
      },
    );

    if (rpcError) {
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la validation' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const payload = result as {
      success: boolean;
      error?: string;
      status?: string;
    } | null;

    if (!payload?.success) {
      return new Response(
        JSON.stringify({ error: payload?.error || 'Validation impossible' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    return new Response(
      JSON.stringify({ success: true, status: payload.status }),
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
