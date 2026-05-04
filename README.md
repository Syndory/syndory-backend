# Syndory Backend (Supabase)

Ce dépôt contient le **backend Supabase** du projet **Syndory** (PostgreSQL + RLS + Edge Functions + Storage).

Ce `README` est une **documentation d’intégration destinée aux équipes frontend** (Flutter Étudiants / Flutter Professeurs / React Admin) qui consomment le backend.

Objectifs :

- **Permettre d’implémenter tous les écrans** du cahier des charges et des spécifications UI/UX.
- **Ne rien inventer** : tout ce qui est décrit ici correspond au schéma SQL, aux RLS policies et aux Edge Functions présentes dans ce dépôt.
- Donner des **patterns CRUD** clairs (PostgREST + Edge Functions) et des **règles d’accès** (RLS) compréhensibles même si vous débutez avec Supabase.

Liens de référence (docs techniques détaillées) :

- Base de données (tables, RLS, fonctions, triggers, storage) : `docs/database.md`
- Edge Functions (endpoints, logique, exemples) : `docs/edge-functions.md`
- Setup production (FCM + pg_net + scheduler) : `docs/setup-production.md`

## Structure du projet

```
docs/
supabase/
  config.toml
  migrations/
  functions/
  seed.sql
```

## Public visé (ce que vous devez savoir)

Ce backend sert 3 clients :

- **App Étudiants (Flutter)** : planning, marquage présence GPS, ressources, assiduité, annonces, justificatifs.
- **App Professeurs (Flutter)** : ouverture/clôture de sessions, gestion présences, progression, ressources, justificatifs.
- **Web Admin (React)** : CRUD structures, salles, EDT, utilisateurs, annonces, rapports, paramètres.

Le backend distingue 4 rôles applicatifs :

- `student`
- `class_representative` (responsable)
- `professor`
- `admin`

Ces rôles sont stockés dans `public.users.role` et sont utilisés dans les RLS policies.

## Prérequis

- Compte Supabase + un projet créé
- Supabase CLI installé
- Connexion : `supabase login`

## Intégration côté frontend (essentiel)

### 1) Configuration Supabase Client

Dans vos apps (Flutter / React), vous utilisez :

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Le **service role key** ne doit jamais être utilisé côté frontend (il bypass RLS).

### 2) Authentification (Supabase Auth)

Important : même si les documents UI/UX parlent d’un `POST /auth/login`, l’implémentation réelle du projet est basée sur **Supabase Auth**.

Pattern :

- Login : `supabase.auth.signInWithPassword({ email, password })`
- Récupérer l’utilisateur : `supabase.auth.getUser()`
- Logout : `supabase.auth.signOut()`

Après login, vous avez un JWT (access token). Supabase l’envoie automatiquement sur :

- les requêtes PostgREST (CRUD tables/views)
- les appels Edge Functions (si vous utilisez le même client)

### 3) Profil applicatif (`public.users`)

À la création d’un compte Supabase, un trigger crée une ligne dans `public.users`.

- **Source de vérité “métier”** : `public.users` (role, is_active, etc.)
- **Source de vérité “Auth”** : `auth.users`

Un compte désactivé (`users.is_active=false`) est bloqué globalement par les RLS (`is_active_user()`).

## Déploiement (recommandé)

### 1) Lier le projet

```bash
supabase link --project-ref <project-ref>
```

### 2) Déployer la base de données

```bash
supabase db push
```

### 3) Déployer les Edge Functions

Déploiement fonction par fonction (conseillé si réseau instable / rate-limit) :

```bash
supabase functions deploy check-conflicts
supabase functions deploy open-session
supabase functions deploy mark-presence
supabase functions deploy close-session
supabase functions deploy send-notification
supabase functions deploy update-progression
supabase functions deploy publish-seances
supabase functions deploy submit-justification
supabase functions deploy review-justification
supabase functions deploy generate-report
supabase functions deploy validate-progression
supabase functions deploy update-fcm-token
supabase functions deploy send-push
supabase functions deploy cron-close-sessions
```

## Identifiants de test (données de dev)

Ces identifiants sont créés par le script `./scripts/populate-supabase.sh` (source de vérité : `scripts/populate-supabase.sh` et `scripts/README.md`).

