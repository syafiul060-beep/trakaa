import { useState, useEffect, useRef } from 'react'
import {
  collection,
  doc,
  addDoc,
  setDoc,
  getDoc,
  updateDoc,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
} from 'firebase/firestore'
import { db, auth } from '../firebase'

export default function Chat() {
  const [chats, setChats] = useState([])
  const [selectedUserId, setSelectedUserId] = useState(null)
  const [messages, setMessages] = useState([])
  const [userInfo, setUserInfo] = useState(null)
  const [inputText, setInputText] = useState('')
  const [loading, setLoading] = useState(true)
  const [closing, setClosing] = useState(false)

  // Daftar chat (admin_chats)
  useEffect(() => {
    const q = query(
      collection(db, 'admin_chats'),
      orderBy('lastMessageAt', 'desc')
    )
    const unsub = onSnapshot(q, (snap) => {
      setChats(snap.docs.map((d) => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
    return () => unsub()
  }, [])

  // Load user info dan set status connected saat admin pilih chat
  useEffect(() => {
    if (!selectedUserId || !auth.currentUser) {
      setUserInfo(null)
      return
    }
    getDoc(doc(db, 'users', selectedUserId)).then((d) => {
      setUserInfo(d.exists() ? { id: d.id, ...d.data() } : null)
    })
    // Set status connected agar banner antrian hilang di app user
    setDoc(
      doc(db, 'admin_chats', selectedUserId),
      {
        status: 'connected',
        assignedAdminId: auth.currentUser.uid,
        assignedAdminName: auth.currentUser.displayName || auth.currentUser.email?.split('@')[0] || 'Admin',
        updatedAt: serverTimestamp(),
      },
      { merge: true }
    ).catch(() => {})
  }, [selectedUserId])

  const messagesEndRef = useRef(null)

  // Stream messages untuk chat terpilih
  useEffect(() => {
    if (!selectedUserId) {
      setMessages([])
      return
    }
    const q = query(
      collection(db, 'admin_chats', selectedUserId, 'messages'),
      orderBy('createdAt', 'asc')
    )
    const unsub = onSnapshot(q, (snap) => {
      setMessages(snap.docs.map((d) => ({ id: d.id, ...d.data() })))
    })
    return () => unsub()
  }, [selectedUserId])

  // Auto-scroll ke pesan terbaru
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const handleSend = async () => {
    const text = inputText.trim()
    if (!text || !selectedUserId || !auth.currentUser) return

    setInputText('')
    try {
      const chatRef = doc(db, 'admin_chats', selectedUserId)
      const messagesRef = collection(chatRef, 'messages')

      await addDoc(messagesRef, {
        senderUid: auth.currentUser.uid,
        senderType: 'admin',
        text,
        type: 'text',
        createdAt: serverTimestamp(),
        status: 'sent',
      })

      const displayName = userInfo?.displayName || userInfo?.email || selectedUserId
      await setDoc(
        chatRef,
        {
          userId: selectedUserId,
          displayName,
          lastMessage: text,
          lastMessageAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
          status: 'connected',
        },
        { merge: true }
      )
    } catch (err) {
      console.error('Gagal kirim pesan:', err)
      alert('Gagal mengirim pesan. Coba lagi.')
    }
  }

  const formatTime = (ts) => {
    if (!ts?.toDate) return '-'
    return ts.toDate().toLocaleTimeString('id-ID', {
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  const handleCloseChat = async () => {
    if (!selectedUserId || !auth.currentUser) return
    if (!confirm('Akhiri percakapan dengan pengguna ini? Pengguna akan menerima notifikasi bahwa chat telah ditutup.')) return
    setClosing(true)
    try {
      const chatRef = doc(db, 'admin_chats', selectedUserId)
      const messagesRef = collection(chatRef, 'messages')

      await updateDoc(chatRef, {
        status: 'closed',
        assignedAdminId: null,
        assignedAdminName: null,
        updatedAt: serverTimestamp(),
      })
      await addDoc(messagesRef, {
        senderUid: 'bot',
        senderType: 'bot',
        text: 'Chat telah ditutup. Terima kasih telah menghubungi kami. Ketik pesan baru untuk memulai lagi.',
        createdAt: serverTimestamp(),
        status: 'sent',
      })
      await setDoc(
        doc(db, 'admin_status', auth.currentUser.uid),
        {
          status: 'online',
          currentChatUserId: null,
          lastSeen: serverTimestamp(),
        },
        { merge: true }
      )
      setSelectedUserId(null)
    } catch (err) {
      console.error('Gagal tutup chat:', err)
      alert('Gagal mengakhiri percakapan. Coba lagi.')
    }
    setClosing(false)
  }

  return (
    <div className="flex gap-4 min-h-[400px] h-[calc(100vh-12rem)] max-h-[calc(100dvh-10rem)]">
      {/* Daftar chat */}
      <div className="w-80 bg-white rounded-lg shadow flex flex-col overflow-hidden">
        <div className="p-4 border-b bg-gray-50">
          <h3 className="font-semibold text-gray-800">Percakapan</h3>
          <p className="text-sm text-gray-500 mt-1">
            {chats.length} chat
          </p>
        </div>
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <p className="p-4 text-center text-gray-500">Memuat...</p>
          ) : chats.length === 0 ? (
            <p className="p-4 text-center text-gray-500">
              Belum ada percakapan.
            </p>
          ) : (
            chats.map((c) => (
              <button
                key={c.id}
                onClick={() => setSelectedUserId(c.id)}
                className={`w-full p-4 text-left border-b hover:bg-gray-50 transition ${
                  selectedUserId === c.id ? 'bg-traka-orange/10 border-l-4 border-l-traka-orange' : ''
                }`}
              >
                <div className="font-medium text-gray-800 truncate">
                  {c.displayName || c.id}
                </div>
                <div className="text-sm text-gray-600 truncate mt-0.5">
                  {c.lastMessage || '-'}
                </div>
              </button>
            ))
          )}
        </div>
      </div>

      {/* Area chat */}
      <div className="flex-1 bg-white rounded-lg shadow flex flex-col overflow-hidden">
        {!selectedUserId ? (
          <div className="flex-1 flex items-center justify-center text-gray-500">
            Pilih percakapan di sebelah kiri
          </div>
        ) : (
          <>
            <div className="p-4 border-b bg-gray-50 flex items-center justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-traka-orange flex items-center justify-center text-white font-semibold">
                  {(userInfo?.displayName || selectedUserId)[0]?.toUpperCase() || '?'}
                </div>
                <div>
                  <div className="font-semibold text-gray-800">
                    {userInfo?.displayName || 'User'}
                  </div>
                  <div className="text-sm text-gray-500">
                    {userInfo?.email || userInfo?.phoneNumber || selectedUserId}
                  </div>
                </div>
              </div>
              <button
                onClick={handleCloseChat}
                disabled={closing}
                className="px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 border border-red-200 rounded-lg transition disabled:opacity-50"
              >
                {closing ? 'Memproses...' : 'Akhiri Percakapan'}
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-4 space-y-3 min-h-0">
              {messages.map((m) => {
                const isAdmin = m.senderUid === auth.currentUser?.uid
                return (
                  <div
                    key={m.id}
                    className={`flex ${isAdmin ? 'justify-end' : 'justify-start'}`}
                  >
                    <div
                      className={`max-w-[75%] rounded-2xl px-4 py-2 ${
                        isAdmin
                          ? 'bg-traka-orange text-white'
                          : 'bg-gray-200 text-gray-800'
                      }`}
                    >
                      <p className="text-sm whitespace-pre-wrap">{m.text}</p>
                      <p
                        className={`text-xs mt-1 ${
                          isAdmin ? 'text-white/80' : 'text-gray-500'
                        }`}
                      >
                        {formatTime(m.createdAt)}
                      </p>
                    </div>
                  </div>
                )
              })}
              <div ref={messagesEndRef} />
            </div>

            <div className="p-4 border-t flex gap-2">
              <input
                type="text"
                value={inputText}
                onChange={(e) => setInputText(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && handleSend()}
                placeholder="Ketik pesan..."
                className="flex-1 px-4 py-2 border rounded-full focus:outline-none focus:ring-2 focus:ring-traka-orange"
              />
              <button
                onClick={handleSend}
                disabled={!inputText.trim()}
                className="px-6 py-2 bg-traka-orange text-white rounded-full font-medium hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Kirim
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
