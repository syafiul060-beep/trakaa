/// Lokalisasi untuk Traka – default Bahasa Indonesia.
enum AppLocale { id, en }

class AppLocalizations {
  final AppLocale locale;

  AppLocalizations({this.locale = AppLocale.id});

  // Bahasa
  String get language => locale == AppLocale.id ? 'Bahasa' : 'Language';

  // Logo & branding
  String get appName => 'Traka';
  String get tagline => 'Travel Kalimantan';

  // Form login
  String get emailHint =>
      locale == AppLocale.id ? 'Masukkan email Anda' : 'Enter your email';
  String get passwordHint =>
      locale == AppLocale.id ? 'Masukkan sandi Anda' : 'Enter your password';
  String get loginButton => locale == AppLocale.id ? 'Masuk' : 'Login';
  String get rememberMe => 'Remember Me';
  String get forgotPassword =>
      locale == AppLocale.id ? 'Lupa kata sandi' : 'Forgot password';
  String get register => locale == AppLocale.id ? 'Daftar' : 'Register';
  String get registerPrompt => locale == AppLocale.id
      ? 'Belum Punya Akun...? Daftar'
      : "Don't have an account...? Register";
  String get penumpang => locale == AppLocale.id ? 'Penumpang' : 'Passenger';
  String get driver => 'Driver';

  // Form registrasi
  String get uploadPhoto =>
      locale == AppLocale.id ? 'Silahkan isi foto diri' : 'Upload self photo';
  String get nameHint => locale == AppLocale.id
      ? 'Silahkan isi nama lengkap'
      : 'Please fill in full name';
  String get emailHintRegister => locale == AppLocale.id
      ? 'Silahkan isi alamat email'
      : 'Please fill in email address';
  String get phoneHintRegister => locale == AppLocale.id
      ? 'Contoh: 08123456789'
      : 'Example: 08123456789';
  String get verificationCodeHint => locale == AppLocale.id
      ? 'Masukkan kode verifikasi'
      : 'Enter verification code';
  String get passwordHintRegister => locale == AppLocale.id
      ? 'Masukkan kata sandi anda'
      : 'Enter your password';
  String get confirmPasswordHint =>
      locale == AppLocale.id ? 'Konfirmasi sandi' : 'Confirm password';
  String get passwordRequirement => locale == AppLocale.id
      ? 'Panjang kata sandi minimal 8, harus mengandung angka'
      : 'Password minimum 8 characters, must contain a number';
  String get submitButton => locale == AppLocale.id ? 'Ajukan' : 'Submit';
  String get agreeTerms =>
      'I agree with the Terms of Service and Privacy Policy';
  String get termsOfService => 'Terms of Service';
  String get privacyPolicy => 'Privacy Policy';
  String get backToLogin =>
      locale == AppLocale.id ? 'Kembali ke Login' : 'Back to Login';
  String get registerSuccess => locale == AppLocale.id
      ? 'Pendaftaran berhasil silahkan login'
      : 'Registration successful, please login';
  String get registerFailure => locale == AppLocale.id
      ? 'Pendaftaran belum berhasil silahkan periksa ulang data pendaftaran yang benar'
      : 'Registration failed, please check your registration data';
  String get faceNotDetected => locale == AppLocale.id
      ? 'Wajah tidak terdeteksi. Silakan ulangi pengambilan foto.'
      : 'Face not detected. Please retake the photo.';

  /// Pesan jika lokasi driver di luar Indonesia.
  String get trakaIndonesiaOnly => locale == AppLocale.id
      ? 'Bahwa Traka hanya dapat di gunakan di Indonesia'
      : 'Traka can only be used in Indonesia';

  /// Gagal memperoleh lokasi (untuk driver).
  String get locationError => locale == AppLocale.id
      ? 'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.'
      : 'Unable to get location. Please enable location permission and GPS.';

  /// Peringatan saat Fake GPS / lokasi palsu terdeteksi.
  String get fakeGpsWarning => locale == AppLocale.id
      ? 'Aplikasi Traka melindungi pengguna dari berbagai modus kejahatan yang disengaja, matikan Fake GPS/Lokasi palsu jika ingin menggunakan Traka...!'
      : 'Traka protects users from intentional fraud; turn off Fake GPS/spoofed location to use Traka...!';

  // ——— Navigasi bottom
  String get navHome => locale == AppLocale.id ? 'Beranda' : 'Home';
  String get navSchedule => locale == AppLocale.id ? 'Jadwal' : 'Schedule';
  String get navChat => 'Chat';
  String get navOrders => locale == AppLocale.id ? 'Pesanan' : 'Orders';
  String get navProfile => locale == AppLocale.id ? 'Profil' : 'Profile';