| Rôle                                 | Email(s)                                         | Mot de passe  |
| ------------------------------------ | ------------------------------------------------ | ------------- |
| Admin                                | `admin@syndory.com`                              | `admin123`    |
| Professeur                           | `prof1@syndory.com` → `prof5@syndory.com`        | `prof123`     |
| Responsable (`class_representative`) | `delegate1@syndory.com`, `delegate2@syndory.com` | `delegate123` |
| Étudiant                             | `student1@syndory.com` → `student10@syndory.com` | `student123`  |

## Modèle de données (carte mentale)

Les fonctionnalités du CDC/UI-UX se mappent aux blocs suivants :

- **Structures** : `filieres`, `classes`, `matieres`, `semestres`, `vacances_examens`
- **Salles (GPS)** : `salles`
- **EDT** : `seances` (brouillon / publié / annulé)
- **Présence** : `sessions` (ouverte/fermée) + `presences` (par étudiant)
- **Justificatifs** : `justificatifs` (workflow étudiant -> prof)
- **Progression** : `programmes` (référentiel) + `progressions` (par séance)
- **Ressources** : `ressources` (métadonnées) + Storage buckets (fichiers)
- **Communication** : `annonces`, `notifications`
- **Audit** : `logs_activite`
- **Paramètres** : `parametres`

Pour la description détaillée des tables + enums : `docs/database.md`.

## RLS (comment raisonner quand un CRUD “ne marche pas”)

Ce backend est construit sur un principe simple :

- Côté frontend, vous utilisez **uniquement la anon key**.
- Les droits sont appliqués par les **RLS policies** (PostgreSQL).
- Certaines actions “métier” passent par une **Edge Function** qui applique ses propres contrôles, puis écrit en admin si nécessaire.

Conséquence pratique :

- Si vous faites un `insert/update/delete` direct sur une table et que ça échoue en `401/403`, ce n’est pas “un bug frontend” : c’est souvent que **l’action n’est pas autorisée en PostgREST** et doit passer par **une Edge Function**.

Les règles exactes sont dans `supabase/migrations/002_rls_policies.sql` et résumées dans `docs/database.md`.

## Matrice d’accès RLS (source de vérité : `002_rls_policies.sql`)

Cette section répond exactement à :

- qui peut faire `SELECT / INSERT / UPDATE / DELETE` par table
- et donc quelles opérations peuvent _techniquement_ passer par PostgREST

Rappel : toutes les policies exigent implicitement `is_active_user()` (utilisateur authentifié + actif), sauf mention contraire.

### Tables référentielles

#### `filieres`

- **SELECT**
  - Tous les utilisateurs authentifiés actifs
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `classes`

- **SELECT**
  - `admin`
  - `professor` si affecté à la classe via `professeur_matieres`
  - `student` / `class_representative` si classe active = `get_student_class_id()`
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `matieres`

- **SELECT**
  - Tous les utilisateurs authentifiés actifs
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `salles`

- **SELECT**
  - Tous les utilisateurs authentifiés actifs
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `semestres`

- **SELECT**
  - Tous les utilisateurs authentifiés actifs
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `vacances_examens`

- **SELECT**
  - Tous les utilisateurs authentifiés actifs
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `parametres`

- **SELECT**
  - Tous les utilisateurs authentifiés actifs
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `professeur_matieres`

- **SELECT**
  - `admin`
  - `professor` : ses affectations (`professor_id = auth.uid()`)
  - `student` / `class_representative` : si inscrit dans la classe associée (`student_classes.is_active=true`)
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `student_classes`

- **SELECT**
  - `admin`
  - `student` / `class_representative` : ses propres lignes (`student_id = auth.uid()`)
  - `professor` : si enseigne la classe (`professor_teaches_class(class_id)`)
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

### Tables “emploi du temps”

#### `seances`

- **SELECT**
  - `admin`
  - `professor` : ses séances (`professor_id = auth.uid()`)
  - `student` / `class_representative` : séances de sa classe active (`class_id = get_student_class_id()`)
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

### Tables “cahier de texte / progression”

#### `programmes`

- **SELECT**
  - `admin`
  - `professor` si enseigne la classe (`professor_teaches_class(class_id)`)
  - `student` / `class_representative` si `class_id = get_student_class_id()`
- **INSERT**
  - `admin` ou `professor` qui enseigne la classe
- **UPDATE**
  - `admin` ou `professor` qui enseigne la classe
- **DELETE**
  - `admin` uniquement

#### `progressions`

