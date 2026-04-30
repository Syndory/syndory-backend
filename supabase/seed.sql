-- Seed data: Données initiales pour Syndory
-- Paramètres système et compte admin

-- =====================================================
-- 1. PARAMÈTRES SYSTÈME
-- =====================================================

INSERT INTO parametres (
    id,
    default_gps_tolerance,
    attendance_critical_threshold,
    default_marking_window,
    allowed_file_formats,
    max_file_size_mb,
    exam_reminder_hours
) VALUES (
    gen_random_uuid(),
    50,      -- 50 mètres de tolérance GPS
    70,      -- 70% seuil critique d'assiduité
    15,      -- 15 minutes fenêtre de marquage par défaut
    ARRAY['pdf', 'docx', 'pptx', 'jpg', 'png'],
    20,      -- 20 Mo max
    24       -- Rappel examen 24h avant
);

-- =====================================================
-- 2. FILIÈRE EXEMPLE (optionnel, à supprimer en prod)
-- =====================================================

-- INSERT INTO filieres (code, name, description) VALUES
-- ('INFO', 'Licence Informatique', 'Formation en développement et systèmes informatiques'),
-- ('MATH', 'Licence Mathématiques', 'Formation en mathématiques fondamentales et appliquées');

-- =====================================================
-- 3. SALLES EXEMPLE (avec coordonnées GPS fictives)
-- =====================================================

-- Note: Remplacer les coordonnées GPS par les vraies valeurs de l'établissement
-- INSERT INTO salles (name, building, floor, capacity, gps_latitude, gps_longitude, tolerance_radius) VALUES
-- ('A101', 'Bâtiment A', '1', 50, 6.3650, 2.4183, 50),
-- ('A102', 'Bâtiment A', '1', 40, 6.3652, 2.4185, 50),
-- ('B201', 'Bâtiment B', '2', 60, 6.3645, 2.4190, 75);

-- =====================================================
-- 4. ADMIN USER (à créer manuellement via Supabase Auth UI ou API)
-- =====================================================
-- 
-- Pour créer l'admin, utilisez la console Supabase ou l'API:
-- 
-- 1. Via Supabase Dashboard:
--    - Authentication > Users > Add User
--    - Email: admin@syndory.com
--    - Password: [mot de passe fort]
--    - Mettre à jour le rôle dans la table users:
--      UPDATE users SET role = 'admin' WHERE email = 'admin@syndory.com';
--
-- 2. Via API:
--    POST /auth/v1/signup
--    {
--      "email": "admin@syndory.com",
--      "password": "[password]",
--      "data": {
--        "first_name": "Admin",
--        "last_name": "Syndory",
--        "role": "admin"
--      }
--    }

-- =====================================================
-- 5. SEMESTRE ACTIF (optionnel)
-- =====================================================

-- INSERT INTO semestres (name, start_date, end_date, is_active) VALUES
-- ('Semestre 1 - 2025-2026', '2025-10-01', '2026-01-31', true),
-- ('Semestre 2 - 2025-2026', '2026-02-01', '2026-06-30', false);
