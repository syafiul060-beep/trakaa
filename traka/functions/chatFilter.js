/**
 * Filter chat untuk mencegah pengguna mengarahkan/diarahkan ke luar aplikasi Traka.
 * Digunakan di Cloud Function onChatMessageCreated (server-side backup).
 */

const BLOCKED_PATTERNS = [
  // Nomor HP Indonesia
  /08[\d\s\-]{8,15}/,
  /\+62[\d\s\-]{8,15}/,
  /\b62[\d\s\-]{9,15}/,
  /0\d{9,12}/,
  // Link WhatsApp
  /wa\.me/i,
  /whatsapp\.com/i,
  /chat\.whatsapp\.com/i,
  // Link platform lain
  /t\.me\//i,
  /telegram\.me/i,
  /line\.me/i,
  /line:\/\//i,
  // Short links (redirect ke mana saja)
  /bit\.ly\//i,
  /goo\.gl\//i,
  /tinyurl\.com/i,
  /t\.co\//i,
  // Sosmed / platform eksternal
  /instagram\.com/i,
  /tiktok\.com/i,
  /facebook\.com/i,
  /fb\.me/i,
  /twitter\.com/i,
  /x\.com\//i,
  // Nomor rekening
  /(?:norek|rekening|no\.?\s*rek)[:\s]*\d{8,16}/i,
  // Kata kunci
  /whatsapp|wa\s*me|chat\s*wa/i,
  /transfer\s+ke|norek|no\s*rek|rekening/i,
  /bayar\s*manual|deal\s*luar|luar\s*aplikasi/i,
  /hubungi\s+saya|kontak\s+saya|nomor\s+saya/i,
  /dilibank|ovo\s*dana|dana\s*ovo/i,
  // Email
  /[\w.+-]+@[\w-]+\.[\w.-]+/,
];

/**
 * Cek apakah teks mengandung konten yang diblokir.
 * @param {string} text
 * @returns {boolean}
 */
function containsBlockedContent(text) {
  if (!text || typeof text !== "string") return false;
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) return false;
  return BLOCKED_PATTERNS.some((re) => re.test(normalized));
}

module.exports = { containsBlockedContent };
