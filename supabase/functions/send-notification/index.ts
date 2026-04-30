// Edge Function: send-notification
// Envoie des notifications push et crée les entrées dans la table notifications

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseClient, getSupabaseAdmin } from '../_shared/supabase.ts';

interface SendNotificationRequest {
  user_ids: string[]; // Si vide, envoie à tous les utilisateurs de la cible
  target_type?: 'all' | 'filiere' | 'classe' | 'professors' | 'students';
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

    if (
      !['admin', 'professor', 'class_representative'].includes(
        userData?.role || '',
      )
    ) {
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

    let targetUserIds: string[] = [];

    // Déterminer les utilisateurs cibles
    if (user_ids && user_ids.length > 0) {
      // Envoi direct aux user_ids spécifiés
      targetUserIds = user_ids;
    } else if (target_type && target_id) {
      // Envoi basé sur la cible
      switch (target_type) {
        case 'classe':
          const { data: classStudents } = await supabase
            .from('student_classes')
            .select('student_id')
            .eq('class_id', target_id);
          targetUserIds = classStudents?.map((s: any) => s.student_id) || [];
          break;

        case 'filiere':
          const { data: classes } = await supabase
            .from('classes')
            .select('id')
            .eq('filiere_id', target_id);
          if (classes) {
            const classIds = classes.map((c: any) => c.id);
            const { data: allStudents } = await supabase
              .from('student_classes')
              .select('student_id')
              .in('class_id', classIds);
            targetUserIds = allStudents?.map((s: any) => s.student_id) || [];
          }
          break;

        case 'professors':
          const { data: profs } = await supabase
            .from('users')
            .select('id')
            .eq('role', 'professor')
            .eq('is_active', true);
          targetUserIds = profs?.map((p: any) => p.id) || [];
          break;

        case 'students':
          const { data: allStudentsUsers } = await supabase
            .from('users')
            .select('id')
            .in('role', ['student', 'class_representative']);
          targetUserIds = allStudentsUsers?.map((s: any) => s.id) || [];
          break;

        case 'all':
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
