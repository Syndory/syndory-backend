-- Migration 003: Functions, Triggers & Scheduled Jobs
-- Logique métier, triggers et fonctions utilitaires

-- =====================================================
-- 1. TRIGGER: Créer profil utilisateur à l'inscription
-- =====================================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO users (id, email, first_name, last_name, role, is_active)
    VALUES (
        NEW.id, 
        NEW.email, 
        COALESCE(NEW.raw_user_meta_data->>'first_name', ''), 
        COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
        COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'student'),
        true
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- =====================================================
-- 2. TRIGGER: Mise à jour automatique de updated_at
-- =====================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_seances_updated_at
    BEFORE UPDATE ON seances
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_programmes_updated_at
    BEFORE UPDATE ON programmes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_presences_updated_at
    BEFORE UPDATE ON presences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_progressions_updated_at
    BEFORE UPDATE ON progressions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_parametres_updated_at
    BEFORE UPDATE ON parametres
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- 3. FUNCTION: Calcul de distance GPS (Haversine)
-- =====================================================

CREATE OR REPLACE FUNCTION calculate_distance(
    lat1 DECIMAL, 
    lon1 DECIMAL, 
    lat2 DECIMAL, 
    lon2 DECIMAL
)
RETURNS DECIMAL AS $$
DECLARE
    R DECIMAL := 6371000; -- Rayon de la Terre en mètres
    phi1 DECIMAL := RADIANS(lat1);
    phi2 DECIMAL := RADIANS(lat2);
    delta_phi DECIMAL := RADIANS(lat2 - lat1);
    delta_lambda DECIMAL := RADIANS(lon2 - lon1);
    a DECIMAL;
    c DECIMAL;
BEGIN
    a := SIN(delta_phi / 2) * SIN(delta_phi / 2) + 
         COS(phi1) * COS(phi2) * 
         SIN(delta_lambda / 2) * SIN(delta_lambda / 2);
    c := 2 * ATAN2(SQRT(a), SQRT(1 - a));
    RETURN R * c; -- Distance en mètres
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =====================================================
-- 4. FUNCTION: Vérifier position dans le rayon de tolérance
-- =====================================================

CREATE OR REPLACE FUNCTION is_within_salle_radius(
    p_user_lat DECIMAL,
    p_user_long DECIMAL,
    p_salle_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_salle_lat DECIMAL;
    v_salle_long DECIMAL;
    v_tolerance INTEGER;
    v_distance DECIMAL;
BEGIN
    SELECT gps_latitude, gps_longitude, tolerance_radius
    INTO v_salle_lat, v_salle_long, v_tolerance
    FROM salles WHERE id = p_salle_id;
    
    IF v_salle_lat IS NULL OR v_salle_long IS NULL THEN
        RETURN false;
    END IF;
    
    v_distance := calculate_distance(p_user_lat, p_user_long, v_salle_lat, v_salle_long);
    
    RETURN v_distance <= v_tolerance;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 5. FUNCTION: Marquer présence avec vérification GPS
-- =====================================================

CREATE OR REPLACE FUNCTION mark_presence(
    p_session_id UUID,
    p_student_id UUID,
    p_gps_lat DECIMAL,
    p_gps_long DECIMAL
)
RETURNS JSONB AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_seance seances%ROWTYPE;
    v_result JSONB;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- Vérifier que la session existe et est ouverte
    SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
    
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session introuvable');
    END IF;
    
    IF v_session.status != 'ouverte' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session fermée');
    END IF;
    
    -- Vérifier que la fenêtre de marquage n'est pas expirée
    v_expires_at := v_session.opened_at + (v_session.marking_window_duration || ' minutes')::INTERVAL;
    IF NOW() > v_expires_at THEN
        RETURN jsonb_build_object('success', false, 'error', 'Fenêtre de marquage expirée');
    END IF;
    
    -- Récupérer la séance pour obtenir la salle
    SELECT * INTO v_seance FROM seances WHERE id = v_session.seance_id;
    
    -- Vérifier la position GPS
    IF NOT is_within_salle_radius(p_gps_lat, p_gps_long, v_seance.salle_id) THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'Position hors du rayon de tolérance de la salle',
            'distance', calculate_distance(p_gps_lat, p_gps_long, 
                (SELECT gps_latitude FROM salles WHERE id = v_seance.salle_id),
                (SELECT gps_longitude FROM salles WHERE id = v_seance.salle_id))
        );
    END IF;
    
    -- Insérer ou mettre à jour la présence
    INSERT INTO presences (session_id, student_id, status, marked_at, student_gps_lat, student_gps_long)
    VALUES (p_session_id, p_student_id, 'present', NOW(), p_gps_lat, p_gps_long)
    ON CONFLICT (session_id, student_id) 
    DO UPDATE SET 
        status = 'present',
        marked_at = NOW(),
        student_gps_lat = p_gps_lat,
        student_gps_long = p_gps_long,
        updated_at = NOW()
    RETURNING * INTO v_result;
    
    RETURN jsonb_build_object('success', true, 'presence_id', v_result->>'id');
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 6. FUNCTION: Fermer une session et marquer les absents
-- =====================================================

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
    -- Vérifier la session
    SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
    
    IF v_session IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Session introuvable');
    END IF;
    
    IF v_session.professor_id != p_professor_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;
    
    IF v_session.status = 'fermée' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Déjà fermée');
    END IF;
    
    -- Récupérer la séance
    SELECT * INTO v_seance FROM seances WHERE id = v_session.seance_id;
    
    -- Marquer les absents
    INSERT INTO presences (session_id, student_id, status, marked_at, marked_by)
    SELECT p_session_id, sc.student_id, 'absent', NOW(), 'student'
    FROM student_classes sc
    WHERE sc.class_id = v_seance.class_id
    AND NOT EXISTS (
        SELECT 1 FROM presences p 
        WHERE p.session_id = p_session_id 
        AND p.student_id = sc.student_id
    );
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    -- Fermer la session
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

