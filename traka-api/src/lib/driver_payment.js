/**
 * Metode pembayaran driver — normalisasi nama/nomor, Firestore + Postgres.
 */

const crypto = require('crypto');
const admin = require('firebase-admin');
const { initFirebase } = require('./auth.js');
const { getPg } = require('./pg.js');

const COLLECTION = 'driver_payment_methods';

function normalizeName(s) {
  return String(s || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function namesMatch(profileName, holderName) {
  return normalizeName(profileName) === normalizeName(holderName);
}

function digitsOnly(s) {
  return String(s || '').replace(/\D/g, '');
}

function slugPart(s) {
  return String(s || '')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, '_')
    .replace(/[^a-z0-9_]/g, '')
    .slice(0, 48);
}

function buildNormalizedKey(type, accountNumber, bankOrProvider, qrisUrl, driverUid) {
  const t = type === 'ewallet' ? 'ewallet' : type === 'qris' ? 'qris' : 'bank';
  if (t === 'qris') {
    const url = String(qrisUrl || '').trim();
    if (!url) return `qris:${driverUid}:${crypto.randomBytes(8).toString('hex')}`;
    const h = crypto.createHash('sha256').update(url).digest('hex').slice(0, 32);
    return `qris:${h}`;
  }
  const digits = digitsOnly(accountNumber);
  const prov = slugPart(bankOrProvider) || 'x';
  return `${t}:${prov}:${digits}`;
}

function getFirestoreDb() {
  initFirebase();
  if (!admin.apps?.length) return null;
  return admin.firestore();
}

async function getUserDisplayName(uid) {
  const db = getFirestoreDb();
  if (!db) return '';
  const doc = await db.collection('users').doc(uid).get();
  if (!doc.exists) return '';
  const d = doc.data();
  return String(d.displayName || '').trim();
}

async function assertOrderParticipant(orderId, uid) {
  const db = getFirestoreDb();
  if (!db) throw new Error('Firestore not available');
  const doc = await db.collection('orders').doc(orderId).get();
  if (!doc.exists) return { ok: false, code: 404 };
  const o = doc.data();
  const driverUid = o.driverUid;
  const passengerUid = o.passengerUid;
  const receiverUid = o.receiverUid || '';
  if (uid !== driverUid && uid !== passengerUid && uid !== receiverUid) {
    return { ok: false, code: 403 };
  }
  return { ok: true, order: o, driverUid };
}

function rowToApi(row) {
  return {
    id: row.id,
    driverUid: row.driver_uid,
    type: row.type,
    bankName: row.bank_name || null,
    ewalletProvider: row.ewallet_provider || null,
    accountNumber: row.account_number || null,
    accountHolderName: row.account_holder_name || null,
    qrisImageUrl: row.qris_image_url || null,
    status: row.status,
    profileMismatch: row.profile_mismatch,
    adminNote: row.admin_note || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function firestoreSetMethod(id, payload) {
  const db = getFirestoreDb();
  if (!db) throw new Error('Firestore not available');
  await db.collection(COLLECTION).doc(id).set(payload, { merge: true });
}

async function firestoreDeleteMethod(id) {
  const db = getFirestoreDb();
  if (!db) throw new Error('Firestore not available');
  await db.collection(COLLECTION).doc(id).delete();
}

/**
 * @param {object} body - type, bankName?, ewalletProvider?, accountNumber?, accountHolderName?, qrisImageUrl?
 */
async function createMethod(driverUid, body) {
  const pg = getPg();
  if (!pg) {
    const err = new Error(
      'PostgreSQL required for payment methods. Run scripts/migration_driver_payment_methods.sql',
    );
    err.statusCode = 503;
    throw err;
  }

  const type = body.type === 'ewallet' ? 'ewallet' : body.type === 'qris' ? 'qris' : 'bank';
  const bankName = type === 'bank' ? String(body.bankName || '').trim() : null;
  const ewalletProvider = type === 'ewallet' ? String(body.ewalletProvider || '').trim() : null;
  const accountNumber =
    type === 'qris' ? null : String(body.accountNumber || '').replace(/\s/g, '').trim();
  const accountHolderName = String(body.accountHolderName || '').trim();
  const qrisImageUrl = type === 'qris' ? String(body.qrisImageUrl || '').trim() : null;

  if (type !== 'qris' && !accountNumber) {
    const err = new Error('accountNumber required');
    err.statusCode = 400;
    throw err;
  }
  if (!accountHolderName) {
    const err = new Error('accountHolderName required');
    err.statusCode = 400;
    throw err;
  }
  if (type === 'bank' && !bankName) {
    const err = new Error('bankName required');
    err.statusCode = 400;
    throw err;
  }
  if (type === 'ewallet' && !ewalletProvider) {
    const err = new Error('ewalletProvider required');
    err.statusCode = 400;
    throw err;
  }
  if (type === 'qris' && !qrisImageUrl) {
    const err = new Error('qrisImageUrl required');
    err.statusCode = 400;
    throw err;
  }
  if (qrisImageUrl && !qrisImageUrl.startsWith('https://')) {
    const err = new Error('qrisImageUrl must be https');
    err.statusCode = 400;
    throw err;
  }

  const profileName = await getUserDisplayName(driverUid);
  const profileMismatch = !namesMatch(profileName, accountHolderName);
  const status = profileMismatch ? 'pending_review' : 'active';

  const bankOrProvider = type === 'bank' ? bankName : type === 'ewallet' ? ewalletProvider : '';
  const normalizedKey = buildNormalizedKey(
    type,
    accountNumber,
    bankOrProvider,
    qrisImageUrl,
    driverUid,
  );

  const id = crypto.randomUUID();
  const now = new Date();

  try {
    await pg.query(
      `INSERT INTO driver_payment_methods (
        id, driver_uid, type, bank_name, ewallet_provider, account_number,
        account_holder_name, qris_image_url, normalized_key, status, profile_mismatch,
        created_at, updated_at
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
      [
        id,
        driverUid,
        type,
        bankName,
        ewalletProvider,
        accountNumber,
        accountHolderName,
        qrisImageUrl,
        normalizedKey,
        status,
        profileMismatch,
        now,
        now,
      ],
    );
  } catch (e) {
    if (e.code === '23505') {
      const err = new Error('duplicate_payment_account');
      err.statusCode = 409;
      throw err;
    }
    throw e;
  }

  const fsPayload = {
    driverUid,
    type,
    bankName: bankName || '',
    ewalletProvider: ewalletProvider || '',
    accountNumber: accountNumber || '',
    accountHolderName,
    qrisImageUrl: qrisImageUrl || '',
    normalizedKey,
    status,
    profileMismatch,
    adminNote: '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await firestoreSetMethod(id, fsPayload);

  return {
    id,
    status,
    profileMismatch,
    message: profileMismatch
      ? 'Nama pemilik tidak sama dengan nama profil. Hubungi admin untuk menyamakan atau tunggu persetujuan.'
      : undefined,
  };
}

async function listByDriver(driverUid) {
  const pg = getPg();
  if (pg) {
    const r = await pg.query(
      `SELECT * FROM driver_payment_methods WHERE driver_uid = $1 AND status <> 'suspended' ORDER BY created_at DESC`,
      [driverUid],
    );
    return r.rows.map(rowToApi);
  }
  const db = getFirestoreDb();
  if (!db) return [];
  const snap = await db
    .collection(COLLECTION)
    .where('driverUid', '==', driverUid)
    .get();
  return snap.docs
    .map((d) => {
      const x = d.data();
      return {
        id: d.id,
        driverUid: x.driverUid,
        type: x.type,
        bankName: x.bankName || null,
        ewalletProvider: x.ewalletProvider || null,
        accountNumber: x.accountNumber || null,
        accountHolderName: x.accountHolderName || null,
        qrisImageUrl: x.qrisImageUrl || null,
        status: x.status,
        profileMismatch: !!x.profileMismatch,
        adminNote: x.adminNote || null,
      };
    })
    .filter((x) => x.status !== 'suspended');
}

async function listActiveForDriver(driverUid) {
  const all = await listByDriver(driverUid);
  return all.filter((m) => m.status === 'active');
}

async function listPendingReview() {
  const pg = getPg();
  if (pg) {
    const r = await pg.query(
      `SELECT * FROM driver_payment_methods WHERE status = 'pending_review' ORDER BY created_at ASC`,
    );
    return r.rows.map(rowToApi);
  }
  const db = getFirestoreDb();
  if (!db) return [];
  const snap = await db.collection(COLLECTION).where('status', '==', 'pending_review').get();
  return snap.docs.map((d) => {
    const x = d.data();
    return {
      id: d.id,
      driverUid: x.driverUid,
      type: x.type,
      bankName: x.bankName || null,
      ewalletProvider: x.ewalletProvider || null,
      accountNumber: x.accountNumber || null,
      accountHolderName: x.accountHolderName || null,
      qrisImageUrl: x.qrisImageUrl || null,
      status: x.status,
      profileMismatch: !!x.profileMismatch,
      adminNote: x.adminNote || null,
    };
  });
}

async function updateMethod(id, driverUid, body) {
  const pg = getPg();
  if (!pg) {
    const err = new Error('PostgreSQL required for payment method updates');
    err.statusCode = 503;
    throw err;
  }
  const r = await pg.query(`SELECT * FROM driver_payment_methods WHERE id = $1`, [id]);
  const row = r.rows[0];
  if (!row) {
    const err = new Error('Not found');
    err.statusCode = 404;
    throw err;
  }
  if (row.driver_uid !== driverUid) {
    const err = new Error('Forbidden');
    err.statusCode = 403;
    throw err;
  }

  const nextHolder = body.accountHolderName != null ? String(body.accountHolderName).trim() : row.account_holder_name;
  const profileName = await getUserDisplayName(driverUid);
  const profileMismatch = !namesMatch(profileName, nextHolder);
  let nextStatus = row.status;
  if (profileMismatch && row.status === 'active') nextStatus = 'pending_review';
  if (!profileMismatch && row.status === 'pending_review') nextStatus = 'active';

  const type = row.type;
  const bankName = body.bankName != null ? String(body.bankName).trim() : row.bank_name;
  const ewalletProvider =
    body.ewalletProvider != null ? String(body.ewalletProvider).trim() : row.ewallet_provider;
  let accountNumber = row.account_number;
  if (body.accountNumber != null && type !== 'qris') {
    accountNumber = String(body.accountNumber).replace(/\s/g, '').trim();
  }
  const qrisImageUrl =
    body.qrisImageUrl != null ? String(body.qrisImageUrl).trim() : row.qris_image_url;

  if (type === 'qris' && body.qrisImageUrl != null) {
    const q = String(body.qrisImageUrl).trim();
    if (!q) {
      const err = new Error('qrisImageUrl required');
      err.statusCode = 400;
      throw err;
    }
    if (!q.startsWith('https://')) {
      const err = new Error('qrisImageUrl must be https');
      err.statusCode = 400;
      throw err;
    }
  }

  const bankOrProvider = type === 'bank' ? bankName : type === 'ewallet' ? ewalletProvider : '';
  const normalizedKey = buildNormalizedKey(
    type,
    accountNumber,
    bankOrProvider,
    qrisImageUrl,
    driverUid,
  );

  if (normalizedKey !== row.normalized_key) {
    try {
      await pg.query(
        `UPDATE driver_payment_methods SET
          bank_name = $2, ewallet_provider = $3, account_number = $4, account_holder_name = $5,
          qris_image_url = $6, normalized_key = $7, status = $8, profile_mismatch = $9, updated_at = NOW()
        WHERE id = $1`,
        [
          id,
          bankName,
          ewalletProvider,
          accountNumber,
          nextHolder,
          qrisImageUrl,
          normalizedKey,
          nextStatus,
          profileMismatch,
        ],
      );
    } catch (e) {
      if (e.code === '23505') {
        const err = new Error('duplicate_payment_account');
        err.statusCode = 409;
        throw err;
      }
      throw e;
    }
  } else {
    await pg.query(
      `UPDATE driver_payment_methods SET
        bank_name = $2, ewallet_provider = $3, account_number = $4, account_holder_name = $5,
        qris_image_url = $6, status = $7, profile_mismatch = $8, updated_at = NOW()
      WHERE id = $1`,
      [
        id,
        bankName,
        ewalletProvider,
        accountNumber,
        nextHolder,
        qrisImageUrl,
        nextStatus,
        profileMismatch,
      ],
    );
  }

  await firestoreSetMethod(id, {
    driverUid,
    type: row.type,
    bankName: bankName || '',
    ewalletProvider: ewalletProvider || '',
    accountNumber: accountNumber || '',
    accountHolderName: nextHolder,
    qrisImageUrl: qrisImageUrl || '',
    normalizedKey,
    status: nextStatus,
    profileMismatch,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { id, status: nextStatus, profileMismatch };
}

async function suspendMethod(id, driverUid) {
  const pg = getPg();
  if (!pg) {
    const err = new Error('PostgreSQL required');
    err.statusCode = 503;
    throw err;
  }
  const r = await pg.query(`SELECT driver_uid FROM driver_payment_methods WHERE id = $1`, [id]);
  const row = r.rows[0];
  if (!row) {
    const err = new Error('Not found');
    err.statusCode = 404;
    throw err;
  }
  if (row.driver_uid !== driverUid) {
    const err = new Error('Forbidden');
    err.statusCode = 403;
    throw err;
  }
  await pg.query(
    `UPDATE driver_payment_methods SET status = 'suspended', updated_at = NOW() WHERE id = $1`,
    [id],
  );
  await firestoreDeleteMethod(id);
  return { ok: true };
}

async function adminSetStatus(id, status, adminNote) {
  const pg = getPg();
  if (!pg) {
    const err = new Error('PostgreSQL required');
    err.statusCode = 503;
    throw err;
  }
  const st = status === 'active' || status === 'suspended' ? status : null;
  if (!st) {
    const err = new Error('Invalid status');
    err.statusCode = 400;
    throw err;
  }
  const r = await pg.query(`SELECT * FROM driver_payment_methods WHERE id = $1`, [id]);
  const row = r.rows[0];
  if (!row) {
    const err = new Error('Not found');
    err.statusCode = 404;
    throw err;
  }
  await pg.query(
    `UPDATE driver_payment_methods SET status = $2, admin_note = $3, profile_mismatch = $4, updated_at = NOW() WHERE id = $1`,
    [id, st, adminNote || null, st === 'active' ? false : row.profile_mismatch],
  );

  if (st === 'suspended') {
    await firestoreDeleteMethod(id);
  } else {
    await firestoreSetMethod(id, {
      driverUid: row.driver_uid,
      type: row.type,
      bankName: row.bank_name || '',
      ewalletProvider: row.ewallet_provider || '',
      accountNumber: row.account_number || '',
      accountHolderName: row.account_holder_name,
      qrisImageUrl: row.qris_image_url || '',
      normalizedKey: row.normalized_key,
      status: 'active',
      profileMismatch: false,
      adminNote: adminNote || '',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  return { ok: true, id, status: st };
}

module.exports = {
  normalizeName,
  namesMatch,
  buildNormalizedKey,
  createMethod,
  listByDriver,
  listActiveForDriver,
  listPendingReview,
  updateMethod,
  suspendMethod,
  adminSetStatus,
  assertOrderParticipant,
  rowToApi,
};
