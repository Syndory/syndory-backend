# Syndory Backend (Supabase)

Ce dépôt contient le **backend Supabase** du projet **Syndory** :

- base de données (migrations SQL, RLS, fonctions, triggers)
- Edge Functions (API serveur)
- politiques Storage (buckets + accès)

## Documentation

- Base de données (structure, RLS, fonctions, triggers, storage) : `docs/database.md`
- Edge Functions (endpoints, logique, exemples d’appel) : `docs/edge-functions.md`
- Setup production (FCM + pg_net + scheduler) : `docs/setup-production.md`

## Structure du projet

```
docs/
scripts/
supabase/
  config.toml
  migrations/
  functions/
  seed.sql
```

## Prérequis

- Compte Supabase + un projet créé
- Supabase CLI installé
- Connexion : `supabase login`

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

## Configuration Storage

Buckets à créer dans Supabase (Dashboard → Storage → Buckets) :

- `avatars` (public)
- `resources` (private)
- `justificatifs` (private)
- `annonces` (private)

Les policies Storage sont déployées via migration SQL.

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
- Les automatisations (fermeture des sessions expirées, publication d’annonces planifiées, rappels d’examen) sont exécutées via l’Edge Function `cron-close-sessions` planifiée dans `supabase/config.toml`.
- `pg_cron` n’est pas utilisé/recommandé pour ce projet.
- Les notifications push utilisent FCM legacy (clé serveur) et un appel `pg_net` vers `send-push` (voir `docs/setup-production.md`).
