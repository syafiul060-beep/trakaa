const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const { verifyProductPurchase } = require("./lib/verifyGooglePlay.js");
const billingValidation = require("./lib/billingValidation.js");
const publicReceiptProof = require("./lib/publicReceiptProof.js");
const {
  sanitizeDriverSchedulesIfNeeded,
  shouldKeepSlot,
  fetchActiveScheduleIdsForDriver,
} = require("./lib/driverScheduleValidation.js");
const { restoreIfScheduleHasActiveOrders } = require("./lib/scheduleItemDeleteGuard.js");
const navPickupGuard = require("./lib/navigationPickupGuard.js");
const { computeNavPremiumRupiah } = require("./lib/driverNavPremiumPricing.js");

// Load .env untuk development lokal (emulator). Production pakai env var dari Cloud Console.
try {
  require("dotenv").config();
} catch (_) {
  // dotenv opsional
}

// Initialize Firebase Admin SDK
admin.initializeApp();

// Konfigurasi SMTP untuk Gmail - WAJIB via Environment Variables
// Set di Firebase Console > Functions > Environment variables: GMAIL_EMAIL, GMAIL_APP_PASSWORD
function getEmailConfig() {
  const gmailEmail = process.env.GMAIL_EMAIL;
  const gmailAppPassword = process.env.GMAIL_APP_PASSWORD;
  if (!gmailEmail || !gmailAppPassword) {
    throw new Error("GMAIL_EMAIL dan GMAIL_APP_PASSWORD harus dikonfigurasi di Firebase Console > Functions > Environment variables");
  }
  return {
    email: gmailEmail,
    transporter: nodemailer.createTransport({
      service: "gmail",
      auth: { user: gmailEmail, pass: gmailAppPassword },
    }),
  };
}

/** Kirim email kode verifikasi. Throw jika gagal (agar client dapat pesan error). */
async function sendVerificationEmail(toEmail, code) {
  const gmailEmail = process.env.GMAIL_EMAIL;
  const gmailAppPassword = process.env.GMAIL_APP_PASSWORD;
  if (!gmailEmail || !gmailAppPassword) {
    console.error("sendVerificationEmail: GMAIL_EMAIL atau GMAIL_APP_PASSWORD kosong");
    throw new Error("GMAIL_EMAIL dan GMAIL_APP_PASSWORD harus dikonfigurasi di Cloud Functions > Environment variables");
  }
  const textTemplate = `
Halo,

Kode verifikasi Traka Anda: ${code}

Kode berlaku 10 menit. Masukkan di aplikasi.

Jika tidak meminta, abaikan email ini.

Salam, Tim Traka
  `.trim();
  const htmlTemplate = `
<!DOCTYPE html><html><head><meta charset="UTF-8"></head><body style="font-family:Arial;line-height:1.6;color:#333;max-width:600px;margin:0 auto;padding:20px">
  <div style="background:#f9f9f9;padding:30px;border-radius:8px">
    <h2>Kode Verifikasi Traka</h2>
    <p>Kode Anda: <strong style="background:#2563EB;color:white;font-size:24px;padding:10px 20px;border-radius:8px;letter-spacing:4px">${code}</strong></p>
    <p>Berlaku 10 menit.</p>
    <p style="color:#999;font-size:12px">Jika tidak meminta, abaikan.</p>
    <p>Salam,<br>Tim Traka</p>
  </div>
</body></html>
  `.trim();
  const { email: fromEmail, transporter } = getEmailConfig();
  const info = await transporter.sendMail({
    from: `"Traka" <${fromEmail}>`,
    to: toEmail,
    subject: "Kode Verifikasi Traka",
    text: textTemplate,
    html: htmlTemplate,
  });
  console.log("sendVerificationEmail OK:", { to: toEmail, messageId: info.messageId });
}

// Rate limit: max 3 kirim kode per email per 15 menit
const VERIFICATION_CODE_RATE_LIMIT = 3;
const VERIFICATION_CODE_RATE_WINDOW_MS = 15 * 60 * 1000;

// App Check: enforce request hanya dari app resmi (anti-cloning)
// Lihat docs/SETUP_APP_CHECK_DAN_ANTI_CLONING.md
const ENFORCE_APP_CHECK = false;
const callable = ENFORCE_APP_CHECK
  ? functions.runWith({ enforceAppCheck: true }).https
  : functions.https;

// Tahap 4 Scaling: minInstances untuk fungsi auth kritis (kurangi cold start)
// maxInstances 50 untuk produksi 1-5 jt pengguna (wajib >= minInstances)
const callableWarm = ENFORCE_APP_CHECK
  ? functions.runWith({
    enforceAppCheck: true,
    minInstances: 1,
    maxInstances: 50,
    memory: "256MB",
    timeoutSeconds: 60,
  }).https
  : functions.runWith({
    minInstances: 1,
    maxInstances: 50,
    memory: "256MB",
    timeoutSeconds: 60,
  }).https;

/**
 * Kirim FCM dengan collapse/tag agar notifikasi tidak menumpuk.
 * @param {object} basePayload - { notification, data, token, android }
 * @param {string} [collapseKey] - Notifikasi dengan key sama saling menggantikan
 * @param {string} [tag] - Android: notifikasi dengan tag sama digabung
 */
async function sendFcmWithCollapse(basePayload, { collapseKey, tag } = {}) {
  try {
    const payload = { ...basePayload };
    if (payload.android == null) payload.android = {};
    if (payload.android.notification == null) payload.android.notification = {};
    if (collapseKey) payload.android.collapseKey = collapseKey;
    if (tag) payload.android.notification.tag = tag;
    // visibility: public = tampil di lockscreen saat layar mati; priority: max = prioritas tertinggi untuk delivery saat Doze
    payload.android.notification.visibility = "public";
    payload.android.notification.priority = "max";
    // ttl 24 jam: agar pesan tidak dibuang saat device dalam Doze lama (Samsung dll.)
    if (payload.android.ttl == null) payload.android.ttl = 86400000; // 24 jam ms
    await admin.messaging().send(payload);
  } catch (e) {
    console.error("sendFcmWithCollapse error:", e);
  }
}

