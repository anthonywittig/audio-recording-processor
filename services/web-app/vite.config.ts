import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Local dev has no API of its own — proxy /api to the deployed CloudFront
// distribution:
//   ARP_WEB_ORIGIN=$(terraform -chdir=../../infra/terraform/web output -raw web_url) npm run dev
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: process.env.ARP_WEB_ORIGIN
      ? { '/api': { target: process.env.ARP_WEB_ORIGIN, changeOrigin: true } }
      : undefined,
  },
});
