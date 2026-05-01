-- Migration 015: Ensure handle_new_user runs with privileges that can bypass RLS and uses stable search_path

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

ALTER FUNCTION handle_new_user() OWNER TO postgres;