/** FCM: admin meminta verifikasi dokumen / data tambahan. */
async function sendAdminVerificationRequestFcm(uid, after) {
  try {
    const userSnap = await admin.firestore().collection("users").doc(uid).get();
    if (!userSnap.exists) return;
    const fcmToken = userSnap.data()?.fcmToken;
    if (!fcmToken) {
      console.warn("sendAdminVerificationRequestFcm: fcmToken kosong uid=" + uid);
      return;
    }
    const rawMsg = (after?.adminVerificationMessage || "").trim();
    const body = rawMsg.length > 120
      ? rawMsg.slice(0, 117) + "..."
      : (rawMsg || "Buka aplikasi → Profil untuk melengkapi verifikasi.");
    const title = "Permintaan verifikasi";
    const payload = {
      notification: { title, body },
      data: {
        type: "admin_verification",
        title,
        body,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      token: fcmToken,
      android: {
        priority: "high",
        notification: {
          channelId: "traka_verification_channel",
          priority: "high",
        },
      },
    };
    await sendFcmWithCollapse(payload, {
      collapseKey: `admin_verification_${uid}`,
      tag: `admin_verification_${uid}`,
    });
  } catch (e) {
    console.error("sendAdminVerificationRequestFcm error:", e);
  }
}

/** Escape minimal untuk isi email HTML. */
function escapeHtmlForEmail(s) {
  return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
}

/**
 * Email alert ke GMAIL_EMAIL — saluran utama untuk admin yang hanya pakai traka-admin (web),
 * karena panel web tidak mengisi fcmToken (tidak ada FCM web di project ini).
 * Tidak throw — gagal email hanya di-log.
 */
async function sendAdminInboundEmail({ title, body, meta = {} }) {
  const gmailEmail = process.env.GMAIL_EMAIL;
  const gmailAppPassword = process.env.GMAIL_APP_PASSWORD;
  if (!gmailEmail || !gmailAppPassword) {
    console.warn(
        "sendAdminInboundEmail: GMAIL_EMAIL / GMAIL_APP_PASSWORD kosong, skip email",
    );
    return;
  }
  try {
    const { email: fromEmail, transporter } = getEmailConfig();
    const metaStr = JSON.stringify(meta);
    const text = `${title}\n\n${body}\n\n---\nTraka Admin (web). Buka panel Pengguna.\nMeta: ${metaStr}`;
    const html = `
<!DOCTYPE html><html><head><meta charset="UTF-8"></head>
<body style="font-family:Arial,sans-serif;line-height:1.5;color:#333;max-width:560px;margin:0 auto;padding:16px">
  <p style="margin:0 0 8px 0"><strong>${escapeHtmlForEmail(title)}</strong></p>
  <p style="margin:0 0 16px 0;white-space:pre-wrap">${escapeHtmlForEmail(body)}</p>
  <p style="color:#666;font-size:12px;margin:0">
    Panel admin hanya di web — notifikasi ini dikirim ke email operasional.
    Buka <strong>traka-admin → Pengguna</strong> untuk detail.
  </p>
  <p style="color:#999;font-size:11px;margin-top:12px">Meta: ${escapeHtmlForEmail(metaStr)}</p>
</body></html>`.trim();
    await transporter.sendMail({
      from: `"Traka Admin" <${fromEmail}>`,
      to: gmailEmail,
      subject: `[Traka] ${title}`,
      text,
      html,
    });
    console.log("sendAdminInboundEmail OK to", gmailEmail);
  } catch (e) {
    console.error("sendAdminInboundEmail error:", e);
  }
}

/**
 * Simpan ke Firestore untuk halaman Notifikasi di traka-admin (baca riwayat + detail).
 */
async function persistAdminNotification({ title, body, data = {} }) {
  try {
    const uid = data.userIdSubject ? String(data.userIdSubject) : "";
    let userLabel = "";
    let userEmail = "";
    if (uid) {
      const uSnap = await admin.firestore().collection("users").doc(uid).get();
      if (uSnap.exists) {
        const d = uSnap.data();
        userLabel = String(d.displayName || d.email || uid).slice(0, 200);
        userEmail = d.email ? String(d.email) : "";
      }
    }
    await admin.firestore().collection("admin_notifications").add({
      type: String(data.type || "admin_inbound").slice(0, 120),
      eventType: String(data.eventType || "").slice(0, 120),
      title: String(title || "").slice(0, 300),
      body: String(body || "").slice(0, 4000),
      userId: uid || null,
      userLabel: userLabel || null,
      userEmail: userEmail || null,
      metaJson: JSON.stringify(data),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      readAt: null,
    });
  } catch (e) {
    console.error("persistAdminNotification error:", e);
  }
}

/**
 * Beri tahu admin: (1) email ke GMAIL_EMAIL selalu jika SMTP diset — utama untuk admin web;
 * (2) FCM opsional ke users role=admin yang kebetulan punya fcmToken (mis. uji di app).
 */
async function notifyAdminsFcm({ title, body, data = {} }) {
  try {
    await persistAdminNotification({ title, body, data });
    await sendAdminInboundEmail({
      title,
      body,
      meta: data,
    });

    const snap = await admin.firestore()
        .collection("users")
        .where("role", "==", "admin")
        .get();
    if (snap.empty) {
      console.warn("notifyAdminsFcm: tidak ada dokumen users dengan role=admin (FCM dilewati)");
      return;
    }
    const baseData = {
      type: data.type || "admin_inbound",
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      ...data,
    };
    let sent = 0;
    for (const doc of snap.docs) {
      const token = doc.data()?.fcmToken;
      if (!token || typeof token !== "string" || !token.trim()) continue;
      const payload = {
        notification: { title, body },
        data: {
          ...baseData,
          title,
          body,
        },
        token: token.trim(),
        android: {
          priority: "high",
          notification: {
            channelId: "traka_verification_channel",
            priority: "high",
          },
        },
      };
      const subj = (data.userIdSubject || "").toString();
      const ev = (data.eventType || "alert").toString();
      await sendFcmWithCollapse(payload, {
        collapseKey: `admin_inbound_${ev}_${subj}_${doc.id}`,
        tag: `admin_inbound_${ev}_${subj}`,
      });
      sent++;
    }
    if (sent === 0) {
      console.warn("notifyAdminsFcm: tidak ada admin dengan fcmToken (email sudah dikirim jika SMTP OK)");
    }
  } catch (e) {
    console.error("notifyAdminsFcm error:", e);
  }
}

/** Kirim FCM notifikasi pengingat bayar (kontribusi driver / pelanggaran). */
async function sendPaymentReminderFcm(uid, type) {
  try {
    const userSnap = await admin.firestore().collection("users").doc(uid).get();
    if (!userSnap.exists) return;
    const fcmToken = userSnap.data()?.fcmToken;
    if (!fcmToken) {
      console.warn("sendPaymentReminderFcm: fcmToken kosong untuk uid=" + uid);
      return;
    }
    const title = type === "kontribusi"
      ? "Bayar kontribusi"
      : "Bayar pelanggaran";
    const body = type === "kontribusi"
      ? "Anda punya kewajiban bayar kontribusi. Buka aplikasi untuk membayar."
      : "Anda punya pelanggaran yang perlu dibayar. Buka aplikasi untuk membayar.";
    const payload = {
      notification: { title, body },
      data: { type: "payment_reminder", paymentType: type },
      token: fcmToken,
      android: {
        priority: "high",
        notification: { channelId: "traka_payment_channel", priority: "high" },
      },
    };
    await sendFcmWithCollapse(payload, { collapseKey: "payment", tag: `payment_${uid}` });
  } catch (e) {
    console.error("sendPaymentReminderFcm error:", e);
  }
}

// DEPRECATED (Tahap 2 Phone Auth): Daftar pakai Phone OTP, bukan email.
// Callable: app memanggil ini untuk minta kode verifikasi (bypass Firestore rules)
// Admin SDK menulis ke Firestore, lalu trigger sendVerificationCode kirim email
exports.requestVerificationCode = callableWarm.onCall(async (data, _context) => {
  const email = data?.email;
  if (!email || typeof email !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  if (!/^[\w.-]+@[\w.-]+\.\w+$/.test(trimmedEmail)) {
    throw new functions.https.HttpsError("invalid-argument", "Format email tidak valid.");
  }

  // Rate limit: cek attempts
  const rateRef = admin.firestore()
      .collection("verification_code_attempts")
      .doc(trimmedEmail);
  const rateSnap = await rateRef.get();
  const now = Date.now();
  if (rateSnap.exists) {
    const d = rateSnap.data();
    const attempts = (d?.attempts || 0);
    const lastAt = d?.lastAttemptAt?.toMillis?.() || 0;
    if (attempts >= VERIFICATION_CODE_RATE_LIMIT &&
        (now - lastAt) < VERIFICATION_CODE_RATE_WINDOW_MS) {
      const waitMin = Math.ceil((VERIFICATION_CODE_RATE_WINDOW_MS - (now - lastAt)) / 60000);
      throw new functions.https.HttpsError(
          "resource-exhausted",
          `Terlalu banyak permintaan. Coba lagi dalam ${waitMin} menit.`,
      );
    }
    // Reset jika window sudah lewat
    if ((now - lastAt) >= VERIFICATION_CODE_RATE_WINDOW_MS) {
      await rateRef.set({
        attempts: 1,
        lastAttemptAt: admin.firestore.Timestamp.now(),
      });
    } else {
      await rateRef.update({
        attempts: admin.firestore.FieldValue.increment(1),
        lastAttemptAt: admin.firestore.Timestamp.now(),
      });
    }
  } else {
    await rateRef.set({
      attempts: 1,
      lastAttemptAt: admin.firestore.Timestamp.now(),
    });
  }

  // Cek apakah email sudah terdaftar
  const usersSnap = await admin.firestore()
      .collection("users")
      .where("email", "==", trimmedEmail)
      .limit(1)
      .get();
  if (!usersSnap.empty) {
    throw new functions.https.HttpsError(
        "already-exists",
        "Email sudah terdaftar. Gunakan email lainnya yang aktif.",
    );
  }

  // Generate kode 6 digit
  const code = String(100000 + Math.floor(Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 menit

  const ref = admin.firestore().collection("verification_codes").doc(trimmedEmail);

  await ref.delete();
  await ref.set({
    code,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Kirim email langsung (bukan via trigger) agar error bisa dikembalikan ke client
  try {
    await sendVerificationEmail(trimmedEmail, code);
  } catch (err) {
    console.error("sendVerificationEmail error:", err);
    const msg = err.message || String(err);
    if (msg.includes("GMAIL_EMAIL") || msg.includes("GMAIL_APP_PASSWORD")) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Konfigurasi email belum lengkap. Hubungi admin.",
      );
    }
    if (msg.includes("Invalid login") || msg.includes("Authentication")) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Gagal mengirim email. Periksa Gmail App Password.",
      );
    }
    throw new functions.https.HttpsError(
        "internal",
        "Gagal mengirim kode verifikasi ke email. Coba lagi.",
    );
  }

  return { success: true };
});

// --- Keamanan: cek email terdaftar (tanpa auth, untuk login/register) ---
exports.checkEmailExists = callable.onCall(async (data) => {
  const email = data?.email;
  if (!email || typeof email !== "string") {
    return { exists: false };
  }
  const trimmed = email.trim().toLowerCase();
  if (!/^[\w.-]+@[\w.-]+\.\w+$/.test(trimmed)) {
    return { exists: false };
  }
  const snap = await admin.firestore()
      .collection("users")
      .where("email", "==", trimmed)
      .limit(1)
      .get();
  const doc = snap.docs[0];
  return {
    exists: !snap.empty,
    uid: doc ? doc.id : null,
  };
});

// --- Keamanan: cek nomor telepon terdaftar (PRIMARY untuk Phone Auth - daftar/login) ---
exports.checkPhoneExists = callable.onCall(async (data) => {
  const phone = data?.phone;
  if (!phone || typeof phone !== "string") {
    return { exists: false };
  }
  let normalized = phone.replace(/\D/g, "");
  if (normalized.startsWith("0")) normalized = "62" + normalized.substring(1);
  if (!normalized.startsWith("62")) normalized = "62" + normalized;
  const phoneE164 = "+" + normalized;
  const snap = await admin.firestore()
      .collection("users")
      .where("phoneNumber", "==", phoneE164)
      .limit(1)
      .get();
  const doc = snap.docs[0];
  return {
    exists: !snap.empty,
    uid: doc ? doc.id : null,
  };
});

// --- Login terpadu: dapatkan authEmail untuk login phone+password (user baru pakai email+password) ---
// User lama (phone OTP only): legacy=true, pakai OTP. User baru (phone+password): authEmail untuk signInWithEmailAndPassword.
function normalizePhoneForAuth(phone) {
  let normalized = (phone || "").replace(/\D/g, "");
  if (normalized.startsWith("0")) normalized = "62" + normalized.substring(1);
  if (!normalized.startsWith("62")) normalized = "62" + normalized;
  return normalized;
}

exports.getPhoneLoginEmail = callable.onCall(async (data) => {
  const phone = data?.phone;
  if (!phone || typeof phone !== "string") {
    return { exists: false };
  }
  const normalized = normalizePhoneForAuth(phone);
  const phoneE164 = "+" + normalized;
  const authEmail = normalized + "@traka.phone";

  const snap = await admin.firestore()
      .collection("users")
      .where("phoneNumber", "==", phoneE164)
      .limit(1)
      .get();
  if (snap.empty) {
    return { exists: false };
  }
  const uid = snap.docs[0].id;

  try {
    const fbUser = await admin.auth().getUser(uid);
    const isNewPhonePassword = fbUser.email === authEmail;
    const isPhoneOnly = fbUser.providerData?.some((p) => p.providerId === "phone") && !fbUser.email;

    if (isNewPhonePassword) {
      return { exists: true, authEmail };
    }
    // User sudah tambah/ubah email (bukan @traka.phone) → login pakai email+password
    if (fbUser.email && fbUser.email.trim()) {
      return { exists: true, authEmail: fbUser.email.trim().toLowerCase() };
    }
    if (isPhoneOnly) {
      return { exists: true, legacy: true };
    }
    return { exists: true, legacy: true };
  } catch (_) {
    return { exists: true, legacy: true };
  }
});

// --- Keamanan: cek apakah registrasi diperbolehkan (device + role) ---
exports.checkRegistrationAllowed = callable.onCall(async (data) => {
  const installId = (data?.installId || "").toString().trim();
  const deviceId = (data?.deviceId || "").toString().trim();
  const role = (data?.role || "").toString();
  if (role !== "penumpang" && role !== "driver") {
    return { allowed: false, message: "Role tidak valid." };
  }
  const db = admin.firestore();

  // 1. Cek device_accounts via installId
  if (installId) {
    const doc = await db.collection("device_accounts").doc(installId).get();
    const data = doc.data();
    const existingRoleUid = role === "penumpang"
        ? (data?.["penumpangUid"])
        : (data?.["driverUid"]);
    if (existingRoleUid) {
      return {
        allowed: false,
        message: role === "driver"
            ? "Perangkat ini sudah terdaftar sebagai driver. Silakan login."
            : "Perangkat ini sudah terdaftar sebagai penumpang. Silakan login.",
      };
    }
    const query = await db.collection("device_accounts")
        .where("installId", "==", installId)
        .limit(1)
        .get();
    for (const d of query.docs) {
      const ddata = d.data();
      const existing = role === "penumpang" ? ddata["penumpangUid"] : ddata["driverUid"];
      if (existing) {
        return {
          allowed: false,
          message: role === "driver"
              ? "Perangkat ini sudah terdaftar sebagai driver. Silakan login."
              : "Perangkat ini sudah terdaftar sebagai penumpang. Silakan login.",
        };
      }
    }
  }

  // 2. Cek users (deviceId + role)
  if (deviceId) {
    const usersSnap = await db.collection("users")
        .where("deviceId", "==", deviceId)
        .where("role", "==", role)
        .limit(1)
        .get();
    if (!usersSnap.empty) {
      return {
        allowed: false,
        message: role === "driver"
            ? "Perangkat ini sudah terdaftar sebagai driver. Silakan login."
            : "Perangkat ini sudah terdaftar sebagai penumpang. Silakan login.",
      };
    }
  }
  return { allowed: true };
});

// --- Tahap 3: device_rate_limit dipindah ke Cloud Function (keamanan) ---
const LOGIN_RATE_LIMIT_MAX_FAILED = 10;
const LOGIN_RATE_LIMIT_HOURS = 1;
const COLLECTION_DEVICE_RATE_LIMIT = "device_rate_limit";

exports.checkLoginRateLimit = callable.onCall(async (data) => {
  const deviceKey = (data?.deviceKey || "").toString().trim();
  if (!deviceKey) {
    return { allowed: true };
  }
  const db = admin.firestore();
  const ref = db.collection(COLLECTION_DEVICE_RATE_LIMIT).doc(deviceKey);
  const doc = await ref.get();
  if (!doc.exists) {
    return { allowed: true };
  }
  const d = doc.data();
  const failedCount = (d?.failedCount || 0);
  const firstFailedAt = d?.firstFailedAt?.toDate?.();
  if (failedCount < LOGIN_RATE_LIMIT_MAX_FAILED) {
    return { allowed: true };
  }
  if (firstFailedAt) {
    const hoursSince = (Date.now() - firstFailedAt.getTime()) / (1000 * 60 * 60);
    if (hoursSince >= LOGIN_RATE_LIMIT_HOURS) {
      await ref.delete();
      return { allowed: true };
    }
  }
  return {
    allowed: false,
    message: `Terlalu banyak percobaan login gagal. Coba lagi dalam ${LOGIN_RATE_LIMIT_HOURS} jam.`,
  };
});

exports.recordLoginFailed = callable.onCall(async (data) => {
  const deviceKey = (data?.deviceKey || "").toString().trim();
  const osVersion = (data?.osVersion || "").toString();
  const model = (data?.model || "").toString();
  if (!deviceKey) return;
  const db = admin.firestore();
  const ref = db.collection(COLLECTION_DEVICE_RATE_LIMIT).doc(deviceKey);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.data();
    const failedCount = (d?.failedCount || 0) + 1;
    let firstFailedAt = d?.firstFailedAt?.toDate?.();
    if (!firstFailedAt) firstFailedAt = new Date();
    tx.set(ref, {
      failedCount,
      firstFailedAt: admin.firestore.Timestamp.fromDate(firstFailedAt),
      osVersion,
      model,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
});

exports.recordLoginSuccess = callable.onCall(async (data) => {
  const deviceKey = (data?.deviceKey || "").toString().trim();
  if (!deviceKey) return;
  const ref = admin.firestore()
      .collection(COLLECTION_DEVICE_RATE_LIMIT)
      .doc(deviceKey);
  await ref.delete();
});

// --- Counter: generate nomor pesanan (hanya Cloud Function tulis counters) ---
exports.generateOrderNumber = callableWarm.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login diperlukan.");
  }
  const now = new Date();
  const dateStr = now.getFullYear() +
    String(now.getMonth() + 1).padStart(2, "0") +
    String(now.getDate()).padStart(2, "0");
  const ref = admin.firestore().collection("counters").doc("order_number");
  const result = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.data()?.lastSequence || 0);
    const next = current + 1;
    tx.set(ref, { lastSequence: next }, { merge: true });
    return `TRK-${dateStr}-${String(next).padStart(6, "0")}`;
  });
  return { orderNumber: result };
});

// --- Counter: generate nomor rute perjalanan (hanya Cloud Function tulis counters) ---
exports.generateRouteJourneyNumber = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login diperlukan.");
  }
  const now = new Date();
  const dateStr = now.getFullYear() +
    String(now.getMonth() + 1).padStart(2, "0") +
    String(now.getDate()).padStart(2, "0");
  const ref = admin.firestore().collection("counters").doc("route_journey_number");
  const result = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.data()?.lastSequence || 0);
    const next = current + 1;
    tx.set(ref, { lastSequence: next }, { merge: true });
    return `RUTE-${dateStr}-${String(next).padStart(6, "0")}`;
  });
  return { routeJourneyNumber: result };
});

// DEPRECATED (Tahap 2 Phone Auth): Verifikasi OTP di-handle Firebase, bukan custom kode.
// --- Keamanan: verifikasi kode registrasi email (baca, validasi, hapus jika valid) ---
exports.verifyRegistrationCode = callable.onCall(async (data) => {
  const email = (data?.email || "").toString().trim().toLowerCase();
  const code = (data?.code || "").toString().trim();
  if (!email || !code || !/^[\w.-]+@[\w.-]+\.\w+$/.test(email)) {
    return { valid: false, reason: "invalid-input" };
  }
  const ref = admin.firestore().collection("verification_codes").doc(email);
  const doc = await ref.get();
  if (!doc.exists) {
    return { valid: false, reason: "not-found" };
  }
  const d = doc.data();
  const savedCode = (d?.code || "").toString();
  const expiresAt = d?.expiresAt?.toDate?.();
  if (!expiresAt || new Date() > expiresAt) {
    return { valid: false, reason: "expired" };
  }
  if (code !== savedCode) {
    return { valid: false, reason: "mismatch" };
  }
  await ref.delete();
  return { valid: true };
});

// --- Ubah email profil: verifikasi OTP lalu update via Admin SDK (untuk user login) ---
exports.verifyAndUpdateProfileEmail = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const email = (data?.email || "").toString().trim().toLowerCase();
  const code = (data?.code || "").toString().trim();
  if (!email || !code || !/^[\w.-]+@[\w.-]+\.\w+$/.test(email)) {
    throw new functions.https.HttpsError("invalid-argument", "Email dan kode wajib diisi.");
  }
  const ref = admin.firestore().collection("verification_codes").doc(email);
  const doc = await ref.get();
  if (!doc.exists) {
    throw new functions.https.HttpsError("failed-precondition", "Kode tidak ditemukan atau sudah kadaluarsa.");
  }
  const d = doc.data();
  const savedCode = (d?.code || "").toString();
  const expiresAt = d?.expiresAt?.toDate?.();
  if (!expiresAt || new Date() > expiresAt) {
    throw new functions.https.HttpsError("failed-precondition", "Kode sudah kadaluarsa.");
  }
  if (code !== savedCode) {
    throw new functions.https.HttpsError("invalid-argument", "Kode tidak sesuai.");
  }
  await ref.delete();
  await admin.auth().updateUser(uid, { email });
  await admin.firestore().collection("users").doc(uid).update({ email });
  return { success: true };
});

