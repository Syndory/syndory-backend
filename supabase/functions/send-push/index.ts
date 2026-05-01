import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { sendPushNotification } from '../_shared/fcm.ts';

interface SendPushRequest {
  user_id?: string;
  notification_id?: string;
  title?: string;
  message?: string;
  data?: Record<string, unknown>;
  type?: string;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = getSupabaseAdmin();
    const {
      user_id,
      notification_id,
      title,
      message,
      data,
      type,
    }: SendPushRequest = await req.json();

    let userId = user_id;
    let notifTitle = title;
    let notifMessage = message;
    let notifData = data;
    let notifType = type;

    if ((!userId || !notifTitle || !notifMessage) && notification_id) {
      const { data: notif, error: notifError } = await supabase
        .from('notifications')
        .select('user_id, title, message, data, type')
        .eq('id', notification_id)
        .single();

      if (notifError) {
        return new Response(
          JSON.stringify({ error: 'Notification introuvable' }),
          {
            status: 404,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        );
      }

      userId = notif.user_id;
      notifTitle = notif.title;
      notifMessage = notif.message;
      notifData = notif.data || notifData;
      notifType = notif.type || notifType;
    }

    if (!userId || !notifTitle || !notifMessage) {
      return new Response(
        JSON.stringify({ error: 'Parametres requis manquants' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { data: userRow, error: userError } = await supabase
      .from('users')
      .select('fcm_token')
      .eq('id', userId)
      .single();

    if (userError || !userRow?.fcm_token) {
      return new Response(
        JSON.stringify({ success: false, error: 'Aucun token FCM' }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const mergedData = {
      ...(notifData || {}),
      ...(notifType ? { type: notifType } : {}),
      ...(notification_id ? { notification_id } : {}),
    };

    const result = await sendPushNotification(
      userRow.fcm_token,
      notifTitle,
      notifMessage,
      mergedData,
    );

    return new Response(
      JSON.stringify({ success: result.success, error: result.error }),
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
