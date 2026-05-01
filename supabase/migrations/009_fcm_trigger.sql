-- Migration 009: trigger push via edge function on notification creation

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION create_notification(
    p_user_id UUID,
    p_type notification_type,
    p_title TEXT,
    p_message TEXT,
    p_data JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    v_notif_id UUID;
    v_functions_url TEXT;
BEGIN
    INSERT INTO notifications (user_id, type, title, message, data)
    VALUES (p_user_id, p_type, p_title, p_message, p_data)
    RETURNING id INTO v_notif_id;

    v_functions_url := current_setting('app.settings.functions_url', true);
    IF v_functions_url IS NULL OR v_functions_url = '' THEN
        v_functions_url := 'http://localhost:54321/functions/v1';
    END IF;

    BEGIN
        PERFORM net.http_post(
            url := v_functions_url || '/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json'),
            body := jsonb_build_object(
                'notification_id', v_notif_id,
                'user_id', p_user_id,
                'title', p_title,
                'message', p_message,
                'data', p_data,
                'type', p_type
            )
        );
    EXCEPTION WHEN OTHERS THEN
        -- Ignore push failures to avoid blocking notification creation
        NULL;
    END;

    RETURN v_notif_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
