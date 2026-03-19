
-- Enable pg_cron for scheduled jobs
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Enable pg_net for async HTTP requests from the database
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
;
