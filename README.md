# Syndory Backend (Supabase)

Ce dépôt contient le **backend Supabase** du projet **Syndory** :

- base de données (migrations SQL, RLS, fonctions, triggers)
- Edge Functions (API serveur)
- politiques Storage (buckets + accès)

## Documentation

- Base de données (structure, RLS, fonctions, triggers, storage) : `docs/database.md`
- Edge Functions (endpoints, logique, exemples d’appel) : `docs/edge-functions.md`

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
supabase functions deploy generate-report
supabase functions deploy validate-progression
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
- Certaines automatisations (rappels examens, fermeture auto…) doivent être planifiées via un scheduler externe (voir `docs/database.md`).