// DEPRECATED (Tahap 2 Phone Auth): Phone Auth tidak pakai password, lupa sandi tidak relevan.
// --- Lupa kata sandi: kirim kode OTP ke email (hanya untuk email yang sudah terdaftar) ---
exports.requestForgotPasswordCode = callable.onCall(async (data, _context) => {
  const email = data?.email;
  if (!email || typeof email !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  if (!/^[\w.-]+@[\w.-]+\.\w+$/.test(trimmedEmail)) {
    throw new functions.https.HttpsError("invalid-argument", "Format email tidak valid.");
  }

  const usersSnap = await admin.firestore()
      .collection("users")
      .where("email", "==", trimmedEmail)
      .limit(1)
      .get();
  if (usersSnap.empty) {
    throw new functions.https.HttpsError(
        "not-found",
        "Email tidak terdaftar.",
    );
  }
  const uid = usersSnap.docs[0].id;

  const code = String(100000 + Math.floor(Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 menit

  const ref = admin.firestore().collection("forgot_password_codes").doc(trimmedEmail);
  await ref.delete();
  await ref.set({
    code,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const textTemplate = `
Halo,

Anda meminta kode verifikasi untuk atur ulang kata sandi Traka.

Kode verifikasi Anda: ${code}

Kode ini berlaku 10 menit. Masukkan di aplikasi, lalu verifikasi wajah dan buat kata sandi baru.

Jika Anda tidak meminta ini, abaikan email ini.

Salam,
Tim Traka
  `.trim();

  const htmlTemplate = `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Arial;line-height:1.6;color:#333;max-width:600px;margin:0 auto;padding:20px;">
  <div style="background:#f9f9f9;padding:30px;border-radius:8px;">
    <h2>Lupa kata sandi</h2>
    <p>Kode verifikasi Anda:</p>
    <div style="background:#2563EB;color:white;font-size:32px;font-weight:bold;text-align:center;padding:20px;border-radius:8px;letter-spacing:5px;">${code}</div>
    <p>Berlaku 10 menit. Masukkan di aplikasi, lalu verifikasi wajah dan buat kata sandi baru.</p>
    <p style="color:#999;font-size:12px;">Jika Anda tidak meminta ini, abaikan email ini.</p>
    <p>Salam,<br>Tim Traka</p>
  </div>
</body>
</html>
  `.trim();

  try {
    const { email, transporter } = getEmailConfig();
    await transporter.sendMail({
      from: `"Traka" <${email}>`,
      to: trimmedEmail,
      subject: "Kode verifikasi lupa kata sandi - Traka",
      text: textTemplate,
      html: htmlTemplate,
    });
  } catch (err) {
    console.error("requestForgotPasswordCode sendMail error:", err);
    throw new functions.https.HttpsError("internal", "Gagal mengirim email. Coba lagi.");
  }

  return { success: true };
});

// DEPRECATED (Tahap 2 Phone Auth): Login via Phone OTP, device terverifikasi tiap login.
// --- Login pertama (no phone): kirim OTP ke email untuk verifikasi device ---
exports.requestLoginVerificationCode = callableWarm.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const email = data?.email;
  if (!email || typeof email !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  if (!/^[\w.-]+@[\w.-]+\.\w+$/.test(trimmedEmail)) {
    throw new functions.https.HttpsError("invalid-argument", "Format email tidak valid.");
  }

  const userSnap = await admin.firestore().collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }
  const userEmail = (userSnap.data()?.email || "").trim().toLowerCase();
  if (userEmail !== trimmedEmail) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Email tidak sesuai dengan akun Anda.",
    );
  }

  const code = String(100000 + Math.floor(Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 menit

  const ref = admin.firestore().collection("login_verification_codes").doc(uid);
  await ref.delete();
  await ref.set({
    code,
    email: trimmedEmail,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const textTemplate = `
Halo,

Anda meminta kode verifikasi untuk login pertama di perangkat baru Traka.

Kode verifikasi Anda: ${code}

Kode ini berlaku 10 menit.

Jika Anda tidak meminta ini, abaikan email ini.

Salam,
Tim Traka
  `.trim();

  const htmlTemplate = `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Arial;line-height:1.6;color:#333;max-width:600px;margin:0 auto;padding:20px;">
  <div style="background:#f9f9f9;padding:30px;border-radius:8px;">
    <h2>Verifikasi login</h2>
    <p>Kode verifikasi Anda:</p>
    <div style="background:#2563EB;color:white;font-size:32px;font-weight:bold;text-align:center;padding:20px;border-radius:8px;letter-spacing:5px;">${code}</div>
    <p>Berlaku 10 menit.</p>
    <p style="color:#999;font-size:12px;">Jika Anda tidak meminta ini, abaikan email ini.</p>
    <p>Salam,<br>Tim Traka</p>
  </div>
</body>
</html>
  `.trim();

  try {
    const { email, transporter } = getEmailConfig();
    await transporter.sendMail({
      from: `"Traka" <${email}>`,
      to: trimmedEmail,
      subject: "Kode verifikasi login - Traka",
      text: textTemplate,
      html: htmlTemplate,
    });
  } catch (err) {
    console.error("requestLoginVerificationCode sendMail error:", err);
    throw new functions.https.HttpsError("internal", "Gagal mengirim email. Coba lagi.");
  }

  return { success: true };
});

// DEPRECATED (Tahap 2 Phone Auth): Login via Phone OTP, tidak perlu verifikasi email.
// --- Login pertama: verifikasi OTP email ---
exports.verifyLoginVerificationCode = callableWarm.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const code = data?.code;
  if (!code || typeof code !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Kode wajib diisi.");
  }
  const trimmedCode = code.trim();

  const ref = admin.firestore().collection("login_verification_codes").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Kode tidak ditemukan atau sudah dipakai. Kirim ulang kode.");
  }
  const d = snap.data();
  const savedCode = d.code;
  const expiresAt = d.expiresAt?.toDate?.() || new Date(0);

  if (trimmedCode !== savedCode) {
    throw new functions.https.HttpsError("invalid-argument", "Kode verifikasi tidak sesuai.");
  }
  if (new Date() > expiresAt) {
    await ref.delete();
    throw new functions.https.HttpsError("failed-precondition", "Kode sudah kedaluwarsa. Kirim ulang kode.");
  }

  await ref.delete();
  return { success: true };
});

// DEPRECATED (Tahap 2 Phone Auth): Phone Auth tidak pakai password.
// --- Lupa kata sandi: verifikasi OTP email, kembalikan custom token untuk sign in ---
exports.verifyForgotPasswordOtpAndGetToken = callable.onCall(async (data, _context) => {
  const email = data?.email;
  const code = data?.code;
  if (!email || typeof email !== "string" || !code || typeof code !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "Email dan kode wajib diisi.");
  }
  const trimmedEmail = email.trim().toLowerCase();
  const trimmedCode = code.trim();

  const ref = admin.firestore().collection("forgot_password_codes").doc(trimmedEmail);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Kode tidak ditemukan atau sudah dipakai. Kirim ulang kode.");
  }
  const d = snap.data();
  const savedCode = d.code;
  const expiresAt = d.expiresAt?.toDate?.() || new Date(0);
  const uid = d.uid;

  if (trimmedCode !== savedCode) {
    throw new functions.https.HttpsError("invalid-argument", "Kode verifikasi tidak sesuai.");
  }
  if (new Date() > expiresAt) {
    await ref.delete();
    throw new functions.https.HttpsError("failed-precondition", "Kode sudah kedaluwarsa. Kirim ulang kode.");
  }

  const customToken = await admin.auth().createCustomToken(uid);
  await ref.delete();

  return { customToken };
});

// DEPRECATED: Email sekarang dikirim langsung di requestVerificationCode
// (trigger sendVerificationCode dihapus agar error bisa dikembalikan ke client)

// --- Notifikasi: ketika order baru dibuat, driver dapat notifikasi ---
exports.onOrderCreated = functions.firestore
    .document("orders/{orderId}")
    .onCreate(async (snap, context) => {
      const orderId = context.params.orderId;
      const data = snap.data();
      const driverUid = data.driverUid || "";
      const passengerName = (data.passengerName || "Penumpang").trim();
      if (!driverUid) return null;

      const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
      if (!driverSnap.exists) return null;
      const fcmToken = driverSnap.data()?.fcmToken;
      if (!fcmToken) return null;

      const payload = {
        notification: {
          title: "Permintaan travel baru",
          body: `${passengerName} ingin pesan travel. Buka chat untuk kesepakatan harga.`,
        },
        data: {
          type: "order",
          orderId,
          passengerName,
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "traka_chat",
            priority: "high",
          },
        },
      };
      try {
        await sendFcmWithCollapse(payload, {
          collapseKey: `order_${orderId}`,
          tag: `order_${orderId}`,
        });
      } catch (e) {
        console.error("FCM onOrderCreated error:", e);
      }
      return null;
    });

// --- Notifikasi: ketika penumpang setuju kesepakatan, driver dapat notifikasi ---
exports.onPassengerAgreed = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      const orderId = context.params.orderId;
      const before = change.before.data();
      const after = change.after.data();
      
      // Cek apakah passengerAgreed berubah dari false ke true dan status menjadi 'agreed'
      const beforePassengerAgreed = before.passengerAgreed || false;
      const afterPassengerAgreed = after.passengerAgreed || false;
      const afterStatus = after.status || "";
      const driverUid = after.driverUid || "";
      const passengerName = (after.passengerName || "Penumpang").trim();
      
      // Hanya kirim notifikasi jika:
      // 1. passengerAgreed berubah dari false ke true
      // 2. Status menjadi 'agreed' (keduanya sudah setuju)
      // 3. Driver UID valid
      if (!beforePassengerAgreed && afterPassengerAgreed && afterStatus === "agreed" && driverUid) {
        // Ambil FCM token driver
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        if (!driverSnap.exists) return null;
        const fcmToken = driverSnap.data()?.fcmToken;
        if (!fcmToken) return null;

        const payload = {
          notification: {
            title: "Kesepakatan telah terjadi",
            body: `${passengerName} telah menyetujui kesepakatan. Pesanan aktif.`,
          },
          data: {
            type: "order_agreed",
            orderId,
            passengerName,
          },
          token: fcmToken,
          android: {
            priority: "high",
            notification: {
              channelId: "traka_chat",
              priority: "high",
            },
          },
        };
        try {
          await sendFcmWithCollapse(payload, {
            collapseKey: `order_${orderId}`,
            tag: `order_${orderId}`,
          });
        } catch (e) {
          console.error("FCM onPassengerAgreed error:", e);
        }
      }
      return null;
    });

// --- Notifikasi chat: ketika penumpang kirim pesan, driver dapat notifikasi ---
// Trigger saat ada pesan baru di orders/{orderId}/messages
const { containsBlockedContent } = require("./chatFilter");

exports.onChatMessageCreated = functions.firestore
    .document("orders/{orderId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const orderId = context.params.orderId;
      const messageId = context.params.messageId;
      const messageData = snap.data();
      const senderUid = messageData.senderUid || "";
      const messageType = messageData.type || "text";
      const text = (messageData.text || "").trim();

      // Filter server-side: hapus pesan teks yang mengarahkan ke luar aplikasi
      if (messageType === "text" && text && containsBlockedContent(text)) {
        try {
          await snap.ref.delete();
        } catch (e) {
          console.error("chatFilter: Gagal hapus pesan", orderId, messageId, e);
        }
        return null;
      }
      
      // Tentukan teks notifikasi berdasarkan type pesan
      let notificationText = text;
      let lastMessageText = text;
      
      if (!text || messageType !== "text") {
        // Untuk pesan non-text, gunakan teks default
        if (messageType === "audio") {
          const duration = messageData.audioDuration || 0;
          const durationText = duration > 0 ? ` (${duration}s)` : "";
          notificationText = `🎤 Pesan suara${durationText}`;
          lastMessageText = `🎤 Pesan suara${durationText}`;
        } else if (messageType === "image") {
          notificationText = "📷 Foto";
          lastMessageText = "📷 Foto";
        } else if (messageType === "video") {
          notificationText = "🎥 Video";
          lastMessageText = "🎥 Video";
        } else if (messageType === "barcode_passenger" || messageType === "barcode_driver") {
          notificationText = "📷 Barcode";
          lastMessageText = "📷 Barcode";
        } else if (messageType === "voice_call_status") {
          notificationText = text || "Panggilan suara";
          lastMessageText = text || "Panggilan suara";
        } else if (messageType === "text") {
          notificationText = text.slice(0, 150) || "Pesan baru";
          lastMessageText = text.slice(0, 100) || "Pesan baru";
        } else {
          notificationText = "Pesan baru";
          lastMessageText = "Pesan baru";
        }
      }

      const orderRef = admin.firestore().collection("orders").doc(orderId);
      const orderSnap = await orderRef.get();
      if (!orderSnap.exists) return null;
      const orderData = orderSnap.data();
      const driverUid = orderData.driverUid || "";
      const passengerUid = orderData.passengerUid || "";
      const passengerName = (orderData.passengerName || "Penumpang").trim();
      let driverName = (orderData.driverName || "").trim();
      if (!driverName && driverUid) {
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        driverName = (driverSnap.exists && driverSnap.data()?.displayName) ? driverSnap.data().displayName.trim() : "Driver";
      }
      if (!driverName) driverName = "Driver";

      // Tentukan siapa yang menerima notifikasi
      let recipientUid = "";
      let senderName = "";
      
      if (senderUid === passengerUid) {
        // Penumpang mengirim → kirim notifikasi ke driver
        recipientUid = driverUid;
        senderName = passengerName;
      } else if (senderUid === driverUid) {
        // Driver mengirim → kirim notifikasi ke penumpang
        recipientUid = passengerUid;
        senderName = driverName;
      } else {
        // Sender tidak dikenal, skip
        return null;
      }

      if (!recipientUid) return null;

      // Cooldown 2 menit: kurangi spam notifikasi chat (notifikasi tertumpuk)
      const CHAT_NOTIFICATION_COOLDOWN_MS = 2 * 60 * 1000;
      const lastChatNotif = orderData.lastChatNotificationAt;
      const nowMs = Date.now();
      const lastMs = lastChatNotif && typeof lastChatNotif.toMillis === "function"
        ? lastChatNotif.toMillis() : 0;
      const inCooldown = lastMs > 0 && (nowMs - lastMs) < CHAT_NOTIFICATION_COOLDOWN_MS;

      // Update order untuk badge unread (lastMessageAt, lastMessageSenderUid, lastMessageText)
      const now = admin.firestore.FieldValue.serverTimestamp();
      const updateData = {
        lastMessageAt: now,
        lastMessageSenderUid: senderUid,
        lastMessageText: lastMessageText.slice(0, 100),
      };
      if (!inCooldown) {
        updateData.lastChatNotificationAt = now;
      }
      await orderRef.update(updateData);

      // voice_call_status: pesan sistem panggilan (tidak terjawab/ditolak/terjawab) - tidak kirim FCM
      if (messageType === "voice_call_status") return null;

      // Skip FCM jika dalam cooldown (kurangi spam notifikasi saat chat aktif)
      if (inCooldown) return null;

      // Jangan kirim notifikasi palsu: skip jika konten kosong/tidak bermakna.
      // Notifikasi "Pesan baru" saat diklik menampilkan chat kosong (pengalaman buruk penumpang).
      if (!notificationText || notificationText === "Pesan baru") return null;

      // Ambil FCM token penerima dari users/{recipientUid}
      const recipientSnap = await admin.firestore().collection("users").doc(recipientUid).get();
      if (!recipientSnap.exists) return null;
      const fcmToken = recipientSnap.data()?.fcmToken;
      if (!fcmToken) return null;

      const notifBody = notificationText.slice(0, 150);
      const dataPayload = {
        type: "chat",
        orderId: String(orderId),
        messageType: String(messageType || ""),
        senderName: String(senderName),
        title: String(senderName),
        body: String(notifBody),
      };
      if (recipientUid === passengerUid) {
        dataPayload.driverUid = String(driverUid);
        dataPayload.driverName = String(driverName);
      }
      // Android: data-only + priority high agar onBackgroundMessage jalan & payload tap ke chat utuh.
      // iOS: APNS alert (sama seperti panggilan suara).
      try {
        await admin.messaging().send({
          token: fcmToken,
          data: dataPayload,
          android: {
            priority: "high",
            ttl: 86400000,
            collapseKey: `chat_${orderId}`,
          },
          apns: {
            headers: {
              "apns-priority": "10",
            },
            payload: {
              aps: {
                alert: {
                  title: senderName,
                  body: notifBody,
                },
                sound: "default",
              },
            },
          },
        });
      } catch (e) {
        console.error("FCM send error:", e);
      }
      return null;
    });