  // ——— Profil & menu
  String get verification => locale == AppLocale.id ? 'Verifikasi' : 'Verification';
  String get settings => locale == AppLocale.id ? 'Pengaturan' : 'Settings';
  String get help => locale == AppLocale.id ? 'Bantuan' : 'Help';
  String get other => locale == AppLocale.id ? 'Lainnya' : 'Other';
  String get verifyData => locale == AppLocale.id ? 'Verifikasi Data' : 'Verify Data';
  String get emailAndPhone => locale == AppLocale.id ? 'Email & No.Telp' : 'Email & Phone';
  String get changePassword => locale == AppLocale.id ? 'Ubah Password' : 'Change Password';
  String get paymentHistory => locale == AppLocale.id ? 'Riwayat Pembayaran' : 'Payment History';
  String get driverEarningsTitle => locale == AppLocale.id ? 'Pendapatan & Potongan' : 'Earnings & Deductions';
  String get driverEarningsEmpty => locale == AppLocale.id
      ? 'Belum ada pendapatan atau potongan. Selesaikan perjalanan untuk melihat ringkasan.'
      : 'No earnings or deductions yet. Complete trips to see summary.';
  String get today => locale == AppLocale.id ? 'Hari ini' : 'Today';
  String get thisWeek => locale == AppLocale.id ? 'Minggu ini' : 'This week';
  String driverEarningsTotal(int count) => locale == AppLocale.id
      ? 'Pendapatan total ($count perjalanan)'
      : 'Total earnings ($count trips)';
  String get driverEarningsDeductionsPaid => locale == AppLocale.id
      ? 'Potongan yang sudah dibayar'
      : 'Deductions paid';
  String get contribution => locale == AppLocale.id ? 'Kontribusi' : 'Contribution';
  String get contributionTariffTitle => locale == AppLocale.id ? 'Tarif Kontribusi' : 'Contribution Rate';
  String get contributionTariffHint => locale == AppLocale.id
      ? 'Lihat tarif travel & kirim barang (Profil > Tarif Kontribusi)'
      : 'View travel & send goods rates (Profile > Contribution Rate)';
  String get contributionTariffDialogTitle => locale == AppLocale.id ? 'Jenis Harga Kontribusi' : 'Contribution Rate Types';
  String get contributionTariffButtonLabel => locale == AppLocale.id ? 'Jenis harga kontribusi' : 'Contribution rates';
  String get contributionTariffTravelLabel => locale == AppLocale.id ? 'Travel (1 penumpang)' : 'Travel (1 passenger)';
  String contributionTariffTravelRates(String t1, String t2, String t3, String min) => locale == AppLocale.id
      ? 'Tarif: dalam provinsi Rp $t1/km, beda provinsi Rp $t2/km, beda pulau Rp $t3/km. Min Rp $min.'
      : 'Rate: same province Rp $t1/km, different province Rp $t2/km, different island Rp $t3/km. Min Rp $min.';
  String contributionTariffExampleTravel(int km) => locale == AppLocale.id
      ? 'Contoh: 1 penumpang, jarak $km km'
      : 'Example: 1 passenger, $km km distance';
  String get contributionTariffBarangLabel => locale == AppLocale.id ? 'Kirim barang' : 'Send goods';
  String contributionTariffBarangRates(String b1, String b2, String b3) => locale == AppLocale.id
      ? 'Tarif: dalam provinsi Rp $b1/km, beda provinsi Rp $b2/km, >1 provinsi Rp $b3/km.'
      : 'Rate: same province Rp $b1/km, different province Rp $b2/km, >1 province Rp $b3/km.';
  String contributionTariffExampleBarang(int km) => locale == AppLocale.id
      ? 'Contoh: 1 kirim barang, jarak $km km'
      : 'Example: 1 send goods, $km km distance';
  String get contributionTariffAdminNote => locale == AppLocale.id
      ? 'Admin dapat mengubah tarif di pengaturan.'
      : 'Admin can change rates in settings.';
  String get contributionTariffTapHint => locale == AppLocale.id
      ? 'Ketuk untuk lihat contoh: 1 penumpang, jarak 50 km = Rp berapa'
      : 'Tap to see example: 1 passenger, 50 km = amount';
  String driverEarningsViolationCount(int count) => locale == AppLocale.id
      ? 'Pelanggaran ($count kali)'
      : 'Violations ($count times)';
  String get driverEarningsOutstanding => locale == AppLocale.id
      ? 'Belum dibayar (pelanggaran)'
      : 'Outstanding (violations)';
  String driverEarningsOutstandingCount(int count) => locale == AppLocale.id
      ? 'Belum dibayar (pelanggaran $count kali)'
      : 'Outstanding ($count violations)';
  String get infoAndPromo => locale == AppLocale.id ? 'Info & Promo' : 'Info & Promo';
  String get guide => locale == AppLocale.id ? 'Panduan' : 'Guide';
  String get suggestionToAdmin => locale == AppLocale.id ? 'Saran ke Admin' : 'Suggestion to Admin';
  String get deleteAccount => locale == AppLocale.id ? 'Hapus akun' : 'Delete account';
  String get showLowRamWarning => locale == AppLocale.id
      ? 'Tampilkan peringatan RAM'
      : 'Show RAM warning';
  String get offlineBannerMessage => locale == AppLocale.id
      ? 'Anda offline. Data dari cache akan tampil. Perubahan akan disinkronkan saat online.'
      : 'You are offline. Cached data will be shown. Changes will sync when online.';
  String get modeLite => locale == AppLocale.id ? 'Mode Lite' : 'Lite Mode';
  String get modeLiteDescription => locale == AppLocale.id
      ? 'Optimasi untuk HP RAM rendah (< 3 GB). Kurangi cache & beban memori. Restart aplikasi untuk menerapkan.'
      : 'Optimized for low-RAM devices (< 3 GB). Reduces cache & memory. Restart app to apply.';
  String get photoDoesNotMeetRequirements => locale == AppLocale.id
      ? 'Foto tidak memenuhi syarat'
      : 'Photo does not meet requirements';
  String get useThisPhoto => locale == AppLocale.id ? 'Pakai foto ini' : 'Use this photo';
  String get changePasswordTitle => locale == AppLocale.id ? 'Ganti Password' : 'Change Password';
  String get addEmailFirstToChangePassword => locale == AppLocale.id
      ? 'Untuk mengubah password, Anda perlu menambahkan dan memverifikasi email terlebih dahulu.'
      : 'To change password, you need to add and verify your email first.';
  String get addEmail => locale == AppLocale.id ? 'Tambah email' : 'Add email';
  String get oldPassword => locale == AppLocale.id ? 'Password lama' : 'Old password';
  String get languageIndonesia => 'Indonesia';
  String get languageEnglish => 'English';
  String get deleteAccountFailed => locale == AppLocale.id
      ? 'Gagal menghapus akun'
      : 'Failed to delete account';
  String get vehiclePlatUsedByOther => locale == AppLocale.id
      ? 'Mobil milik Driver lain'
      : 'Vehicle plate used by another driver';
  String get completeVehicleData => locale == AppLocale.id
      ? 'Mohon lengkapi semua data kendaraan'
      : 'Please complete all vehicle data';
  String get fillDestinationFirst => locale == AppLocale.id
      ? 'Silakan isi tujuan perjalanan terlebih dahulu'
      : 'Please fill in destination first';
  String get waitingPassengerLocation => locale == AppLocale.id
      ? 'Menunggu lokasi penumpang...'
      : 'Waiting for passenger location...';
  String get searchDriverFailed => locale == AppLocale.id
      ? 'Gagal mencari driver'
      : 'Failed to search driver';
  String get passengerPickedUp => locale == AppLocale.id
      ? 'Penumpang sudah dijemput. Kembali ke rute.'
      : 'Passenger picked up. Return to route.';
  String get finishWorkConfirm => locale == AppLocale.id
      ? 'Apakah pekerjaan telah selesai?'
      : 'Is the work finished?';
  String get sendVerificationLink => locale == AppLocale.id
      ? 'Kirim link verifikasi'
      : 'Send verification link';
  String get logout => 'Logout';
  String get save => locale == AppLocale.id ? 'Simpan' : 'Save';
  String get cancel => locale == AppLocale.id ? 'Batal' : 'Cancel';
  String get ok => 'OK';
  String get next => locale == AppLocale.id ? 'Lanjut' : 'Next';
  String get reload => locale == AppLocale.id ? 'Muat ulang' : 'Reload';
  String get pay => locale == AppLocale.id ? 'Bayar' : 'Pay';

