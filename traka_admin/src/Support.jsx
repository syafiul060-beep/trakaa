import { useState, useEffect, useRef } from 'react'
import {
  collection,
  doc,
  getDoc,
  getDocs,
  addDoc,
  updateDoc,
  query,
  where,
  orderBy,
  onSnapshot,
  serverTimestamp,
  setDoc
} from 'firebase/firestore'
import { db, auth } from './firebase'

const ADMIN_CHATS = 'admin_chats'
const MESSAGES = 'messages'
const ADMIN_STATUS = 'admin_status'

export default function Support({ onLogout }) {
  const [tab, setTab] = useState('support')
  const [queue, setQueue] = useState([])
  const [currentChatUserId, setCurrentChatUserId] = useState(null)
  const [currentChatUserInfo, setCurrentChatUserInfo] = useState(null)
  const [messages, setMessages] = useState([])
  const [messageText, setMessageText] = useState('')
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const [adminName, setAdminName] = useState('')
  const messagesEndRef = useRef(null)
  const unsubQueue = useRef(null)
  const unsubStatus = useRef(null)
  const unsubMessages = useRef(null)

  const user = auth.currentUser

  useEffect(() => {
    if (!user) return
    async function init() {
      try {
        const userDoc = await getDoc(doc(db, 'users', user.uid))
        const d = userDoc.data()
        const name = d?.displayName || user.displayName || user.email?.split('@')[0] || 'Admin'
        setAdminName(name)
        const statusDoc = await getDoc(doc(db, ADMIN_STATUS, user.uid))
        const statusData = statusDoc.data()
        if (statusData?.status !== 'busy') {
          await setDoc(doc(db, ADMIN_STATUS, user.uid), {
            status: 'online',
            displayName: name,
            lastSeen: serverTimestamp()
          }, { merge: true })
        }
      } catch (e) {
        console.error('Support init', e)
      }
    }
    init()
    return () => {
      setDoc(doc(db, ADMIN_STATUS, user.uid), {
        status: 'offline',
        lastSeen: serverTimestamp()
      }, { merge: true }).catch(() => {})
    }
  }, [user?.uid])

  useEffect(() => {
    if (!user) return
    const q = query(
      collection(db, ADMIN_CHATS),
      where('status', '==', 'in_queue'),
      orderBy('queueJoinedAt', 'asc')
    )
    unsubQueue.current = onSnapshot(q, (snap) => {
      setQueue(snap.docs.map(d => ({ id: d.id, ...d.data() })))
    })
    return () => {
      if (unsubQueue.current) unsubQueue.current()
    }
  }, [user?.uid])

  useEffect(() => {
    if (!user) return
    unsubStatus.current = onSnapshot(doc(db, ADMIN_STATUS, user.uid), (snap) => {
      const d = snap.data()
      setCurrentChatUserId(d?.currentChatUserId || null)
    })
    return () => {
      if (unsubStatus.current) unsubStatus.current()
    }
  }, [user?.uid])

  useEffect(() => {
    if (!currentChatUserId) {
      setMessages([])
      setCurrentChatUserInfo(null)
      return
    }
    getDoc(doc(db, ADMIN_CHATS, currentChatUserId)).then((snap) => {
      if (snap.exists()) setCurrentChatUserInfo({ id: snap.id, ...snap.data() })
    })
  }, [currentChatUserId])

  useEffect(() => {
    if (!currentChatUserId) {
      setMessages([])
      return
    }
    const q = query(
      collection(db, ADMIN_CHATS, currentChatUserId, MESSAGES),
      orderBy('createdAt', 'asc')
    )
    unsubMessages.current = onSnapshot(q, (snap) => {
      setMessages(snap.docs.map(d => ({ id: d.id, ...d.data() })))
    })
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
    return () => {
      if (unsubMessages.current) unsubMessages.current()
    }
  }, [currentChatUserId])

  async function takeChat(userId) {
    if (!user) return
    setSending(true)
    const name = adminName || user.displayName || user.email?.split('@')[0] || 'Admin'
    try {
      await updateDoc(doc(db, ADMIN_CHATS, userId), {
        status: 'connected',
        assignedAdminId: user.uid,
        assignedAdminName: name,
        updatedAt: serverTimestamp()
      })
      await addDoc(collection(db, ADMIN_CHATS, userId, MESSAGES), {
        senderUid: 'bot',
        senderType: 'bot',
        text: `Anda terhubung dengan ${name}. Silakan sampaikan keluhan Anda.`,
        createdAt: serverTimestamp(),
        status: 'sent'
      })
      await setDoc(doc(db, ADMIN_STATUS, user.uid), {
        status: 'busy',
        currentChatUserId: userId,
        lastSeen: serverTimestamp()
      }, { merge: true })
      setCurrentChatUserId(userId)
      const remainingQueue = await getDocs(query(
        collection(db, ADMIN_CHATS),
        where('status', '==', 'in_queue'),
        orderBy('queueJoinedAt', 'asc')
      ))
      for (let i = 0; i < remainingQueue.docs.length; i++) {
        await updateDoc(remainingQueue.docs[i].ref, { queuePosition: i + 1 })
      }
    } catch (e) {
      console.error('takeChat', e)
    }
    setSending(false)
  }

  async function sendMessage() {
    if (!user || !currentChatUserId || !messageText.trim()) return
    setSending(true)
    try {
      await addDoc(collection(db, ADMIN_CHATS, currentChatUserId, MESSAGES), {
        senderUid: user.uid,
        senderType: 'admin',
        text: messageText.trim(),
        createdAt: serverTimestamp(),
        status: 'sent'
      })
      await updateDoc(doc(db, ADMIN_CHATS, currentChatUserId), {
        lastMessage: messageText.trim(),
        lastMessageAt: serverTimestamp(),
        updatedAt: serverTimestamp()
      })
      setMessageText('')
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
    } catch (e) {
      console.error('sendMessage', e)
    }
    setSending(false)
  }

  async function closeChat() {
    if (!user || !currentChatUserId) return
    setSending(true)
    try {
      await updateDoc(doc(db, ADMIN_CHATS, currentChatUserId), {
        status: 'closed',
        assignedAdminId: null,
        assignedAdminName: null,
        updatedAt: serverTimestamp()
      })
      await addDoc(collection(db, ADMIN_CHATS, currentChatUserId, MESSAGES), {
        senderUid: 'bot',
        senderType: 'bot',
        text: 'Chat telah ditutup. Terima kasih telah menghubungi kami. Ketik pesan baru untuk memulai lagi.',
        createdAt: serverTimestamp(),
        status: 'sent'
      })
      await setDoc(doc(db, ADMIN_STATUS, user.uid), {
        status: 'online',
        currentChatUserId: null,
        lastSeen: serverTimestamp()
      }, { merge: true })
      setCurrentChatUserId(null)
    } catch (e) {
      console.error('closeChat', e)
    }
    setSending(false)
  }

  const formatTime = (ts) => {
    if (!ts?.toDate) return ''
    return ts.toDate().toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })
  }

  return (
    <div className="container">
      <div className="support-layout">
        <div className="support-sidebar card">
          <h3 style={{ marginBottom: 16 }}>Antrian ({queue.length})</h3>
          {queue.length === 0 ? (
            <p style={{ color: '#64748b', fontSize: 14 }}>Tidak ada antrian</p>
          ) : (
            <div className="queue-list">
              {queue.map((q, i) => (
                <div key={q.id} className="queue-item">
                  <div>
                    <strong>#{i + 1} {q.displayName || q.userId?.slice(0, 8)}</strong>
                    <p style={{ fontSize: 12, color: '#64748b', marginTop: 4 }}>{q.lastMessage?.slice(0, 40)}...</p>
                  </div>
                  <button
                    className="btn btn-primary"
                    style={{ padding: '6px 12px', fontSize: 12 }}
                    onClick={() => takeChat(q.id)}
                    disabled={sending || currentChatUserId}
                  >
                    Ambil
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="support-chat card" style={{ flex: 1 }}>
          {currentChatUserId ? (
            <>
              <div className="chat-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16, paddingBottom: 12, borderBottom: '1px solid #eee' }}>
                <div>
                  <h3 style={{ margin: 0 }}>Chat dengan {currentChatUserInfo?.displayName || currentChatUserId?.slice(0, 8) || 'User'}</h3>
                  <p style={{ fontSize: 12, color: '#64748b', marginTop: 4 }}>User ID: {currentChatUserId}</p>
                </div>
                <button className="btn btn-danger" style={{ padding: '6px 12px' }} onClick={closeChat} disabled={sending}>
                  Tutup Chat
                </button>
              </div>
              <div className="chat-messages" style={{ height: 400, overflowY: 'auto', marginBottom: 16, padding: 12, background: '#f8fafc', borderRadius: 8 }}>
                {messages.map((m) => (
                  <div
                    key={m.id}
                    style={{
                      marginBottom: 8,
                      textAlign: m.senderType === 'admin' ? 'right' : 'left',
                      padding: '8px 12px',
                      borderRadius: 12,
                      maxWidth: '80%',
                      marginLeft: m.senderType === 'admin' ? 'auto' : 0,
                      marginRight: m.senderType === 'admin' ? 0 : 'auto',
                      background: m.senderType === 'admin' ? '#22c55e' : m.senderType === 'bot' ? '#e2e8f0' : '#fff',
                      color: m.senderType === 'admin' ? 'white' : '#333',
                      border: m.senderType === 'user' ? '1px solid #e5e7eb' : 'none'
                    }}
                  >
                    {m.senderType === 'admin' && <span style={{ fontSize: 11, opacity: 0.9 }}>Anda</span>}
                    {m.senderType === 'bot' && <span style={{ fontSize: 11, color: '#64748b' }}>Sistem</span>}
                    {m.senderType === 'user' && <span style={{ fontSize: 11, color: '#64748b' }}>User</span>}
                    <div style={{ marginTop: 4 }}>{m.text}</div>
                    <div style={{ fontSize: 10, opacity: 0.8, marginTop: 4 }}>{formatTime(m.createdAt)}</div>
                  </div>
                ))}
                <div ref={messagesEndRef} />
              </div>
              <div className="template-buttons" style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 10 }}>
                {['Terima kasih telah menghubungi kami.', 'Mohon tunggu, saya cek dulu.', 'Pesanan Anda sedang kami proses.', 'Ada yang bisa saya bantu lagi?', 'Terima kasih, chat ini akan ditutup.'].map(t => (
                  <button key={t} className="btn" style={{ background: '#e2e8f0', padding: '6px 10px', fontSize: 12 }} onClick={() => { setMessageText(t) }}>
                    {t.length > 30 ? t.slice(0, 30) + '...' : t}
                  </button>
                ))}
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                <input
                  type="text"
                  value={messageText}
                  onChange={(e) => setMessageText(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && sendMessage()}
                  placeholder="Ketik pesan..."
                  style={{ flex: 1 }}
                />
                <button className="btn btn-primary" onClick={sendMessage} disabled={sending || !messageText.trim()}>
                  Kirim
                </button>
              </div>
            </>
          ) : (
            <div style={{ padding: 40, textAlign: 'center', color: '#64748b' }}>
              <p>Pilih chat dari antrian</p>
              <p style={{ fontSize: 14, marginTop: 8 }}>Klik "Ambil" pada user di antrian untuk memulai chat</p>
            </div>
          )}
        </div>
      </div>

      <style>{`
        .support-layout { display: flex; gap: 20px; flex-wrap: wrap; }
        .support-sidebar { width: 320px; min-width: 280px; }
        .queue-item { display: flex; justify-content: space-between; align-items: center; padding: 12px; border-radius: 8px; background: #f8fafc; margin-bottom: 8; }
        .queue-list { display: flex; flex-direction: column; gap: 8px; }
      `}</style>
    </div>
  )
}
