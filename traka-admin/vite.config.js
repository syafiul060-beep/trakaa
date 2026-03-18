import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// base: '/' untuk traka-admin.web.app (standalone)
// Untuk syafiul-traka.web.app/admin/ pakai: npm run build:syafiul
export default defineConfig({
  plugins: [react()],
  base: '/',
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor-react': ['react', 'react-dom', 'react-router-dom'],
          'vendor-firebase': ['firebase/app', 'firebase/auth', 'firebase/firestore'],
          'vendor-recharts': ['recharts'],
        },
      },
    },
    chunkSizeWarningLimit: 600,
  },
})
