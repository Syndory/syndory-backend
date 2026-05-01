-- Migration 005: Notifications automatiques + Rappels examens
-- Garantit la conformité au cahier des charges sans dépendre des clients.

-- =====================================================
-- 1. Helper: notifier le professeur d'une séance
-- =====================================================

CREATE OR REPLACE FUNCTION notify_professor_for_seance(
  p_seance_id UUID,
  p_type notification_type,
  p_title TEXT,
  p_message TEXT,
  p_data JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
  v_professor_id UUID;
  v_notif_id UUID;
BEGIN
  SELECT professor_id INTO v_professor_id
  FROM seances
  WHERE id = p_seance_id;

  IF v_professor_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_notif_id := create_notification(v_professor_id, p_type, p_title, p_message, p_data);
  RETURN v_notif_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Notifier uniquement les étudiants avec une affectation active
CREATE OR REPLACE FUNCTION notify_class_active(
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

-- =====================================================
-- 2. EDT: notifier sur publication / modification / annulation
-- =====================================================

CREATE OR REPLACE FUNCTION trigger_notify_seance_changes()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_message TEXT;
  v_payload JSONB;
BEGIN
  -- Construire payload minimal
  v_payload := jsonb_build_object(
    'seance_id', NEW.id,
    'class_id', NEW.class_id,
    'matiere_id', NEW.matiere_id,
    'professor_id', NEW.professor_id,
    'date', NEW.date,
    'start_time', NEW.start_time,
    'end_time', NEW.end_time,
    'salle_id', NEW.salle_id
  );

  -- Publication (brouillon -> publié) ou insertion déjà publiée
  IF (TG_OP = 'INSERT' AND NEW.status = 'publié')
     OR (TG_OP = 'UPDATE' AND OLD.status <> 'publié' AND NEW.status = 'publié') THEN
    v_title := 'Emploi du temps publié';
    v_message := 'Une séance a été publiée dans votre emploi du temps.';

    PERFORM notify_class_active(NEW.class_id, 'schedule_update', v_title, v_message, v_payload);
    PERFORM notify_professor_for_seance(NEW.id, 'schedule_update', v_title, v_message, v_payload);

    RETURN NEW;
  END IF;

  -- Annulation
  IF TG_OP = 'UPDATE' AND OLD.status <> 'annulé' AND NEW.status = 'annulé' THEN
    v_title := 'Séance annulée';
    v_message := 'Une séance de votre emploi du temps a été annulée.';

    PERFORM notify_class_active(NEW.class_id, 'session_cancelled', v_title, v_message, v_payload);
    PERFORM notify_professor_for_seance(NEW.id, 'session_cancelled', v_title, v_message, v_payload);

    RETURN NEW;
  END IF;

  -- Modification d'une séance déjà publiée (changement date/heure/salle/prof)
  IF TG_OP = 'UPDATE' AND OLD.status = 'publié' AND NEW.status = 'publié' THEN
    IF (NEW.date IS DISTINCT FROM OLD.date)
      OR (NEW.start_time IS DISTINCT FROM OLD.start_time)
      OR (NEW.end_time IS DISTINCT FROM OLD.end_time)
      OR (NEW.salle_id IS DISTINCT FROM OLD.salle_id)
      OR (NEW.professor_id IS DISTINCT FROM OLD.professor_id)
      OR (NEW.matiere_id IS DISTINCT FROM OLD.matiere_id)
      OR (NEW.class_id IS DISTINCT FROM OLD.class_id)
    THEN
      v_title := 'Emploi du temps modifié';
      v_message := 'Une séance publiée a été modifiée.';

      PERFORM notify_class_active(NEW.class_id, 'schedule_update', v_title, v_message, v_payload);
      PERFORM notify_professor_for_seance(NEW.id, 'schedule_update', v_title, v_message, v_payload);
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_seance_changes ON seances;
CREATE TRIGGER trg_notify_seance_changes
AFTER INSERT OR UPDATE ON seances
FOR EACH ROW
EXECUTE FUNCTION trigger_notify_seance_changes();

-- =====================================================
-- 3. Ressources: notifier la classe à l'upload
-- =====================================================

CREATE OR REPLACE FUNCTION trigger_notify_new_resource()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_message TEXT;
  v_payload JSONB;
BEGIN
  v_title := 'Nouvelle ressource';
  v_message := 'Une nouvelle ressource pédagogique a été ajoutée.';
  v_payload := jsonb_build_object(
    'resource_id', NEW.id,
    'class_id', NEW.class_id,
    'matiere_id', NEW.matiere_id,
    'uploaded_by', NEW.uploaded_by,
    'resource_type', NEW.resource_type,
    'title', NEW.title
  );

  PERFORM notify_class_active(NEW.class_id, 'new_resource', v_title, v_message, v_payload);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_new_resource ON ressources;
CREATE TRIGGER trg_notify_new_resource
AFTER INSERT ON ressources
FOR EACH ROW
EXECUTE FUNCTION trigger_notify_new_resource();

-- =====================================================
-- 4. Justificatifs: notifier l'étudiant sur validation/rejet
-- =====================================================

CREATE OR REPLACE FUNCTION trigger_notify_justification_status()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_message TEXT;
  v_payload JSONB;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_payload := jsonb_build_object(
      'justificatif_id', NEW.id,
      'presence_id', NEW.presence_id,
      'status', NEW.status
    );

    v_title := 'Statut du justificatif';
    IF NEW.status = 'validé' THEN
      v_message := 'Votre justificatif a été validé.';
    ELSIF NEW.status = 'rejeté' THEN
      v_message := 'Votre justificatif a été rejeté.';
    ELSE
      v_message := 'Le statut de votre justificatif a été mis à jour.';
    END IF;

    PERFORM create_notification(NEW.student_id, 'justification_status', v_title, v_message, v_payload);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_justification_status ON justificatifs;
CREATE TRIGGER trg_notify_justification_status
AFTER UPDATE OF status ON justificatifs
FOR EACH ROW
EXECUTE FUNCTION trigger_notify_justification_status();

-- =====================================================
-- 5. Rappels examens J-1 (source = seances.is_exam = true)
-- =====================================================

CREATE TABLE IF NOT EXISTS exam_reminders_sent (
  seance_id UUID PRIMARY KEY REFERENCES seances(id) ON DELETE CASCADE,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE exam_reminders_sent ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS exam_reminders_sent_admin ON exam_reminders_sent;
CREATE POLICY exam_reminders_sent_admin ON exam_reminders_sent
  FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

CREATE OR REPLACE FUNCTION send_exam_reminders()
RETURNS INTEGER AS $$
DECLARE
  v_hours INTEGER;
  v_count INTEGER := 0;
  v_row RECORD;
  v_title TEXT;
  v_message TEXT;
  v_payload JSONB;
BEGIN
  SELECT exam_reminder_hours INTO v_hours
  FROM parametres
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_hours IS NULL THEN
    v_hours := 24;
  END IF;

  FOR v_row IN
    SELECT s.*
    FROM seances s
    WHERE s.is_exam = true
      AND s.status = 'publié'
      AND ((s.date + s.start_time) AT TIME ZONE 'Africa/Porto-Novo') >= NOW()
      AND ((s.date + s.start_time) AT TIME ZONE 'Africa/Porto-Novo') <= NOW() + (v_hours || ' hours')::INTERVAL
      AND NOT EXISTS (
        SELECT 1 FROM exam_reminders_sent ers WHERE ers.seance_id = s.id
      )
  LOOP
    v_title := 'Rappel examen';
    v_message := 'Un examen est prévu bientôt. Consultez votre emploi du temps.';
    v_payload := jsonb_build_object(
      'seance_id', v_row.id,
      'class_id', v_row.class_id,
      'matiere_id', v_row.matiere_id,
      'date', v_row.date,
      'start_time', v_row.start_time,
      'end_time', v_row.end_time,
      'salle_id', v_row.salle_id
    );

    PERFORM notify_class_active(v_row.class_id, 'exam_reminder', v_title, v_message, v_payload);
    INSERT INTO exam_reminders_sent(seance_id) VALUES (v_row.id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- NOTE: pg_cron n'est généralement pas disponible dans l'environnement Supabase hébergé.
-- Ce job doit être configuré manuellement via le dashboard Supabase
-- ou via une Edge Function externe avec un scheduler.
--
-- Job recommandé:
-- - Toutes les 5 minutes: SELECT send_exam_reminders();
