/// Client ID OAuth bertipe **Web** (client_type 3) dari `google-services.json` / Firebase Console.
/// Dipakai [GoogleSignIn.serverClientId] agar Android mengembalikan **idToken** untuk Firebase Auth.
///
/// Setelah mengubah project Firebase, unduh ulang `android/app/google-services.json` dan sesuaikan
/// entri `oauth_client` dengan `"client_type": 3`.
const String kGoogleOAuthWebClientId =
    '652861002574-396c2e6b02ef9d4cmoenpgtkchnlsk63.apps.googleusercontent.com';
