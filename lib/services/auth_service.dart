import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'profile_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  final ProfileService _profileService = ProfileService.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Get current user email - ADD THIS PROPERTY
  String? get userEmail => _auth.currentUser?.email;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        await _profileService.upsertFromAuthUser(result.user!);
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Sign up with email and password
  Future<UserCredential> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (fullName != null && fullName.trim().isNotEmpty) {
        await result.user?.updateDisplayName(fullName.trim());
      }

      if (result.user != null) {
        await _profileService.upsertFromAuthUser(
          result.user!,
          fullNameOverride: fullName,
        );
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Sign in with Google - Updated with better error handling
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Check if Google Play Services is available
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        throw Exception('Login dibatalkan oleh pengguna');
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      UserCredential result = await _auth.signInWithCredential(credential);

      if (result.user != null) {
        await _profileService.upsertFromAuthUser(result.user!);
      }

      return result;
    } catch (e) {
      print('Google Sign-In Error: $e');

      // Handle specific error cases
      if (e.toString().contains('sign_in_failed') ||
          e.toString().contains('ApiException: 10')) {
        throw Exception(
          'Google Sign-In tidak dikonfigurasi dengan benar. Silakan gunakan login email.',
        );
      } else if (e.toString().contains('network_error')) {
        throw Exception('Tidak ada koneksi internet. Periksa koneksi Anda.');
      } else if (e.toString().contains('sign_in_canceled')) {
        throw Exception('Login dibatalkan oleh pengguna');
      } else {
        throw Exception(
          'Google Sign-In gagal. Silakan coba lagi atau gunakan email.',
        );
      }
    }
  }

  // Reset password
  Future<void> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Sign out from Google first if signed in
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      await _auth.signOut();
    } catch (e) {
      print('Sign out error: $e');
      // Even if Google sign out fails, we should still sign out from Firebase
      await _auth.signOut();
    }
  }

  Future<void> ensureCurrentUserProfile({String? fullNameOverride}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _profileService.upsertFromAuthUser(
      user,
      fullNameOverride: fullNameOverride,
    );
  }

  String get currentProvider {
    final user = _auth.currentUser;
    if (user == null) return 'unknown';
    final providers = user.providerData.map((e) => e.providerId).toSet();
    if (providers.contains('google.com')) return 'google';
    return 'password';
  }

  Future<void> changePasswordForEmailUser({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw 'User belum login';
    if ((user.email ?? '').isEmpty) throw 'Email user tidak ditemukan';
    if (currentProvider != 'password') {
      throw 'Ubah password hanya tersedia untuk akun email/password';
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Email tidak terdaftar';
      case 'wrong-password':
        return 'Password salah';
      case 'email-already-in-use':
        return 'Email sudah digunakan';
      case 'weak-password':
        return 'Password terlalu lemah (minimal 6 karakter)';
      case 'invalid-email':
        return 'Format email tidak valid';
      case 'user-disabled':
        return 'Akun telah dinonaktifkan';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Coba lagi nanti';
      case 'operation-not-allowed':
        return 'Operasi tidak diizinkan';
      default:
        return 'Terjadi kesalahan: ${e.message}';
    }
  }
}
