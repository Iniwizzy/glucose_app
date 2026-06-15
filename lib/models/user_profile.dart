import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String email;
  final String provider;
  final String fullName;
  final String? photoUrl;
  final DateTime? birthDate;
  final String? gender;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.provider,
    required this.fullName,
    required this.createdAt,
    required this.updatedAt,
    this.photoUrl,
    this.birthDate,
    this.gender,
  });

  static DateTime _asDateTime(dynamic value, DateTime fallback) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static DateTime? _asNullableDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final now = DateTime.now();

    return UserProfile(
      uid: doc.id,
      email: (data['email'] ?? '') as String,
      provider: (data['provider'] ?? 'password') as String,
      fullName: (data['fullName'] ?? '') as String,
      photoUrl: data['photoUrl'] as String?,
      birthDate: _asNullableDateTime(data['birthDate']),
      gender: data['gender'] as String?,
      createdAt: _asDateTime(data['createdAt'], now),
      updatedAt: _asDateTime(data['updatedAt'], now),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'provider': provider,
      'fullName': fullName,
      'photoUrl': photoUrl,
      'birthDate': birthDate,
      'gender': gender,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