- **SELECT**
  - `admin`
  - `professor` (si `progressions.seance_id` appartient au prof)
  - `student` / `class_representative` (si la séance est dans sa classe)
- **INSERT**
  - `professor` : si `updated_by = auth.uid()`, `updated_by_role='professor'`, et la séance appartient au prof
  - `class_representative` : si `updated_by = auth.uid()`, `updated_by_role='class_representative'`, et la séance est dans sa classe
- **UPDATE**
  - `professor` : si la séance appartient au prof **et** `is_validated=false`
  - `class_representative` : si la séance est dans sa classe **et** `is_validated=false`
  - `admin` : autorisé (tant que `is_validated=false` selon la policy)
- **DELETE**
  - Personne (policy `USING (false)`)

### Tables “présence”

#### `sessions`

- **SELECT**
  - `admin`
  - `professor` : ses sessions (`professor_id = auth.uid()`)
  - `student` / `class_representative` : si inscrit dans la classe de la séance (via join `seances`/`student_classes.is_active=true`)
- **INSERT**
  - `admin`
  - `professor` si `professor_id = auth.uid()`
- **UPDATE**
  - `admin`
  - `professor` si `professor_id = auth.uid()`
- **DELETE**
  - `admin` uniquement

#### `presences`

- **SELECT**
  - `admin`
  - `student` / `class_representative` : ses présences (`student_id = auth.uid()`)
  - `professor` : présences des séances qu’il enseigne (via join `sessions` → `seances`)
  - `class_representative` : présences de sa classe (via join `sessions` → `seances`)
- **INSERT**
  - `admin`
  - `professor` : uniquement pour ses séances (via join)
- **UPDATE**
  - `admin`
  - `professor` : uniquement pour ses séances
  - `student` : uniquement pour marquer _sa_ présence avec contraintes strictes :
    - `marked_by = 'student'`
    - `status = 'present'`
    - session `ouverte`
    - `NOW()` dans la fenêtre `opened_at + marking_window_duration`
- **DELETE**
  - Non défini → refusé par défaut

#### `justificatifs`

- **SELECT**
  - `admin`
  - `student` : ses justificatifs (`student_id = auth.uid()`)
  - `professor` : justificatifs des présences liées à ses séances
- **INSERT**
  - `student` uniquement (avec `student_id = auth.uid()`)
- **UPDATE**
  - `professor` : uniquement pour justificatifs de ses séances
- **DELETE**
  - Non défini → refusé par défaut

### Tables “ressources / communication”

#### `ressources`

- **SELECT**
  - `admin`
  - `student` / `class_representative` : ressources de sa classe active (`class_id = get_student_class_id()`)
  - `professor` : si enseigne la classe (`professor_teaches_class(class_id)`)
- **INSERT**
  - `admin`
  - tout rôle si `uploaded_by = auth.uid()` (donc prof/responsable peuvent insérer leurs propres ressources)
- **UPDATE/DELETE**
  - `admin` ou propriétaire (`uploaded_by = auth.uid()`)

#### `annonces`

- **SELECT**
  - `admin`
  - sinon si l’annonce est accessible par ciblage :
    - `is_published = true` (publique)
    - ou `target_type = 'all'`
    - ou `target_type='students'` et `is_student()`
    - ou `target_type='professors'` et `is_professor()`
    - ou `target_type='classe'` et `target_id = get_student_class_id()`
    - ou `target_type='filiere'` et filière de l’étudiant
- **INSERT/UPDATE/DELETE**
  - `admin` uniquement

#### `notifications`

- **SELECT**
  - uniquement le propriétaire (`user_id = auth.uid()`)
- **INSERT**
  - `admin` uniquement (par RLS)
- **UPDATE/DELETE**
  - uniquement le propriétaire (`user_id = auth.uid()`)

#### `logs_activite`

- **SELECT / INSERT / UPDATE / DELETE**
  - `admin` uniquement

### Table “profil applicatif”

#### `users`

- **SELECT**
  - Tous les utilisateurs authentifiés actifs
- **INSERT/DELETE**
  - `admin` uniquement
- **UPDATE**
  - `admin` ou l’utilisateur lui-même (`id = auth.uid()`), avec contrainte :
    - un utilisateur non-admin ne peut pas changer son `role`

## Opérations “obligatoires via Edge Functions / RPC”

Même si certaines écritures sont _possibles_ via PostgREST/RLS, ces opérations doivent passer par les Edge Functions/RPC pour respecter la logique métier implémentée côté serveur.

