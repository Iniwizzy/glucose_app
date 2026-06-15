import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  String _providerId(User user) {
    final ids = user.providerData.map((e) => e.providerId).toSet();
    if (ids.contains('google.com')) return 'google';
    return 'password';
  }

  Future<void> upsertFromAuthUser(User user, {String? fullNameOverride}) async {
    final ref = _userDoc(user.uid);
    final existing = await ref.get();
    final now = DateTime.now();
    final provider = _providerId(user);

    final displayName =
        (fullNameOverride?.trim().isNotEmpty ?? false)
            ? fullNameOverride!.trim()
            : (user.displayName ?? 'Pengguna GLUVER');

    final payload = <String, dynamic>{
      'email': user.email ?? '',
      'provider': provider,
      'fullName': displayName,
      'photoUrl': user.photoURL,
      'updatedAt': now,
    };

    if (!existing.exists) {
      payload['createdAt'] = now;
    }

    await ref.set(payload, SetOptions(merge: true));
  }

  Stream<UserProfile?> profileStream(String uid) {
    return _userDoc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  Future<UserProfile?> getProfile(String uid) async {
    final doc = await _userDoc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  Future<void> updateProfile({
    required String uid,
    required String fullName,
    String? photoUrl,
    DateTime? birthDate,
    String? gender,
  }) async {
    await _userDoc(uid).set({
      'fullName': fullName.trim(),
      'photoUrl': (photoUrl?.trim().isEmpty ?? true) ? null : photoUrl?.trim(),
      'birthDate': birthDate,
      'gender': (gender?.trim().isEmpty ?? true) ? null : gender?.trim(),
      'updatedAt': DateTime.now(),
    }, SetOptions(merge: true));
  }
}