// --- Notifikasi: driver scan barcode penumpang → penumpang dapat notifikasi "Anda sudah dijemput" ---
// --- Notifikasi: penumpang scan barcode driver → driver dapat notifikasi "Penumpang sudah sampai" ---
// --- Audit log: catat setiap scan untuk investigasi dan monitoring jangka panjang ---
exports.onOrderUpdatedScan = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      const orderId = context.params.orderId;
      const before = change.before.data();
      const after = change.after.data();
      // Audit log: catat scan untuk investigasi dan monitoring
      const pickupScannedBefore = before.passengerScannedPickupAt != null;
      const pickupScannedAfter = after.passengerScannedPickupAt != null;
      const passengerScannedBefore = before.passengerScannedAt != null;
      const passengerScannedAfter = after.passengerScannedAt != null;
      const receiverScannedBefore = before.receiverScannedAt != null;
      const receiverScannedAfter = after.receiverScannedAt != null;
      const driverScannedBefore = before.driverScannedAt != null;
      const driverScannedAfter = after.driverScannedAt != null;

      if (!pickupScannedBefore && pickupScannedAfter) {
        try {
          await admin.firestore().collection("scan_audit_log").add({
            orderId,
            scanType: "pickup",
            scannedBy: "passenger",
            passengerUid: after.passengerUid || null,
            driverUid: after.driverUid || null,
            pickupLat: after.pickupLat ?? null,
            pickupLng: after.pickupLng ?? null,
            orderType: after.orderType || "travel",
            status: after.status || "",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.error("scan_audit_log (pickup) error:", e);
        }
      }
      if (!passengerScannedBefore && passengerScannedAfter) {
        try {
          await admin.firestore().collection("scan_audit_log").add({
            orderId,
            scanType: "complete",
            scannedBy: "passenger",
            passengerUid: after.passengerUid || null,
            driverUid: after.driverUid || null,
            dropLat: after.dropLat ?? null,
            dropLng: after.dropLng ?? null,
            pickupLat: after.pickupLat ?? null,
            pickupLng: after.pickupLng ?? null,
            tripDistanceKm: after.tripDistanceKm ?? null,
            tripFareRupiah: after.tripFareRupiah ?? null,
            orderType: after.orderType || "travel",
            status: after.status || "",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.error("scan_audit_log (complete) error:", e);
        }
      }
      if (!receiverScannedBefore && receiverScannedAfter) {
        try {
          await admin.firestore().collection("scan_audit_log").add({
            orderId,
            scanType: "receiver",
            scannedBy: "receiver",
            receiverUid: after.receiverUid || null,
            driverUid: after.driverUid || null,
            dropLat: after.dropLat ?? null,
            dropLng: after.dropLng ?? null,
            pickupLat: after.pickupLat ?? null,
            pickupLng: after.pickupLng ?? null,
            tripDistanceKm: after.tripDistanceKm ?? null,
            tripBarangFareRupiah: after.tripBarangFareRupiah ?? null,
            orderType: after.orderType || "travel",
            status: after.status || "",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.error("scan_audit_log (receiver) error:", e);
        }
      }
      if (!driverScannedBefore && driverScannedAfter) {
        try {
          await admin.firestore().collection("scan_audit_log").add({
            orderId,
            scanType: "driver_pickup",
            scannedBy: "driver",
            passengerUid: after.passengerUid || null,
            driverUid: after.driverUid || null,
            pickupLat: after.pickupLat ?? null,
            pickupLng: after.pickupLng ?? null,
            orderType: after.orderType || "travel",
            status: after.status || "",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.error("scan_audit_log (driver_pickup) error:", e);
        }
      }

      // Audit: konfirmasi otomatis travel (tanpa scan barcode) — support & forensik
      const autoPickupBefore = before.autoConfirmPickup === true;
      const autoPickupAfter = after.autoConfirmPickup === true;
      const autoCompleteBefore = before.autoConfirmComplete === true;
      const autoCompleteAfter = after.autoConfirmComplete === true;
      if (!autoPickupBefore && autoPickupAfter) {
        try {
          await admin.firestore().collection("scan_audit_log").add({
            orderId,
            scanType: "auto_confirm_pickup",
            scannedBy: "system",
            passengerUid: after.passengerUid || null,
            driverUid: after.driverUid || null,
            pickupLat: after.pickupLat ?? null,
            pickupLng: after.pickupLng ?? null,
            driverViolationFee: after.driverViolationFee ?? null,
            orderType: after.orderType || "travel",
            status: after.status || "",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.error("scan_audit_log (auto_confirm_pickup) error:", e);
        }
      }
      if (!autoCompleteBefore && autoCompleteAfter) {
        try {
          await admin.firestore().collection("scan_audit_log").add({
            orderId,
            scanType: "auto_confirm_complete",
            scannedBy: "system",
            passengerUid: after.passengerUid || null,
            driverUid: after.driverUid || null,
            dropLat: after.dropLat ?? null,
            dropLng: after.dropLng ?? null,
            tripDistanceKm: after.tripDistanceKm ?? null,
            passengerViolationFee: after.passengerViolationFee ?? null,
            orderType: after.orderType || "travel",
            status: after.status || "",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (e) {
          console.error("scan_audit_log (auto_confirm_complete) error:", e);
        }
      }

      // Penumpang baru saja scan barcode PICKUP (passengerScannedPickupAt baru di-set) → notifikasi ke driver
      if (!pickupScannedBefore && pickupScannedAfter) {
        const driverUidForPickup = after.driverUid || "";
        const orderTypePickup = (after.orderType || "travel").toString();
        if (driverUidForPickup) {
          const driverSnap = await admin.firestore().collection("users").doc(driverUidForPickup).get();
          if (driverSnap.exists) {
            const fcmToken = driverSnap.data()?.fcmToken;
            if (fcmToken) {
              const title = orderTypePickup === "kirim_barang" ? "Barang sudah diterima" : "Penumpang sudah dijemput";
              const body = orderTypePickup === "kirim_barang"
                ? "Pengirim telah memindai barcode. Barang tercatat diterima. Antar ke penerima."
                : "Penumpang telah memindai barcode. Tunjukkan barcode selesai saat sampai tujuan.";
              const payload = {
                notification: { title, body },
                data: { type: "order_picked_up", orderId },
                token: fcmToken,
                android: { priority: "high", notification: { channelId: "traka_chat", priority: "high" } },
              };
              try {
                await sendFcmWithCollapse(payload, {
                  collapseKey: `order_${orderId}`,
                  tag: `order_${orderId}`,
                });
              } catch (e) {
                console.error("FCM onOrderUpdatedScan (passengerScannedPickup) error:", e);
              }
            }
          }
        }
        // Kirim barang: notifikasi ke penerima saat barang dijemput driver
        if (orderTypePickup === "kirim_barang") {
          const receiverUid = after.receiverUid || "";
          if (receiverUid) {
            const receiverSnap = await admin.firestore().collection("users").doc(receiverUid).get();
            if (receiverSnap.exists) {
              const receiverToken = receiverSnap.data()?.fcmToken;
              if (receiverToken) {
                const receiverPayload = {
                  notification: {
                    title: "Barang sudah dijemput",
                    body: "Driver telah menerima barang dari pengirim. Lacak perjalanan di aplikasi.",
                  },
                  data: { type: "order_picked_up", orderId },
                  token: receiverToken,
                  android: { priority: "high", notification: { channelId: "traka_chat", priority: "high" } },
                };
                try {
                  await sendFcmWithCollapse(receiverPayload, {
                    collapseKey: `order_${orderId}`,
                    tag: `order_${orderId}`,
                  });
                } catch (e) {
                  console.error("FCM onOrderUpdatedScan (receiver pickup) error:", e);
                }
              }
            }
          }
        }
      }

      // Driver baru saja scan barcode penumpang (driverScannedAt baru di-set) - backward compat
      if (!driverScannedBefore && driverScannedAfter) {
        const passengerUid = after.passengerUid || "";
        if (!passengerUid) return null;
        const passengerSnap = await admin.firestore().collection("users").doc(passengerUid).get();
        if (!passengerSnap.exists) return null;
        const fcmToken = passengerSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Anda sudah dijemput",
            body: "Driver telah memindai barcode Anda. Anda tercatat naik. Saat sampai tujuan, scan barcode driver.",
          },
          data: { type: "order_picked_up", orderId },
          token: fcmToken,
          android: { priority: "high", notification: { channelId: "traka_chat", priority: "high" } },
        };
        try {
          await sendFcmWithCollapse(payload, {
            collapseKey: `order_${orderId}`,
            tag: `order_${orderId}`,
          });
        } catch (e) {
          console.error("FCM onOrderUpdatedScan (driverScanned) error:", e);
        }
      }

      // Penumpang baru saja scan barcode driver (passengerScannedAt baru di-set, status completed)
      if (!passengerScannedBefore && passengerScannedAfter) {
        const driverUid = after.driverUid || "";
        const passengerName = (after.passengerName || "Penumpang").trim();
        if (!driverUid) return null;
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        if (!driverSnap.exists) return null;
        const fcmToken = driverSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Penumpang sudah sampai",
            body: `${passengerName} telah memindai barcode. Perjalanan selesai.`,
          },
          data: { type: "order_completed", orderId },
          token: fcmToken,
          android: { priority: "high", notification: { channelId: "traka_chat", priority: "high" } },
        };
        try {
          await sendFcmWithCollapse(payload, {
            collapseKey: `order_${orderId}`,
            tag: `order_${orderId}`,
          });
        } catch (e) {
          console.error("FCM onOrderUpdatedScan (passengerScanned) error:", e);
        }

        // Kontribusi travel: trigger per rute selesai (bukan per order). Route_session disimpan saat driver Berhenti Kerja.
      }

      // Penerima baru saja scan barcode (receiverScannedAt) → kirim barang selesai → kontribusi driver
      if (!receiverScannedBefore && receiverScannedAfter) {
        const orderTypeBarang = (after.orderType || "travel").toString();
        if (orderTypeBarang === "kirim_barang") {
          const driverUidBarang = after.driverUid || "";
          const tripBarangFareRupiah = typeof after.tripBarangFareRupiah === "number"
            ? after.tripBarangFareRupiah
            : (typeof after.tripBarangFareRupiah === "string" ? parseInt(after.tripBarangFareRupiah, 10) : 0);
          if (driverUidBarang && tripBarangFareRupiah > 0) {
            try {
              await admin.firestore().collection("users").doc(driverUidBarang).update({
                totalBarangContributionRupiah: admin.firestore.FieldValue.increment(tripBarangFareRupiah),
              });
              await sendPaymentReminderFcm(driverUidBarang, "kontribusi");
            } catch (e) {
              console.error("Kontribusi kirim barang: increment totalBarangContributionRupiah error:", e);
            }
          }
        }
      }
      return null;
    });

// --- Notifikasi pembatalan pesanan: ketika driver atau penumpang klik Batalkan/Konfirmasi,
//     pihak yang menerima konfirmasi dapat notifikasi ---
exports.onOrderCancellationUpdate = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      const orderId = context.params.orderId;
      const before = change.before.data();
      const after = change.after.data();
      const driverUid = after.driverUid || "";
      const passengerUid = after.passengerUid || "";
      const passengerName = (after.passengerName || "Penumpang").trim();
      let driverName = (after.driverName || "").trim();
      if (!driverName && driverUid) {
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        driverName = (driverSnap.exists && driverSnap.data()?.displayName)
          ? driverSnap.data().displayName.trim() : "Driver";
      }
      if (!driverName) driverName = "Driver";

      // Driver baru saja membatalkan → kirim notifikasi ke penumpang
      const driverCancelledBefore = before.driverCancelled || false;
      const driverCancelledAfter = after.driverCancelled || false;
      if (!driverCancelledBefore && driverCancelledAfter && passengerUid) {
        const passengerSnap = await admin.firestore().collection("users").doc(passengerUid).get();
        if (!passengerSnap.exists) return null;
        const fcmToken = passengerSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Pembatalan pesanan",
            body: "Driver telah membatalkan pesanan. Buka Data Order untuk konfirmasi pembatalan.",
          },
          data: { type: "order_cancellation", orderId, initiator: "driver" },
          token: fcmToken,
          android: {
            priority: "high",
            notification: { channelId: "traka_chat", priority: "high" },
          },
        };
        try {
          await sendFcmWithCollapse(payload, {
            collapseKey: `order_${orderId}`,
            tag: `order_${orderId}`,
          });
        } catch (e) {
          console.error("FCM onOrderCancellationUpdate (driver->passenger):", e);
        }
      }

      // Penumpang baru saja membatalkan → kirim notifikasi ke driver
      const passengerCancelledBefore = before.passengerCancelled || false;
      const passengerCancelledAfter = after.passengerCancelled || false;
      if (!passengerCancelledBefore && passengerCancelledAfter && driverUid) {
        const driverSnap = await admin.firestore().collection("users").doc(driverUid).get();
        if (!driverSnap.exists) return null;
        const fcmToken = driverSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const payload = {
          notification: {
            title: "Pembatalan pesanan",
            body: `${passengerName} telah membatalkan pesanan. Buka Data Order untuk konfirmasi pembatalan.`,
          },
          data: { type: "order_cancellation", orderId, initiator: "passenger" },
          token: fcmToken,
          android: {
            priority: "high",
            notification: { channelId: "traka_chat", priority: "high" },
          },
        };
        try {
          await sendFcmWithCollapse(payload, {
            collapseKey: `order_${orderId}`,
            tag: `order_${orderId}`,
          });
        } catch (e) {
          console.error("FCM onOrderCancellationUpdate (passenger->driver):", e);
        }
      }

      return null;
    });

// --- Notifikasi bayar pelanggaran/kontribusi: saat outstandingViolationFee atau kontribusi di users bertambah ---
exports.onUserPaymentDuesUpdate = functions.firestore
    .document("users/{userId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data();
      const after = change.after.data();
      const uid = context.params.userId;

      const beforeFee = (before?.outstandingViolationFee ?? 0);
      const afterFee = (after?.outstandingViolationFee ?? 0);
      if (afterFee > beforeFee) {
        await sendPaymentReminderFcm(uid, "pelanggaran");
      }

      // Backup: notifikasi kontribusi saat totalTravelContributionRupiah atau totalBarangContributionRupiah naik
      const beforeTravel = (before?.totalTravelContributionRupiah ?? 0);
      const afterTravel = (after?.totalTravelContributionRupiah ?? 0);
      const beforeBarang = (before?.totalBarangContributionRupiah ?? 0);
      const afterBarang = (after?.totalBarangContributionRupiah ?? 0);
      if (afterTravel > beforeTravel || afterBarang > beforeBarang) {
        await sendPaymentReminderFcm(uid, "kontribusi");
      }

      // Permintaan verifikasi dari admin → notifikasi push (collapse per user).
      const ap = after?.adminVerificationPendingAt;
      if (ap) {
        const bp = before?.adminVerificationPendingAt;
        const msgBefore = (before?.adminVerificationMessage || "").trim();
        const msgAfter = (after?.adminVerificationMessage || "").trim();
        const pendingNew = !bp && ap;
        let tsChanged = false;
        if (bp && ap && bp.toMillis && ap.toMillis) {
          tsChanged = bp.toMillis() !== ap.toMillis();
        }
        const msgChanged = msgBefore !== msgAfter && msgAfter.length > 0;
        if (pendingNew || tsChanged || msgChanged) {
          await sendAdminVerificationRequestFcm(uid, after);
        }
      }

      // --- Notifikasi ke admin: pengguna tap "Sudah kirim data" (permintaan verifikasi admin) ---
      const beforeSub = before?.adminVerificationUserSubmittedAt;
      const afterSub = after?.adminVerificationUserSubmittedAt;
      if (!beforeSub && afterSub) {
        const name = (after?.displayName || after?.email || uid).toString().slice(0, 120);
        await notifyAdminsFcm({
          title: "Konfirmasi kirim data",
          body: `${name} mengonfirmasi sudah mengirim data yang diminta.`,
          data: {
            type: "admin_user_submitted_verification",
            eventType: "verification_submitted",
            userIdSubject: uid,
          },
        });
      }

      // --- Notifikasi ke admin: driver kirim / ganti foto STNK (minta ubah kendaraan) ---
      const role = after?.role;
      const beforeVc = before?.vehicleChangeRequestAt;
      const afterVc = after?.vehicleChangeRequestAt;
      const beforeStnk = (before?.vehicleChangeRequestStnkUrl || "").toString();
      const afterStnk = (after?.vehicleChangeRequestStnkUrl || "").toString();
      if (role === "driver" && afterVc) {
        const isNewRequest = !beforeVc;
        const stnkReplaced = beforeVc && beforeStnk !== afterStnk && afterStnk.length > 0;
        if (isNewRequest || stnkReplaced) {
          const name = (after?.displayName || after?.email || uid).toString().slice(0, 120);
          await notifyAdminsFcm({
            title: "Permintaan ubah kendaraan",
            body: `${name} mengirim foto STNK (minta ubah data kendaraan).`,
            data: {
              type: "admin_vehicle_stnk_request",
              eventType: "vehicle_change_request",
              userIdSubject: uid,
            },
          });
        }
      }

      return null;
    });

// --- Kontribusi driver: verifikasi pembayaran gabungan (rute + kirim barang + pelanggaran) ---
// Trigger per rute selesai (bukan 1× kapasitas). Saat bayar: mark route_sessions lunas.
exports.verifyContributionPayment = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const driverUid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const orderId = data?.orderId;
  const productId = (data?.productId || "traka_driver_dues_7500").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken || !orderId) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken dan orderId wajib.");
  }

  const userRef = admin.firestore().collection("users").doc(driverUid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }

  const verifyResult = await verifyProductPurchase(
      packageName, productId, purchaseToken);
  if (!verifyResult.verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  const current = userSnap.data();
  const totalBarangContributionRupiah = (current?.totalBarangContributionRupiah ?? 0);
  const outstandingViolationFee = (current?.outstandingViolationFee ?? 0);
  const outstandingViolationCount = (current?.outstandingViolationCount ?? 0);

  // Unpaid travel: dari route_sessions (contributionPaidAt null, contributionRupiah > 0)
  const unpaidRouteSessions = await admin.firestore()
      .collection("route_sessions")
      .where("driverUid", "==", driverUid)
      .get();
  let unpaidTravel = 0;
  const routeRefsToMarkPaid = [];
  for (const doc of unpaidRouteSessions.docs) {
    const d = doc.data();
    if (d.contributionPaidAt == null && (d.contributionRupiah || 0) > 0) {
      unpaidTravel += (d.contributionRupiah || 0);
      routeRefsToMarkPaid.push(doc.ref);
    }
  }

  const unpaidBarang = Math.max(0,
      totalBarangContributionRupiah - (current?.contributionBarangPaidUpToRupiah ?? 0));
  const amountOwed = unpaidTravel + unpaidBarang + Math.round(outstandingViolationFee);

  const purchaseAmount = billingValidation.parseDriverDuesAmountRupiah(productId);
  if (purchaseAmount == null || purchaseAmount <= 0) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "ID produk kontribusi tidak dikenal.",
    );
  }

  if (amountOwed <= 0) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Tidak ada kewajiban pembayaran.",
    );
  }

  if (amountOwed > billingValidation.MAX_DRIVER_DUES_SINGLE_PURCHASE_RUPIAH) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Total kewajiban melebihi batas pembayaran tunggal. Hubungi admin.",
    );
  }

  if (purchaseAmount < amountOwed) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Nominal produk tidak mencukupi total kewajiban saat ini.",
    );
  }

  const amountRupiah = amountOwed;

  if (routeRefsToMarkPaid.length > 0) {
    const batch = admin.firestore().batch();
    for (const ref of routeRefsToMarkPaid) {
      batch.update(ref, { contributionPaidAt: admin.firestore.FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }

  const paidAt = admin.firestore.FieldValue.serverTimestamp();
  const violationRupiah = Math.round(outstandingViolationFee);
  const updateData = {
    contributionBarangPaidUpToRupiah: totalBarangContributionRupiah,
    outstandingViolationFee: 0,
    outstandingViolationCount: 0,
    contributionLastPaidAt: paidAt,
  };
  await userRef.update(updateData);
  await admin.firestore().collection("contribution_payments").add({
    driverUid,
    amountRupiah,
    paidAt,
    orderId,
    productId,
    contributionTravelRupiah: unpaidTravel,
    contributionBarangRupiah: unpaidBarang,
    contributionViolationRupiah: violationRupiah,
  });

  // Tandai violation_records (type: driver) sebagai paid
  if (outstandingViolationFee > 0) {
    const violationSnap = await admin.firestore()
        .collection("violation_records")
        .where("userId", "==", driverUid)
        .where("type", "==", "driver")
        .where("paidAt", "==", null)
        .orderBy("createdAt")
        .limit(Math.max(1, outstandingViolationCount))
        .get();
    const batch = admin.firestore().batch();
    for (const doc of violationSnap.docs) {
      batch.update(doc.ref, { paidAt: admin.firestore.FieldValue.serverTimestamp() });
    }
    if (!violationSnap.empty) {
      await batch.commit();
    }
  }

  return {
    success: true,
    contributionBarangPaidUpToRupiah: totalBarangContributionRupiah,
  };
});

// --- Rute selesai: saat route_session dibuat dengan kontribusi > 0, kirim FCM pengingat bayar ---
exports.onRouteSessionCreated = functions.firestore
    .document("route_sessions/{sessionId}")
    .onCreate(async (snap, _context) => {
      const d = snap.data();
      const contributionRupiah = (d?.contributionRupiah || 0);
      const driverUid = d?.driverUid || "";
      if (driverUid && contributionRupiah > 0) {
        await sendPaymentReminderFcm(driverUid, "kontribusi");
      }
      return null;
    });

// --- Kirim Barang: cek nomor HP mana yang terdaftar sebagai user Traka (untuk contact picker) ---
// Input: { phoneNumbers: string[] } max 50. Output: { registered: [{ phoneNumber, uid, displayName, photoUrl }] }
function normalizePhoneId(phone) {
  if (!phone || typeof phone !== "string") return null;
  let s = phone.replace(/\D/g, "");
  if (s.startsWith("62")) return "+" + s;
  if (s.startsWith("0")) return "+62" + s.substring(1);
  if (s.length >= 9) return "+62" + s;
  return null;
}

exports.checkRegisteredContacts = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const raw = data?.phoneNumbers;
  if (!Array.isArray(raw) || raw.length === 0) {
    return { registered: [] };
  }
  const normalized = [];
  const seen = new Set();
  for (let i = 0; i < Math.min(raw.length, 50); i++) {
    const n = normalizePhoneId(raw[i]);
    if (n && !seen.has(n)) {
      seen.add(n);
      normalized.push(n);
    }
  }
  if (normalized.length === 0) {
    return { registered: [] };
  }
  const db = admin.firestore();
  const registered = [];
  // Firestore 'in' supports max 30 values per query
  for (let i = 0; i < normalized.length; i += 30) {
    const batch = normalized.slice(i, i + 30);
    const snap = await db.collection("users")
        .where("phoneNumber", "in", batch)
        .get();
    for (const doc of snap.docs) {
      const d = doc.data();
      const phone = d.phoneNumber || "";
      if (batch.includes(phone)) {
        registered.push({
          phoneNumber: phone,
          uid: doc.id,
          displayName: d.displayName || null,
          photoUrl: d.photoUrl || null,
        });
      }
    }
  }
  return { registered };
});