  // ——— Data order / pesanan
  String get dataOrder => locale == AppLocale.id ? 'Data Order' : 'Data Order';
  String get tabOrders => locale == AppLocale.id ? 'Pesanan' : 'Orders';
  String get tabScheduledOrders =>
      locale == AppLocale.id ? 'Pesanan Terjadwal' : 'Scheduled Orders';
  String get tabInTransit => locale == AppLocale.id ? 'Dalam Perjalanan' : 'In Transit';
  String get tabHistory => locale == AppLocale.id ? 'Riwayat' : 'History';
  String get noActiveTrips => locale == AppLocale.id ? 'Belum ada perjalanan aktif' : 'No active trips yet';
  String get noActiveTripsHint => locale == AppLocale.id
      ? '1. Setelah setuju harga, pesanan ada di tab Pesanan.\n'
        '2. Anda scan barcode driver saat dijemput → pesanan pindah ke sini.\n'
        '3. Saat sampai tujuan, scan barcode driver lagi (barcode selesai).\n'
        '(Penerima kirim barang: scan barcode driver untuk terima barang.)'
      : '1. After agreeing on price, order is in Orders tab.\n'
        '2. Scan driver barcode when picked up → order moves here.\n'
        '3. At destination, scan driver barcode again (complete barcode).\n'
        '(Receiver: scan driver barcode to receive goods.)';
  String get noOrders => locale == AppLocale.id ? 'Belum ada pesanan' : 'No orders yet';
  String get noOrderHistory => locale == AppLocale.id ? 'Belum ada riwayat pesanan' : 'No order history yet';
  String get noOrderHistoryHint => locale == AppLocale.id
      ? 'Pesanan yang sudah selesai (setelah Anda scan barcode driver di tujuan) akan muncul di sini.'
      : 'Completed orders (after you scan driver barcode at destination) will appear here.';
  String get noOrdersHint => locale == AppLocale.id
      ? 'Pesanan yang sudah terjadi kesepakatan akan muncul di sini.'
      : 'Orders with agreed price will appear here.';
  String get reportPriceMismatch => locale == AppLocale.id ? 'Laporkan harga tidak sesuai' : 'Report price mismatch';
  String get agreedPrice => locale == AppLocale.id ? 'Harga kesepakatan' : 'Agreed price';
  String get activeTravelOrderTitle =>
      locale == AppLocale.id ? 'Pesanan Travel Aktif' : 'Active Travel Order';
  String get activeTravelOrderMessage => locale == AppLocale.id
      ? 'Anda punya pesanan travel aktif. Selesaikan atau batalkan untuk pesan lagi.'
      : 'You have an active travel order. Complete or cancel it to place another.';
  String get activeTravelOrderHint => locale == AppLocale.id
      ? 'Buka tab Pesanan untuk melihat pesanan Anda.'
      : 'Open the Orders tab to view your order.';
  String get reject => locale == AppLocale.id ? 'Tolak' : 'Reject';
  String get agree => locale == AppLocale.id ? 'Setuju' : 'Agree';
  String get sos => 'SOS';
  String get share => locale == AppLocale.id ? 'Bagikan' : 'Share';
  String get trackGoods => locale == AppLocale.id ? 'Lacak Barang' : 'Track Goods';
  String get trackDriver => locale == AppLocale.id ? 'Lacak Driver' : 'Track Driver';
  String get driverDistanceToYou => locale == AppLocale.id
      ? 'Jarak driver ke lokasi Anda'
      : 'Driver distance to your location';
  String get etaToYourLocation => locale == AppLocale.id
      ? 'Estimasi tiba di lokasi Anda'
      : 'Estimated arrival at your location';
  String get back => locale == AppLocale.id ? 'Kembali' : 'Back';
  String get rateDriver => locale == AppLocale.id ? 'Beri rating driver' : 'Rate driver';
  String get later => locale == AppLocale.id ? 'Nanti' : 'Later';
  String get send => locale == AppLocale.id ? 'Kirim' : 'Send';

  // ——— Driver
  String get vehicleData => locale == AppLocale.id ? 'Data Kendaraan' : 'Vehicle Data';
  String get driverVerification => locale == AppLocale.id ? 'Verifikasi Driver' : 'Driver Verification';
  String get route => locale == AppLocale.id ? 'Rute' : 'Route';
  String get schedule => locale == AppLocale.id ? 'Jadwal' : 'Schedule';
  String get startWork => locale == AppLocale.id ? 'Mulai bekerja' : 'Start work';
  String get finishWork => locale == AppLocale.id ? 'Selesai bekerja' : 'Finish work';
  String get routeSelected => locale == AppLocale.id ? 'Rute dipilih' : 'Route selected';
  String get readyToWork => locale == AppLocale.id ? 'Siap Kerja' : 'Ready to work';
  String get pickUpPassenger => locale == AppLocale.id ? 'Ambil pemesan' : 'Pick up passenger';
  String get tabOperToMe => locale == AppLocale.id ? 'Oper ke Saya' : 'Transfer to Me';
  String get tabOrdersComplete => locale == AppLocale.id ? 'Pesanan Selesai' : 'Orders Complete';
  String get tabRouteHistory => locale == AppLocale.id ? 'Riwayat Rute' : 'Route History';
  String get routeInfo => locale == AppLocale.id ? 'Informasi rute' : 'Route info';
  String get operDriver => 'Oper Driver';
  String get operDriverTooltipEnabled => locale == AppLocale.id
      ? 'Transfer penumpang ke driver lain'
      : 'Transfer passengers to another driver';
  String get operDriverTooltipDisabled => locale == AppLocale.id
      ? 'Oper Driver tersedia setelah ada penumpang yang dijemput'
      : 'Oper Driver available after picking up passengers';
  String get headingToPassenger => locale == AppLocale.id ? 'Menuju penumpang' : 'Heading to passenger';
  String get backToRoute => locale == AppLocale.id ? 'Kembali ke rute' : 'Back to route';
  String get distanceToPassenger => locale == AppLocale.id ? 'Jarak ke penumpang' : 'Distance to passenger';
  String get otherPassengers => locale == AppLocale.id ? 'Penumpang lainnya' : 'Other passengers';
  String get routeOrigin => locale == AppLocale.id ? 'Rute awal' : 'Route origin';
  String get routeDestination => locale == AppLocale.id ? 'Tujuan Rute' : 'Route destination';
  String get passengerCount => locale == AppLocale.id ? 'Jumlah Penumpang' : 'Passenger count';
  String get goodsCount => locale == AppLocale.id ? 'Jumlah Barang' : 'Goods count';
  String get passengersWaiting => locale == AppLocale.id ? 'Penumpang menunggu' : 'Passengers waiting';
  String get navigatingToPassengerHint => locale == AppLocale.id
      ? 'Setelah scan barcode/konfirmasi otomatis, Anda akan kembali ke rute utama.'
      : 'After scanning barcode/auto confirmation, you will return to the main route.';

  // ——— Umum
  String get search => locale == AppLocale.id ? 'Cari' : 'Search';
  String get close => locale == AppLocale.id ? 'Tutup' : 'Close';
  String get yes => locale == AppLocale.id ? 'Ya' : 'Yes';
  String get no => locale == AppLocale.id ? 'Tidak' : 'No';
  String get understand => locale == AppLocale.id ? 'Mengerti' : 'Got it';
  String get retry => locale == AppLocale.id ? 'Coba lagi' : 'Try again';
  String get errorOccurred => locale == AppLocale.id ? 'Terjadi kesalahan' : 'An error occurred';
  String get accountBlocked => locale == AppLocale.id ? 'Akun Diblokir' : 'Account Blocked';
  String get accountSuspendedMessage => locale == AppLocale.id
      ? 'Akun Anda telah dibekukan. Hubungi admin untuk informasi lebih lanjut.'
      : 'Your account has been suspended. Contact admin for more information.';
  String get locationAndDevicePermissionRequired => locale == AppLocale.id
      ? 'Izin lokasi dan device ID diperlukan. Buka aplikasi lagi dan berikan izin.'
      : 'Location and device ID permission required. Reopen the app and grant permission.';
  String get firebaseConfigHint => locale == AppLocale.id
      ? 'Pastikan google-services.json dan firebase_options.dart sesuai dengan app id.traka.app.'
      : 'Ensure google-services.json and firebase_options.dart match app id.traka.app.';
  String get failedToLoadRoute => locale == AppLocale.id ? 'Gagal memuat rute. Coba lagi.' : 'Failed to load route. Try again.';
  String get failedToLoadRouteDirections => locale == AppLocale.id
      ? 'Gagal memuat rute. Pastikan Directions API aktif di Google Cloud Console.'
      : 'Failed to load route. Ensure Directions API is enabled in Google Cloud Console.';
  String get failedToLoadOrderData => locale == AppLocale.id
      ? 'Gagal memuat data pesanan. Silakan coba lagi.'
      : 'Failed to load order data. Please try again.';
  String get driverSecondScanHint => locale == AppLocale.id
      ? 'Driver kedua scan tiap barcode, lalu masukkan password akun.'
      : 'Second driver scans each barcode, then enters account password.';
  String get selectRouteOnMapHint => locale == AppLocale.id
      ? 'Pilih rute di map (tap garis kuning), lalu tap Mulai rute ini.'
      : 'Select route on map (tap yellow line), then tap Start this route.';
  String get showBarcodeToSecondDriver => locale == AppLocale.id
      ? 'Tunjukkan barcode ke driver kedua'
      : 'Show barcode to second driver';
  String transferCount(int current, int total) => locale == AppLocale.id
      ? 'Transfer $current/$total'
      : 'Transfer $current/$total';
  String get invalidSession => locale == AppLocale.id ? 'Sesi tidak valid' : 'Invalid session';
  String get locationPermissionRequired => locale == AppLocale.id
      ? 'Izin lokasi diperlukan untuk menggunakan aplikasi Traka.'
      : 'Location permission is required to use Traka app.';

