import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.firebase-perf")
    id("com.google.firebase.crashlytics")
}

// Load key.properties untuk release signing
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}
val hasReleaseSigning =
    !keystoreProperties["keyAlias"]?.toString().isNullOrBlank() &&
    !keystoreProperties["keyPassword"]?.toString().isNullOrBlank() &&
    !keystoreProperties["storeFile"]?.toString().isNullOrBlank() &&
    !keystoreProperties["storePassword"]?.toString().isNullOrBlank()

val releaseKeystoreFile = keystoreProperties["storeFile"]?.toString()?.let { rootProject.file(it) }
val releaseKeystoreExists = releaseKeystoreFile != null && releaseKeystoreFile.exists()

// Play Store / AAB-APK release: wajib keystore lengkap — tidak ada fallback ke debug.
val isPlayStoreReleaseTask = gradle.startParameter.taskNames.any { task ->
    val t = task.lowercase()
    t.contains("bundlerelease") ||
        t.contains("assemblerelease") ||
        t.contains("signreleasebundle") ||
        t.contains("signreleasebuild")
}
if (isPlayStoreReleaseTask) {
    if (!hasReleaseSigning) {
        error(
            "Release Play Store: isi lengkap android/key.properties dengan:\n" +
                "  storePassword=...\n  keyPassword=...\n  keyAlias=...\n" +
                "  storeFile=path/relatif/dari/folder/android/ke/upload-keystore.jks\n" +
                "(MAPS_API_KEY tetap boleh di file yang sama.)",
        )
    }
    if (!releaseKeystoreExists) {
        error(
            "Release: file keystore tidak ditemukan: ${keystoreProperties["storeFile"]}\n" +
                "Path relatif terhadap folder android/ (bukan traka/).",
        )
    }
}

android {
    namespace = "id.traka.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
    defaultConfig {
        applicationId = "id.traka.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Maps API key: dari key.properties (MAPS_API_KEY) atau env MAPS_API_KEY. WAJIB di-set.
        val mapsKey = (keystoreProperties["MAPS_API_KEY"]?.toString()
            ?: System.getenv("MAPS_API_KEY")
            ?: "")
        manifestPlaceholders["mapsApiKey"] = mapsKey
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                keyAlias = keystoreProperties["keyAlias"]?.toString()
                keyPassword = keystoreProperties["keyPassword"]?.toString()
                storeFile = keystoreProperties["storeFile"]?.toString()?.let { rootProject.file(it) }
                storePassword = keystoreProperties["storePassword"]?.toString()
            }
        }
    }
    buildTypes {
        release {
            // Selalu release keystore untuk AAB/APK release (bukan debug).
            signingConfig = signingConfigs.getByName("release")
            // R8: menghasilkan mapping.txt untuk deobfuscation di Play Console + Crashlytics.
            // shrinkResources=false: kurangi risiko resource hilang (Flutter/plugin); ukuran tetap turun dari minify.
            isMinifyEnabled = true
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            firebaseCrashlytics {
                mappingFileUploadEnabled = true
            }
        }
    }
}

flutter {
    source = "../.."
}

// Exclude play-services-safetynet: digantikan Play Integrity API (Firebase App Check & Auth sudah pakai Play Integrity)
configurations.all {
    exclude(group = "com.google.android.gms", module = "play-services-safetynet")
}

dependencies {
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
  // Import the Firebase BoM
  implementation(platform("com.google.firebase:firebase-bom:34.8.0"))


  // TODO: Add the dependencies for Firebase products you want to use
  // When using the BoM, don't specify versions in Firebase dependencies
  implementation("com.google.firebase:firebase-analytics")


  // Add the dependencies for any other desired Firebase products
  // https://firebase.google.com/docs/android/setup#available-libraries

  // Google Play Services — wajib untuk FirebaseApp.initializeApp (StringResourceValueReader memakai
  // com.google.android.gms.common.R$string). Tanpa base/basement eksplisit, beberapa device crash
  // NoClassDefFoundError saat splash (terlihat di logcat: FATAL EXCEPTION main).
  implementation("com.google.android.gms:play-services-base:18.9.0")
  implementation("com.google.android.gms:play-services-basement:18.9.0")
  // Google Play Services Location (untuk deteksi mock location)
  implementation("com.google.android.gms:play-services-location:21.3.0")
  implementation("com.google.firebase:firebase-crashlytics")
}