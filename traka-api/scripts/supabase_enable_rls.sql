-- =============================================================================
-- Traka — atasi Security Advisor (rls_disabled_in_public) + policy untuk JWT user
-- Jalankan di Supabase SQL Editor (role postgres). Aman dijalankan ulang.
--
-- • anon: tidak ada policy → tidak ada baris lewat PostgREST.
-- • authenticated: hanya SELECT sesuai Firebase UID (= auth.uid()::text) jika Anda
--   menghubungkan Supabase Auth / JWT custom dengan UID yang sama.
-- • traka-api (DATABASE_URL user postgres) & service_role: bypass RLS (tetap full akses).
--
-- App Traka saat ini pakai Firebase + REST API; policy ini “siap pakai” untuk
-- integrasi Supabase client nanti tanpa membuka INSERT/UPDATE dari klien.
-- =============================================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_payment_methods ENABLE ROW LEVEL SECURITY;

-- ----- public.users -----
DROP POLICY IF EXISTS "traka_users_select_own" ON public.users;
CREATE POLICY "traka_users_select_own"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (id = (auth.uid())::text);

-- ----- public.orders -----
DROP POLICY IF EXISTS "traka_orders_select_participant" ON public.orders;
CREATE POLICY "traka_orders_select_participant"
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    (auth.uid())::text = "passengerUid"
    OR (auth.uid())::text = "driverUid"
    OR (
      "receiverUid" IS NOT NULL
      AND (auth.uid())::text = "receiverUid"
    )
  );

-- ----- public.driver_payment_methods -----
DROP POLICY IF EXISTS "traka_driver_payment_select_own" ON public.driver_payment_methods;
CREATE POLICY "traka_driver_payment_select_own"
  ON public.driver_payment_methods
  FOR SELECT
  TO authenticated
  USING (driver_uid = (auth.uid())::text);