-- =====================================================
-- 7. FUNCTION: Vérifier conflits d'emploi du temps
-- =====================================================

CREATE OR REPLACE FUNCTION check_schedule_conflicts(
    p_seance_id UUID DEFAULT NULL,
    p_matiere_id UUID,
    p_professor_id UUID,
    p_class_id UUID,
    p_salle_id UUID,
    p_date DATE,
    p_start_time TIME,
    p_end_time TIME
)
RETURNS TABLE (
    conflict_type TEXT,
    conflict_details JSONB
) AS $$
BEGIN
    -- Conflit salle
    RETURN QUERY
    SELECT 
        'salle'::TEXT,
        jsonb_build_object(
            'seance_id', s.id,
            'matiere', m.name,
            'professor', u.first_name || ' ' || u.last_name,
            'class', c.name,
            'time', s.start_time || ' - ' || s.end_time
        )
    FROM seances s
    JOIN matieres m ON s.matiere_id = m.id
    JOIN users u ON s.professor_id = u.id
    JOIN classes c ON s.class_id = c.id
    WHERE s.salle_id = p_salle_id
    AND s.date = p_date
    AND s.status != 'annulé'
    AND (p_seance_id IS NULL OR s.id != p_seance_id)
    AND (
        (p_start_time, p_end_time) OVERLAPS (s.start_time, s.end_time)
    );
    
    -- Conflit professeur
    RETURN QUERY
    SELECT 
        'professeur'::TEXT,
        jsonb_build_object(
            'seance_id', s.id,
            'matiere', m.name,
            'salle', sa.name,
            'class', c.name,
            'time', s.start_time || ' - ' || s.end_time
        )
    FROM seances s
    JOIN matieres m ON s.matiere_id = m.id
    JOIN salles sa ON s.salle_id = sa.id
    JOIN classes c ON s.class_id = c.id
    WHERE s.professor_id = p_professor_id
    AND s.date = p_date
    AND s.status != 'annulé'
    AND (p_seance_id IS NULL OR s.id != p_seance_id)
    AND (
        (p_start_time, p_end_time) OVERLAPS (s.start_time, s.end_time)
    );
    
    -- Conflit classe
    RETURN QUERY
    SELECT 
        'classe'::TEXT,
        jsonb_build_object(
            'seance_id', s.id,
            'matiere', m.name,
            'professor', u.first_name || ' ' || u.last_name,
            'salle', sa.name,
            'time', s.start_time || ' - ' || s.end_time
        )
    FROM seances s
    JOIN matieres m ON s.matiere_id = m.id
    JOIN users u ON s.professor_id = u.id
    JOIN salles sa ON s.salle_id = sa.id
    WHERE s.class_id = p_class_id
    AND s.date = p_date
    AND s.status != 'annulé'
    AND (p_seance_id IS NULL OR s.id != p_seance_id)
    AND (
        (p_start_time, p_end_time) OVERLAPS (s.start_time, s.end_time)
    );
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 8. FUNCTION: Calculer statistiques de présence
-- =====================================================

