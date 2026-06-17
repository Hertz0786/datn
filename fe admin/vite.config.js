import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174,
    host: '0.0.0.0',
  },
  // Make sure stale JS/CSS from a previous tab does not freeze
  // the user on a white screen after we change the entry point.
  // We force-disable the Cache-Control header on transformed
  // module responses so the dev server always wins.
  headers: {
    'Cache-Control': 'no-store, no-cache, must-revalidate',
  },
});
