# Documentation Base de données (Supabase / PostgreSQL)

Ce document décrit la base de données du projet **Syndory** : structure, relations, sécurité (RLS), fonctions et triggers.

## 1) Vue d’ensemble

La base de données est organisée autour de 4 domaines :

- **Référentiels académiques** : filières, classes, matières, salles.
- **Emploi du temps** : séances.
- **Présences** : sessions de présence, présences, justificatifs.
- **Pédagogie & communication** : programmes, progressions, ressources, annonces, notifications.

## 2) Enums (types)

Ces enums sont définis dans `001_initial_schema.sql`.

- `user_role` : `student`, `class_representative`, `professor`, `admin`
- `seance_type` : `cours`, `td`, `tp`, `examen`
- `seance_status` : `brouillon`, `publié`, `annulé`
- `session_status` : `ouverte`, `fermée`
- `presence_status` : `present`, `absent`, `late`, `justified`
- `justification_status` : `en_attente`, `validé`, `rejeté`
- `resource_file_type` : `pdf`, `docx`, `pptx`, `image`, `link`, `other`
- `resource_type` : `cours`, `td`, `tp`, `corrige`, `note`, `exercice`, `autre`
- `annonce_target_type` : `all`, `filiere`, `classe`, `professors`, `students`
- `notification_type` : `session_opened`, `new_resource`, `schedule_update`, `justification_status`, `announcement`, `exam_reminder`, `session_cancelled`
- `log_action_type` : journalisation des actions critiques
- `progression_updater_role` : `professor`, `class_representative`
- `resource_uploader_role` : `professor`, `class_representative`, `admin`
- `presence_marker` : `student`, `professor_correction`

## 3) Tables (structure et relations)

### 3.1 `users`

Extension de `auth.users` (1 ligne applicative par compte Supabase).

- **Colonnes clés**
  - `id` (PK) : référence `auth.users(id)`
  - `email` (unique)
  - `first_name`, `last_name`
  - `role` (`user_role`)
  - `fcm_token` : token push de l’utilisateur (legacy FCM)
  - `is_active` (bool) : permet de désactiver globalement l’accès.

- **Règles**
  - Le trigger `handle_new_user()` crée automatiquement le profil lors de l’inscription.

### 3.2 Référentiels

- `filieres`
  - `code` unique, `name`

- `classes`
  - `filiere_id` -> `filieres.id`
  - `class_representative_id` -> `users.id` (nullable)

- `matieres`
  - `filiere_id` -> `filieres.id`
  - `code` unique

- `salles`
  - GPS : `gps_latitude`, `gps_longitude`
  - `tolerance_radius` : rayon (mètres)

### 3.3 Affectations

- `professeur_matieres`
  - associe un professeur à une matière et une classe
  - contrainte unique : `(professor_id, matiere_id, class_id)`

- `student_classes`
  - associe un étudiant à une classe (et une année)
  - contrainte unique : `(student_id, class_id, academic_year)`
  - **extension** : `is_active` (ajoutée par migrations) pour ne garder qu’une affectation active.

### 3.4 Emploi du temps

- `semestres`
  - périodes, `is_active`

- `seances`
  - FKs : `matiere_id`, `professor_id`, `class_id`, `salle_id`
  - `date`, `start_time`, `end_time`
  - `status` (`brouillon` / `publié` / `annulé`)
  - `is_exam`

### 3.5 Présences

- `sessions`
  - FK : `seance_id`
  - `opened_at`, `closed_at`
  - `marking_window_duration` (minutes)
  - `professor_gps_lat/long`

- `presences`
  - FK : `session_id`, `student_id`
  - `status` (par défaut `absent`)
  - `marked_at` + GPS étudiant
  - `marked_by` (`student` ou `professor_correction`)
  - contrainte unique : `(session_id, student_id)`

- `justificatifs`
  - FK : `presence_id`, `student_id`
  - `file_url` (lien du fichier)
  - `status` : `en_attente` / `validé` / `rejeté`

### 3.6 Pédagogie & communication

- `programmes`
  - `chapters` (JSON)
  - unique : `(matiere_id, class_id)`

- `progressions`
  - FK : `seance_id`, `updated_by`
  - `chapters_covered` (JSON)
  - `is_validated` : une fois validée, la progression est verrouillée.

- `ressources`
  - `file_url`
  - FK : `matiere_id`, `class_id`, `uploaded_by`

- `annonces`
  - ciblage : `target_type` + `target_id`
  - `attachment_url` (optionnel)
  - publication immédiate ou programmée via `scheduled_at`

- `notifications`
  - FK : `user_id`
  - `type`, `title`, `message`, `data` (JSON)
  - `is_read`

- `logs_activite`
  - journal d’audit (actions critiques)

