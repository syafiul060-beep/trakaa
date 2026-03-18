/**
 * Verifikasi purchase token Google Play via Android Publisher API.
 * Memerlukan: GOOGLE_PLAY_SERVICE_ACCOUNT_KEY (JSON string) atau
 * GOOGLE_PLAY_SERVICE_ACCOUNT_PATH (path ke file JSON) di environment.
 * Jika tidak dikonfigurasi, mengembalikan false (gagal verifikasi).
 */
const { google } = require("googleapis");

let _androidPublisher = null;

function getAndroidPublisher() {
  if (_androidPublisher) return _androidPublisher;
  const keyJson = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_KEY;
  const keyPath = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PATH;
  let credentials;
  try {
    if (keyJson) {
      credentials = JSON.parse(keyJson);
    } else if (keyPath) {
      const fs = require("fs");
      credentials = JSON.parse(fs.readFileSync(keyPath, "utf8"));
    } else {
      return null;
    }
  } catch (e) {
    console.error("verifyGooglePlay: Failed to load credentials:", e.message);
    return null;
  }
  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  _androidPublisher = google.androidpublisher({ version: "v3", auth });
  return _androidPublisher;
}

/**
 * Verifikasi in-app product purchase.
 * @param {string} packageName - Package name app (e.g. id.traka.app)
 * @param {string} productId - SKU product (e.g. traka_contribution_once)
 * @param {string} purchaseToken - Token dari device
 * @returns {Promise<{verified: boolean, orderId?: string, purchaseState?: number}>}
 */
async function verifyProductPurchase(packageName, productId, purchaseToken) {
  const android = getAndroidPublisher();
  if (!android) {
    console.warn("verifyGooglePlay: GOOGLE_PLAY_SERVICE_ACCOUNT not configured");
    return { verified: false };
  }
  try {
    const res = await android.purchases.products.get({
      packageName,
      productId,
      token: purchaseToken,
    });
    const data = res.data;
    const purchaseState = data.purchaseState ?? -1;
    // 0 = Purchased, 1 = Canceled, 2 = Pending
    if (purchaseState !== 0) {
      return { verified: false, purchaseState };
    }
    return {
      verified: true,
      orderId: data.orderId || null,
      purchaseState,
    };
  } catch (e) {
    console.error("verifyGooglePlay:", e.message);
    return { verified: false };
  }
}

module.exports = { verifyProductPurchase };
