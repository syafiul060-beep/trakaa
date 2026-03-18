/**
 * Konfigurasi Firebase untuk Traka Admin.
 * 
 * Cara setup:
 * 1. Buka Firebase Console > Project Settings > General
 * 2. Scroll ke "Your apps" > Tambah web app (jika belum)
 * 3. Copy config object ke bawah
 * 4. Buat file .env dengan:
 *    VITE_FIREBASE_API_KEY=xxx
 *    VITE_FIREBASE_AUTH_DOMAIN=xxx
 *    ... dst
 * 5. Atau isi langsung di sini (JANGAN commit ke git!)
 */

import { initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'
import { getFunctions, httpsCallable } from 'firebase/functions'

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || 'YOUR_API_KEY',
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || 'YOUR_PROJECT.firebaseapp.com',
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || 'YOUR_PROJECT_ID',
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || 'YOUR_PROJECT.appspot.com',
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || '123456789',
  appId: import.meta.env.VITE_FIREBASE_APP_ID || 'YOUR_APP_ID',
}

const app = initializeApp(firebaseConfig)
export const auth = getAuth(app)
export const db = getFirestore(app)
export const functions = getFunctions(app)
export { httpsCallable }
export default app
