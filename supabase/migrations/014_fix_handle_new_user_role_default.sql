-- Migration 014: Fix handle_new_user to default role to 'student' when metadata role is NULL/empty

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_role public.user_role := 'student';
    v_role_text text;
BEGIN
    IF NEW.raw_user_meta_data IS NOT NULL THEN
        v_role_text := NEW.raw_user_meta_data->>'role';

        IF v_role_text IS NOT NULL AND btrim(v_role_text) <> '' THEN
            BEGIN
                v_role := v_role_text::public.user_role;
            EXCEPTION WHEN OTHERS THEN
                v_role := 'student';
            END;
        END IF;
    END IF;

    INSERT INTO public.users (id, email, first_name, last_name, role, is_active)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
        COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
        v_role,
        true
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
