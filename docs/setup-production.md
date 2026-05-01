# Production setup

## Configure functions URL for pg_net

The notification trigger uses `pg_net` to call the `send-push` edge function.

The database function uses `app.settings.functions_url` when available, but falls back to the project Functions URL if the setting cannot be configured on hosted Supabase.

## Required secrets

Set these secrets in your Supabase project:

- `FCM_SERVER_KEY` (legacy FCM server key) — optional

If `FCM_SERVER_KEY` is not set, the `send-push` function returns `success=true` with `skipped=true` and no push is sent.

## Scheduler (optionnel)

Le mécanisme recommandé est l'Edge Function `cron-close-sessions`.

**Ce cron est optionnel** : le backend fonctionne parfaitement sans, mais les tâches suivantes devront être faites manuellement :

- Fermeture des sessions expirées (les professeurs peuvent fermer manuellement via `close-session`)
- Publication des annonces planifiées (publier manuellement l’annonce via la table `annonces` ou exécuter `publish_scheduled_annonces()` avec des privilèges admin)
- Envoi des rappels d'examen (pas de rappel automatique)

### Configuration (peut être faite plus tard)

Pour activer l'automatisation, créer un job dans **Supabase Cron** (Dashboard → Integrations → Cron) :

- **Method** : `POST`
- **URL** : `https://<project-ref>.supabase.co/functions/v1/cron-close-sessions`
- **Schedule** : `* * * * *` (toutes les minutes)
- **Headers** : `Content-Type: application/json`
- **Body** : `{}`

Note : on ne configure pas la clé `schedule` dans `supabase/config.toml` (compatibilité Supabase CLI).
