# Production setup

## Configure functions URL for pg_net

The notification trigger uses `pg_net` to call the `send-push` edge function. Set the base functions URL in Postgres so the trigger can reach your production endpoint.

Run this in the Supabase SQL editor (or a migration if you prefer):

```sql
alter database postgres set app.settings.functions_url = 'https://<project-ref>.functions.supabase.co';
```

Then reload the setting:

```sql
select pg_reload_conf();
```

For local development, the default fallback remains:

```
http://localhost:54321/functions/v1
```

## Required secrets

Set these secrets in your Supabase project:

- `FCM_SERVER_KEY` (legacy FCM server key)

## Scheduler

Le mécanisme recommandé est l’Edge Function `cron-close-sessions`.

Pour la planification, utiliser **Supabase Cron** (Dashboard → Integrations → Cron) afin d’appeler l’endpoint :

`POST https://<project-ref>.supabase.co/functions/v1/cron-close-sessions`

Planification recommandée : `* * * * *` (toutes les minutes).

Note : on ne configure pas la clé `schedule` dans `supabase/config.toml` (compatibilité Supabase CLI).
