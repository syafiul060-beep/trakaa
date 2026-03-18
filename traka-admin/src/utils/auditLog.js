import { collection, addDoc, serverTimestamp, query, orderBy, limit, getDocs } from 'firebase/firestore'
import { db, auth } from '../firebase'

const COLLECTION = 'admin_audit_logs'

export async function logAudit(action, details = {}) {
  const user = auth.currentUser
  if (!user) return
  try {
    await addDoc(collection(db, COLLECTION), {
      action,
      adminUid: user.uid,
      adminEmail: user.email || '',
      details,
      createdAt: serverTimestamp(),
    })
  } catch (err) {
    console.error('Audit log error:', err)
  }
}

export async function getAuditLogs(limitCount = 100) {
  try {
    const q = query(
      collection(db, COLLECTION),
      orderBy('createdAt', 'desc'),
      limit(limitCount)
    )
    const snap = await getDocs(q)
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }))
  } catch (err) {
    console.error('Audit log fetch error:', err)
    return []
  }
}
