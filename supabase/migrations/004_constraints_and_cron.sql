-- Migration 004: Contraintes & Cron Jobs
-- 1) Empêcher un étudiant d'être affecté à plusieurs classes en même temps
-- 2) Programmer les jobs de maintenance (fermeture de sessions expirées, publication d'annonces)

-- =====================================================
-- 1. STUDENT_CLASSES: une seule classe active par étudiant
-- =====================================================

ALTER TABLE student_classes
ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- Désactiver toutes les anciennes affectations lors d'une nouvelle affectation active
CREATE OR REPLACE FUNCTION enforce_single_active_class_per_student()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_active THEN
    UPDATE student_classes
    SET is_active = false
    WHERE student_id = NEW.student_id
      AND id <> NEW.id
      AND is_active = true;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_single_active_class_per_student ON student_classes;
CREATE TRIGGER trg_enforce_single_active_class_per_student
AFTER INSERT OR UPDATE OF is_active ON student_classes
FOR EACH ROW
EXECUTE FUNCTION enforce_single_active_class_per_student();

-- Unicité: au plus une affectation active par étudiant
-- NOTE: Utilisation d'un index partiel + trigger au lieu de EXCLUDE (qui nécessite btree_gist sur Supabase)
DO $$
BEGIN
  -- Créer un index partiel unique pour les affectations actives
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE indexname = 'idx_student_classes_one_active'
  ) THEN
    CREATE UNIQUE INDEX idx_student_classes_one_active 
    ON student_classes (student_id) 
    WHERE (is_active = true);
  END IF;
END $$;

-- =====================================================
-- 2. CRON JOBS (pg_cron)
-- =====================================================
-- NOTE: pg_cron n'est généralement pas disponible dans l'environnement Supabase hébergé.
-- Les jobs suivants doivent être configurés manuellement via le dashboard Supabase
-- ou via une Edge Function externe avec un scheduler.
--
-- Jobs recommandés:
-- 1. Fermer les sessions expirées: toutes les minutes
--    - Appeler la fonction: SELECT close_expired_sessions();
-- 2. Publier les annonces programmées: toutes les minutes
--    - Appeler la fonction: SELECT publish_scheduled_annonces();
--
-- Alternative: Utiliser une Edge Function avec un cron externe (GitHub Actions, etc.)
