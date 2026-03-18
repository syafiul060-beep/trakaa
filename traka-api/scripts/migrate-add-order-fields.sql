-- Migrasi: tambah kolom order dan users yang kurang
-- Jalankan jika schema.sql sudah pernah dijalankan sebelumnya (tabel sudah ada)
-- Supabase SQL Editor atau: psql $DATABASE_URL -f scripts/migrate-add-order-fields.sql

-- Users: region, latitude, longitude
ALTER TABLE users ADD COLUMN IF NOT EXISTS region TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Orders: field baru
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "chatHiddenByReceiver" BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "receiverLastReadAt" TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "driverBarcodePickupPayload" TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "passengerScannedPickupAt" TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "destinationValidationLevel" TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "ferryDistanceKm" DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "tripBarangFareRupiah" DOUBLE PRECISION;

-- Orders: field kirim barang (dokumen/kargo)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangCategory" TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangNama" TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangBeratKg" DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangPanjangCm" DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangLebarCm" DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangTinggiCm" DOUBLE PRECISION;

-- Index receiver
CREATE INDEX IF NOT EXISTS idx_orders_receiver ON orders("receiverUid");
