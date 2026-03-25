-- =============================================================================
-- Traka — tempel sekali di Supabase SQL Editor (Primary Database, role postgres)
-- Setelah ini: API Railway bisa menulis kolom travelFarePaidBy saat create order.
-- =============================================================================

-- Kirim barang: siapa bayar ongkos ke driver — 'sender' | 'receiver'. Order lama = sender.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "travelFarePaidBy" TEXT DEFAULT 'sender';

-- (Opsional) cek kolom sudah ada:
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'travelFarePaidBy';
