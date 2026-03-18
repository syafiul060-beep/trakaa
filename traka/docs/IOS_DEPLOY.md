# Panduan Deploy iOS Traka

## Alur: Tes dulu → Upload ke App Store

### Fase 1: Tes di iPhone (Ad-hoc)

1. **Daftar Apple Developer** ($99/tahun) di [developer.apple.com](https://developer.apple.com)

2. **Dapatkan UDID iPhone** teman:
   - Settings → General → About → tap UDID untuk copy
   - Atau hubungkan ke Mac/PC, buka Finder/iTunes

3. **Daftar device** di Apple Developer:
   - Certificates, Identifiers & Profiles → Devices → +
   - Masukkan nama + UDID

4. **Buat Ad-hoc Provisioning Profile**:
   - Profiles → + → Ad Hoc
   - Pilih App ID `com.example.traka`
   - Pilih certificate
   - Pilih device yang didaftar
   - Generate & download (.mobileprovision)

5. **Upload ke Codemagic**:
   - Team settings → Code signing identities
   - iOS certificates: Upload Distribution certificate (.p12)
   - iOS provisioning profiles: Upload Ad-hoc profile

6. **Build di Codemagic**:
   - Pilih workflow **"Traka iOS - Tes iPhone (Ad-hoc)"**
   - Start build
   - Download file `.ipa` setelah selesai

7. **Instal ke iPhone**:
   - **Via kabel:** Hubungkan iPhone → Finder (Mac) / iTunes (Windows) → drag .ipa
   - **Via web:** Upload .ipa ke [diawi.com](https://www.diawi.com) → buka link di Safari iPhone

---

### Fase 2: Upload ke App Store (setelah tes berhasil)

1. **Buat App Store Provisioning Profile** di developer.apple.com (jika belum)

2. **Upload ke Codemagic** (App Store profile)

3. **Buat app di App Store Connect**:
   - [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   - My Apps → + → New App
   - Isi nama, bundle ID `com.example.traka`

4. **Build di Codemagic**:
   - Pilih workflow **"Traka iOS - App Store"**
   - Start build

5. **Submit ke App Store Connect**:
   - Di Codemagic: Setup publishing → App Store Connect
   - Atau upload .ipa manual via Transporter app

---

## Workflow di Codemagic

| Workflow | Untuk |
|----------|-------|
| **Traka iOS Verify** | Cek kompilasi (tanpa code signing) |
| **Traka iOS - Tes iPhone (Ad-hoc)** | Install langsung ke iPhone |
| **Traka iOS - App Store** | Upload ke App Store |
