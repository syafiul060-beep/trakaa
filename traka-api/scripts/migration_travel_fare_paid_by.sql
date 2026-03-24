-- Siapa bayar ongkos travel (kirim barang): sender | receiver. Default sender (order lama).
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "travelFarePaidBy" TEXT DEFAULT 'sender';
