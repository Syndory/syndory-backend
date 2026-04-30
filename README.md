# Syndory - Backend Supabase

Plateforme intégrée de gestion universitaire - Backend complet sur Supabase.

## 📁 Structure du projet

```
supabase/
├── config.toml                    # Configuration Supabase CLI
├── seed.sql                       # Données initiales
├── migrations/
│   ├── 001_initial_schema.sql     # Schéma de base de données
│   ├── 002_rls_policies.sql       # Politiques de sécurité
│   └── 003_functions_triggers.sql # Fonctions et triggers
└── functions/
    ├── _shared/
    │   ├── cors.ts               # Headers CORS
    │   └── supabase.ts           # Client Supabase utilitaire
    ├── mark-presence/            # Marquage de présence GPS
    ├── open-session/             # Ouverture session prof
    ├── close-session/            # Fermeture session
    ├── check-conflicts/          # Vérification conflits EDT
    ├── validate-progression/     # Validation progression
    ├── send-notification/        # Envoi notifications
    └── generate-report/          # Génération rapports
```

## 🚀 Déploiement

### Prérequis

1. Créer un projet sur [Supabase](https://supabase.com)
2. Installer Supabase CLI: `npm install -g supabase`
3. Se connecter: `supabase login`

### Configuration

1. Lier le projet local:
```bash
supabase link --project-ref <votre-project-ref>
```

2. Configurer les variables d'environnement dans le Dashboard Supabase:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`

### Déploiement du schéma

```bash
# Exécuter les migrations
supabase db push

# Ou exécuter les migrations SQL via le SQL Editor du Dashboard
```

### Déploiement des Edge Functions

```bash
# Déployer toutes les fonctions
supabase functions deploy

# Ou déployer une fonction spécifique
supabase functions deploy mark-presence
supabase functions deploy open-session
supabase functions deploy close-session
supabase functions deploy check-conflicts
supabase functions deploy validate-progression
supabase functions deploy send-notification
supabase functions deploy generate-report
```

### Configuration du Storage

Créer les buckets suivants dans Storage > Buckets:

1. **avatars** (public)
   - File size limit: 2MB
   - Allowed types: jpg, png, webp

2. **resources** (private)
   - File size limit: 20MB
   - Allowed types: pdf, docx, pptx, images

3. **justificatifs** (private)
   - File size limit: 10MB
   - Allowed types: pdf, jpg, png

4. **annonces** (private)
   - File size limit: 10MB
   - Allowed types: pdf, docx, images

### Création du compte admin initial

```sql
-- Via le SQL Editor ou après connexion
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
VALUES (
  gen_random_uuid(),
  'admin@syndory.com',
  crypt('VotreMotDePasseFort', gen_salt('bf')),
  NOW(),
  '{"first_name": "Admin", "last_name": "Syndory", "role": "admin"}'::jsonb
);

-- Puis vérifier que le trigger a créé l'entrée dans la table users
-- et mettre à jour le rôle si nécessaire:
UPDATE users SET role = 'admin' WHERE email = 'admin@syndory.com';
```

## 📊 Schéma de base de données

### Tables principales

| Table | Description |
|-------|-------------|
| `users` | Profils utilisateurs (étudiants, profs, admin) |
| `filieres` | Filières académiques |
| `classes` | Classes/groupes |
| `matieres` | Matières enseignées |
| `salles` | Salles avec coordonnées GPS |
| `seances` | Emploi du temps |
| `sessions` | Sessions de présence géolocalisées |
| `presences` | Marquage de présence |
| `justificatifs` | Justificatifs d'absence |
| `programmes` | Cahiers de texte |
| `progressions` | Suivi de progression pédagogique |
| `ressources` | Documents pédagogiques |
| `annonces` | Annonces et communications |
| `notifications` | Notifications push |
| `logs_activite` | Journal d'audit |
| `parametres` | Configuration système |

### Rôles et permissions

- **student**: Consultation planning, marquage présence, justificatifs
- **class_representative**: Permissions étudiant + gestion progression, documents classe
- **professor**: Gestion sessions, présences, ressources, progression
- **admin**: Contrôle total sur la plateforme

## 🔧 Edge Functions

### `mark-presence`
```http
POST /functions/v1/mark-presence
Body: { session_id, gps_lat, gps_long }
```
Marque la présence d'un étudiant avec vérification GPS.

### `open-session`
```http
POST /functions/v1/open-session
Body: { seance_id, gps_lat, gps_long, marking_window_duration }
```
Ouvre une session de présence (professeur uniquement).

### `close-session`
```http
POST /functions/v1/close-session
Body: { session_id }
```
Ferme une session et marque les absents.

### `check-conflicts`
```http
POST /functions/v1/check-conflicts
Body: { matiere_id, professor_id, class_id, salle_id, date, start_time, end_time }
```
Vérifie les conflits d'emploi du temps.

### `validate-progression`
```http
POST /functions/v1/validate-progression
Body: { progression_id }
```
Valide définitivement une progression.

### `send-notification`
```http
POST /functions/v1/send-notification
Body: { user_ids?, target_type?, target_id?, type, title, message, data? }
```
Envoie des notifications aux utilisateurs.

### `generate-report`
```http
POST /functions/v1/generate-report
Body: { report_type, format: 'csv'|'json', filters? }
```
Génère des rapports statistiques.

## 🛡️ Sécurité

### RLS (Row Level Security)
Toutes les tables ont RLS activé avec des politiques granulaires:
- Les étudiants ne voient que leurs données et celles de leur classe
- Les profs accèdent aux données de leurs classes/matières
- L'admin a un accès complet

### Authentification
- Authentification email/password via Supabase Auth
- Pas d'inscription publique (enable_signup = false)
- Tokens JWT avec expiration et refresh

### Vérification GPS
- Calcul de distance Haversine pour validation de présence
- Rayon de tolérance configurable par salle (défaut: 50m)
- Vérification côté serveur uniquement

## 📱 Notifications Push

Les notifications sont stockées dans la table `notifications` et peuvent être poussées vers les apps mobiles via:
- Firebase Cloud Messaging (FCM) pour Android
- Supabase Realtime pour les mises à jour temps réel

Événements déclenchant des notifications:
- Publication/modification emploi du temps
- Ouverture session de présence
- Nouveau document publié
- Justificatif soumis/validé/rejeté
- Annonce publiée
- Rappel examen (24h avant)

## 📈 Monitoring et logs

- Journal d'activité dans `logs_activite`
- Logs Supabase Functions dans le Dashboard
- Métriques de performance via Supabase Analytics

## 🔗 API Reference

### Base URL
```
https://<project-ref>.supabase.co
```

### Endpoints principaux

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/auth/v1/token` | POST | Connexion |
| `/rest/v1/users` | GET/POST/PATCH | Gestion utilisateurs |
| `/rest/v1/seances` | GET/POST/PATCH | Emploi du temps |
| `/rest/v1/sessions` | GET/POST/PATCH | Sessions présence |
| `/rest/v1/presences` | GET/POST/PATCH | Présences |
| `/rest/v1/ressources` | GET/POST | Ressources |
| `/functions/v1/*` | POST | Edge Functions |
| `/storage/v1/object/*` | GET/POST | Fichiers |

## 🆘 Support

Pour toute question ou problème:
- Documentation Supabase: https://supabase.com/docs
- Issues: Créer une issue sur le repository

---

**Syndory** - Plateforme de gestion universitaire | L3 Architecture Logicielle
