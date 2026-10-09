import { applyD1Migrations, type D1Migration, env } from 'cloudflare:test';

const migrations = (env as unknown as { TEST_MIGRATIONS: D1Migration[] }).TEST_MIGRATIONS;
await applyD1Migrations(env.DB, migrations, 'amc_api_migrations');
