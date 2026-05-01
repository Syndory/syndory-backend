import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient } from '../_shared/supabase.ts';

interface UpdateProgressionRequest {
  seance_id: string;
  chapters_covered: string[];
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

    const role = userData?.role || '';
    if (!['professor', 'class_representative'].includes(role)) {
      return new Response(JSON.stringify({ error: 'Non autorise' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { seance_id, chapters_covered }: UpdateProgressionRequest =
      await req.json();

    if (!seance_id || !Array.isArray(chapters_covered)) {
      return new Response(
        JSON.stringify({
          error: 'Parametres requis: seance_id, chapters_covered',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const invalidChapter = chapters_covered.some(
      (chapter) => typeof chapter !== 'string' || chapter.trim() === '',
    );
    if (invalidChapter) {
      return new Response(
        JSON.stringify({
          error: 'chapters_covered doit contenir des identifiants valides',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: seance, error: seanceError } = await supabase
      .from('seances')
      .select('id, professor_id, class_id')
      .eq('id', seance_id)
      .single();

    if (seanceError || !seance) {
      return new Response(JSON.stringify({ error: 'Seance introuvable' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (role === 'professor' && seance.professor_id !== user.id) {
      return new Response(JSON.stringify({ error: 'Seance non autorisee' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (role === 'class_representative') {
      const { data: repClass, error: repError } = await supabase
        .from('student_classes')
        .select('class_id')
        .eq('student_id', user.id)
        .eq('is_active', true)
        .maybeSingle();

      if (
        repError ||
        !repClass?.class_id ||
        repClass.class_id !== seance.class_id
      ) {
        return new Response(
          JSON.stringify({ error: 'Seance hors de votre classe' }),
          {
            status: 403,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }
    }

    const { data: existing, error: existingError } = await supabase
      .from('progressions')
      .select('id, is_validated')
      .eq('seance_id', seance_id)
      .maybeSingle();

    if (existingError) {
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la verification' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    if (existing?.is_validated) {
      return new Response(
        JSON.stringify({ error: 'Progression deja validee' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const payload = {
      seance_id,
      chapters_covered,
      updated_by: user.id,
      updated_by_role: role,
    };

    if (existing?.id) {
      const { data: updated, error: updateError } = await supabase
        .from('progressions')
        .update(payload)
        .eq('id', existing.id)
        .select()
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

      return new Response(
        JSON.stringify({ success: true, progression: updated }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: inserted, error: insertError } = await supabase
      .from('progressions')
      .insert(payload)
      .select()
      .single();

    if (insertError) {
      return new Response(
        JSON.stringify({ error: 'Erreur lors de la creation' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    return new Response(
      JSON.stringify({ success: true, progression: inserted }),
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
