type FcmData = Record<string, unknown>;

type FcmSendResult = {
  success: boolean;
  error?: string;
};

const toFcmData = (data: FcmData | undefined) => {
  if (!data) return undefined;
  const entries = Object.entries(data).map(([key, value]) => [
    key,
    typeof value === 'string' ? value : JSON.stringify(value),
  ]);
  return Object.fromEntries(entries) as Record<string, string>;
};

export const sendPushNotification = async (
  fcmToken: string,
  title: string,
  body: string,
  data?: FcmData,
): Promise<FcmSendResult> => {
  if (!fcmToken) {
    return { success: false, error: 'missing_fcm_token' };
  }

  const serverKey = Deno.env.get('FCM_SERVER_KEY');

  if (!serverKey) {
    console.warn('FCM config missing');
    return { success: false, error: 'missing_fcm_config' };
  }

  const payload = {
    to: fcmToken,
    notification: { title, body },
    data: toFcmData(data),
  };

  try {
    const response = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        Authorization: `key=${serverKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('FCM error', response.status, errorText);
      return { success: false, error: 'fcm_request_failed' };
    }

    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('FCM request exception', message);
    return { success: false, error: 'fcm_request_exception' };
  }
};
