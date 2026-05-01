-- Migration 008: add fcm_token to users

ALTER TABLE users
ADD COLUMN IF NOT EXISTS fcm_token TEXT;