- `parametres`
  - paramètres globaux (tolérance GPS, seuils, etc.)

- `vacances_examens`
  - périodes de vacances / examens

## 4) Indexes

Les principaux indexes sont créés dans `001_initial_schema.sql` (ex : `idx_seances_date`, `idx_presences_student`, etc.) pour accélérer les requêtes courantes.

## 5) Sécurité : RLS (Row Level Security)

Les règles RLS sont définies dans `002_rls_policies.sql`.

### 5.1 Principes

- Toutes les tables applicatives ont **RLS activée**.
- Les accès sont contrôlés via des fonctions utilitaires (ex : `is_admin()`, `is_professor()`…).
- La désactivation d’un compte (`users.is_active = false`) bloque globalement l’accès grâce à `is_active_user()`.

### 5.2 Fonctions utilitaires importantes

- `is_active_user()` : vrai si l’utilisateur connecté existe et est actif.
- `get_current_user_role()` : rôle de l’utilisateur connecté (retourne `NULL` si inactif).
- `is_admin()`, `is_professor()`, `is_student()`, `is_class_representative()`.
- `get_student_class_id()` : classe active de l’étudiant.
- `professor_teaches_class(class_uuid)` : contrôle d’accès côté prof.

### 5.3 Résumé des règles

- **Étudiant**
  - voit ses données, sa classe, ses présences, ses justificatifs.
  - peut marquer sa présence (dans la fenêtre autorisée).

- **Responsable de classe** (`class_representative`)
  - mêmes droits qu’un étudiant
  - droits supplémentaires sur la consultation (selon les policies).

- **Professeur**
  - accès aux données de ses séances / classes
  - peut ouvrir / fermer des sessions
  - peut corriger certaines présences (si prévu dans les policies)

- **Admin**
  - accès large sur les référentiels
  - restrictions spécifiques appliquées sur certains objets métier (ex : règles strictes sur progressions / justificatifs selon CDC).

## 6) Fonctions & Triggers (logique métier)

La majorité est dans `003_functions_triggers.sql` et `005_automatic_notifications.sql`.

### 6.1 Création automatique du profil

- **Trigger** `on_auth_user_created` sur `auth.users`
- **Fonction** `handle_new_user()`

### 6.2 Mise à jour automatique `updated_at`

- Fonction `update_updated_at_column()`
- Triggers `update_*_updated_at` (users, seances, programmes, presences, progressions, parametres)

### 6.3 GPS et présence

- `calculate_distance()` : Haversine
- `is_within_salle_radius()` : vérifie si la position est dans le rayon de la salle
- `mark_presence()` : logique serveur du marquage (fenêtre de marquage + GPS + statut)

### 6.4 Sessions

- `close_session()` : clôture et marque les absents
- `create_initial_presences()` + trigger `on_session_opened` : pré-crée les lignes de présence

### 6.5 Emploi du temps

- `check_schedule_conflicts()` : détecte conflits de salle / professeur / classe

### 6.6 Notifications automatiques

Dans `005_automatic_notifications.sql` :

- triggers pour notifier sur :
  - publication/modification de séances
  - ajout de ressource
  - changement de statut de justificatif
- `send_exam_reminders()` : envoie des rappels d’examens (appel à planifier par scheduler externe)

### 6.7 Validation atomique des justificatifs

- `validate_justification(...)` : valide/rejette un justificatif et met à jour la présence associée dans une transaction unique.

### 6.8 Push notifications

- `create_notification(...)` déclenche un appel HTTP via `pg_net` vers l’Edge Function `send-push`.
- L’Edge Function `send-push` envoie la notification via FCM legacy.

## 7) Storage (buckets + policies)

Les policies Storage sont définies dans `006_storage_policies.sql`.

Buckets attendus :

- `avatars` (public)
- `resources` (privé)
- `justificatifs` (privé)
- `annonces` (privé)

Les policies lient un objet Storage à une ligne applicative via `file_url` / `attachment_url`.

## 8) Migrations

Ordre principal :

- `001_initial_schema.sql` : schéma
- `002_rls_policies.sql` : sécurité
- `003_functions_triggers.sql` : logique + triggers
- `004_constraints_and_cron.sql` : contrainte “classe active” (implémentée via trigger + index partiel)
- `005_automatic_notifications.sql` : notifications automatiques + rappels examens (scheduler externe)
- `006_storage_policies.sql` : policies storage
- `007_fix_active_filters.sql` : filtres `is_active` pour les présences et notifications
- `008_add_fcm_token.sql` : ajout de `users.fcm_token`
- `009_fcm_trigger.sql` : trigger `pg_net` pour pousser via `send-push`
- `010_validate_justification.sql` : validation atomique justificatif + présence
