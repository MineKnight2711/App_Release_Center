import path from 'node:path';
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-plugin';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [
    cloudflareTest(async () => ({
      wrangler: { configPath: './wrangler.jsonc' },
      // Tests stub Workers AI; never reach the real account or spend neurons.
      remoteBindings: false,
      miniflare: {
        bindings: {
          PASSWORD_PEPPER: 'test-pepper',
          DESKTOP_ENABLED: 'true',
          TURN_URLS: 'turn:turn.test:3478?transport=udp,turns:turn.test:443?transport=tcp',
          TURN_SECRET: 'local-test-only-turn-secret',
          TEST_MIGRATIONS: await readD1Migrations(path.join(import.meta.dirname, 'migrations')),
        },
      },
    })),
  ],
  test: {
    setupFiles: ['./test/apply-migrations.ts'],
  },
});
