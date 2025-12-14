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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vinilos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero INTEGER UNIQUE NOT NULL,
            artista TEXT NOT NULL,
            album TEXT NOT NULL,
            year TEXT,
            coverPath TEXT,
            mbid TEXT,
            UNIQUE(artista, album)
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('ALTER TABLE vinilos ADD COLUMN coverPath TEXT;');
          await db.execute('ALTER TABLE vinilos ADD COLUMN mbid TEXT;');
        }
      },
    );
  }

  Future<int> getCount() async {
    final database = await db;
    final res = await database.rawQuery('SELECT COUNT(*) as c FROM vinilos');
    return (res.first['c'] as int?) ?? 0;
  }

  Future<int> _nextNumero() async {
    final database = await db;
    final res = await database.rawQuery('SELECT MAX(numero) as m FROM vinilos');
    final maxNum = (res.first['m'] as int?) ?? 0;
    return maxNum + 1; // empieza en 1
  }

  Future<void> insertVinyl({
    required String artista,
    required String album,
    String? year,
    String? coverPath,
    String? mbid,
  }) async {
    final database = await db;
    await database.insert('vinilos', {
      'numero': await _nextNumero(),
      'artista': artista.trim(),
      'album': album.trim(),
      'year': (year ?? '').trim(),
      'coverPath': (coverPath ?? '').trim(),
      'mbid': (mbid ?? '').trim(),
    });
  }

  Future<List<Map<String, dynamic>>> search({
    required String artista,
    String album = '',
  }) async {
    final database = await db;

    final a = artista.trim();
    final al = album.trim();

    if (a.isEmpty && al.isEmpty) return [];

    final where = <String>[];
    final args = <String>[];

    if (a.isNotEmpty) {
      where.add("artista LIKE ? COLLATE NOCASE");
      args.add("%$a%");
    }
    if (al.isNotEmpty) {
      where.add("album LIKE ? COLLATE NOCASE");
      args.add("%$al%");
    }

    return database.query(
      'vinilos',
      where: where.join(' AND '),
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
