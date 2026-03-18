import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

/**
 * Firebase config - JANGAN hardcode API key!
 * Buat .env dengan VITE_FIREBASE_* dan pastikan .env ada di .gitignore.
 */
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || 'syafiul-traka.firebaseapp.com',
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || 'syafiul-traka',
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || 'syafiul-traka.firebasestorage.app',
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || '652861002574',
  appId: import.meta.env.VITE_FIREBASE_APP_ID || '1:652861002574:web:4bdc74993fc9859650041f',
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
