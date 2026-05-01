-- Migration 002: Row Level Security Policies
-- Activation RLS et création des politiques de sécurité

-- =====================================================
-- 1. ACTIVER RLS SUR TOUTES LES TABLES
-- =====================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE filieres ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE matieres ENABLE ROW LEVEL SECURITY;
ALTER TABLE salles ENABLE ROW LEVEL SECURITY;
ALTER TABLE professeur_matieres ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE semestres ENABLE ROW LEVEL SECURITY;
ALTER TABLE seances ENABLE ROW LEVEL SECURITY;
ALTER TABLE programmes ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE presences ENABLE ROW LEVEL SECURITY;
ALTER TABLE justificatifs ENABLE ROW LEVEL SECURITY;
ALTER TABLE progressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ressources ENABLE ROW LEVEL SECURITY;
ALTER TABLE annonces ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs_activite ENABLE ROW LEVEL SECURITY;
ALTER TABLE parametres ENABLE ROW LEVEL SECURITY;
ALTER TABLE vacances_examens ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 1b. AJOUT COLONNE MANQUANTE student_classes.is_active
-- =====================================================

-- Cette colonne est nécessaire pour les policies mais manquait dans le schéma initial
ALTER TABLE student_classes ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
CREATE INDEX IF NOT EXISTS idx_student_class_active ON student_classes(student_id, is_active) WHERE is_active = true;

-- =====================================================
-- 2. FONCTIONS UTILITAIRES POUR RLS
-- =====================================================

-- Fonction pour vérifier si l'utilisateur connecté est actif
CREATE OR REPLACE FUNCTION is_active_user()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM users
        WHERE id = auth.uid()
        AND is_active = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour récupérer le rôle de l'utilisateur connecté
CREATE OR REPLACE FUNCTION get_current_user_role()
RETURNS user_role AS $$
DECLARE
    v_role user_role;
BEGIN
    SELECT role
    INTO v_role
    FROM users
    WHERE id = auth.uid()
    AND is_active = true;
    RETURN v_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour vérifier si l'utilisateur est admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN get_current_user_role() = 'admin';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour vérifier si l'utilisateur est professeur
CREATE OR REPLACE FUNCTION is_professor()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN get_current_user_role() = 'professor';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour vérifier si l'utilisateur est étudiant
CREATE OR REPLACE FUNCTION is_student()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN get_current_user_role() IN ('student', 'class_representative');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour vérifier si l'utilisateur est responsable de classe
CREATE OR REPLACE FUNCTION is_class_representative()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN get_current_user_role() = 'class_representative';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour obtenir la classe de l'étudiant connecté
CREATE OR REPLACE FUNCTION get_student_class_id()
RETURNS UUID AS $$
DECLARE
    v_class_id UUID;
BEGIN
    SELECT class_id INTO v_class_id 
    FROM student_classes 
    WHERE student_id = auth.uid() 
    AND is_active = true
    LIMIT 1;
    RETURN v_class_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fonction pour vérifier si le professeur enseigne dans une classe
CREATE OR REPLACE FUNCTION professor_teaches_class(class_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM professeur_matieres 
        WHERE professor_id = auth.uid() AND class_id = class_uuid
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 3. POLICIES - USERS
-- =====================================================

-- Suppression préalable pour idempotence
DROP POLICY IF EXISTS users_select ON users;
DROP POLICY IF EXISTS users_update ON users;
DROP POLICY IF EXISTS users_insert ON users;
DROP POLICY IF EXISTS users_delete ON users;

-- SELECT: tout le monde peut voir les profils de base
CREATE POLICY users_select ON users
    FOR SELECT TO authenticated
    USING (is_active_user());

-- UPDATE: admin peut tout modifier, user peut modifier son propre profil (sauf rôle)
CREATE POLICY users_update ON users
    FOR UPDATE TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR id = auth.uid()
        )
    )
    WITH CHECK (
        is_active_user()
        AND (
            is_admin() 
            OR (id = auth.uid() AND role = (SELECT role FROM users WHERE id = auth.uid()))
        )
    );

-- INSERT: admin uniquement
CREATE POLICY users_insert ON users
    FOR INSERT TO authenticated
    WITH CHECK (is_active_user() AND is_admin());

