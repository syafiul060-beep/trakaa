-- Metode pembayaran driver (mirror API + cek unik normalized_key)
-- Jalankan di Postgres yang dipakai traka-api (setelah tabel lain).

CREATE TABLE IF NOT EXISTS driver_payment_methods (
  id TEXT PRIMARY KEY,
  driver_uid TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('bank', 'ewallet', 'qris')),
  bank_name TEXT,
  ewallet_provider TEXT,
  account_number TEXT,
  account_holder_name TEXT,
  qris_image_url TEXT,
  normalized_key TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('draft', 'pending_review', 'active', 'suspended')),
  profile_mismatch BOOLEAN NOT NULL DEFAULT false,
  admin_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_payment_norm_active
  ON driver_payment_methods (normalized_key)
  WHERE status <> 'suspended';

CREATE INDEX IF NOT EXISTS idx_driver_payment_driver ON driver_payment_methods (driver_uid);
CREATE INDEX IF NOT EXISTS idx_driver_payment_status ON driver_payment_methods (status);
