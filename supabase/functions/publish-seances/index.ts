import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface PublishSeancesRequest {
  seance_ids?: string[];
  publish_all?: boolean;
  class_id?: string;
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

    if (userData?.role !== 'admin') {
      return new Response(JSON.stringify({ error: 'Acces admin requis' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { seance_ids, publish_all, class_id }: PublishSeancesRequest =
      await req.json();

    if (!publish_all && (!seance_ids || seance_ids.length === 0)) {
      return new Response(
        JSON.stringify({
          error: 'Parametres requis: seance_ids ou publish_all',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    let targetIds: string[] = [];

    if (publish_all) {
      let query = supabase
        .from('seances')
        .select('id, status')
        .eq('status', 'brouillon');

      if (class_id) {
        query = query.eq('class_id', class_id);
      }

      const { data: seances, error: seancesError } = await query;

      if (seancesError) {
        return new Response(
          JSON.stringify({ error: 'Erreur lors de la selection des seances' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }

      if (!seances || seances.length === 0) {
        return new Response(
          JSON.stringify({ error: 'Aucune seance a publier' }),
          {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }

      targetIds = seances.map((seance) => seance.id);
    } else {
      const uniqueIds = [...new Set(seance_ids || [])].filter(Boolean);

      const { data: seances, error: seancesError } = await supabase
        .from('seances')
        .select('id, status')
        .in('id', uniqueIds);

      if (seancesError) {
        return new Response(
          JSON.stringify({ error: 'Erreur lors de la selection des seances' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }

      if (!seances || seances.length !== uniqueIds.length) {
        return new Response(JSON.stringify({ error: 'Seances invalides' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const nonDraft = seances.filter(
        (seance) => seance.status !== 'brouillon',
      );
      if (nonDraft.length > 0) {
        return new Response(
          JSON.stringify({
            error: 'Toutes les seances doivent etre en brouillon',
          }),
          {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }

      targetIds = uniqueIds;
    }

    const { data: updated, error: updateError } = await supabase
      .from('seances')
      .update({ status: 'publié' })
      .in('id', targetIds)
      .select('id');

    if (updateError) {
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la publication' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    return new Response(
      JSON.stringify({ success: true, published: updated?.length || 0 }),
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
