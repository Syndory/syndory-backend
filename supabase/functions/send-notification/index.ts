// Edge Function: send-notification
// Envoie des notifications push et crée les entrées dans la table notifications

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient, getSupabaseAdmin } from '../_shared/supabase.ts';

interface SendNotificationRequest {
  user_ids: string[]; // Si vide, envoie à tous les utilisateurs de la cible
  target_type?:
    | 'all'
    | 'filiere'
    | 'classe'
    | 'class'
    | 'professors'
    | 'students';
  target_id?: string;
  type: string;
  title: string;
  message: string;
  data?: Record<string, any>;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getSupabaseClient(req);
    const adminClient = getSupabaseAdmin();

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

    // Check if user is admin or professor
    const { data: userData } = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single();

    const role = userData?.role || '';

    if (!['admin', 'professor', 'class_representative'].includes(role)) {
      return new Response(JSON.stringify({ error: 'Non autorisé' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Parse request body
    const {
      user_ids,
      target_type,
      target_id,
      type,
      title,
      message,
      data = {},
    }: SendNotificationRequest = await req.json();

    // Validation
    if (!type || !title || !message) {
      return new Response(
        JSON.stringify({ error: 'Paramètres requis: type, title, message' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const normalizedTargetType =
      target_type === 'class' ? 'classe' : target_type;
    let targetUserIds: string[] = [];

    // Déterminer les utilisateurs cibles
    if (user_ids && user_ids.length > 0) {
      const uniqueUserIds = [...new Set(user_ids.filter(Boolean))];

      if (role === 'admin') {
        targetUserIds = uniqueUserIds;
      } else if (role === 'professor') {
        const { data: allowedStudents } = await supabase
          .from('student_classes')
          .select('student_id')
          .in('student_id', uniqueUserIds)
          .eq('is_active', true);

        const allowedIds = new Set(
          (allowedStudents || []).map((row: any) => row.student_id),
        );

        if (allowedIds.size !== uniqueUserIds.length) {
          return new Response(
            JSON.stringify({
              error: 'Certains utilisateurs ne sont pas autorisés',
            }),
            {
              status: 403,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            },
          );
        }

        targetUserIds = uniqueUserIds;
      } else if (role === 'class_representative') {
        const { data: repClass, error: repError } = await supabase
          .from('student_classes')
          .select('class_id')
          .eq('student_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

        if (repError || !repClass?.class_id) {
          return new Response(
            JSON.stringify({ error: 'Classe du responsable introuvable' }),
            {
              status: 403,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            },
          );
        }

        const { data: classStudents } = await adminClient
          .from('student_classes')
          .select('student_id')
          .eq('class_id', repClass.class_id)
          .eq('is_active', true)
          .in('student_id', uniqueUserIds);

        const allowedIds = new Set(
          (classStudents || []).map((row: any) => row.student_id),
        );

        if (allowedIds.size !== uniqueUserIds.length) {
          return new Response(
            JSON.stringify({ error: 'Cible hors de votre classe' }),
            {
              status: 403,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            },
          );
        }

        targetUserIds = uniqueUserIds;
      } else {
        return new Response(JSON.stringify({ error: 'Non autorisé' }), {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    } else if (normalizedTargetType && target_id) {
      // Envoi basé sur la cible
      switch (normalizedTargetType) {
        case 'classe':
          if (role === 'class_representative') {
            const { data: repClass, error: repError } = await supabase
              .from('student_classes')
              .select('class_id')
              .eq('student_id', user.id)
              .eq('is_active', true)
              .maybeSingle();

            if (repError || !repClass?.class_id) {
              return new Response(
                JSON.stringify({ error: 'Classe du responsable introuvable' }),
                {
                  status: 403,
                  headers: {
                    ...corsHeaders,
                    'Content-Type': 'application/json',
                  },
                },
              );
            }

            if (repClass.class_id !== target_id) {
              return new Response(
                JSON.stringify({ error: 'Cible hors de votre classe' }),
                {
                  status: 403,
                  headers: {
                    ...corsHeaders,
                    'Content-Type': 'application/json',
                  },
                },
              );
            }

            const { data: classStudents } = await adminClient
              .from('student_classes')
              .select('student_id')
              .eq('class_id', target_id)
              .eq('is_active', true);

            targetUserIds = classStudents?.map((s: any) => s.student_id) || [];
            break;
          }

          if (role === 'professor') {
            const { data: profClass, error: profError } = await supabase
              .from('professeur_matieres')
              .select('id')
              .eq('class_id', target_id)
              .eq('professor_id', user.id)
              .limit(1);

            if (profError || !profClass?.length) {
              return new Response(
                JSON.stringify({ error: 'Classe non assignée au professeur' }),
                {
                  status: 403,
                  headers: {
                    ...corsHeaders,
                    'Content-Type': 'application/json',
                  },
                },
              );
            }
          }

          const { data: classStudents } = await supabase
            .from('student_classes')
            .select('student_id')
            .eq('class_id', target_id)
            .eq('is_active', true);

          targetUserIds = classStudents?.map((s: any) => s.student_id) || [];
          break;

        case 'filiere':
          if (role !== 'admin') {
            return new Response(
              JSON.stringify({
                error: 'Cible filière réservée aux administrateurs',
              }),
              {
                status: 403,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              },
            );
          }
          const { data: classes } = await supabase
            .from('classes')
            .select('id')
            .eq('filiere_id', target_id);
          if (classes) {
            const classIds = classes.map((c: any) => c.id);
            const { data: allStudents } = await supabase
              .from('student_classes')
              .select('student_id')
              .in('class_id', classIds)
              .eq('is_active', true);
            targetUserIds = allStudents?.map((s: any) => s.student_id) || [];
          }
          break;

        case 'professors':
          if (role !== 'admin') {
            return new Response(
              JSON.stringify({
                error: 'Cible professeurs réservée aux administrateurs',
              }),
              {
                status: 403,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              },
            );
          }
          const { data: profs } = await supabase
            .from('users')
            .select('id')
            .eq('role', 'professor')
            .eq('is_active', true);
          targetUserIds = profs?.map((p: any) => p.id) || [];
          break;

        case 'students':
          if (role !== 'admin') {
            return new Response(
              JSON.stringify({
                error: 'Cible étudiants réservée aux administrateurs',
              }),
              {
                status: 403,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              },
            );
          }
          const { data: allStudentsUsers } = await supabase
            .from('users')
            .select('id')
            .in('role', ['student', 'class_representative']);
          targetUserIds = allStudentsUsers?.map((s: any) => s.id) || [];
          break;

        case 'all':
          if (role !== 'admin') {
            return new Response(
              JSON.stringify({
                error: 'Cible globale réservée aux administrateurs',
              }),
              {
                status: 403,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
              },
            );
          }
          const { data: allUsers } = await supabase
            .from('users')
            .select('id')
            .eq('is_active', true);
          targetUserIds = allUsers?.map((u: any) => u.id) || [];
          break;
      }
    }

    if (targetUserIds.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Aucun utilisateur cible trouvé' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    // Créer les notifications
    const uniqueUserIds = [...new Set(targetUserIds)].filter(Boolean);
    const notifications = uniqueUserIds.map((userId: any) => ({
      user_id: userId,
      type,
      title,
      message,
      data,
    }));

    const { data: createdNotifications, error: notifError } = await adminClient
      .from('notifications')
      .insert(notifications)
      .select();

    if (notifError) {
      console.error('Error creating notifications:', notifError);
      return new Response(
        JSON.stringify({
          error: 'Erreur lors de la création des notifications',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `${createdNotifications?.length || 0} notifications envoyées`,
        count: createdNotifications?.length || 0,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (error: any) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Erreur serveur', details: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }
});