-- DELETE: admin uniquement
CREATE POLICY users_delete ON users
    FOR DELETE TO authenticated
    USING (is_active_user() AND is_admin());

-- =====================================================
-- 4. POLICIES - FILIERES
-- =====================================================

DROP POLICY IF EXISTS filieres_select ON filieres;
DROP POLICY IF EXISTS filieres_all_admin ON filieres;

CREATE POLICY filieres_select ON filieres
    FOR SELECT TO authenticated
    USING (is_active_user());

CREATE POLICY filieres_all_admin ON filieres
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 5. POLICIES - CLASSES
-- =====================================================

DROP POLICY IF EXISTS classes_select ON classes;
DROP POLICY IF EXISTS classes_all_admin ON classes;

CREATE POLICY classes_select ON classes
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR EXISTS (
                SELECT 1 FROM professeur_matieres pm
                WHERE pm.class_id = classes.id
                AND pm.professor_id = auth.uid()
            )
            OR id = get_student_class_id()
            OR (is_class_representative() AND id = get_student_class_id())
        )
    );

CREATE POLICY classes_all_admin ON classes
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 6. POLICIES - MATIERES
-- =====================================================

DROP POLICY IF EXISTS matieres_select ON matieres;
DROP POLICY IF EXISTS matieres_all_admin ON matieres;

CREATE POLICY matieres_select ON matieres
    FOR SELECT TO authenticated
    USING (is_active_user());

CREATE POLICY matieres_all_admin ON matieres
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 7. POLICIES - SALLES
-- =====================================================

DROP POLICY IF EXISTS salles_select ON salles;
DROP POLICY IF EXISTS salles_all_admin ON salles;

CREATE POLICY salles_select ON salles
    FOR SELECT TO authenticated
    USING (is_active_user());

CREATE POLICY salles_all_admin ON salles
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 8. POLICIES - PROFESSEUR_MATIERES
-- =====================================================

DROP POLICY IF EXISTS prof_mat_select ON professeur_matieres;
DROP POLICY IF EXISTS prof_mat_all_admin ON professeur_matieres;

CREATE POLICY prof_mat_select ON professeur_matieres
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR professor_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM student_classes sc 
                WHERE sc.student_id = auth.uid() 
                AND sc.class_id = professeur_matieres.class_id
                AND sc.is_active = true
            )
        )
    );

CREATE POLICY prof_mat_all_admin ON professeur_matieres
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 9. POLICIES - STUDENT_CLASSES
-- =====================================================

DROP POLICY IF EXISTS student_class_select ON student_classes;
DROP POLICY IF EXISTS student_class_all_admin ON student_classes;

CREATE POLICY student_class_select ON student_classes
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR student_id = auth.uid()
            OR professor_teaches_class(class_id)
        )
    );

CREATE POLICY student_class_all_admin ON student_classes
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 10. POLICIES - SEMESTRES
-- =====================================================

DROP POLICY IF EXISTS semestres_select ON semestres;
DROP POLICY IF EXISTS semestres_all_admin ON semestres;

CREATE POLICY semestres_select ON semestres
    FOR SELECT TO authenticated
    USING (is_active_user());

CREATE POLICY semestres_all_admin ON semestres
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 11. POLICIES - SEANCES (Emploi du temps)
-- =====================================================

DROP POLICY IF EXISTS seances_select ON seances;
DROP POLICY IF EXISTS seances_all_admin ON seances;

CREATE POLICY seances_select ON seances
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR professor_id = auth.uid()
            OR class_id = get_student_class_id()
            OR (is_class_representative() AND class_id = get_student_class_id())
        )
    );

CREATE POLICY seances_all_admin ON seances
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 12. POLICIES - PROGRAMMES
-- =====================================================

DROP POLICY IF EXISTS programmes_select ON programmes;
DROP POLICY IF EXISTS programmes_insert_update ON programmes;
DROP POLICY IF EXISTS programmes_update ON programmes;
DROP POLICY IF EXISTS programmes_delete ON programmes;