CREATE OR REPLACE FUNCTION get_attendance_stats(
    p_student_id UUID DEFAULT NULL,
    p_class_id UUID DEFAULT NULL,
    p_matiere_id UUID DEFAULT NULL,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    total_seances BIGINT,
    present_count BIGINT,
    absent_count BIGINT,
    late_count BIGINT,
    justified_count BIGINT,
    attendance_rate DECIMAL
) AS $$
DECLARE
    v_total BIGINT;
    v_present BIGINT;
    v_absent BIGINT;
    v_late BIGINT;
    v_justified BIGINT;
BEGIN
    SELECT 
        COUNT(*),
        COUNT(*) FILTER (WHERE p.status = 'present'),
        COUNT(*) FILTER (WHERE p.status = 'absent'),
        COUNT(*) FILTER (WHERE p.status = 'late'),
        COUNT(*) FILTER (WHERE p.status = 'justified')
    INTO v_total, v_present, v_absent, v_late, v_justified
    FROM presences p
    JOIN sessions ses ON p.session_id = ses.id
    JOIN seances sea ON ses.seance_id = sea.id
    WHERE (p_student_id IS NULL OR p.student_id = p_student_id)
    AND (p_class_id IS NULL OR sea.class_id = p_class_id)
    AND (p_matiere_id IS NULL OR sea.matiere_id = p_matiere_id)
    AND (p_start_date IS NULL OR sea.date >= p_start_date)
    AND (p_end_date IS NULL OR sea.date <= p_end_date);
    
    RETURN QUERY SELECT
        v_total,
        v_present,
        v_absent,
        v_late,
        v_justified,
        CASE 
            WHEN v_total > 0 THEN 
                ROUND(((v_present + v_justified)::DECIMAL / v_total) * 100, 2)
            ELSE 0
        END;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 9. FUNCTION: Logger une activité
-- =====================================================

