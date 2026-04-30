-- Migration 001: Schéma initial complet Syndory
-- Création des tables, enums, indexes et foreign keys

-- =====================================================
-- 1. ENUMS
-- =====================================================

CREATE TYPE user_role AS ENUM ('student', 'class_representative', 'professor', 'admin');
CREATE TYPE seance_type AS ENUM ('cours', 'td', 'tp', 'examen');
CREATE TYPE seance_status AS ENUM ('brouillon', 'publié', 'annulé');
CREATE TYPE session_status AS ENUM ('ouverte', 'fermée');
CREATE TYPE presence_status AS ENUM ('present', 'absent', 'late', 'justified');
CREATE TYPE justification_status AS ENUM ('en_attente', 'validé', 'rejeté');
CREATE TYPE resource_file_type AS ENUM ('pdf', 'docx', 'pptx', 'image', 'link', 'other');
CREATE TYPE resource_type AS ENUM ('cours', 'td', 'tp', 'corrige', 'note', 'exercice', 'autre');
CREATE TYPE annonce_target_type AS ENUM ('all', 'filiere', 'classe', 'professors', 'students');
CREATE TYPE notification_type AS ENUM ('session_opened', 'new_resource', 'schedule_update', 'justification_status', 'announcement', 'exam_reminder', 'session_cancelled');
CREATE TYPE log_action_type AS ENUM ('user_created', 'user_updated', 'user_disabled', 'schedule_published', 'session_opened', 'session_closed', 'justification_validated', 'justification_rejected', 'structure_deleted', 'announcement_published');
CREATE TYPE progression_updater_role AS ENUM ('professor', 'class_representative');
CREATE TYPE resource_uploader_role AS ENUM ('professor', 'class_representative', 'admin');
CREATE TYPE presence_marker AS ENUM ('student', 'professor_correction');

-- =====================================================
-- 2. TABLES
-- =====================================================

-- Table users (extension de auth.users)
CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    phone TEXT,
    avatar_url TEXT,
    role user_role NOT NULL DEFAULT 'student',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table filières