CREATE POLICY programmes_select ON programmes
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR professor_teaches_class(class_id)
            OR class_id = get_student_class_id()
        )
    );

CREATE POLICY programmes_insert_update ON programmes
    FOR INSERT TO authenticated
    WITH CHECK (is_active_user() AND (is_admin() OR professor_teaches_class(class_id)));

CREATE POLICY programmes_update ON programmes
    FOR UPDATE TO authenticated
    USING (is_active_user() AND (is_admin() OR professor_teaches_class(class_id)))
    WITH CHECK (is_active_user() AND (is_admin() OR professor_teaches_class(class_id)));

CREATE POLICY programmes_delete ON programmes
    FOR DELETE TO authenticated
    USING (is_active_user() AND is_admin());

-- =====================================================
-- 13. POLICIES - SESSIONS (Présence)
-- =====================================================

DROP POLICY IF EXISTS sessions_select ON sessions;
DROP POLICY IF EXISTS sessions_insert ON sessions;
DROP POLICY IF EXISTS sessions_update ON sessions;
DROP POLICY IF EXISTS sessions_delete ON sessions;

CREATE POLICY sessions_select ON sessions
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR professor_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM seances s
                JOIN student_classes sc ON s.class_id = sc.class_id
                WHERE sessions.seance_id = s.id
                AND sc.student_id = auth.uid()
                AND sc.is_active = true
            )
        )
    );

CREATE POLICY sessions_insert ON sessions
    FOR INSERT TO authenticated
    WITH CHECK (
        is_active_user()
        AND (
            is_admin() 
            OR (is_professor() AND professor_id = auth.uid())
        )
    );

CREATE POLICY sessions_update ON sessions
    FOR UPDATE TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR professor_id = auth.uid()
        )
    )
    WITH CHECK (
        is_active_user()
        AND (
            is_admin() 
            OR professor_id = auth.uid()
        )
    );

CREATE POLICY sessions_delete ON sessions
    FOR DELETE TO authenticated
    USING (is_active_user() AND is_admin());

-- =====================================================
-- 14. POLICIES - PRESENCES
-- =====================================================

DROP POLICY IF EXISTS presences_select ON presences;
DROP POLICY IF EXISTS presences_insert ON presences;
DROP POLICY IF EXISTS presences_update ON presences;

CREATE POLICY presences_select ON presences
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR student_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM sessions ses
                JOIN seances sea ON ses.seance_id = sea.id
                WHERE presences.session_id = ses.id
                AND sea.professor_id = auth.uid()
            )
            OR EXISTS (
                SELECT 1 FROM sessions ses
                JOIN seances sea ON ses.seance_id = sea.id
                WHERE presences.session_id = ses.id
                AND sea.class_id = get_student_class_id()
                AND is_class_representative()
            )
        )
    );

CREATE POLICY presences_insert ON presences
    FOR INSERT TO authenticated
    WITH CHECK (
        is_active_user()
        AND (
            is_admin()
            OR EXISTS (
                SELECT 1 FROM sessions ses
                JOIN seances sea ON ses.seance_id = sea.id
                WHERE presences.session_id = ses.id
                AND sea.professor_id = auth.uid()
            )
        )
    );

CREATE POLICY presences_update ON presences
    FOR UPDATE TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR student_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM sessions ses
                JOIN seances sea ON ses.seance_id = sea.id
                WHERE presences.session_id = ses.id
                AND sea.professor_id = auth.uid()
            )
        )
    )
    WITH CHECK (
        is_active_user()
        AND (
            is_admin() 
            OR (
                student_id = auth.uid()
                AND marked_by = 'student'
                AND status = 'present'
                AND EXISTS (
                    SELECT 1
                    FROM sessions ses
                    WHERE ses.id = presences.session_id
                    AND ses.status = 'ouverte'
                    AND NOW() <= (ses.opened_at + (ses.marking_window_duration || ' minutes')::INTERVAL)
                )
            )
            OR EXISTS (
                SELECT 1 FROM sessions ses
                JOIN seances sea ON ses.seance_id = sea.id
                WHERE presences.session_id = ses.id
                AND sea.professor_id = auth.uid()
            )
        )
    );