CREATE OR REPLACE FUNCTION log_activity(
    p_user_id UUID,
    p_action_type log_action_type,
    p_entity_type TEXT,
    p_entity_id UUID,
    p_details JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO logs_activite (user_id, action_type, entity_type, entity_id, details)
    VALUES (p_user_id, p_action_type, p_entity_type, p_entity_id, p_details)
    RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 10. TRIGGER: Logger les actions critiques
-- =====================================================

CREATE OR REPLACE FUNCTION trigger_log_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM log_activity(
            auth.uid(), 
            'user_created', 
            'users', 
            NEW.id,
            jsonb_build_object('email', NEW.email, 'role', NEW.role)
        );
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.is_active = false AND OLD.is_active = true THEN
            PERFORM log_activity(
                auth.uid(), 
                'user_disabled', 
                'users', 
                NEW.id,
                jsonb_build_object('email', NEW.email)
            );
        ELSE
            PERFORM log_activity(
                auth.uid(), 
                'user_updated', 
                'users', 
                NEW.id,
                jsonb_build_object('changes', jsonb_build_object(
                    'old_role', OLD.role, 'new_role', NEW.role,
                    'old_active', OLD.is_active, 'new_active', NEW.is_active
                ))
            );
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER log_user_changes
    AFTER INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION trigger_log_user_changes();

-- Trigger pour les séances
CREATE OR REPLACE FUNCTION trigger_log_seance_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'publié' THEN
        PERFORM log_activity(
            auth.uid(), 
            'schedule_published', 
            'seances', 
            NEW.id,
            jsonb_build_object('matiere_id', NEW.matiere_id, 'date', NEW.date)
        );
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'brouillon' AND NEW.status = 'publié' THEN
        PERFORM log_activity(
            auth.uid(), 
            'schedule_published', 
            'seances', 
            NEW.id,
            jsonb_build_object('matiere_id', NEW.matiere_id, 'date', NEW.date)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER log_seance_changes
    AFTER INSERT OR UPDATE ON seances
    FOR EACH ROW EXECUTE FUNCTION trigger_log_seance_changes();

-- =====================================================
-- 11. FUNCTION: Créer automatiquement les présences à l'ouverture d'une session
-- =====================================================

CREATE OR REPLACE FUNCTION create_initial_presences()
RETURNS TRIGGER AS $$
DECLARE
    v_class_id UUID;
BEGIN
    -- Récupérer la classe de la séance
    SELECT class_id INTO v_class_id 
    FROM seances WHERE id = NEW.seance_id;
    
    -- Créer des entrées de présence vides pour tous les étudiants de la classe
    INSERT INTO presences (session_id, student_id, status, marked_by)
    SELECT NEW.id, sc.student_id, 'absent', 'student'
    FROM student_classes sc
    WHERE sc.class_id = v_class_id
    ON CONFLICT (session_id, student_id) DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_session_opened
    AFTER INSERT ON sessions
    FOR EACH ROW EXECUTE FUNCTION create_initial_presences();

-- =====================================================
-- 12. FUNCTION: Fermer automatiquement les sessions expirées
-- =====================================================

CREATE OR REPLACE FUNCTION close_expired_sessions()
RETURNS void AS $$
DECLARE
    v_session RECORD;
BEGIN
    FOR v_session IN 
        SELECT * FROM sessions 
        WHERE status = 'ouverte'
        AND opened_at + (marking_window_duration || ' minutes')::INTERVAL < NOW()
        AND closed_at IS NULL
    LOOP
        PERFORM close_session(v_session.id, v_session.professor_id);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 13. FUNCTION: Publier les annonces programmées
-- =====================================================

CREATE OR REPLACE FUNCTION publish_scheduled_annonces()
RETURNS void AS $$
BEGIN
    UPDATE annonces 
    SET is_published = true, published_at = NOW()
    WHERE is_published = false 
    AND scheduled_at <= NOW();
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 14. FUNCTION: Créer notification
-- =====================================================

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
BEGIN
    INSERT INTO notifications (user_id, type, title, message, data)
    VALUES (p_user_id, p_type, p_title, p_message, p_data)
    RETURNING id INTO v_notif_id;
    
    RETURN v_notif_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 15. FUNCTION: Notifier les étudiants d'une classe
-- =====================================================

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
        SELECT student_id FROM student_classes WHERE class_id = p_class_id
    LOOP
        PERFORM create_notification(v_student_id, p_type, p_title, p_message, p_data);
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 16. VIEW: Vue synthétique des séances avec présences
-- =====================================================

CREATE OR REPLACE VIEW seances_view AS
SELECT 
    s.*,
    m.name AS matiere_name,
    m.code AS matiere_code,
    u.first_name || ' ' || u.last_name AS professor_name,
    c.name AS class_name,
    c.filiere_id,
    f.name AS filiere_name,
    sa.name AS salle_name,
    sa.building,
    sa.gps_latitude AS salle_gps_lat,
    sa.gps_longitude AS salle_gps_long,
    sa.tolerance_radius AS salle_tolerance
FROM seances s
JOIN matieres m ON s.matiere_id = m.id
JOIN users u ON s.professor_id = u.id
JOIN classes c ON s.class_id = c.id
JOIN filieres f ON c.filiere_id = f.id
JOIN salles sa ON s.salle_id = sa.id;

-- =====================================================
-- 17. VIEW: Vue des présences détaillée
-- =====================================================

CREATE OR REPLACE VIEW presences_view AS
SELECT 
    p.*,
    u.first_name || ' ' || u.last_name AS student_name,
    u.email AS student_email,
    ses.seance_id,
    ses.professor_id,
    ses.opened_at AS session_opened_at,
    ses.closed_at AS session_closed_at,
    ses.status AS session_status,
    sea.date AS seance_date,
    sea.start_time AS seance_start,
    sea.end_time AS seance_end,
    sea.matiere_id,
    sea.class_id,
    sea.salle_id
FROM presences p
JOIN users u ON p.student_id = u.id
JOIN sessions ses ON p.session_id = ses.id
JOIN seances sea ON ses.seance_id = sea.id;
