-- Migration 006: Storage Buckets RLS Policies
-- Configuration des politiques RLS pour les buckets de stockage
-- =====================================================

-- =====================================================
-- 1. BUCKET AVATARS (Public)
-- =====================================================

-- Suppression préalable pour idempotence
DROP POLICY IF EXISTS avatars_select ON storage.objects;
DROP POLICY IF EXISTS avatars_insert ON storage.objects;
DROP POLICY IF EXISTS avatars_update ON storage.objects;
DROP POLICY IF EXISTS avatars_delete ON storage.objects;

-- Autoriser lecture publique (avatars visibles par tous)
CREATE POLICY avatars_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'avatars');

-- Upload avatar : utilisateur connecté et actif, uniquement dans son propre dossier
CREATE POLICY avatars_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'avatars'
        AND is_active_user()
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Mise à jour avatar : propriétaire uniquement
CREATE POLICY avatars_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'avatars'
        AND is_active_user()
        AND (storage.foldername(name))[1] = auth.uid()::text
    )
    WITH CHECK (
        bucket_id = 'avatars'
        AND is_active_user()
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Suppression avatar : propriétaire ou admin
CREATE POLICY avatars_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'avatars'
        AND is_active_user()
        AND (
            (storage.foldername(name))[1] = auth.uid()::text
            OR is_admin()
        )
    );

-- =====================================================
-- 2. BUCKET RESOURCES (Privé - Documents pédagogiques)
-- =====================================================

-- Suppression préalable pour idempotence
DROP POLICY IF EXISTS resources_select ON storage.objects;
DROP POLICY IF EXISTS resources_insert ON storage.objects;
DROP POLICY IF EXISTS resources_update ON storage.objects;
DROP POLICY IF EXISTS resources_delete ON storage.objects;

-- Lecture : admin, prof concerné, ou étudiants de la classe concernée
CREATE POLICY resources_select ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'resources'
        AND is_active_user()
        AND (
            is_admin()
            OR EXISTS (
                -- Prof qui enseigne dans cette classe
                SELECT 1 FROM ressources r
                JOIN student_classes sc ON r.class_id = sc.class_id
                WHERE r.file_url LIKE '%' || name
                AND sc.student_id = auth.uid()
                AND sc.is_active = true
            )
            OR EXISTS (
                -- Étudiant de la classe
                SELECT 1 FROM ressources r
                JOIN student_classes sc ON r.class_id = sc.class_id
                WHERE r.file_url LIKE '%' || name
                AND sc.student_id = auth.uid()
                AND sc.is_active = true
            )
            OR EXISTS (
                -- Uploader = soi-même
                SELECT 1 FROM ressources r
                WHERE r.file_url LIKE '%' || name
                AND r.uploaded_by = auth.uid()
            )
        )
    );

-- Upload : admin, prof, ou responsable de classe
CREATE POLICY resources_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'resources'
        AND is_active_user()
        AND (
            is_admin()
            OR is_professor()
            OR is_class_representative()
        )
    );

-- Mise à jour : uploader uniquement
CREATE POLICY resources_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'resources'
        AND is_active_user()
        AND EXISTS (
            SELECT 1 FROM ressources r
            WHERE r.file_url LIKE '%' || name
            AND r.uploaded_by = auth.uid()
        )
    )
    WITH CHECK (
        bucket_id = 'resources'
        AND is_active_user()
        AND EXISTS (
            SELECT 1 FROM ressources r
            WHERE r.file_url LIKE '%' || name
            AND r.uploaded_by = auth.uid()
        )
    );

-- Suppression : uploader ou admin
CREATE POLICY resources_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'resources'
        AND is_active_user()
        AND (
            is_admin()
            OR EXISTS (
                SELECT 1 FROM ressources r
                WHERE r.file_url LIKE '%' || name
                AND r.uploaded_by = auth.uid()
            )
        )
    );

-- =====================================================
-- 3. BUCKET JUSTIFICATIFS (Privé - Pièces justificatives)
-- =====================================================