  // ——— Onboarding
  String get onboardingWelcome => locale == AppLocale.id ? 'Selamat datang di Traka' : 'Welcome to Traka';
  String get onboardingWelcomeBody => locale == AppLocale.id
      ? 'Aplikasi travel dan pengiriman barang terpercaya di Kalimantan. Pesan tiket travel atau kirim barang dengan mudah.'
      : 'Trusted travel and delivery app in Kalimantan. Book travel tickets or send goods easily.';
  String get onboardingVerify => locale == AppLocale.id ? 'Verifikasi untuk keamanan' : 'Verify for security';
  String get onboardingVerifyBody => locale == AppLocale.id
      ? 'Lengkapi verifikasi data (foto wajah, KTP/SIM) dan nomor telepon di profil untuk menggunakan semua fitur.'
      : 'Complete verification (face photo, ID/driver license) and phone number in profile to use all features.';
  String get onboardingReady => locale == AppLocale.id ? 'Siap memulai' : 'Ready to start';
  String get onboardingReadyBody => locale == AppLocale.id
      ? 'Jelajahi rute travel, pesan tiket, atau kirim barang. Semua dalam satu aplikasi.'
      : 'Explore travel routes, book tickets, or send goods. All in one app.';
  String get start => locale == AppLocale.id ? 'Mulai' : 'Start';

  // ——— Forgot password
  String get forgotPasswordTitle => locale == AppLocale.id ? 'Lupa kata sandi' : 'Forgot password';
  String get chooseVerificationMethod => locale == AppLocale.id ? 'Pilih metode verifikasi' : 'Choose verification method';
  String get newPassword => locale == AppLocale.id ? 'Kata sandi baru' : 'New password';
  String get confirmNewPassword => locale == AppLocale.id ? 'Konfirmasi kata sandi baru' : 'Confirm new password';
  String get sendCode => locale == AppLocale.id ? 'Kirim kode' : 'Send code';
  String get verify => locale == AppLocale.id ? 'Verifikasi' : 'Verify';
  String get changeEmail => locale == AppLocale.id ? 'Ganti email' : 'Change email';
  String get sendSmsCode => locale == AppLocale.id ? 'Kirim kode SMS' : 'Send SMS code';
  String get changePhone => locale == AppLocale.id ? 'Ganti no. telepon' : 'Change phone number';
  String get emailRequired => locale == AppLocale.id ? 'Email wajib diisi' : 'Email is required';
  String get emailNotRegistered => locale == AppLocale.id ? 'Email tidak terdaftar.' : 'Email not registered.';
  String get codeSentToEmail => locale == AppLocale.id
      ? 'Kode verifikasi telah dikirim ke email. Cek inbox atau folder Spam.'
      : 'Verification code sent to email. Check inbox or Spam folder.';
  String get failedToSendCode => locale == AppLocale.id ? 'Gagal mengirim kode. Coba lagi.' : 'Failed to send code. Try again.';
  String get enterCodeFromEmail => locale == AppLocale.id ? 'Masukkan kode verifikasi dari email' : 'Enter verification code from email';
  String get wrongOrExpiredCode => locale == AppLocale.id ? 'Kode salah atau kedaluwarsa.' : 'Wrong or expired code.';
  String get phoneRequired => locale == AppLocale.id ? 'No. telepon wajib diisi' : 'Phone number is required';
  String get phoneNotRegistered => locale == AppLocale.id ? 'No. telepon tidak terdaftar.' : 'Phone not registered.';
  String get passwordChangedSuccess => locale == AppLocale.id
      ? 'Kata sandi berhasil diubah. Silakan login.'
      : 'Password changed successfully. Please login.';
  String get phoneNotLinkedToAccount => locale == AppLocale.id
      ? 'No. telepon belum terhubung ke akun. Gunakan reset via email.'
      : 'Phone not linked to account. Use email reset.';
  String get enterCodeFromSms => locale == AppLocale.id ? 'Masukkan kode verifikasi dari SMS' : 'Enter verification code from SMS';
  String get sessionExpired => locale == AppLocale.id ? 'Sesi habis. Mulai dari awal.' : 'Session expired. Start over.';
  String get passwordMin8Chars => locale == AppLocale.id ? 'Kata sandi minimal 8 karakter.' : 'Password must be at least 8 characters.';
  String get passwordMustContainNumber => locale == AppLocale.id ? 'Kata sandi harus mengandung angka.' : 'Password must contain a number.';
  String get confirmPasswordMismatch => locale == AppLocale.id ? 'Konfirmasi kata sandi tidak sama.' : 'Password confirmation does not match.';
  String get faceDataNotFound => locale == AppLocale.id ? 'Data wajah tidak ditemukan.' : 'Face data not found.';
  String get cameraPermissionRequired => locale == AppLocale.id ? 'Izin kamera diperlukan untuk verifikasi wajah.' : 'Camera permission required for face verification.';
  String get faceVerificationCancelled => locale == AppLocale.id ? 'Verifikasi wajah dibatalkan.' : 'Face verification cancelled.';
  String get faceNotMatch => locale == AppLocale.id ? 'Wajah tidak cocok. Silakan coba lagi.' : 'Face does not match. Please try again.';
  String get faceVerificationFailed => locale == AppLocale.id ? 'Verifikasi wajah gagal.' : 'Face verification failed.';
  String get failedToSave => locale == AppLocale.id ? 'Gagal menyimpan' : 'Failed to save';
  String get verificationFailed => locale == AppLocale.id ? 'Verifikasi gagal.' : 'Verification failed.';

  /// Status offline (nama jalan tidak tersedia).
  String get offline => locale == AppLocale.id ? 'Offline' : 'Offline';

