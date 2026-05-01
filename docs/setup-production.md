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

The cron job is configured in [supabase/config.toml](../supabase/config.toml) under `functions.cron-close-sessions`.
Ensure the `cron-close-sessions` function is deployed in production so Supabase can execute it every minute.