-- =====================================================
-- 15. POLICIES - JUSTIFICATIFS
-- =====================================================

DROP POLICY IF EXISTS justificatifs_select ON justificatifs;
DROP POLICY IF EXISTS justificatifs_insert ON justificatifs;
DROP POLICY IF EXISTS justificatifs_update ON justificatifs;

CREATE POLICY justificatifs_select ON justificatifs
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR student_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM presences p
                JOIN sessions ses ON p.session_id = ses.id
                JOIN seances sea ON ses.seance_id = sea.id
                WHERE justificatifs.presence_id = p.id
                AND sea.professor_id = auth.uid()
            )
        )
    );

CREATE POLICY justificatifs_insert ON justificatifs
    FOR INSERT TO authenticated
    WITH CHECK (
        is_active_user()
        AND (student_id = auth.uid())
    );

CREATE POLICY justificatifs_update ON justificatifs
    FOR UPDATE TO authenticated
    USING (
        is_active_user()
        AND EXISTS (
            SELECT 1 FROM presences p
            JOIN sessions ses ON p.session_id = ses.id
            JOIN seances sea ON ses.seance_id = sea.id
            WHERE justificatifs.presence_id = p.id
            AND sea.professor_id = auth.uid()
        )
    )
    WITH CHECK (
        is_active_user()
        AND EXISTS (
            SELECT 1 FROM presences p
            JOIN sessions ses ON p.session_id = ses.id
            JOIN seances sea ON ses.seance_id = sea.id
            WHERE justificatifs.presence_id = p.id
            AND sea.professor_id = auth.uid()
        )
    );

-- =====================================================
-- 16. POLICIES - PROGRESSIONS
-- =====================================================

DROP POLICY IF EXISTS progressions_select ON progressions;
DROP POLICY IF EXISTS progressions_insert ON progressions;
DROP POLICY IF EXISTS progressions_update ON progressions;
DROP POLICY IF EXISTS progressions_delete ON progressions;

CREATE POLICY progressions_select ON progressions
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR EXISTS (
                SELECT 1 FROM seances s
                WHERE progressions.seance_id = s.id
                AND (s.professor_id = auth.uid() OR s.class_id = get_student_class_id())
            )
        )
    );

CREATE POLICY progressions_insert ON progressions
    FOR INSERT TO authenticated
    WITH CHECK (
        is_active_user()
        AND (
            (updated_by = auth.uid() AND updated_by_role = 'professor' AND EXISTS (
                SELECT 1 FROM seances s
                WHERE progressions.seance_id = s.id
                AND s.professor_id = auth.uid()
            ))
            OR (updated_by = auth.uid() AND updated_by_role = 'class_representative' AND is_class_representative() AND EXISTS (
                SELECT 1 FROM seances s
                WHERE progressions.seance_id = s.id
                AND s.class_id = get_student_class_id()
            ))
        )
    );

CREATE POLICY progressions_update ON progressions
    FOR UPDATE TO authenticated
    USING (
        is_active_user()
        AND is_validated = false
        AND (
            EXISTS (
                SELECT 1 FROM seances s
                WHERE progressions.seance_id = s.id
                AND s.professor_id = auth.uid()
            )
            OR (
                is_class_representative()
                AND EXISTS (
                    SELECT 1 FROM seances s
                    WHERE progressions.seance_id = s.id
                    AND s.class_id = get_student_class_id()
                )
            )
        )
    )
    WITH CHECK (
        is_active_user()
        AND is_validated = false
        AND (
            (updated_by = auth.uid() AND updated_by_role = 'professor' AND EXISTS (
                SELECT 1 FROM seances s
                WHERE progressions.seance_id = s.id
                AND s.professor_id = auth.uid()
            ))
            OR (updated_by = auth.uid() AND updated_by_role = 'class_representative' AND is_class_representative() AND EXISTS (
                SELECT 1 FROM seances s
                WHERE progressions.seance_id = s.id
                AND s.class_id = get_student_class_id()
            ))
        )
    );

CREATE POLICY progressions_delete ON progressions
    FOR DELETE TO authenticated
    USING (false);

-- =====================================================
-- 17. POLICIES - RESSOURCES
-- =====================================================

