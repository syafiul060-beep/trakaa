# Build di laptop spesifikasi terbatas (RAM/CPU penuh)

## Gejala

- `Running Gradle task 'bundleRelease'...` sangat lama.
- Error: **`R.jar: The process cannot access the file because it is being used by another process`** (`:app:processReleaseResources`).
- Task Manager: CPU ~100%, RAM hampir penuh.

## Penyebab umum

1. **File terkunci** — Windows Defender / antivirus memindai folder `build\`, atau ada **dua proses** Gradle/Java, atau **Android Studio** + terminal build bersamaan.
2. **RAM kritis** — Gradle + Flutter + browser + IDE memakan memori; build bisa gagal atau swap berat.

## Langkah cepat (urut)

1. **Tutup** yang tidak perlu: tab Chrome banyak, aplikasi berat, **duplikat terminal** build.
2. **Hentikan Gradle lalu bersihkan:**
   ```bat
   cd D:\Traka\traka\android
   gradlew --stop
   cd ..
   ```
   Jika masih aneh: `taskkill /F /IM java.exe` (hati-hati jika ada app lain pakai Java).
3. **`flutter clean`** lalu build **sekali** saja (jangan jalankan dua build paralel).
4. **Pengecualian antivirus** untuk folder proyek (setidaknya `D:\Traka\traka\build` dan `D:\Traka\traka\android\build`) — mengurangi lock pada `R.jar` saat resource linking.

Proyek ini sudah mengatur **`org.gradle.workers.max=1`** dan heap ~2GB di `android/gradle.properties` untuk menghemat RAM; jangan naikkan parallel tanpa RAM longgar.

## Jika tetap sering gagal

- Build **App Bundle** sekali dari PC lain / **CI** (GitHub Actions, Codemagic) — unggah `.aab` dari artefak.
- Atau jalankan build saat **malam**, sedikit app terbuka, kabel listrik menyala (hindari throttle baterai).

## `flutter clean` gagal hapus `build` / `.dart_tool`

Pesan: *A program may still be using a file in the directory* — folder terkunci (Gradle/Java, IDE, antivirus, atau `flutter run` masih aktif).

1. Stop `flutter run` / cabut device; `cd android` → `gradlew --stop`; tutup Android Studio / Explorer di folder proyek.
2. Ulangi `flutter clean`. Jika perlu: `taskkill /F /IM java.exe` (setelah tutup IDE).
3. Masih gagal: restart PC atau kecualikan `D:\Traka\traka` dari scan antivirus sementara.

## Tautan terkait

- [`BUILD_STUCK_SOLUSI.md`](BUILD_STUCK_SOLUSI.md) — build macet / daemon.
- [`BUILD_PLAY_STORE.md`](BUILD_PLAY_STORE.md) — `build_hybrid.bat -Target appbundle` dan upload Play Store.