// --- Oper Driver: cek kontak yang terdaftar sebagai driver (role=driver) ---
exports.checkRegisteredDrivers = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const raw = data?.phoneNumbers;
  if (!Array.isArray(raw) || raw.length === 0) {
    return { registered: [] };
  }
  const normalized = [];
  const seen = new Set();
  for (let i = 0; i < Math.min(raw.length, 50); i++) {
    const n = normalizePhoneId(raw[i]);
    if (n && !seen.has(n)) {
      seen.add(n);
      normalized.push(n);
    }
  }
  if (normalized.length === 0) {
    return { registered: [] };
  }
  const db = admin.firestore();
  const registered = [];
  for (let i = 0; i < normalized.length; i += 30) {
    const batch = normalized.slice(i, i + 30);
    const snap = await db.collection("users")
        .where("phoneNumber", "in", batch)
        .get();
    for (const doc of snap.docs) {
      const d = doc.data();
      if ((d.role || "") !== "driver") continue;
      const phone = d.phoneNumber || "";
      if (batch.includes(phone)) {
        registered.push({
          phoneNumber: phone,
          uid: doc.id,
          displayName: d.displayName || null,
          photoUrl: d.photoUrl || null,
          email: d.email || null,
          vehicleJumlahPenumpang: d.vehicleJumlahPenumpang ?? null,
        });
      }
    }
  }
  return { registered };
});

// --- Oper Driver: notifikasi ke driver kedua saat transfer dibuat ---
exports.onDriverTransferCreated = functions.firestore
    .document("driver_transfers/{transferId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const toDriverUid = data?.toDriverUid || "";
      const fromDriverUid = data?.fromDriverUid || "";
      if (!toDriverUid) return null;

      const fromDriverSnap = await admin.firestore()
          .collection("users").doc(fromDriverUid).get();
      const fromName = fromDriverSnap.exists
          ? (fromDriverSnap.data()?.displayName || "Driver").trim()
          : "Driver";

      const toDriverSnap = await admin.firestore()
          .collection("users").doc(toDriverUid).get();
      const fcmToken = toDriverSnap.data()?.fcmToken;
      if (!fcmToken) return null;

      const payload = {
        notification: {
          title: "Oper Driver",
          body: `${fromName} ingin mengoper penumpang ke Anda. Buka Data Order > Oper ke Saya.`,
        },
        data: {
          type: "driver_transfer",
          transferId: context.params.transferId,
        },
        token: fcmToken,
        android: {
          priority: "high",
          notification: {
            channelId: "traka_chat",
            priority: "high",
          },
        },
      };

      try {
        const transferId = context.params.transferId;
        await sendFcmWithCollapse(payload, {
          collapseKey: `transfer_${transferId}`,
          tag: `transfer_${transferId}`,
        });
      } catch (e) {
        console.error("FCM onDriverTransferCreated error:", e);
      }
      return null;
    });

// --- Oper Driver: saat driver kedua scan transfer → kontribusi driver pertama (totalTravelContributionRupiah)
exports.onDriverTransferScanned = functions.firestore
    .document("driver_transfers/{transferId}")
    .onUpdate(async (change, _context) => {
      const before = change.before.data();
      const after = change.after.data();
      const statusBefore = before?.status || "";
      const statusAfter = after?.status || "";
      if (statusBefore === "scanned" || statusAfter !== "scanned") return null;

      const fromDriverUid = after?.fromDriverUid || "";
      const orderId = after?.orderId || "";
      if (!fromDriverUid || !orderId) return null;

      const orderSnap = await admin.firestore().collection("orders").doc(orderId).get();
      if (!orderSnap.exists) return null;
      const orderData = orderSnap.data() || {};
      const orderType = (orderData.orderType || "travel").toString();
      if (orderType !== "travel") return null;

      // Kontribusi flat untuk oper: min 5000 (bisa diubah admin via app_config/settings)
      const configSnap = await admin.firestore().doc("app_config/settings").get();
      const minContrib = (configSnap.data()?.minKontribusiTravelRupiah ?? 5000) || 5000;

      try {
        await admin.firestore().collection("users").doc(fromDriverUid).update({
          totalTravelContributionRupiah: admin.firestore.FieldValue.increment(minContrib),
        });
      } catch (e) {
        console.error("onDriverTransferScanned: increment totalTravelContributionRupiah error:", e);
      }
      return null;
    });

/** @param {string} driverId @param {object[]} newSchedules */
async function notifyPassengersNewScheduleSlots(driverId, newSchedules) {
  if (!Array.isArray(newSchedules) || newSchedules.length === 0) return;
  const driverSnap = await admin.firestore().collection("users").doc(driverId).get();
  const driverName = (driverSnap.data()?.displayName || "Driver").trim();
  const regionKeywords = new Set();
  for (const s of newSchedules) {
    const origin = ((s?.origin || "") + " " + (s?.destination || "")).toLowerCase();
    const parts = origin.split(/[\s,]+/).filter(Boolean);
    for (const p of parts) {
      if (p.length >= 3) regionKeywords.add(p);
    }
  }
  if (regionKeywords.size === 0) return;
  const usersSnap = await admin.firestore().collection("users")
      .where("role", "==", "penumpang")
      .limit(500)
      .get();
  let sent = 0;
  for (const doc of usersSnap.docs) {
    const d = doc.data();
    const fcmToken = d?.fcmToken;
    const region = (d?.region || "").trim().toLowerCase();
    if (!fcmToken || !region) continue;
    const regionParts = region.split(/[\s,]+/).filter(Boolean);
    const match = regionParts.some((r) => regionKeywords.has(r)) ||
        [...regionKeywords].some((k) => region.includes(k));
    if (!match) continue;
    const payload = {
      notification: {
        title: "Jadwal travel baru",
        body: `${driverName} menambah jadwal baru. Cek di Pesan nanti.`,
      },
      data: { type: "schedule_new", driverId },
      token: fcmToken,
      android: {
        priority: "high",
        notification: { channelId: "traka_order_channel", priority: "high" },
      },
    };
    try {
      await sendFcmWithCollapse(payload, {
        collapseKey: `schedule_new_${driverId}`,
        tag: `schedule_new_${driverId}`,
      });
      sent++;
    } catch (e) {
      console.error("notifyPassengersNewScheduleSlots FCM error for", doc.id, e);
    }
  }
  if (sent > 0) {
    console.log("notifyPassengersNewScheduleSlots: sent", sent, "for driver", driverId);
  }
}

// --- Pulihkan slot jadwal jika dihapus saat masih ada order aktif (jaring pengguna curang / race) ---
exports.onDriverScheduleItemDeleted = functions.firestore
    .document("driver_schedules/{driverId}/schedule_items/{itemId}")
    .onDelete(async (snap, context) => {
      const driverId = context.params.driverId;
      try {
        await restoreIfScheduleHasActiveOrders(snap, driverId);
      } catch (e) {
        console.error("onDriverScheduleItemDeleted:", driverId, e);
      }
    });

