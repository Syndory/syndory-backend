-- Migration 007: Correctifs filtres is_active pour presences/notifications

CREATE OR REPLACE FUNCTION create_initial_presences()
RETURNS TRIGGER AS $$
DECLARE
    v_class_id UUID;
BEGIN
    SELECT class_id INTO v_class_id
    FROM seances
    WHERE id = NEW.seance_id;

    INSERT INTO presences (session_id, student_id, status, marked_by)
    SELECT NEW.id, sc.student_id, 'absent', 'student'
    FROM student_classes sc
    JOIN users u ON u.id = sc.student_id
    WHERE sc.class_id = v_class_id
    AND sc.is_active = true
    AND u.is_active = true
    ON CONFLICT (session_id, student_id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION close_session(
    p_session_id UUID,
    p_professor_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_seance seances%ROWTYPE;
    v_count INTEGER;
BEGIN
    SELECT * INTO v_session FROM sessions WHERE id = p_session_id;

    IF v_session IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session introuvable');
    END IF;

    IF v_session.professor_id != p_professor_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorise');
    END IF;

    IF v_session.status = 'fermée' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Deja fermee');
    END IF;

    SELECT * INTO v_seance FROM seances WHERE id = v_session.seance_id;

    INSERT INTO presences (session_id, student_id, status, marked_at, marked_by)
    SELECT p_session_id, sc.student_id, 'absent', NOW(), 'student'
    FROM student_classes sc
    JOIN users u ON u.id = sc.student_id
    WHERE sc.class_id = v_seance.class_id
    AND sc.is_active = true
    AND u.is_active = true
    AND NOT EXISTS (
        SELECT 1 FROM presences p
        WHERE p.session_id = p_session_id
        AND p.student_id = sc.student_id
    );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    UPDATE sessions SET
        status = 'fermée',
        closed_at = NOW()
    WHERE id = p_session_id;

    RETURN jsonb_build_object(
        'success', true,
        'absents_marked', v_count,
        'session_closed', true
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_class(
    p_class_id UUID,
    p_type notification_type,
    p_title TEXT,
    p_message TEXT,
    p_data JSONB DEFAULT '{}'
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_student_id UUID;
BEGIN
    FOR v_student_id IN
        SELECT sc.student_id
        FROM student_classes sc
        JOIN users u ON u.id = sc.student_id
        WHERE sc.class_id = p_class_id
        AND sc.is_active = true
        AND u.is_active = true
    LOOP
        PERFORM create_notification(v_student_id, p_type, p_title, p_message, p_data);
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