- **Ouvrir une session (prof)** : utiliser `open-session`
  - Pourquoi : vérifications jour/heure (timezone `Africa/Porto-Novo`), assignation, GPS (rayon salle), unicité “une session ouverte”.
- **Marquer une présence (étudiant)** : utiliser `mark-presence`
  - Pourquoi : vérification GPS côté serveur + règles de fenêtre + logique centralisée `mark_presence(...)`.
- **Clôturer une session (prof)** : utiliser `close-session`
  - Pourquoi : marque automatiquement les absents via `close_session(...)`.
- **Détection conflits EDT (admin)** : utiliser `check-conflicts`
  - Pourquoi : logique centralisée `check_schedule_conflicts(...)`.
- **Publier des séances (admin)** : utiliser `publish-seances`
  - Pourquoi : publication en masse + cohérence côté admin (et déclencheurs de notifications sur changement de statut).
- **Mettre à jour progression (prof/responsable)** : utiliser `update-progression`
  - Pourquoi : contrôle de rôle et d’appartenance + gestion insert/update.
- **Valider progression (prof)** : utiliser `validate-progression`
  - Pourquoi : verrouillage final (met `is_validated=true`).
- **Soumettre un justificatif (étudiant)** : utiliser `submit-justification`
  - Pourquoi : vérifie règles métier (présence = absent, unicité selon statut) + notification professeur.
- **Traiter un justificatif (prof)** : utiliser `review-justification`
  - Pourquoi : transaction atomique via `validate_justification(...)` + notifications.
- **Envoyer des notifications ciblées (admin/prof/responsable)** : utiliser `send-notification`
  - Pourquoi : insertion via client admin + résolution des cibles.
- **Rapports (admin/prof)** : utiliser `generate-report`
  - Pourquoi : génération côté serveur (JSON/CSV).
- **Job périodique** : `cron-close-sessions` (appelé par Supabase Cron)
  - Pourquoi : exécute `close_expired_sessions`, `publish_scheduled_annonces`, `send_exam_reminders`.

## Guide d’implémentation par module (CRUD + fonctions)

Cette section est organisée pour correspondre aux écrans UI/UX.

### A) Étudiant (Flutter) — planning, présence, ressources, assiduité

#### A1) Calendrier / EDT (ETU-04, ETU-05)

- **Lire les séances** : table `seances` (et/ou vues exposées par le schéma si présentes).
- Champs utiles : `date`, `start_time`, `end_time`, `matiere_id`, `salle_id`, `professor_id`, `status`, `is_exam`.

Attendu UX :

- séances publiées visibles
- badge “mis à jour” (côté app) si vous comparez `updated_at` ou via notifications

#### A2) Marquage de présence GPS (ETU-06)

Action critique : **ne pas faire un CRUD direct**.

- Appeler l’Edge Function : `mark-presence`
- Body : `{ "session_id": "uuid", "gps_lat": number, "gps_long": number }`

La logique serveur :

- vérifie fenêtre de marquage
- vérifie GPS vs `salles` via `is_within_salle_radius`
- met à jour `presences`

Référence : `docs/edge-functions.md` → `mark-presence`.

#### A3) Justifier une absence (ETU-10)

Workflow recommandé :

1. Upload du fichier dans Storage bucket `justificatifs`.
2. Obtenir un `file_url` (public URL ou signed URL selon stratégie).
3. Appeler l’Edge Function `submit-justification` avec :
   - `presence_id`
   - `file_url`
   - `reason` (optionnel)

Le professeur traite ensuite via `review-justification`.

#### A4) Ressources pédagogiques (ETU-08)

- Métadonnées : table `ressources` (filtre par `class_id`, `matiere_id`, `resource_type`)
- Fichier : Storage bucket `resources`

Téléchargement :

- soit via URL stockée en DB (si exposée)
- soit via génération de signed URL côté client (selon policies)

Référence Storage : section “Storage (buckets attendus)” plus bas + `docs/database.md`.

#### A5) Assiduité (ETU-09)

- Source : table `presences` join `sessions` join `seances`.
- Statuts : `present | absent | late | justified`.

### B) Responsable de classe (Flutter) — progression + assiduité de la classe

#### B1) Mettre à jour la progression (ETU-13)