// --- FCM: admin membalas live chat (admin_chats) ---
exports.onAdminSupportMessageCreated = functions.firestore
    .document("admin_chats/{userId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const userId = context.params.userId;
      const d = snap.data();
      if (!d) return;
      if (d.senderType !== "admin") return;
      const text = String(d.text || "").trim().slice(0, 180);
      try {
        const userSnap = await admin.firestore().collection("users").doc(userId).get();
        if (!userSnap.exists) return;
        const fcmToken = userSnap.data()?.fcmToken;
        if (!fcmToken) return;
        const title = "Pesan dari Admin Traka";
        const body = text || "Ada pesan baru dari admin.";
        const dataPayload = {
          type: "admin_support",
          title,
          body,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        };
        await sendFcmWithCollapse({
          notification: { title, body },
          data: dataPayload,
          token: fcmToken,
          android: {
            priority: "high",
            notification: {
              channelId: "traka_admin_support_channel",
              priority: "high",
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: {
              aps: {
                alert: { title, body },
                sound: "default",
              },
            },
          },
        }, {
          collapseKey: `admin_support_${userId}`,
          tag: `admin_support_${userId}`,
        });
      } catch (e) {
        console.error("onAdminSupportMessageCreated:", userId, e);
      }
    });

// --- SOS: log frekuensi tinggi (monitoring / alert log-based di Cloud Logging) ---
exports.onSosEventCreated = functions.firestore
    .document("sos_events/{eventId}")
    .onCreate(async (snap, context) => {
      const d = snap.data();
      const uid = d?.uid;
      if (!uid || typeof uid !== "string") return;
      const oneHourAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
      try {
        const recent = await admin.firestore().collection("sos_events")
            .where("uid", "==", uid)
            .where("triggeredAt", ">", oneHourAgo)
            .limit(25)
            .get();
        if (recent.size >= 10) {
          console.warn("onSosEventCreated: high_frequency_sos uid=" + uid +
              " events_last_hour=" + recent.size + " eventId=" + context.params.eventId);
        }
      } catch (e) {
        console.error("onSosEventCreated rate check:", uid, e);
      }
    });

// --- Subkoleksi schedule_items: sanitasi per dokumen + notifikasi create ---
exports.onDriverScheduleItemWritten = functions.firestore
    .document("driver_schedules/{driverId}/schedule_items/{itemId}")
    .onWrite(async (change, context) => {
      const driverId = context.params.driverId;
      if (!change.after.exists) return null;
      const slot = change.after.data();
      let activeIds;
      try {
        activeIds = await fetchActiveScheduleIdsForDriver(driverId);
      } catch (e) {
        console.error("onDriverScheduleItemWritten: active ids", driverId, e);
        return null;
      }
      if (!shouldKeepSlot(slot, driverId, activeIds)) {
        try {
          await change.after.ref.delete();
        } catch (e) {
          console.error("onDriverScheduleItemWritten: delete slot", driverId, e);
        }
        return null;
      }
      if (!change.before.exists) {
        await notifyPassengersNewScheduleSlots(driverId, [slot]);
      }
      return null;
    });

// --- Notifikasi jadwal baru: saat driver menambah jadwal di driver_schedules ---
// Target: penumpang dengan region (provinsi) yang cocok dengan origin/destination jadwal
// + Enforcement jendela 7 hari WIB (strip slot di luar jendela tanpa order aktif).
exports.onDriverScheduleWritten = functions.firestore
    .document("driver_schedules/{driverId}")
    .onWrite(async (change, context) => {
      const driverId = context.params.driverId;

      if (change.after.exists) {
        const after = change.after.data();
        const raw = after?.schedules;
        if (Array.isArray(raw) && raw.length > 0) {
          const sanitized = await sanitizeDriverSchedulesIfNeeded(driverId, raw);
          if (sanitized != null) {
            try {
              await admin.firestore().collection("driver_schedules").doc(driverId).update({
                schedules: sanitized,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(
                "onDriverScheduleWritten: sanitized schedules",
                driverId,
                "from",
                raw.length,
                "to",
                sanitized.length,
              );
            } catch (e) {
              console.error("onDriverScheduleWritten: sanitize update failed", driverId, e);
            }
            return null;
          }
        }
      }

      const after = change.after.exists ? change.after.data() : null;
      const afterSchedules = (after?.schedules || []);
      if (afterSchedules.length === 0) return null;

      let newSchedules;
      if (!change.before.exists) {
        newSchedules = afterSchedules;
      } else {
        const before = change.before.data();
        const beforeSchedules = (before?.schedules || []);
        if (afterSchedules.length <= beforeSchedules.length) return null;
        newSchedules = afterSchedules.slice(beforeSchedules.length);
      }

      await notifyPassengersNewScheduleSlots(driverId, newSchedules);
      return null;
    });

// --- Lacak Driver: penumpang bayar via Google Play (min Rp 3000) untuk fitur Lacak Driver per order ---
exports.verifyPassengerTrackPayment = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const passengerUid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const orderId = data?.orderId;
  const productId = (data?.productId || "traka_lacak_driver_3000").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken || !orderId) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken dan orderId wajib.");
  }

  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Pesanan tidak ditemukan.");
  }

  const orderData = orderSnap.data();
  const orderPassengerUid = orderData?.passengerUid || "";
  if (orderPassengerUid !== passengerUid) {
    throw new functions.https.HttpsError("permission-denied", "Anda bukan penumpang pesanan ini.");
  }

  const verifyResult = await verifyProductPurchase(
      packageName, productId, purchaseToken);
  if (!verifyResult.verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  const feeExpected = await billingValidation.getLacakDriverFeeRupiah(admin.firestore());
  const productIdExpected = billingValidation.expectedLacakDriverProductId(feeExpected);
  if (productId !== productIdExpected) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        `Produk tidak sesuai tarif saat ini (harus: ${productIdExpected}).`,
    );
  }

  // Parse amount dari productId (traka_lacak_driver_3000 → 3000) untuk Riwayat Pembayaran
  const lacakDriverMatch = productId.match(/traka_lacak_driver_(\d+)/);
  const amountRupiah = lacakDriverMatch ? parseInt(lacakDriverMatch[1], 10) : feeExpected;

  await orderRef.update({
    passengerTrackDriverPaidAt: admin.firestore.FieldValue.serverTimestamp(),
    passengerTrackDriverAmountRupiah: amountRupiah,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// --- Lacak Barang: pengirim atau penerima bayar via Google Play ---
exports.verifyLacakBarangPayment = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const orderId = data?.orderId;
  const payerType = (data?.payerType || "").toString();
  const productId = (data?.productId || "traka_lacak_barang_10k").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken || !orderId) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken dan orderId wajib.");
  }
  if (payerType !== "passenger" && payerType !== "receiver") {
    throw new functions.https.HttpsError("invalid-argument", "payerType harus passenger atau receiver.");
  }

  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Pesanan tidak ditemukan.");
  }

  const orderData = orderSnap.data();
  const orderType = (orderData?.orderType || "travel").toString();
  if (orderType !== "kirim_barang") {
    throw new functions.https.HttpsError("failed-precondition", "Bukan pesanan kirim barang.");
  }

  if (payerType === "passenger") {
    if (orderData?.passengerUid !== uid) {
      throw new functions.https.HttpsError("permission-denied", "Anda bukan pengirim pesanan ini.");
    }
  } else {
    if (orderData?.receiverUid !== uid) {
      throw new functions.https.HttpsError("permission-denied", "Anda bukan penerima pesanan ini.");
    }
  }

  const verifyResult = await verifyProductPurchase(
      packageName, productId, purchaseToken);
  if (!verifyResult.verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  const paidParsed = billingValidation.parseLacakBarangAmountRupiah(productId);
  if (paidParsed == null) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "ID produk lacak barang tidak dikenal.",
    );
  }

  const rawExpected = orderData?.lacakBarangIapFeeRupiah;
  const expectedNum = rawExpected != null ? Number(rawExpected) : NaN;
  if (Number.isFinite(expectedNum) && expectedNum > 0) {
    if (paidParsed !== Math.round(expectedNum)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Produk tidak sesuai biaya lacak untuk pesanan ini.",
      );
    }
  } else {
    const allowed = await billingValidation.getLacakBarangTierFeesRupiah(admin.firestore());
    if (!allowed.includes(paidParsed)) {
      throw new functions.https.HttpsError(
          "failed-precondition",
          "Produk lacak barang tidak valid untuk tarif saat ini.",
      );
    }
  }

  const amountRupiah = paidParsed;

  const updateData = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (payerType === "passenger") {
    updateData.passengerLacakBarangPaidAt = admin.firestore.FieldValue.serverTimestamp();
    updateData.passengerLacakBarangAmountRupiah = amountRupiah;
  } else {
    updateData.receiverLacakBarangPaidAt = admin.firestore.FieldValue.serverTimestamp();
    updateData.receiverLacakBarangAmountRupiah = amountRupiah;
  }

  await orderRef.update(updateData);
  return { success: true };
});

// --- Pelanggaran: penumpang bayar Rp 5000 per pelanggaran via Google Play ---
exports.verifyViolationPayment = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const passengerUid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const productId = (data?.productId || "traka_violation_fee_5k").toString();
  const packageName = (data?.packageName || "id.traka.app").toString();

  if (!purchaseToken) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken wajib.");
  }

  const userRef = admin.firestore().collection("users").doc(passengerUid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }

  const current = userSnap.data();
  const outstandingFee = (current?.outstandingViolationFee ?? 0);
  const outstandingCount = (current?.outstandingViolationCount ?? 0);
  if (outstandingFee <= 0) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Tidak ada pelanggaran yang perlu dibayar.",
    );
  }

  const verifyResult = await verifyProductPurchase(
      packageName, productId, purchaseToken);
  if (!verifyResult.verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  const skuAmount = billingValidation.parseViolationFeeAmountRupiah(productId);
  if (skuAmount == null || skuAmount <= 0) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "ID produk pelanggaran tidak dikenal.",
    );
  }

  // Ambil satu violation record penumpang yang belum dibayar (tertua)
  const violationSnap = await admin.firestore()
      .collection("violation_records")
      .where("userId", "==", passengerUid)
      .where("type", "==", "passenger")
      .where("paidAt", "==", null)
      .orderBy("createdAt")
      .limit(1)
      .get();

  if (violationSnap.empty) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Data pelanggaran tidak konsisten.",
    );
  }

  const firstViolation = violationSnap.docs[0];
  const violationAmount = Math.round(firstViolation.data()?.amount ?? 5000);
  if (skuAmount < violationAmount) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Nominal produk tidak mencukupi denda pelanggaran ini.",
    );
  }

  const deductAmount = Math.min(violationAmount, outstandingFee);

  const batch = admin.firestore().batch();

  // Update user: kurangi outstanding
  batch.update(userRef, {
    outstandingViolationFee: Math.max(0, outstandingFee - deductAmount),
    outstandingViolationCount: Math.max(0, outstandingCount - 1),
  });

  // Tandai satu violation record sebagai paid
  batch.update(firstViolation.ref, {
    paidAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  return {
    success: true,
    deductedAmount: deductAmount,
    remainingOutstanding: Math.max(0, outstandingFee - deductAmount),
  };
});

async function assertCallerIsAdmin(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists || snap.data()?.role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Hanya admin.");
  }
}

function normalizePhoneDigitsForNavPremiumExempt(s) {
  if (!s || typeof s !== "string") return "";
  let d = s.replace(/\D/g, "");
  if (d.startsWith("0")) d = "62" + d.substring(1);
  if (!d.startsWith("62") && d.length >= 9) d = "62" + d;
  return d;
}

// --- Navigasi premium driver: cek nomor HP di daftar pembebasan (app_config/settings.driverNavPremiumExemptPhones) ---
exports.checkDriverNavPremiumPhoneExempt = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const uid = context.auth.uid;
  const userSnap = await admin.firestore().collection("users").doc(uid).get();
  if (!userSnap.exists) {
    return { exempt: false };
  }
  const phone = String(userSnap.data()?.phoneNumber || "").trim();
  const userNorm = normalizePhoneDigitsForNavPremiumExempt(phone);
  if (!userNorm) {
    return { exempt: false };
  }
  const settings = await billingValidation.getSettingsData(admin.firestore());
  const exemptList = settings?.driverNavPremiumExemptPhones;
  if (!Array.isArray(exemptList)) {
    return { exempt: false };
  }
  for (const entry of exemptList) {
    if (normalizePhoneDigitsForNavPremiumExempt(String(entry)) === userNorm) {
      return { exempt: true };
    }
  }
  return { exempt: false };
});

// --- Navigasi premium: verifikasi IAP + selaraskan tarif server dengan settings ---
exports.verifyDriverNavPremiumPayment = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const driverUid = context.auth.uid;
  const purchaseToken = data?.purchaseToken;
  const packageName = (data?.packageName || "id.traka.app").toString();
  let productId = (data?.productId || "").toString().trim();
  const routeJourneyIn = (data?.routeJourneyNumber || "").toString().trim();
  const navScopeIn = (data?.navPremiumScope || "").toString().trim();
  const routeDistIn = data?.routeDistanceMeters;

  if (!purchaseToken) {
    throw new functions.https.HttpsError("invalid-argument", "purchaseToken wajib.");
  }

  const userRef = admin.firestore().collection("users").doc(driverUid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }
  const udata = userSnap.data() || {};

  const owedJourney = (udata.driverNavPremiumOwedJourney || "").toString().trim();
  const journey = routeJourneyIn || owedJourney;
  if (owedJourney && routeJourneyIn && owedJourney !== routeJourneyIn) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Nomor rute tidak cocok dengan hutang navigasi premium.",
    );
  }

  let scope = navScopeIn ||
      (udata.driverNavPremiumOwedScope || "").toString().trim() ||
      "dalamNegara";
  let distanceMeters = null;
  if (routeDistIn != null && routeDistIn !== "") {
    const dm = typeof routeDistIn === "number" ? routeDistIn : parseInt(String(routeDistIn), 10);
    if (!isNaN(dm) && dm > 0) distanceMeters = dm;
  }
  if (distanceMeters == null && udata.driverNavPremiumOwedDistanceM != null) {
    const od = udata.driverNavPremiumOwedDistanceM;
    const n = typeof od === "number" ? od : parseInt(String(od), 10);
    if (!isNaN(n) && n > 0) distanceMeters = n;
  }

  if (journey) {
    const q = await admin.firestore().collection("orders")
        .where("routeJourneyNumber", "==", journey)
        .where("driverUid", "==", driverUid)
        .limit(5)
        .get();
    if (q.empty) {
      throw new functions.https.HttpsError("not-found", "Pesanan untuk rute ini tidak ditemukan.");
    }
  }

  const settings = await billingValidation.getSettingsData(admin.firestore());
  const expected = computeNavPremiumRupiah({
    scope,
    distanceMeters,
    settings,
  });

  if (!productId) {
    productId = `traka_driver_nav_premium_${expected}`;
  }

  const verifyResult = await verifyProductPurchase(packageName, productId, purchaseToken);
  if (!verifyResult.verified) {
    throw new functions.https.HttpsError("failed-precondition", "Pembayaran tidak valid.");
  }

  const paidAmount = billingValidation.parseDriverNavPremiumAmountRupiah(productId);
  if (paidAmount == null || paidAmount <= 0) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "ID produk navigasi premium tidak dikenal.",
    );
  }

  if (paidAmount !== expected) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        `Nominal tidak sesuai tarif saat ini (harus Rp ${expected}).`,
    );
  }

  await userRef.update({
    driverNavPremiumOwedJourney: admin.firestore.FieldValue.delete(),
    driverNavPremiumOwedScope: admin.firestore.FieldValue.delete(),
    driverNavPremiumOwedDistanceM: admin.firestore.FieldValue.delete(),
    driverNavPremiumOwedFeeRupiah: admin.firestore.FieldValue.delete(),
  });

  return { success: true, amountRupiah: paidAmount };
});

