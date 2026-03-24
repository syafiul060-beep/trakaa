-- Jalankan sekali di Supabase / psql (selaras POST /api/orders + Flutter)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "passengerAppLocale" TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangFotoUrl" TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS "lacakBarangIapFeeRupiah" INT;