  // ——— Chat & Pesan
  String get messages => locale == AppLocale.id ? 'Pesan' : 'Messages';
  String get noChatsYet => locale == AppLocale.id ? 'Belum ada obrolan' : 'No chats yet';
  String get typeMessage => locale == AppLocale.id ? 'Ketik pesan...' : 'Type message...';
  String get deleteChat => locale == AppLocale.id ? 'Hapus Chat' : 'Delete Chat';
  String get delete => locale == AppLocale.id ? 'Hapus' : 'Delete';
  String get hide => locale == AppLocale.id ? 'Sembunyikan' : 'Hide';
  String get scheduledTravel => locale == AppLocale.id ? 'Pesan Travel Terjadwal' : 'Scheduled Travel';
  String get searchSchedule => locale == AppLocale.id ? 'Cari Jadwal' : 'Search Schedule';
  String get bookTravelAlone => locale == AppLocale.id ? 'Pesan Travel Sendiri' : 'Book Travel Alone';
  String get bookTravelWithFamily => locale == AppLocale.id ? 'Pesan Travel dengan Kerabat' : 'Book Travel with Family';
  String get sendGoods => locale == AppLocale.id ? 'Kirim Barang' : 'Send Goods';
  String get viewOrders => locale == AppLocale.id ? 'Lihat Pesanan' : 'View Orders';
  String get noScheduleYet => locale == AppLocale.id ? 'Belum ada jadwal tersimpan' : 'No schedule saved yet';
  String get tapDateOnCalendar => locale == AppLocale.id ? 'Tap tanggal di kalender...' : 'Tap date on calendar...';

  // ——— Panduan & Saran
  String get appGuide => locale == AppLocale.id ? 'Panduan Aplikasi' : 'App Guide';
  String get panduanSpesifikasiTitle => locale == AppLocale.id ? 'Spesifikasi Perangkat' : 'Device Specifications';
  String get panduanSpesifikasiContent => locale == AppLocale.id
      ? 'Aplikasi Traka berjalan optimal di perangkat dengan RAM minimal 6 GB. '
          'Perangkat dengan RAM di bawah 6 GB masih dapat menggunakan aplikasi, '
          'namun mungkin terasa lebih lambat atau kurang responsif.'
      : 'Traka app runs optimally on devices with at least 6 GB RAM. '
          'Devices with less than 6 GB RAM can still use the app, '
          'but may experience slower performance or reduced responsiveness.';
  String get panduanFungsiTitle => locale == AppLocale.id ? 'Fungsi Aplikasi' : 'App Function';
  String get panduanFungsiContent => locale == AppLocale.id
      ? 'Traka adalah platform penghubung antara penumpang dan driver travel di Kalimantan. '
          'Aplikasi berfungsi sebagai sarana untuk:\n\n'
          '• Memesan travel terjadwal (penumpang ke driver)\n'
          '• Mengirim barang via driver travel\n'
          '• Lacak Driver dan Lacak Barang (real-time)\n'
          '• Chat dan kesepakatan harga langsung antar pengguna\n\n'
          'Traka bukan penyedia angkutan dan tidak memegang dana pengguna. '
          'Seluruh transaksi terjadi langsung antara penumpang dan driver.'
      : 'Traka is a platform connecting passengers and travel drivers in Kalimantan. '
          'The app serves as a means for:\n\n'
          '• Booking scheduled travel (passenger to driver)\n'
          '• Sending goods via travel driver\n'
          '• Track Driver and Track Goods (real-time)\n'
          '• Chat and direct price agreements between users\n\n'
          'Traka is not a transport provider and does not hold user funds. '
          'All transactions occur directly between passengers and drivers.';
  String get panduanFiturTitle => locale == AppLocale.id ? 'Fitur' : 'Features';
  String get panduanFiturContent => locale == AppLocale.id
      ? '• Travel Terjadwal: Pesan tiket travel, pilih rute, nego harga via chat\n'
          '• Kirim Barang: Kirim paket via driver travel dengan lacak real-time\n'
          '• Lacak Driver: Pantau posisi driver saat perjalanan\n'
          '• Lacak Barang: Pantau lokasi paket saat dikirim\n'
          '• Verifikasi: Foto wajah, KTP (penumpang), SIM (driver) untuk keamanan\n'
          '• Chat: Komunikasi langsung dengan driver/penumpang\n'
          '• Scan Barcode: Konfirmasi penjemputan dan sampai tujuan'
      : '• Scheduled Travel: Book travel tickets, choose routes, negotiate prices via chat\n'
          '• Send Goods: Send packages via travel driver with real-time tracking\n'
          '• Track Driver: Monitor driver position during the trip\n'
          '• Track Goods: Monitor package location when shipped\n'
          '• Verification: Face photo, ID (passenger), license (driver) for security\n'
          '• Chat: Direct communication with driver/passenger\n'
          '• Scan Barcode: Confirm pickup and arrival at destination';
  String get panduanPeraturanTitle => locale == AppLocale.id ? 'Peraturan' : 'Rules';
  String get panduanPeraturanContent => locale == AppLocale.id
      ? '• Berikan informasi akun yang benar dan lengkap\n'
          '• Patuhi peraturan lalu lintas dan hukum Indonesia\n'
          '• Lakukan scan barcode saat penjemputan dan sampai tujuan\n'
          '• Jaga kerahasiaan akun\n'
          '• Bertanggung jawab atas transaksi dan kesepakatan dengan pengguna lain\n\n'
          'Layanan tunduk pada UU ITE, UU Perlindungan Data Pribadi, dan peraturan transportasi.'
      : '• Provide accurate and complete account information\n'
          '• Comply with traffic regulations and Indonesian law\n'
          '• Scan barcode at pickup and upon arrival at destination\n'
          '• Keep account confidential\n'
          '• Be responsible for transactions and agreements with other users\n\n'
          'Service is subject to ITE Law, Personal Data Protection Law, and transportation regulations.';
  String get panduanKontribusiTitle => locale == AppLocale.id ? 'Kontribusi & Pembayaran' : 'Contribution & Payment';
  String get panduanKontribusiContent => locale == AppLocale.id
      ? '• Lacak Driver / Lacak Barang: Dibayar via Google Play sesuai paket\n'
          '• Kontribusi Driver: Driver membayar kontribusi travel dan kirim barang via Google Play. Travel: jarak × tarif per km (tier provinsi). Kirim barang: jarak × tarif per km. Tarif dapat dilihat di halaman Bayar Kontribusi.\n'
          '• Pembayaran antar pengguna (harga travel, kirim barang) terjadi langsung; aplikasi tidak menyimpan uang\n'
          '• Riwayat pembayaran dapat dilihat di menu Riwayat Pembayaran'
      : '• Track Driver / Track Goods: Paid via Google Play according to package\n'
          '• Driver Contribution: Driver pays travel and send goods contribution via Google Play. Travel: distance × rate per km (province tier). Send goods: distance × rate per km. Rates visible on Pay Contribution screen.\n'
          '• Payments between users (travel price, send goods) occur directly; app does not store money\n'
          '• Payment history can be viewed in Payment History menu';
  String get panduanKenapaBiayaTitle => locale == AppLocale.id ? 'Kenapa Ada Biaya? (Transparansi)' : 'Why Are There Fees? (Transparency)';
  String get panduanKenapaBiayaContent => locale == AppLocale.id
      ? 'Aplikasi Traka memerlukan biaya operasional untuk tetap berjalan. Berikut alasan kenapa pengguna membayar kontribusi, pembayaran pelacakan, dan pelanggaran:\n\n'
          '• Database Firebase: Penyimpanan data pengguna, pesanan, chat, dan lokasi real-time memerlukan layanan cloud Firebase (Google).\n\n'
          '• Google & Infrastruktur: Aplikasi berjalan di Google Play, menggunakan layanan Google (peta, notifikasi, pembayaran). Biaya infrastruktur hybrid (cloud + mobile) diperlukan untuk keamanan dan ketersediaan layanan.\n\n'
          '• Kontribusi Driver: Membantu menutupi biaya database dan operasional aplikasi per perjalanan/kirim barang.\n\n'
          '• Pembayaran Pelacakan (Lacak Driver/Lacak Barang): Fitur pelacakan real-time memakai database dan layanan lokasi yang berbiaya.\n\n'
          '• Pelanggaran: Konfirmasi otomatis (tanpa scan barcode) memakai pemrosesan lokasi dan database tambahan; biaya pelanggaran membantu menutupi hal ini.\n\n'
          'Dengan transparansi ini, pengguna memahami bahwa biaya yang dibayar mendukung kelangsungan aplikasi.'
      : 'Traka app requires operational costs to keep running. Here is why users pay contribution, tracking payment, and violation fees:\n\n'
          '• Firebase Database: Storing user data, orders, chat, and real-time location requires Firebase (Google) cloud service.\n\n'
          '• Google & Infrastructure: App runs on Google Play, using Google services (maps, notifications, payment). Hybrid infrastructure costs (cloud + mobile) are needed for security and service availability.\n\n'
          '• Driver Contribution: Helps cover database and app operational costs per trip/send goods.\n\n'
          '• Tracking Payment (Track Driver/Track Goods): Real-time tracking uses database and location services that incur costs.\n\n'
          '• Violations: Automatic confirmation (without barcode scan) uses additional location processing and database; violation fees help cover this.\n\n'
          'With this transparency, users understand that fees paid support the sustainability of the app.';
  String get panduanNotifikasiTitle => locale == AppLocale.id ? 'Notifikasi tidak muncul saat layar mati?' : 'Notifications not showing when screen is off?';
  String get panduanNotifikasiContent => locale == AppLocale.id
      ? 'Jika notifikasi baru muncul setelah layar dinyalakan, ini karena penghemat baterai HP (terutama Samsung, Xiaomi, Oppo).\n\n'
          'Langkah untuk Samsung:\n'
          '1. Buka Pengaturan → Aplikasi → Traka\n'
          '2. Ketuk Baterai → pilih "Tidak dibatasi"\n'
          '3. Jika ada "Aplikasi tidur" / "Sleeping apps", pastikan Traka TIDAK ada di daftar\n'
          '4. Pastikan notifikasi Traka diaktifkan\n\n'
          'Langkah untuk Xiaomi/Oppo/Vivo: Baterai → Traka → Izinkan di latar belakang / Tanpa batasan'
      : 'If notifications only appear after turning on the screen, this is due to phone battery saver (especially Samsung, Xiaomi, Oppo).\n\n'
          'Steps for Samsung:\n'
          '1. Open Settings → Apps → Traka\n'
          '2. Tap Battery → select "Unrestricted"\n'
          '3. If "Sleeping apps" exists, ensure Traka is NOT in the list\n'
          '4. Ensure Traka notifications are enabled\n\n'
          'For Xiaomi/Oppo/Vivo: Battery → Traka → Allow in background / Unrestricted';
  String get panduanNotifikasiBukaPengaturan => locale == AppLocale.id ? 'Buka Pengaturan Aplikasi' : 'Open App Settings';
  String get panduanPelanggaranTitle => locale == AppLocale.id ? 'Pelanggaran' : 'Violations';
  String get panduanPelanggaranContent => locale == AppLocale.id
      ? 'Apabila tidak melakukan scan barcode saat penjemputan atau sampai tujuan, '
          'aplikasi dapat melakukan konfirmasi otomatis berdasarkan lokasi. '
          'Penggunaan konfirmasi otomatis dikenai biaya pelanggaran.\n\n'
          '• Penumpang: Bayar pelanggaran via Google Play sebelum dapat cari travel lagi\n'
          '• Driver: Biaya pelanggaran ditambahkan ke pembayaran kontribusi\n\n'
          'Ketentuan ini tidak berlaku untuk layanan kirim barang.'
      : 'If you do not scan barcode at pickup or upon arrival at destination, '
          'the app may perform automatic confirmation based on location. '
          'Use of automatic confirmation incurs a violation fee.\n\n'
          '• Passenger: Pay violation via Google Play before being able to search for travel again\n'
          '• Driver: Violation fee is added to contribution payment\n\n'
          'This does not apply to send goods service.';
  String get termsSubtitle => locale == AppLocale.id ? 'Ketentuan layanan Traka' : 'Traka service terms';
  String get privacySubtitle => locale == AppLocale.id ? 'Perlindungan data pribadi' : 'Personal data protection';

