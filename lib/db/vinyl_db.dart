import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class VinylDb {
  static final VinylDb instance = VinylDb._();
  VinylDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'vinilos.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vinilos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero INTEGER UNIQUE,
            artista TEXT NOT NULL,
            album TEXT NOT NULL,
            year TEXT,
            UNIQUE(artista, album)
          )
        ''');
      },
    );
  }

  Future<int> getCount() async {
    final database = await db;
    final res = await database.rawQuery('SELECT COUNT(*) as c FROM vinilos');
    return (res.first['c'] as int?) ?? 0;
  }

  Future<int> nextNumero() async {
    final database = await db;
    final res =
        await database.rawQuery('SELECT MAX(numero) as maxNum FROM vinilos');
    final maxNum = (res.first['maxNum'] as int?) ?? 0;
    return maxNum + 1;
  }

  Future<void> insertVinyl({
    required String artista,
    required String album,
    String? year,
  }) async {
    final database = await db;
    final numero = await nextNumero();
    await database.insert('vinilos', {
      'numero': numero,
      'artista': artista.trim(),
      'album': album.trim(),
      'year': (year ?? '').trim(),
    });
  }

  Future<List<Map<String, dynamic>>> search({
    required String artista,
    String? album,
  }) async {
    final database = await db;
    final a = artista.trim();
    final al = (album ?? '').trim();

    if (a.isEmpty && al.isEmpty) return [];

    final whereParts = <String>[];
    final args = <String>[];

    if (a.isNotEmpty) {
      whereParts.add("artista LIKE ? COLLATE NOCASE");
      args.add("%$a%");
    }
    if (al.isNotEmpty) {
      whereParts.add("album LIKE ? COLLATE NOCASE");
      args.add("%$al%");
    }

    final where = whereParts.join(" AND ");

    return database.query(
      'vinilos',
      where: where,
      whereArgs: args,
      orderBy: 'numero ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final database = await db;
    return database.query('vinilos', orderBy: 'numero ASC');
  }

  Future<void> deleteById(int id) async {
    final database = await db;
    await database.delete('vinilos', where: 'id = ?', whereArgs: [id]);
  }
}