// --- Rekonsiliasi navigasi jemput (driver_status vs orders) ---
exports.onOrderNavigationPickupReconcile = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      try {
        const orderId = context.params.orderId;
        const before = change.before.exists ? change.before.data() : null;
        const after = change.after.exists ? change.after.data() : null;
        if (!after) return null;
        const orderRef = change.after.ref;
        await navPickupGuard.reconcileDriverStatusWhenOrderClearsNav(before, after, orderId);
        await navPickupGuard.reconcileOrderNavigatingToPickupIfStale(orderRef, after, orderId);
      } catch (e) {
        console.error("onOrderNavigationPickupReconcile:", e);
      }
      return null;
    });

exports.onDriverStatusNavigationPickupReconcile = functions.firestore
    .document("driver_status/{driverId}")
    .onUpdate(async (change, context) => {
      try {
        const driverId = context.params.driverId;
        await navPickupGuard.reconcileDriverStatusActivePointerIfStale(driverId, change.after);
        await navPickupGuard.reconcilePreviousOrderWhenDriverStatusPointerMoves(change, driverId);
      } catch (e) {
        console.error("onDriverStatusNavigationPickupReconcile:", e);
      }
      return null;
    });

// --- Penumpang: notifikasi saat driver setuju + harga disepakati driver ---
exports.onDriverAgreedPriceNotify = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      try {
        const before = change.before.data();
        const after = change.after.data();
        const beforeDriverAgreed = before.driverAgreed || false;
        const afterDriverAgreed = after.driverAgreed || false;
        const ap = after.agreedPrice;
        const hasPrice = ap != null && ap !== "" && (typeof ap !== "number" || !isNaN(ap));
        if (beforeDriverAgreed || !afterDriverAgreed || !hasPrice) return null;
        const passengerUid = after.passengerUid || "";
        const orderId = context.params.orderId;
        if (!passengerUid) return null;
        const pSnap = await admin.firestore().collection("users").doc(passengerUid).get();
        if (!pSnap.exists) return null;
        const fcmToken = pSnap.data()?.fcmToken;
        if (!fcmToken) return null;
        const driverName = (after.driverName || "Driver").trim();
        const priceStr = String(ap);
        const payload = {
          notification: {
            title: "Driver menyepakati harga",
            body: `${driverName} mengajukan harga Rp ${priceStr}. Buka chat untuk menanggapi.`,
          },
          data: {
            type: "order",
            orderId,
            driverUid: after.driverUid || "",
            driverName,
          },
          token: fcmToken,
          android: {
            priority: "high",
            notification: {
              channelId: "traka_chat",
              priority: "high",
            },
          },
        };
        await sendFcmWithCollapse(payload, {
          collapseKey: `order_${orderId}`,
          tag: `order_${orderId}`,
        });
      } catch (e) {
        console.error("onDriverAgreedPriceNotify:", e);
      }
      return null;
    });

// --- Admin: batalkan pesanan / paksa selesai (Admin SDK, bypass rules) ---
exports.adminCancelOrder = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  await assertCallerIsAdmin(context.auth.uid);
  const orderId = (data?.orderId || "").toString().trim();
  const reason = (data?.reason || "").toString().trim().slice(0, 500);
  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "orderId wajib.");
  }
  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const snap = await orderRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Pesanan tidak ditemukan.");
  }
  await orderRef.update({
    status: "cancelled",
    adminCancelled: true,
    adminCancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    adminCancelReason: reason || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true };
});

exports.adminForceCompleteOrder = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  await assertCallerIsAdmin(context.auth.uid);
  const orderId = (data?.orderId || "").toString().trim();
  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "orderId wajib.");
  }
  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const snap = await orderRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Pesanan tidak ditemukan.");
  }
  const st = (snap.data()?.status || "").toString();
  if (st === "completed") {
    return { success: true, alreadyCompleted: true };
  }
  if (st === "cancelled") {
    throw new functions.https.HttpsError("failed-precondition", "Pesanan sudah dibatalkan.");
  }
  await orderRef.update({
    status: "completed",
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true };
});

// --- Pembebasan kontribusi driver penguji: set contributionTravelPaidUpToRupiah = 999999999 untuk driver di daftar ---
// Daftar UID di Firestore: app_config/contribution_exempt_drivers, field driverUids: ["uid1", "uid2", ...]
// Berjalan otomatis setiap hari jam 00:00 WIB.
exports.updateContributionExemptDrivers = functions.pubsub
    .schedule("0 0 * * *")
    .timeZone("Asia/Jakarta")
    .onRun(async () => {
      const db = admin.firestore();
      const exemptDoc = await db.collection("app_config")
          .doc("contribution_exempt_drivers")
          .get();

      if (!exemptDoc.exists) {
        console.log("contribution_exempt_drivers: doc tidak ada, skip.");
        return null;
      }

      const driverUids = exemptDoc.data()?.driverUids;
      if (!Array.isArray(driverUids) || driverUids.length === 0) {
        console.log("contribution_exempt_drivers: driverUids kosong, skip.");
        return null;
      }

      const EXEMPT_TRAVEL_RUPIAH = 999999999;
      let updated = 0;

      for (const uid of driverUids) {
        if (!uid || typeof uid !== "string") continue;
        try {
          await db.collection("users").doc(uid).update({
            contributionTravelPaidUpToRupiah: EXEMPT_TRAVEL_RUPIAH,
            contributionExemptUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          updated++;
        } catch (e) {
          console.error("updateContributionExemptDrivers: error for", uid, e);
        }
      }

      if (updated > 0) {
        console.log("updateContributionExemptDrivers: updated", updated, "drivers");
      }
      return null;
    });

// --- Pengingat bayar kontribusi harian: kirim FCM ke driver dengan kontribusi belum dibayar jam 9 pagi WIB ---
// Rate limit: max 1x per 24 jam per user (lastPaymentReminderAt)
exports.sendDailyPaymentReminder = functions.pubsub
    .schedule("0 9 * * *")
    .timeZone("Asia/Jakarta")
    .onRun(async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();
      const oneDayAgo = new Date(now.toMillis() - 24 * 60 * 60 * 1000);
      const oneDayAgoTs = admin.firestore.Timestamp.fromDate(oneDayAgo);

      const uidsToCheck = new Set();

      // 1. Driver dengan rute belum lunas (route_sessions)
      const unpaidSessionsSnap = await db.collection("route_sessions")
          .where("contributionPaidAt", "==", null)
          .get();
      for (const doc of unpaidSessionsSnap.docs) {
        const d = doc.data();
        const contribution = (d?.contributionRupiah || 0);
        const driverUid = d?.driverUid || "";
        if (driverUid && contribution > 0) uidsToCheck.add(driverUid);
      }

      // 2. Users dengan outstandingViolationFee > 0
      const violationSnap = await db.collection("users")
          .where("outstandingViolationFee", ">", 0)
          .get();
      for (const doc of violationSnap.docs) uidsToCheck.add(doc.id);

      // 3. Users dengan totalBarangContributionRupiah > 0 (filter unpaid di bawah)
      const barangSnap = await db.collection("users")
          .where("totalBarangContributionRupiah", ">", 0)
          .get();
      for (const doc of barangSnap.docs) uidsToCheck.add(doc.id);

      let sent = 0;
      for (const uid of uidsToCheck) {
        try {
          const userSnap = await db.collection("users").doc(uid).get();
          if (!userSnap.exists) continue;
          const userData = userSnap.data() || {};
          const fcmToken = userData.fcmToken;
          if (!fcmToken) continue;

          const lastReminder = userData.lastPaymentReminderAt;
          if (lastReminder && lastReminder.toMillis && lastReminder.toMillis() > oneDayAgoTs.toMillis()) {
            continue; // Sudah dikirim dalam 24 jam terakhir
          }

          // Hitung mustPay: unpaid travel + unpaid barang + violation
          let unpaidTravel = 0;
          const unpaidSessionsForUser = unpaidSessionsSnap.docs.filter(
            (d) => (d.data()?.driverUid || "") === uid,
          );
          for (const d of unpaidSessionsForUser) {
            unpaidTravel += (d.data()?.contributionRupiah || 0);
          }
          const totalBarang = (userData.totalBarangContributionRupiah || 0);
          const barangPaidUp = (userData.contributionBarangPaidUpToRupiah || 0);
          const unpaidBarang = Math.max(0, totalBarang - barangPaidUp);
          const violationFee = (userData.outstandingViolationFee || 0);

          const mustPay = unpaidTravel > 0 || unpaidBarang > 0 || violationFee > 0;
          if (!mustPay) continue;

          const type = violationFee > 0 && (unpaidTravel + unpaidBarang) === 0 ? "pelanggaran" : "kontribusi";
          await sendPaymentReminderFcm(uid, type);
          await db.collection("users").doc(uid).update({
            lastPaymentReminderAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          sent++;
        } catch (e) {
          console.error("sendDailyPaymentReminder: error for", uid, e);
        }
      }
      if (sent > 0) console.log("sendDailyPaymentReminder: sent", sent, "reminders");
      return null;
    });

// --- Pengingat H-1 pesanan terjadwal: kirim FCM ke penumpang jam 7 pagi WIB ---
// Query orders dengan scheduledDate = besok dan status agreed/picked_up
exports.sendScheduledOrderReminderH1 = functions.pubsub
    .schedule("0 7 * * *")
    .timeZone("Asia/Jakarta")
    .onRun(async () => {
      const db = admin.firestore();
      const now = new Date();
      const wib = new Date(now.getTime() + 7 * 60 * 60 * 1000);
      const y = wib.getUTCFullYear();
      const m = wib.getUTCMonth();
      const day = wib.getUTCDate();
      const tomorrow = new Date(Date.UTC(y, m, day + 1));
      const tomorrowYmd = `${tomorrow.getUTCFullYear()}-${String(tomorrow.getUTCMonth() + 1).padStart(2, "0")}-${String(tomorrow.getUTCDate()).padStart(2, "0")}`;

      const ordersSnap = await db.collection("orders")
          .where("scheduledDate", "==", tomorrowYmd)
          .where("status", "in", ["agreed", "picked_up"])
          .get();

      let sent = 0;
      const seenPassengers = new Set();

      for (const doc of ordersSnap.docs) {
        const data = doc.data();
        const passengerUid = data?.passengerUid;
        const orderId = doc.id;
        if (!passengerUid || seenPassengers.has(passengerUid)) continue;
        seenPassengers.add(passengerUid);

        const userSnap = await db.collection("users").doc(passengerUid).get();
        if (!userSnap.exists) continue;
        const fcmToken = userSnap.data()?.fcmToken;
        if (!fcmToken) continue;

        const payload = {
          notification: {
            title: "Pengingat perjalanan besok",
            body: "Anda punya perjalanan terjadwal besok. Buka aplikasi untuk detail.",
          },
          data: { type: "scheduled_reminder", orderId },
          token: fcmToken,
          android: {
            priority: "high",
            notification: { channelId: "traka_order_channel", priority: "high" },
          },
        };
        try {
          await sendFcmWithCollapse(payload, {
            collapseKey: `scheduled_reminder_${passengerUid}`,
            tag: `scheduled_reminder_${passengerUid}`,
          });
          sent++;
        } catch (e) {
          console.error("sendScheduledOrderReminderH1 FCM error for", orderId, e);
        }
      }

      if (sent > 0) {
        console.log("sendScheduledOrderReminderH1: sent", sent, "reminders for", tomorrowYmd);
      }
      return null;
    });

// Callable: panggil manual untuk update pembebasan kontribusi (tanpa menunggu jadwal).
exports.runContributionExemptUpdate = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  // Opsional: cek apakah user adalah admin (bisa tambah validasi role)
  const db = admin.firestore();
  const exemptDoc = await db.collection("app_config")
      .doc("contribution_exempt_drivers")
      .get();

  if (!exemptDoc.exists) {
    return { success: false, message: "Dokumen contribution_exempt_drivers tidak ada." };
  }

  const driverUids = exemptDoc.data()?.driverUids;
  if (!Array.isArray(driverUids) || driverUids.length === 0) {
    return { success: false, message: "driverUids kosong." };
  }

  const EXEMPT_TRAVEL_RUPIAH = 999999999;
  let updated = 0;

  for (const uid of driverUids) {
    if (!uid || typeof uid !== "string") continue;
    try {
      await db.collection("users").doc(uid).update({
        contributionTravelPaidUpToRupiah: EXEMPT_TRAVEL_RUPIAH,
        contributionExemptUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updated++;
    } catch (e) {
      console.error("runContributionExemptUpdate: error for", uid, e);
    }
  }

  return { success: true, updated };
});

// --- Notifikasi: saat panggilan suara masuk (status ringing), kirim FCM ke callee ---
exports.onVoiceCallRinging = functions.firestore
    .document("voice_calls/{orderId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const status = data?.status || "";
      if (status !== "ringing") return null;
      const calleeUid = data?.calleeUid || "";
      const callerUid = data?.callerUid || "";
      const callerName = (data?.callerName || "Pemanggil").trim();
      if (!calleeUid || !callerUid) return null;

      const calleeSnap = await admin.firestore().collection("users").doc(calleeUid).get();
      if (!calleeSnap.exists) return null;
      const fcmToken = calleeSnap.data()?.fcmToken;
      if (!fcmToken) return null;

      const orderId = context.params.orderId;
      const title = "Panggilan suara masuk";
      const body = `${callerName} memanggil Anda. Buka aplikasi untuk menerima.`;
      // Android: data-only + priority high agar onBackgroundMessage jalan & app bisa
      // tampilkan notifikasi lokal (fullScreenIntent). Pesan "notification" saja sering
      // tertunda saat Doze/layar mati lalu baru muncul saat buka layar.
      // iOS: APNS alert agar tetap ada banner saat app tidak aktif.
      try {
        await admin.messaging().send({
          token: fcmToken,
          data: {
            type: "voice_call",
            orderId: String(orderId),
            callerName: String(callerName),
            callerUid: String(callerUid),
            title,
            body,
          },
          android: {
            priority: "high",
            ttl: 86400000,
            collapseKey: `voice_${orderId}`,
          },
          apns: {
            headers: {
              "apns-priority": "10",
            },
            payload: {
              aps: {
                alert: {
                  title,
                  body,
                },
                sound: "default",
              },
            },
          },
        });
      } catch (e) {
        console.error("FCM onVoiceCallRinging error:", e);
      }
      return null;
    });

// --- Voice call cleanup: hapus subcollection ice dan doc voice_calls saat panggilan selesai ---
// Juga kirim pesan voice_call_status ke chat (seperti WhatsApp: tidak terjawab/ditolak/terjawab)
exports.onVoiceCallEnded = functions.firestore
    .document("voice_calls/{orderId}")
    .onUpdate(async (change, context) => {
      const after = change.after.data();
      const status = after?.status || "";
      if (status !== "ended" && status !== "rejected") return null;

      const orderId = context.params.orderId;
      const db = admin.firestore();
      const callerUid = after?.callerUid || "";
      const connectedAt = after?.connectedAt;
      const endedAt = after?.endedAt;

      // Buat pesan voice_call_status di chat
      let displayText = "";
      if (status === "rejected") {
        displayText = "Panggilan suara ditolak";
      } else if (status === "ended") {
        if (connectedAt && endedAt && connectedAt.toMillis && endedAt.toMillis) {
          const durationSec = Math.max(0, Math.floor((endedAt.toMillis() - connectedAt.toMillis()) / 1000));
          const min = Math.floor(durationSec / 60);
          const sec = durationSec % 60;
          if (min > 0) {
            displayText = `Panggilan suara (${min} menit ${sec} detik)`;
          } else {
            displayText = `Panggilan suara (${sec} detik)`;
          }
        } else {
          displayText = "Panggilan suara tidak terjawab";
        }
      }
      if (displayText && callerUid) {
        try {
          await db.collection("orders").doc(orderId).collection("messages").add({
            senderUid: callerUid,
            text: displayText,
            type: "voice_call_status",
            voiceCallStatus: status,
            voiceCallDurationSeconds: (connectedAt && endedAt && connectedAt.toMillis && endedAt.toMillis)
              ? Math.max(0, Math.floor((endedAt.toMillis() - connectedAt.toMillis()) / 1000))
              : null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            status: "sent",
          });
        } catch (e) {
          console.error("onVoiceCallEnded: gagal tambah pesan chat", e);
        }
      }

      const iceRef = db.collection("voice_calls").doc(orderId).collection("ice");
      const BATCH_SIZE = 400;
      let snap = await iceRef.limit(BATCH_SIZE).get();
      while (!snap.empty) {
        const batch = db.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (snap.docs.length < BATCH_SIZE) break;
        snap = await iceRef.limit(BATCH_SIZE).get();
      }

      await change.after.ref.delete();
      console.log("Voice call cleanup: deleted voice_calls/", orderId);
      return null;
    });

// --- Voice call cleanup: hapus voice_calls lama (ended/rejected > 24 jam) - backup jika onUpdate terlewat ---
exports.cleanupOldVoiceCalls = functions.pubsub
    .schedule("every 6 hours")
    .onRun(async () => {
      const db = admin.firestore();
      const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      // Query ended dan rejected terpisah (hindari composite index)
      const [endedSnap, rejectedSnap] = await Promise.all([
        db.collection("voice_calls").where("status", "==", "ended")
            .where("updatedAt", "<", cutoffTs).limit(50).get(),
        db.collection("voice_calls").where("status", "==", "rejected")
            .where("updatedAt", "<", cutoffTs).limit(50).get(),
      ]);
      const allDocs = [...endedSnap.docs, ...rejectedSnap.docs];

      for (const doc of allDocs) {
        try {
          const iceRef = doc.ref.collection("ice");
          let iceSnap = await iceRef.limit(400).get();
          while (!iceSnap.empty) {
            const batch = db.batch();
            iceSnap.docs.forEach((d) => batch.delete(d.ref));
            await batch.commit();
            if (iceSnap.docs.length < 400) break;
            iceSnap = await iceRef.limit(400).get();
          }
          await doc.ref.delete();
        } catch (e) {
          console.error("cleanupOldVoiceCalls error for", doc.id, e);
        }
      }
      if (allDocs.length > 0) {
        console.log("cleanupOldVoiceCalls: deleted", allDocs.length, "old voice_calls");
      }
      return null;
    });

// --- Hapus akun permanen: user dengan scheduledDeletionAt sudah lewat (grace period 30 hari) ---
exports.deleteScheduledAccounts = functions.pubsub
    .schedule("0 2 * * *")
    .timeZone("Asia/Jakarta")
    .onRun(async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      const usersSnap = await db.collection("users")
          .where("scheduledDeletionAt", "<=", now)
          .limit(20)
          .get();

      for (const doc of usersSnap.docs) {
        const uid = doc.id;
        const data = doc.data();
        if (!data.deletedAt || !data.scheduledDeletionAt) continue;
        try {
          await admin.auth().deleteUser(uid);
          await doc.ref.delete();
          console.log("deleteScheduledAccounts: deleted user", uid);
        } catch (e) {
          console.error("deleteScheduledAccounts: error for", uid, e);
        }
      }
      if (usersSnap.size > 0) {
        console.log("deleteScheduledAccounts: processed", usersSnap.size, "accounts");
      }
      return null;
    });

// --- Hapus chat (messages) 24 jam setelah pesanan selesai. Order doc TIDAK dihapus (riwayat driver/penumpang tetap). ---
const SCHEDULE_HOURS = 24;
const BATCH_SIZE = 400;

exports.deleteCompletedOrderChats = functions.pubsub
    .schedule("every 1 hours")
    .onRun(async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();
      const cutoff = new Date(now.toMillis() - SCHEDULE_HOURS * 60 * 60 * 1000);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

      const ordersSnap = await db.collection("orders")
          .where("status", "==", "completed")
          .where("completedAt", "<", cutoffTs)
          .limit(50)
          .get();

      // Hanya hapus messages (isi chat). Dokumen order TIDAK dihapus agar riwayat driver/penumpang tetap ada.
      for (const orderDoc of ordersSnap.docs) {
        const messagesRef = orderDoc.ref.collection("messages");
        let snap = await messagesRef.orderBy("createdAt").limit(BATCH_SIZE).get();
        while (!snap.empty) {
          const batch = db.batch();
          snap.docs.forEach((d) => batch.delete(d.ref));
          await batch.commit();
          if (snap.docs.length < BATCH_SIZE) break;
          const last = snap.docs[snap.docs.length - 1];
          snap = await messagesRef.orderBy("createdAt").startAfter(last).limit(BATCH_SIZE).get();
        }
      }
      if (ordersSnap.size > 0) {
        console.log("Deleted chat messages (not order docs) for", ordersSnap.size, "completed orders");
      }
      return null;
    });

