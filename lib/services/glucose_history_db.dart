import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/glucose_record.dart';

class GlucoseHistoryDb {
  GlucoseHistoryDb._();

  static final GlucoseHistoryDb instance = GlucoseHistoryDb._();
  static const String _dbName = 'glucose_history.db';
  static const int _dbVersion = 1;
  static const String _tableName = 'glucose_history';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final directory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(directory.path, _dbName);

    _database = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
    );
    return _database!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        value REAL NOT NULL,
        status TEXT NOT NULL,
        source TEXT NOT NULL,
        notes TEXT,
        measured_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_glucose_history_user_measured ON $_tableName(user_id, measured_at DESC)',
    );
  }

  Future<int> insertRecord(GlucoseRecord record) async {
    final db = await database;
    return db.insert(_tableName, record.toMap());
  }

  Future<List<GlucoseRecord>> getRecentRecords(
    String userId, {
    int limit = 10,
  }) async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'measured_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(GlucoseRecord.fromMap).toList();
  }

  Future<int> deleteOlderThan(String userId, DateTime threshold) async {
    final db = await database;
    return db.delete(
      _tableName,
      where: 'user_id = ? AND measured_at < ?',
      whereArgs: [userId, threshold.toIso8601String()],
    );
  }

  /// Delete all records for a user older than [days]. Returns number of rows deleted.
  Future<int> enforceRetentionPolicy({
    required String userId,
    int days = 90,
  }) async {
    final threshold = DateTime.now().subtract(Duration(days: days));
    return deleteOlderThan(userId, threshold);
  }

  /// Delete all history for a given user. Returns number of rows deleted.
  Future<int> deleteAllForUser(String userId) async {
    final db = await database;
    return db.delete(_tableName, where: 'user_id = ?', whereArgs: [userId]);
  }

  /// Delete a single record by its id.
  Future<int> deleteById(int id) async {
    final db = await database;
    return db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }
}
