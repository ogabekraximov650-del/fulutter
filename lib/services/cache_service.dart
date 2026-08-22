// lib/services/cache_service.dart
//
// Lokal SQLite kesh:
// - Anime ro'yxatini diskda saqlaydi
// - Ilova offline holatda ham ishlaydi (eski kesh ko'rsatiladi)
// - 5 daqiqa o'tmagan kesh to'g'ridan ishlatiladi — API so'rov ketmaydi
// - cached_network_image rasm fayllarini disk keshiga alohida saqlaydi
//   (B2 dan har safar yuklab olish kerak bo'lmaydi)

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class CacheService {
  static Database? _db;
  static const _dbName = 'fulutter_cache.db';
  static const _dbVersion = 1;

  // Kesh muddati (millisekundda) — 5 daqiqa
  static const _cacheTtlMs = 5 * 60 * 1000;

  // ── DB ini ───────────────────────────────────────────────────

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        // Anime kesh jadvali
        await db.execute('''
          CREATE TABLE anime_cache (
            id   INTEGER PRIMARY KEY,
            data TEXT    NOT NULL,
            ts   INTEGER NOT NULL
          )
        ''');
        // Metadata (so'nggi yuklash vaqti va boshqalar)
        await db.execute('''
          CREATE TABLE meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ── Animelar ─────────────────────────────────────────────────

  /// Keshdan animelarni qaytaradi.
  /// Agar kesh yo'q yoki muddati o'tgan bo'lsa — null qaytaradi.
  static Future<List<Map<String, dynamic>>?> getAnimes() async {
    final database = await db;

    // So'nggi yuklash vaqtini tekshirish
    final meta = await database.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['last_anime_fetch'],
    );
    if (meta.isEmpty) return null;

    final lastFetch = int.parse(meta.first['value'] as String);
    final age = DateTime.now().millisecondsSinceEpoch - lastFetch;

    // Kesh muddati o'tgan — yangi so'rov kerak
    if (age > _cacheTtlMs) return null;

    final rows = await database.query('anime_cache', orderBy: 'id DESC');
    if (rows.isEmpty) return null;

    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  /// Animelarni keshga saqlaydi.
  static Future<void> saveAnimes(List<Map<String, dynamic>> animes) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = database.batch();

    // Eski keshni tozalash
    batch.delete('anime_cache');

    // Yangilarini saqlash
    for (final anime in animes) {
      batch.insert(
        'anime_cache',
        {'id': anime['id'], 'data': jsonEncode(anime), 'ts': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // So'nggi yuklash vaqtini yangilash
    batch.insert(
      'meta',
      {'key': 'last_anime_fetch', 'value': now.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await batch.commit(noResult: true);
  }

  /// Keshni butunlay tozalaydi (majburiy yangilash uchun).
  static Future<void> clearCache() async {
    final database = await db;
    await database.delete('anime_cache');
    await database.delete('meta');
  }

  /// Bitta animening kesh nusxasini yangilaydi (tahrirlashdan keyin).
  static Future<void> updateAnime(Map<String, dynamic> anime) async {
    final database = await db;
    await database.insert(
      'anime_cache',
      {
        'id': anime['id'],
        'data': jsonEncode(anime),
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Bitta animeni keshdan o'chiradi (o'chirishdan keyin).
  static Future<void> deleteAnime(int id) async {
    final database = await db;
    await database.delete('anime_cache', where: 'id = ?', whereArgs: [id]);
  }
}
