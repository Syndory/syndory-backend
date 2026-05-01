-- Migration 013: Fix handle_new_user to always insert into public.users (avoid auth.users name collision)

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_role public.user_role := 'student';
BEGIN
    IF NEW.raw_user_meta_data IS NOT NULL THEN
        BEGIN
            v_role := (NEW.raw_user_meta_data->>'role')::public.user_role;
        EXCEPTION WHEN OTHERS THEN
            v_role := 'student';
        END;
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