-- Suppression préalable pour idempotence
DROP POLICY IF EXISTS justificatifs_select ON storage.objects;
DROP POLICY IF EXISTS justificatifs_insert ON storage.objects;
DROP POLICY IF EXISTS justificatifs_update ON storage.objects;
DROP POLICY IF EXISTS justificatifs_delete ON storage.objects;

-- Lecture : admin, prof concerné (via présence), ou étudiant propriétaire
CREATE POLICY justificatifs_select ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'justificatifs'
        AND is_active_user()
        AND (
            is_admin()
            OR EXISTS (
                -- Prof de la séance concernée
                SELECT 1 FROM justificatifs j
                JOIN presences p ON j.presence_id = p.id
                JOIN sessions ses ON p.session_id = ses.id
                JOIN seances sea ON ses.seance_id = sea.id
                WHERE j.file_url LIKE '%' || name
                AND sea.professor_id = auth.uid()
            )
            OR EXISTS (
                -- Étudiant propriétaire
                SELECT 1 FROM justificatifs j
                WHERE j.file_url LIKE '%' || name
                AND j.student_id = auth.uid()
            )
        )
    );

-- Upload : étudiant uniquement, pour ses propres justificatifs
CREATE POLICY justificatifs_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'justificatifs'
        AND is_active_user()
        AND is_student()
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Mise à jour : impossible (immutabilité des justificatifs)
CREATE POLICY justificatifs_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (false);

-- Suppression : impossible (conservation des preuves)
CREATE POLICY justificatifs_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (false);

-- =====================================================
-- 4. BUCKET ANNONCES (Privé - Fichiers attachés aux annonces)
-- =====================================================

-- Suppression préalable pour idempotence
DROP POLICY IF EXISTS annonces_storage_select ON storage.objects;
DROP POLICY IF EXISTS annonces_storage_insert ON storage.objects;
DROP POLICY IF EXISTS annonces_storage_update ON storage.objects;
DROP POLICY IF EXISTS annonces_storage_delete ON storage.objects;

-- Lecture : selon visibilité de l'annonce
CREATE POLICY annonces_storage_select ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'annonces'
        AND is_active_user()
        AND (
            is_admin()
            OR EXISTS (
                -- Annonce publique
                SELECT 1 FROM annonces a
                WHERE a.attachment_url LIKE '%' || name
                AND a.is_published = true
            )
            OR EXISTS (
                -- Annonce ciblée étudiants
                SELECT 1 FROM annonces a
                WHERE a.attachment_url LIKE '%' || name
                AND a.target_type = 'students'
                AND is_student()
            )
            OR EXISTS (
                -- Annonce ciblée profs
                SELECT 1 FROM annonces a
                WHERE a.attachment_url LIKE '%' || name
                AND a.target_type = 'professors'
                AND is_professor()
            )
            OR EXISTS (
                -- Annonce ciblée classe de l'étudiant
                SELECT 1 FROM annonces a
                JOIN student_classes sc ON a.target_id = sc.class_id
                WHERE a.attachment_url LIKE '%' || name
                AND a.target_type = 'classe'
                AND sc.student_id = auth.uid()
                AND sc.is_active = true
            )
            OR EXISTS (
                -- Annonce ciblée filière de l'étudiant
                SELECT 1 FROM annonces a
                JOIN classes c ON a.target_id = c.filiere_id
                JOIN student_classes sc ON c.id = sc.class_id
                WHERE a.attachment_url LIKE '%' || name
                AND a.target_type = 'filiere'
                AND sc.student_id = auth.uid()
                AND sc.is_active = true
            )
        )
    );

-- Upload : admin uniquement
CREATE POLICY annonces_storage_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'annonces'
        AND is_active_user()
        AND is_admin()
    );

-- Mise à jour : admin uniquement
CREATE POLICY annonces_storage_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'annonces'
        AND is_active_user()
        AND is_admin()
    )
    WITH CHECK (
        bucket_id = 'annonces'
        AND is_active_user()
        AND is_admin()
    );

-- Suppression : admin uniquement
CREATE POLICY annonces_storage_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'annonces'
        AND is_active_user()
        AND is_admin()
    );