  // ——— Admin contact (tanpa tampilkan alamat/nomor/username sebenarnya)
  String get contactAdminEmail => locale == AppLocale.id ? 'Kirim email ke admin' : 'Send email to admin';
  String get contactAdminWhatsApp => locale == AppLocale.id ? 'Hubungi via WhatsApp' : 'Contact via WhatsApp';
  String get contactAdminInstagram => locale == AppLocale.id ? 'Kunjungi profil Instagram' : 'Visit Instagram profile';
  String get contactAdminNotConfigured => locale == AppLocale.id ? '(Belum dikonfigurasi)' : '(Not configured)';

  // Indikator turis (penumpang berbahasa Inggris) untuk driver
  String get passengerUsesEnglish => locale == AppLocale.id ? 'Penumpang berbahasa Inggris' : 'Passenger uses English';
  String get touristBadge => locale == AppLocale.id ? 'Turis' : 'Tourist';
  String get suggestionToAdminTitle => locale == AppLocale.id ? 'Saran ke Admin' : 'Suggestion to Admin';
  String get suggestionHint => locale == AppLocale.id
      ? 'Berikan saran atau masukan untuk pengembangan aplikasi Traka. Admin akan menerima dan menindaklanjuti.'
      : 'Give suggestions or feedback for Traka app development. Admin will receive and follow up.';
  String get sendToAdmin => locale == AppLocale.id ? 'Kirim ke Admin' : 'Send to Admin';
  String get selected => locale == AppLocale.id ? 'dipilih' : 'selected';
  String get refresh => locale == AppLocale.id ? 'Refresh' : 'Refresh';

  // ——— Payment & Maintenance
  String get noPaymentHistory => locale == AppLocale.id ? 'Belum ada riwayat pembayaran' : 'No payment history yet';
  String get paymentHistoryEmptyDriver => locale == AppLocale.id
      ? 'Pembayaran kontribusi dan pelanggaran akan muncul di sini.'
      : 'Contribution and violation payments will appear here.';
  String get paymentHistoryEmptyPassenger => locale == AppLocale.id
      ? 'Pembayaran Lacak Driver, Lacak Barang, atau Pelanggaran akan muncul di sini.'
      : 'Track Driver, Track Goods, or Violation payments will appear here.';
  String get payContribution => locale == AppLocale.id ? 'Bayar Kontribusi' : 'Pay Contribution';
  String get underMaintenance => locale == AppLocale.id ? 'Sedang Maintenance' : 'Under Maintenance';
  String get maintenanceMessage => locale == AppLocale.id
      ? 'Aplikasi sedang dalam perbaikan. Silakan coba lagi beberapa saat lagi.'
      : 'App is under maintenance. Please try again later.';
  String get updateRequired => locale == AppLocale.id ? 'Update Diperlukan' : 'Update Required';
  String get updateRequiredMessage => locale == AppLocale.id
      ? 'Versi aplikasi Anda sudah tidak didukung. Silakan update ke versi terbaru untuk melanjutkan.'
      : 'Your app version is no longer supported. Please update to the latest version to continue.';
  String get openPlayStore => locale == AppLocale.id ? 'Buka Play Store' : 'Open Play Store';

