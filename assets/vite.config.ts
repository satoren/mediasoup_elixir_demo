import path from "path"
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import dns from "node:dns";
dns.setDefaultResultOrder("ipv4first");
// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:4000",
        secure: false,
        ws: true,
      },
      "/socket": {
        target: "http://localhost:4000",
        ws: true,
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    outDir: "../priv/static/",
  },
});