DROP POLICY IF EXISTS ressources_select ON ressources;
DROP POLICY IF EXISTS ressources_insert ON ressources;
DROP POLICY IF EXISTS ressources_update_delete ON ressources;

CREATE POLICY ressources_select ON ressources
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR class_id = get_student_class_id()
            OR professor_teaches_class(class_id)
        )
    );

CREATE POLICY ressources_insert ON ressources
    FOR INSERT TO authenticated
    WITH CHECK (
        is_active_user()
        AND (
            is_admin() 
            OR uploaded_by = auth.uid()
        )
    );

CREATE POLICY ressources_update_delete ON ressources
    FOR ALL TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR uploaded_by = auth.uid()
        )
    )
    WITH CHECK (
        is_active_user()
        AND (
            is_admin() 
            OR uploaded_by = auth.uid()
        )
    );

-- =====================================================
-- 18. POLICIES - ANNONCES
-- =====================================================

DROP POLICY IF EXISTS annonces_select ON annonces;
DROP POLICY IF EXISTS annonces_all_admin ON annonces;

CREATE POLICY annonces_select ON annonces
    FOR SELECT TO authenticated
    USING (
        is_active_user()
        AND (
            is_admin() 
            OR is_published = true
            OR (target_type = 'all')
            OR (target_type = 'students' AND is_student())
            OR (target_type = 'professors' AND is_professor())
            OR (target_type = 'classe' AND target_id = get_student_class_id())
            OR (target_type = 'filiere' AND target_id IN (
                SELECT c.filiere_id FROM classes c 
                JOIN student_classes sc ON c.id = sc.class_id 
                WHERE sc.student_id = auth.uid()
                AND sc.is_active = true
            ))
        )
    );

CREATE POLICY annonces_all_admin ON annonces
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 19. POLICIES - NOTIFICATIONS
-- =====================================================

DROP POLICY IF EXISTS notifications_select ON notifications;
DROP POLICY IF EXISTS notifications_insert ON notifications;
DROP POLICY IF EXISTS notifications_update ON notifications;
DROP POLICY IF EXISTS notifications_delete ON notifications;

CREATE POLICY notifications_select ON notifications
    FOR SELECT TO authenticated
    USING (is_active_user() AND user_id = auth.uid());

CREATE POLICY notifications_insert ON notifications
    FOR INSERT TO authenticated
    WITH CHECK (is_active_user() AND is_admin());

CREATE POLICY notifications_update ON notifications
    FOR UPDATE TO authenticated
    USING (is_active_user() AND user_id = auth.uid())
    WITH CHECK (is_active_user() AND user_id = auth.uid());

CREATE POLICY notifications_delete ON notifications
    FOR DELETE TO authenticated
    USING (is_active_user() AND user_id = auth.uid());

-- =====================================================
-- 20. POLICIES - LOGS_ACTIVITE
-- =====================================================

DROP POLICY IF EXISTS logs_select ON logs_activite;
DROP POLICY IF EXISTS logs_all_admin ON logs_activite;

CREATE POLICY logs_select ON logs_activite
    FOR SELECT TO authenticated
    USING (is_active_user() AND is_admin());

CREATE POLICY logs_all_admin ON logs_activite
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 21. POLICIES - PARAMETRES
-- =====================================================

DROP POLICY IF EXISTS parametres_select ON parametres;
DROP POLICY IF EXISTS parametres_all_admin ON parametres;

CREATE POLICY parametres_select ON parametres
    FOR SELECT TO authenticated
    USING (is_active_user());

CREATE POLICY parametres_all_admin ON parametres
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());

-- =====================================================
-- 22. POLICIES - VACANCES_EXAMENS
-- =====================================================

DROP POLICY IF EXISTS vacances_select ON vacances_examens;
DROP POLICY IF EXISTS vacances_all_admin ON vacances_examens;

CREATE POLICY vacances_select ON vacances_examens
    FOR SELECT TO authenticated
    USING (is_active_user());

CREATE POLICY vacances_all_admin ON vacances_examens
    FOR ALL TO authenticated
    USING (is_active_user() AND is_admin())
    WITH CHECK (is_active_user() AND is_admin());
