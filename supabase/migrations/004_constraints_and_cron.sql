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
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'student_classes_one_active_per_student'
  ) THEN
    ALTER TABLE student_classes
    ADD CONSTRAINT student_classes_one_active_per_student
    EXCLUDE USING gist (student_id WITH =)
    WHERE (is_active);
  END IF;
END $$;

-- =====================================================
-- 2. CRON JOBS (pg_cron)
-- =====================================================

DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    -- pg_cron peut ne pas être disponible selon l'environnement Supabase
    RETURN;
  END;

  -- Fermer les sessions expirées: toutes les minutes
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'close_expired_sessions_job') THEN
    PERFORM cron.schedule(
      'close_expired_sessions_job',
      '* * * * *',
      $$SELECT close_expired_sessions();$$
    );
  END IF;

  -- Publier les annonces programmées: toutes les minutes
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'publish_scheduled_annonces_job') THEN
    PERFORM cron.schedule(
      'publish_scheduled_annonces_job',
      '* * * * *',
      $$SELECT publish_scheduled_annonces();$$
    );
  END IF;
END $$;
