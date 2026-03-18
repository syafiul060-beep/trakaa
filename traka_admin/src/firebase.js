import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: 'AIzaSyA-DAHNjx9iJF54sxd0GaYb3b0gbVkbETQ',
  authDomain: 'syafiul-traka.firebaseapp.com',
  projectId: 'syafiul-traka',
  storageBucket: 'syafiul-traka.firebasestorage.app',
  messagingSenderId: '652861002574',
  appId: '1:652861002574:web:4bdc74993fc9859650041f',
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