// --- Broadcast notifikasi ke semua user (admin only) ---
exports.broadcastNotification = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const adminSnap = await admin.firestore().collection("users").doc(context.auth.uid).get();
  if (!adminSnap.exists || adminSnap.data()?.role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Hanya admin yang dapat broadcast.");
  }
  const title = (data?.title || "Traka").toString().trim() || "Traka";
  const body = (data?.body || "").toString().trim();
  if (!body) {
    throw new functions.https.HttpsError("invalid-argument", "Isi pesan wajib.");
  }
  const payload = {
    topic: "traka_broadcast",
    notification: { title, body },
    android: { priority: "high" },
  };
  await admin.messaging().send(payload);
  return { success: true };
});

// Migrasi: update order kirim_barang lama yang belum punya barangCategory → set 'kargo'.
// Panggil sekali via Firebase Console > Functions > migrateKirimBarangCategory.
exports.migrateKirimBarangCategory = callable.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login.");
  }
  const db = admin.firestore();
  const ordersRef = db.collection("orders");
  const snap = await ordersRef
      .where("orderType", "==", "kirim_barang")
      .get();

  const toUpdate = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const cat = d?.barangCategory;
    if (!cat || (typeof cat === "string" && cat.trim() === "")) {
      toUpdate.push(doc.ref);
    }
  }

  if (toUpdate.length === 0) {
    return { success: true, updated: 0, message: "Tidak ada order yang perlu diupdate." };
  }

  const BATCH_SIZE = 500;
  let updated = 0;
  for (let i = 0; i < toUpdate.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = toUpdate.slice(i, i + BATCH_SIZE);
    for (const ref of chunk) {
      batch.update(ref, {
        barangCategory: "kargo",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updated++;
    }
    await batch.commit();
  }

  console.log("migrateKirimBarangCategory: updated", updated, "orders");
  return { success: true, updated };
});

// --- Recovery: nomor hilang / tidak aktif ---
// Set RECOVERY_ADMIN_SECRET di Firebase Console > Functions > Environment variables

const RECOVERY_CODE_LENGTH = 8;
const RECOVERY_CODE_EXPIRE_MINUTES = 15;
const RECOVERY_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // tanpa 0,O,1,I

function generateRecoveryCode() {
  let code = "";
  for (let i = 0; i < RECOVERY_CODE_LENGTH; i++) {
    code += RECOVERY_CODE_CHARS.charAt(
      Math.floor(Math.random() * RECOVERY_CODE_CHARS.length)
    );
  }
  return code;
}

/** Admin: generate kode recovery untuk user (nomor hilang). Verifikasi identitas dulu. */
/** Dapat dipanggil dari: (1) script dengan adminSecret, (2) web admin (user login dengan role=admin). */
exports.createRecoveryToken = callable.onCall(async (data, context) => {
  const uid = data?.uid;
  if (!uid || typeof uid !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "uid wajib diisi.");
  }
  let allowed = false;
  const adminSecret = process.env.RECOVERY_ADMIN_SECRET;
  const secret = data?.adminSecret;
  if (adminSecret && secret === adminSecret) {
    allowed = true;
  } else if (context.auth) {
    const callerSnap = await admin.firestore().collection("users").doc(context.auth.uid).get();
    const callerRole = callerSnap.exists ? callerSnap.data()?.role : null;
    if (callerRole === "admin") allowed = true;
  }
  if (!allowed) {
    throw new functions.https.HttpsError("permission-denied", "Akses ditolak.");
  }
  const userRecord = await admin.auth().getUser(uid).catch(() => null);
  if (!userRecord) {
    throw new functions.https.HttpsError("not-found", "User tidak ditemukan.");
  }
  const customToken = await admin.auth().createCustomToken(uid);
  let code = generateRecoveryCode();
  const db = admin.firestore();
  const ref = db.collection("recovery_codes").doc(code);
  const exists = await ref.get();
  if (exists.exists) {
    code = generateRecoveryCode();
  }
  await ref.set({
    token: customToken,
    uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  // TTL: hapus setelah 15 menit (Firestore TTL atau cron)
  return { code, expiresInMinutes: RECOVERY_CODE_EXPIRE_MINUTES };
});

/** User: pakai kode recovery untuk login (one-time use). */
exports.consumeRecoveryCode = callable.onCall(async (data) => {
  const code = (data?.code || "").toString().trim().toUpperCase();
  if (!code || code.length !== RECOVERY_CODE_LENGTH) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Kode recovery tidak valid."
    );
  }
  const db = admin.firestore();
  const ref = db.collection("recovery_codes").doc(code);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
      "not-found",
      "Kode tidak ditemukan atau sudah dipakai."
    );
  }
  const d = snap.data();
  const token = d?.token;
  const createdAt = d?.createdAt?.toMillis?.() || 0;
  const ageMinutes = (Date.now() - createdAt) / 60000;
  if (ageMinutes > RECOVERY_CODE_EXPIRE_MINUTES) {
    await ref.delete();
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Kode sudah kedaluwarsa."
    );
  }
  await ref.delete();
  return { token };
});

// --- Bukti struk publik (profil.html?bukti=) — TTL 6 hari, anti pemalsuan PDF ---
const PUBLIC_RECEIPT_ORIGINS = [
  "https://syafiul-traka.web.app",
  "https://syafiul-traka.firebaseapp.com",
  "http://localhost:5000",
  "http://127.0.0.1:5000",
];

function setCorsPublicReceipt(req, res) {
  const origin = (req.headers.origin || "").toString();
  if (PUBLIC_RECEIPT_ORIGINS.includes(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
  } else {
    res.set("Access-Control-Allow-Origin", "https://syafiul-traka.web.app");
  }
  res.set("Vary", "Origin");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
}

/** Verifikasi token tanpa login (dipanggil dari hosting profil.html). */
exports.getPublicReceiptProof = functions.https.onRequest(async (req, res) => {
  setCorsPublicReceipt(req, res);
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  if (req.method !== "GET") {
    res.status(405).json({ status: "method_not_allowed" });
    return;
  }
  const token = (req.query.token || req.query.bukti || "").toString().trim();
  if (!token || token.length < 48) {
    res.status(200).json({ status: "invalid" });
    return;
  }
  try {
    const doc = await admin
      .firestore()
      .collection(publicReceiptProof.COLLECTION)
      .doc(token)
      .get();
    if (!doc.exists) {
      res.status(200).json({ status: "not_issued" });
      return;
    }
    const d = doc.data();
    const exp = d.expiresAt?.toMillis?.() || 0;
    if (Date.now() > exp) {
      res.status(200).json({
        status: "expired",
        message:
          "Bukti ini sudah lewat masa berlaku (6 hari sejak diterbitkan). Untuk keperluan resmi, hubungi admin Traka melalui kanal resmi aplikasi atau email support.",
      });
      return;
    }
    res.status(200).json({
      status: "ok",
      data: publicReceiptProof.sanitizeForPublic(d),
    });
  } catch (e) {
    console.error("getPublicReceiptProof", e);
    res.status(500).json({ status: "error" });
  }
});

/** Penumpang/penerima: terbitkan token bukti untuk order selesai (sebelum PDF / QR). */
exports.issuePublicReceiptProof = callable.onCall(async (data, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Login diperlukan.");
  }
  const orderId = (data?.orderId || "").toString().trim();
  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "orderId wajib.");
  }
  const uid = context.auth.uid;
  const orderSnap = await admin.firestore().collection("orders").doc(orderId).get();
  if (!orderSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Pesanan tidak ditemukan.");
  }
  const o = orderSnap.data();
  if (o.status !== "completed") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Hanya pesanan selesai yang bisa diterbitkan bukti."
    );
  }
  const isPassengerSide = publicReceiptProof.isParticipant(uid, o);
  const isDriverSide = publicReceiptProof.isDriver(uid, o);
  if (!isPassengerSide && !isDriverSide) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Anda bukan pihak pada pesanan ini."
    );
  }
  const orderFields = {
    kind: isDriverSide ? "driver_order" : "passenger_order",
    orderNumber: o.orderNumber || null,
    orderType: o.orderType || "travel",
    completedAt: o.completedAt || null,
    originText: (o.originText || "").slice(0, 500),
    destText: (o.destText || "").slice(0, 500),
    agreedPriceRupiah: o.agreedPrice != null ? Number(o.agreedPrice) : null,
    tripFareRupiah: o.tripFareRupiah != null ? Number(o.tripFareRupiah) : null,
    tripBarangFareRupiah:
      o.tripBarangFareRupiah != null ? Number(o.tripBarangFareRupiah) : null,
  };
  const db = admin.firestore();
  const { token, reused } = await publicReceiptProof.findOrCreateProof(
    db,
    orderId,
    orderFields
  );
  return {
    token,
    reused,
    verifyUrl: `https://syafiul-traka.web.app/profil.html?bukti=${encodeURIComponent(token)}`,
  };
});