  // ——— Umum tambahan
  String get completeVerification => locale == AppLocale.id ? 'Lengkapi data verifikasi' : 'Complete verification';
  String get completeDataVerificationPrompt => locale == AppLocale.id
      ? 'Lengkapi data verifikasi terlebih dahulu untuk memesan travel atau kirim barang.'
      : 'Complete verification first to book travel or send goods.';
  String get completeDataVerificationPromptDriver => locale == AppLocale.id
      ? 'Lengkapi data verifikasi terlebih dahulu untuk memilih rute, mulai kerja, atau menambah jadwal travel.'
      : 'Complete verification first to select route, start work, or add travel schedule.';
  String get completeDataVerificationPromptPesan => locale == AppLocale.id
      ? 'Lengkapi data verifikasi terlebih dahulu untuk memesan travel terjadwal.'
      : 'Complete verification first to book scheduled travel.';
  String get completeDataHint => locale == AppLocale.id
      ? 'Lengkapi data Anda: Verifikasi Data (KTP), Email & No. Telepon agar dapat menggunakan semua fitur.'
      : 'Complete your data: Verify Data (ID), Email & Phone to use all features.';
  String verificationCompleteCount(int done, int total) => locale == AppLocale.id
      ? 'Verifikasi: $done/$total lengkap'
      : 'Verification: $done/$total complete';
  String get fetchingLocation => locale == AppLocale.id ? 'Mengambil lokasi...' : 'Fetching location...';
  String get completeNow => locale == AppLocale.id ? 'Lengkapi Sekarang' : 'Complete Now';
  String get notLoggedIn => locale == AppLocale.id ? 'Anda belum login.' : 'You are not logged in.';