CREATE TABLE filieres (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table classes
CREATE TABLE classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    filiere_id UUID NOT NULL REFERENCES filieres(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    promotion TEXT,
    capacity_max INTEGER,
    class_representative_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table matières
CREATE TABLE matieres (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    filiere_id UUID NOT NULL REFERENCES filieres(id) ON DELETE RESTRICT,
    coefficient INTEGER DEFAULT 1,
    credits INTEGER DEFAULT 3,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table salles
CREATE TABLE salles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    building TEXT NOT NULL,
    floor TEXT,
    capacity INTEGER,
    equipments JSONB DEFAULT '[]',
    gps_latitude DECIMAL(10, 8),
    gps_longitude DECIMAL(11, 8),
    tolerance_radius INTEGER DEFAULT 50, -- en mètres
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table professeur_matières (affectation prof-matière-classe)
CREATE TABLE professeur_matieres (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    matiere_id UUID NOT NULL REFERENCES matieres(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(professor_id, matiere_id, class_id)
);

-- Table student_classes
CREATE TABLE student_classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    academic_year TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(student_id, class_id, academic_year)
);

-- Table semestres
CREATE TABLE semestres (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table seances (emploi du temps)
CREATE TABLE seances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    matiere_id UUID NOT NULL REFERENCES matieres(id) ON DELETE RESTRICT,
    professor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    class_id UUID NOT NULL REFERENCES classes(id) ON DELETE RESTRICT,
    salle_id UUID NOT NULL REFERENCES salles(id) ON DELETE RESTRICT,
    date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    type seance_type NOT NULL DEFAULT 'cours',
    status seance_status NOT NULL DEFAULT 'brouillon',
    is_exam BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table programmes (cahier de texte)
CREATE TABLE programmes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    matiere_id UUID NOT NULL REFERENCES matieres(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    chapters JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(matiere_id, class_id)
);

-- Table sessions (sessions de présence)
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seance_id UUID NOT NULL REFERENCES seances(id) ON DELETE CASCADE,
    professor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    marking_window_duration INTEGER NOT NULL DEFAULT 15, -- en minutes
    status session_status NOT NULL DEFAULT 'ouverte',
    professor_gps_lat DECIMAL(10, 8),
    professor_gps_long DECIMAL(11, 8),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table présences
CREATE TABLE presences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status presence_status NOT NULL DEFAULT 'absent',
    marked_at TIMESTAMPTZ,
    student_gps_lat DECIMAL(10, 8),
    student_gps_long DECIMAL(11, 8),
    marked_by presence_marker NOT NULL DEFAULT 'student',
    correction_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(session_id, student_id)
);

-- Table justificatifs
CREATE TABLE justificatifs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    presence_id UUID NOT NULL REFERENCES presences(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    reason TEXT,
    status justification_status NOT NULL DEFAULT 'en_attente',
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table progressions
CREATE TABLE progressions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seance_id UUID NOT NULL REFERENCES seances(id) ON DELETE CASCADE,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    chapters_covered JSONB NOT NULL DEFAULT '[]',
    updated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    updated_by_role progression_updater_role NOT NULL,
    is_validated BOOLEAN NOT NULL DEFAULT false,
    validated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(seance_id)
);

-- Table ressources
CREATE TABLE ressources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_type resource_file_type NOT NULL,
    resource_type resource_type NOT NULL DEFAULT 'cours',
    matiere_id UUID NOT NULL REFERENCES matieres(id) ON DELETE CASCADE,
    class_id UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    uploaded_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    uploaded_by_role resource_uploader_role NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table annonces
CREATE TABLE annonces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    target_type annonce_target_type NOT NULL DEFAULT 'all',
    target_id UUID, -- peut être filiere_id ou class_id selon target_type
    attachment_url TEXT,
    published_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    published_at TIMESTAMPTZ,
    scheduled_at TIMESTAMPTZ,
    is_published BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type notification_type NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table logs_activité
CREATE TABLE logs_activite (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action_type log_action_type NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    details JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table paramètres
CREATE TABLE parametres (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    default_gps_tolerance INTEGER NOT NULL DEFAULT 50, -- mètres
    attendance_critical_threshold INTEGER NOT NULL DEFAULT 70, -- %
    default_marking_window INTEGER NOT NULL DEFAULT 15, -- minutes
    allowed_file_formats TEXT[] NOT NULL DEFAULT ARRAY['pdf', 'docx', 'pptx', 'jpg', 'png'],
    max_file_size_mb INTEGER NOT NULL DEFAULT 20,
    exam_reminder_hours INTEGER NOT NULL DEFAULT 24,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table vacances_examens
CREATE TABLE vacances_examens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL CHECK (type IN ('vacances', 'examens')),
    name TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================
-- 3. INDEXES
-- =====================================================

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_classes_filiere ON classes(filiere_id);
CREATE INDEX idx_matieres_filiere ON matieres(filiere_id);
CREATE INDEX idx_prof_mat_prof ON professeur_matieres(professor_id);
CREATE INDEX idx_prof_mat_matiere ON professeur_matieres(matiere_id);
CREATE INDEX idx_prof_mat_class ON professeur_matieres(class_id);
CREATE INDEX idx_student_class_student ON student_classes(student_id);
CREATE INDEX idx_student_class_class ON student_classes(class_id);
CREATE INDEX idx_seances_professor ON seances(professor_id);
CREATE INDEX idx_seances_class ON seances(class_id);
CREATE INDEX idx_seances_salle ON seances(salle_id);
CREATE INDEX idx_seances_date ON seances(date);
CREATE INDEX idx_seances_matiere ON seances(matiere_id);
CREATE INDEX idx_sessions_seance ON sessions(seance_id);
CREATE INDEX idx_sessions_professor ON sessions(professor_id);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_presences_session ON presences(session_id);
CREATE INDEX idx_presences_student ON presences(student_id);
CREATE INDEX idx_presences_status ON presences(status);
CREATE INDEX idx_justificatifs_presence ON justificatifs(presence_id);
CREATE INDEX idx_justificatifs_student ON justificatifs(student_id);
CREATE INDEX idx_justificatifs_status ON justificatifs(status);
CREATE INDEX idx_progressions_seance ON progressions(seance_id);
CREATE INDEX idx_ressources_matiere ON ressources(matiere_id);
CREATE INDEX idx_ressources_class ON ressources(class_id);
CREATE INDEX idx_annonces_target ON annonces(target_type, target_id);
CREATE INDEX idx_annonces_published ON annonces(is_published, published_at);
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_read ON notifications(is_read);
CREATE INDEX idx_logs_user ON logs_activite(user_id);
CREATE INDEX idx_logs_action ON logs_activite(action_type);
CREATE INDEX idx_logs_created ON logs_activite(created_at);

-- =====================================================
-- 4. COMMENTS
-- =====================================================

COMMENT ON TABLE users IS 'Extension des profils auth.users avec rôles et métadonnées';
COMMENT ON TABLE seances IS 'Emploi du temps - séances de cours programmées';
COMMENT ON TABLE sessions IS 'Sessions de présence géolocalisées ouvertes par les profs';
COMMENT ON TABLE presences IS 'Marquage de présence des étudiants';
COMMENT ON TABLE justificatifs IS 'Justificatifs d''absence soumis par les étudiants';
COMMENT ON TABLE progressions IS 'Suivi de progression pédagogique par séance';
COMMENT ON TABLE programmes IS 'Programmes/cahiers de texte par matière et classe';
COMMENT ON TABLE ressources IS 'Documents pédagogiques partagés';
COMMENT ON TABLE logs_activite IS 'Journal d''audit des actions critiques';
