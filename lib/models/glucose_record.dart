class GlucoseRecord {
  final int? id;
  final String userId;
  final double value;
  final String status;
  final String source;
  final String? notes;
  final DateTime measuredAt;
  final DateTime createdAt;

  GlucoseRecord({
    this.id,
    required this.userId,
    required this.value,
    required this.status,
    required this.source,
    this.notes,
    required this.measuredAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'value': value,
      'status': status,
      'source': source,
      'notes': notes,
      'measured_at': measuredAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory GlucoseRecord.fromMap(Map<String, Object?> map) {
    return GlucoseRecord(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      value: (map['value'] as num).toDouble(),
      status: map['status'] as String,
      source: map['source'] as String,
      notes: map['notes'] as String?,
      measuredAt: DateTime.parse(map['measured_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