  // ——— Penumpang & Cari Travel
  String get noActiveDriversForRoute => locale == AppLocale.id
      ? 'Tidak ada driver aktif yang sesuai dengan rute tujuan. Coba Pesan nanti untuk jadwal terjadwal.'
      : 'No active drivers matching your route. Try Book later for scheduled travel.';
  String get driverNearby => locale == AppLocale.id ? 'Driver sekitar' : 'Nearby drivers';
  String get driverNearbyRadius => locale == AppLocale.id ? 'Dalam 40 km' : 'Within 40 km';
  String get pesanNanti => locale == AppLocale.id ? 'Pesan nanti' : 'Book later';
  String get tapDriverToSeeRouteAndBook => locale == AppLocale.id
      ? 'Tap driver untuk lihat rute dan pesan'
      : 'Tap driver to see route and book';
  String get noNearbyDrivers => locale == AppLocale.id
      ? 'Tidak ada driver aktif dalam 40 km. Coba cari dengan rute spesifik.'
      : 'No active drivers within 40 km. Try searching with a specific route.';
  String get failedToFindDestination => locale == AppLocale.id ? 'Gagal menemukan tujuan' : 'Failed to find destination';
  String failedToFindDestinationDetail(Object e) => locale == AppLocale.id
      ? 'Gagal menemukan tujuan: $e'
      : 'Failed to find destination: $e';
  String get destinationNotFound => locale == AppLocale.id ? 'Tujuan tidak ditemukan' : 'Destination not found';
  String get searchingDriver => locale == AppLocale.id ? 'Mencari driver...' : 'Searching for driver...';
  String get checkingDriverRoutes => locale == AppLocale.id ? 'Memeriksa rute driver yang sesuai' : 'Checking matching driver routes';
  String get checkingNearbyDrivers => locale == AppLocale.id ? 'Memeriksa driver dalam radius 40 km' : 'Checking drivers within 40 km';
  String get failedToCreateOrder => locale == AppLocale.id ? 'Gagal membuat pesanan. Silakan coba lagi.' : 'Failed to create order. Please try again.';
  String get failedToCreateOrderTryAgain => locale == AppLocale.id ? 'Gagal membuat pesanan. Coba lagi.' : 'Failed to create order. Try again.';
  String get failedToSend => locale == AppLocale.id ? 'Gagal mengirim' : 'Failed to send';
  String failedToSendDetail(Object e) => locale == AppLocale.id ? 'Gagal mengirim: $e' : 'Failed to send: $e';
  String get failedToCancel => locale == AppLocale.id ? 'Gagal membatalkan. Coba lagi.' : 'Failed to cancel. Try again.';
  String get fillOriginAndDestination => locale == AppLocale.id ? 'Isi asal dan tujuan perjalanan.' : 'Fill in origin and destination.';
  String get fillOriginAndDestinationPesan => locale == AppLocale.id ? 'Isi awal tujuan dan tujuan perjalanan.' : 'Fill in origin and destination.';
  String get driverSeatsFull => locale == AppLocale.id ? 'Kursi mobil driver sudah penuh.' : 'Driver seats are full.';
  String get orderNumberCopied => locale == AppLocale.id ? 'Nomor pesanan disalin' : 'Order number copied';
  String get passengerLocationUnavailable => locale == AppLocale.id ? 'Lokasi penumpang tidak tersedia.' : 'Passenger location unavailable.';
  String get sosSent => locale == AppLocale.id ? 'SOS terkirim. WhatsApp akan terbuka ke admin.' : 'SOS sent. WhatsApp will open to admin.';
  String routeSavedPartially(Object e) => locale == AppLocale.id
      ? 'Riwayat rute disimpan sebagian. $e'
      : 'Route history saved partially. $e';
  String get workFinished => locale == AppLocale.id ? 'Pekerjaan selesai. Tombol kembali ke Siap Kerja.' : 'Work finished. Button returns to Ready to work.';
  String get workStarted => locale == AppLocale.id ? 'Pekerjaan dimulai. Status: Berhenti Kerja.' : 'Work started. Status: Stop work.';
  String get originOrDestinationNotFound => locale == AppLocale.id ? 'Lokasi awal atau tujuan tidak ditemukan.' : 'Origin or destination not found.';
  String get noAlternativeRoute => locale == AppLocale.id ? 'Tidak ada rute alternatif tersedia' : 'No alternative route available';
  String get loadingAlternativeRoute => locale == AppLocale.id ? 'Memuat rute alternatif...' : 'Loading alternative route...';
  String get routeUpdated => locale == AppLocale.id ? 'Rute diperbarui untuk kembali ke tujuan.' : 'Route updated to return to destination.';
  String get driverLocationUnavailable => locale == AppLocale.id ? 'Lokasi driver belum tersedia.' : 'Driver location not available yet.';
  String get driverEnRoute => locale == AppLocale.id ? 'Driver sedang dalam perjalanan' : 'Driver is on the way';
  String get shareLinkSuccess => locale == AppLocale.id ? 'Link berhasil dibagikan. Keluarga bisa buka di browser.' : 'Link shared. Family can open in browser.';
  String failedToLoadOrder(Object e) => locale == AppLocale.id ? 'Gagal memuat pesanan: $e' : 'Failed to load order: $e';
  String get fillDestinationFirstPesan => locale == AppLocale.id ? 'Isi tujuan perjalanan terlebih dahulu.' : 'Fill in destination first.';
  String get selectOrderToTransfer => locale == AppLocale.id ? 'Pilih pesanan yang akan dioper' : 'Select order to transfer';
  String get emailAndPhoneRequired => locale == AppLocale.id ? 'Email dan nomor HP driver kedua wajib' : 'Email and phone of second driver required';
  String get tooManyAttempts => locale == AppLocale.id ? 'Terlalu banyak percobaan. Coba lagi dalam 1 menit.' : 'Too many attempts. Try again in 1 minute.';
  String get scanFailed => locale == AppLocale.id ? 'Scan gagal. Coba lagi.' : 'Scan failed. Try again.';
  String get enterItemNameType => locale == AppLocale.id ? 'Masukkan nama/jenis barang.' : 'Enter item name/type.';
  String get weightRequired => locale == AppLocale.id ? 'Berat harus 0,1 - 100 kg.' : 'Weight must be 0.1 - 100 kg.';
  String get dimensionsRequired => locale == AppLocale.id ? 'Panjang dan lebar wajib diisi.' : 'Length and width required.';
  String get maxDimensionSize => locale == AppLocale.id ? 'Maksimal tiap dimensi 300 cm.' : 'Max 300 cm per dimension.';
  String get totalDimensionsMax => locale == AppLocale.id ? 'Total dimensi (P+L+T) maksimal 400 cm.' : 'Total dimensions (L+W+H) max 400 cm.';
  String get locationPermissionRequiredSettings => locale == AppLocale.id ? 'Izin lokasi diperlukan. Aktifkan di pengaturan.' : 'Location permission required. Enable in settings.';
  String get failedToGetLocation => locale == AppLocale.id ? 'Gagal mengambil lokasi. Coba lagi.' : 'Failed to get location. Try again.';
  String get paymentSuccessTrackGoods => locale == AppLocale.id ? 'Pembayaran berhasil. Anda dapat melacak barang.' : 'Payment successful. You can track goods.';
  String get paymentSuccessTrackDriver => locale == AppLocale.id ? 'Pembayaran berhasil. Anda dapat melacak driver.' : 'Payment successful. You can track driver.';
  String get paymentSuccessSearchTravel => locale == AppLocale.id ? 'Pembayaran berhasil. Anda dapat mencari travel lagi.' : 'Payment successful. You can search travel again.';
  String get viewPaymentHistory => locale == AppLocale.id ? 'Lihat Riwayat' : 'View History';
  String get invalidOrderData => locale == AppLocale.id ? 'Gagal mengirim: data pesanan tidak valid.' : 'Failed to send: invalid order data.';
  String get failedToSendMessage => locale == AppLocale.id ? 'Gagal mengirim pesan. Periksa koneksi dan coba lagi.' : 'Failed to send message. Check connection and try again.';
  String get failedToSendPrice => locale == AppLocale.id ? 'Gagal mengirim harga. Coba lagi.' : 'Failed to send price. Try again.';
  String get failedToSendVoice => locale == AppLocale.id ? 'Gagal mengirim pesan suara. Periksa koneksi dan coba lagi.' : 'Failed to send voice message. Check connection and try again.';
  String get failedToSendImage => locale == AppLocale.id ? 'Gagal mengirim gambar. Periksa koneksi dan coba lagi.' : 'Failed to send image. Check connection and try again.';
  String get failedToSendVideo => locale == AppLocale.id ? 'Gagal mengirim video. Periksa koneksi dan coba lagi.' : 'Failed to send video. Check connection and try again.';
  String failedToCreatePdf(Object e) => locale == AppLocale.id ? 'Gagal membuat PDF: $e' : 'Failed to create PDF: $e';
  String get failedToUploadPhoto => locale == AppLocale.id ? 'Gagal mengunggah foto' : 'Failed to upload photo';
  String failedToUploadPhotoDetail(Object e) => locale == AppLocale.id ? 'Gagal mengunggah foto: $e' : 'Failed to upload photo: $e';
  String get passwordMin8CharsHint => locale == AppLocale.id ? 'Password baru minimal 8 karakter.' : 'New password must be at least 8 characters.';
  String get passwordMismatch => locale == AppLocale.id ? 'Password tidak sama.' : 'Passwords do not match.';
  String get wrongPassword => locale == AppLocale.id ? 'Password lama salah.' : 'Wrong current password.';
  String verificationLinkSentTo(String email) => locale == AppLocale.id
      ? 'Link verifikasi telah dikirim ke $email. Buka inbox (atau folder Spam) dan klik link untuk mengaktifkan email baru.'
      : 'Verification link sent to $email. Check inbox (or Spam) and click link to activate new email.';
  String get failedToSendVerificationEmail => locale == AppLocale.id ? 'Gagal mengirim verifikasi email.' : 'Failed to send verification email.';
  String get phoneAddedSuccess => locale == AppLocale.id ? 'No. telepon berhasil ditambahkan. Login bisa dengan email atau no. telepon.' : 'Phone number added. You can login with email or phone.';
  String get faceVerificationSuccess => locale == AppLocale.id ? 'Foto verifikasi wajah berhasil. Lanjut ambil foto SIM.' : 'Face verification successful. Next: take SIM photo.';
  String get failedToReadSim => locale == AppLocale.id ? 'Gagal membaca data SIM. Pastikan foto SIM jelas dan lengkap.' : 'Failed to read SIM data. Ensure photo is clear and complete.';
  String get failedToSendFeedback => locale == AppLocale.id ? 'Gagal mengirim. Coba lagi.' : 'Failed to send. Try again.';
  String get profilePhotoUpdated => locale == AppLocale.id ? 'Foto profil berhasil diubah.' : 'Profile photo updated successfully.';
  String get requestSentWaitingDriver => locale == AppLocale.id ? 'Permintaan terkirim. Menunggu kesepakatan driver.' : 'Request sent. Waiting for driver agreement.';
  String sendRequestTo(String name) => locale == AppLocale.id ? 'Kirim permintaan ke $name' : 'Send request to $name';
  String get confirmationSentToDriver => locale == AppLocale.id ? 'Pesan permintaan konfirmasi telah dikirim ke driver.' : 'Confirmation request sent to driver.';
  String get cancellationConfirmed => locale == AppLocale.id ? 'Pembatalan telah dikonfirmasi. Pesanan dibatalkan.' : 'Cancellation confirmed. Order cancelled.';
  String get cancellationRequestSent => locale == AppLocale.id ? 'Permintaan pembatalan telah dikirim. Menunggu konfirmasi driver.' : 'Cancellation request sent. Waiting for driver confirmation.';
  String get cancellationRequestSentPassenger => locale == AppLocale.id ? 'Permintaan pembatalan telah dikirim. Menunggu konfirmasi penumpang.' : 'Cancellation request sent. Waiting for passenger confirmation.';

  AppLocalizations copyWith({AppLocale? locale}) {
    return AppLocalizations(locale: locale ?? this.locale);
  }
}