- Edge Function : `update-progression`
- Autorisé : `class_representative` et `professor`
- Bloqué si progression validée : `progressions.is_validated = true`

#### B2) Lecture assiduité classe (ETU-14)

La consultation est basée sur RLS : le responsable ne voit que sa classe.

### C) Professeur (Flutter) — sessions, présences, progression, justificatifs

#### C1) Ouvrir une session de présence (PROF-05)

- Edge Function : `open-session`
- Body : `{ "seance_id": "uuid", "gps_lat": number, "gps_long": number, "marking_window_duration": number }`

La fonction vérifie :

- séance du jour, créneau horaire (timezone `Africa/Porto-Novo`)
- appartenance du prof à la séance
- position GPS dans le rayon de la salle
- pas de session déjà ouverte

#### C2) Clôturer une session (PROF-05)

- Edge Function : `close-session`
- Body : `{ "session_id": "uuid" }`

La clôture :

- ferme la session
- marque absents

#### C3) Traitement des justificatifs (PROF-12)

- Edge Function : `review-justification`
- Body : `{ "justificatif_id": "uuid", "decision": "validé"|"rejeté", "rejection_reason"?: string }`

#### C4) Validation finale de progression

- Edge Function : `validate-progression`
- Body : `{ "progression_id": "uuid" }`

### D) Admin (React) — CRUD structures, EDT, annonces, rapports

#### D1) Conflits EDT avant sauvegarde (ADM-06)

- Edge Function : `check-conflicts`
- Sert à afficher les conflits “salle / prof / classe” dans le formulaire.

#### D2) Publication des séances (ADM-06c)

- Edge Function : `publish-seances`
- Permet `Publier tout` ou par liste d’IDs.

#### D3) Annonces (ADM-07)

- CRUD via table `annonces` (selon policies)
- ou utiliser `send-notification` si vous voulez diffuser uniquement une notification (indépendante d’une annonce persistée).

#### D4) Rapports (ADM-08)

- Edge Function : `generate-report`
- Supporte `format=json` et `format=csv`.

## Edge Functions (référence rapide)

Base URL : `https://<project-ref>.supabase.co/functions/v1/<function-name>`

Fonctions disponibles (voir détail dans `docs/edge-functions.md`) :

- `mark-presence`
- `open-session`
- `close-session`
- `check-conflicts` (admin)
- `publish-seances` (admin)
- `update-progression`
- `validate-progression`
- `submit-justification`
- `review-justification`
- `send-notification`
- `generate-report`
- `update-fcm-token`
- `cron-close-sessions` (interne / scheduler)
- `send-push` (interne via `pg_net`)

## Storage (buckets attendus)

Buckets à créer dans Supabase (Dashboard → Storage → Buckets) :

- `avatars` (public)
- `resources` (private)
- `justificatifs` (private)
- `annonces` (private)

Les policies Storage sont déployées via migrations SQL (référence : `docs/database.md`).

## Setup applications (mobile) et dashboard

Cette section décrit le minimum à configurer côté clients.

### Mobile (app étudiants / professeurs)

- **Variables à définir** (dans l’app) :
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
- **Fonctions utilisées** : voir `docs/edge-functions.md`
- **Storage** : utiliser les buckets selon le besoin (avatars, justificatifs, ressources, annonces)

### Dashboard (administration)

- **Variables à définir** :
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
- Les opérations sensibles sont protégées par RLS + vérifications côté Edge Functions.

## Notes importantes

- Le projet utilise **RLS** sur toutes les tables applicatives.
- Les comptes désactivés (`users.is_active=false`) sont bloqués globalement.
- Les automatisations (fermeture des sessions expirées, publication d'annonces planifiées, rappels d'examen) peuvent être exécutées via l'Edge Function `cron-close-sessions` planifiée dans Supabase Cron (Dashboard → Integrations → Cron). Ce cron est optionnel : sans lui, ces tâches devront être faites manuellement (fermeture de session par le professeur, publication manuelle des annonces).
- `pg_cron` n’est pas utilisé/recommandé pour ce projet.
- Les notifications push utilisent FCM legacy (clé serveur) et un appel `pg_net` vers `send-push` (voir `docs/setup-production.md`). La configuration FCM est optionnelle : sans `FCM_SERVER_KEY`, les pushes sont ignorés.

## Liens internes (lecture recommandée)

- `docs/database.md`
- `docs/edge-functions.md`
- `docs/setup-production.md`
