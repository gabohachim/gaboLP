import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class vinylDb {
  vinylDb._();
  static final vinylDb instance = vinylDb._();

  static const String table = 'vinyls';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'gabolp.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migración sencilla: si vienes de versiones viejas, crea columnas faltantes.
        // Si ya existe la tabla, intentamos agregar columnas nuevas.
        if (oldVersion < 2) {
          await db.execute("CREATE TABLE IF NOT EXISTS $table ("
              "id INTEGER PRIMARY KEY AUTOINCREMENT,"
              "numero INTEGER NOT NULL,"
              "artista TEXT NOT NULL,"
              "album TEXT NOT NULL,"
              "year INTEGER,"
              "genre TEXT,"
              "country TEXT,"
              "bio TEXT,"
              "coverPath TEXT"
              ")");
          await _tryAddColumn(db, table, 'genre', 'TEXT');
          await _tryAddColumn(db, table, 'country', 'TEXT');
          await _tryAddColumn(db, table, 'bio', 'TEXT');
          await _tryAddColumn(db, table, 'coverPath', 'TEXT');
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero INTEGER NOT NULL,
        artista TEXT NOT NULL,
        album TEXT NOT NULL,
        year INTEGER,
        genre TEXT,
        country TEXT,
        bio TEXT,
        coverPath TEXT
      )
    ''');
  }

  Future<void> _tryAddColumn(Database db, String tableName, String col, String type) async {
    try {
      await db.execute('ALTER TABLE $tableName ADD COLUMN $col $type');
    } catch (_) {
      // ya existe
    }
  }

  // ====== CRUD ======

  Future<int> insertVinyl(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(table, row);
  }

  Future<int> deleteById(int id) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await database;
    return db.query(table, orderBy: 'numero ASC');
  }

  Future<int> getCount() async {
    final db = await database;
    final res = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table'));
    return res ?? 0;
  }

  /// Busca en tu colección.
  /// - Si viene solo artista: devuelve todos los del artista.
  /// - Si viene artista + album: filtra ambos.
  /// - El año NO se usa para buscar.
  Future<List<Map<String, dynamic>>> search({String? artista, String? album}) async {
    final db = await database;
    final a = (artista ?? '').trim();
    final al = (album ?? '').trim();

    final where = <String>[];
    final args = <Object?>[];

    if (a.isNotEmpty) {
      where.add('LOWER(artista) LIKE ?');
      args.add('%${a.toLowerCase()}%');
    }
    if (al.isNotEmpty) {
      where.add('LOWER(album) LIKE ?');
      args.add('%${al.toLowerCase()}%');
    }

    return db.query(
      table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'numero ASC',
    );
  }

  /// Duplicado exacto (artista+album)
  Future<bool> existsExact({required String artista, required String album}) async {
    final db = await database;
    final res = await db.query(
      table,
      columns: ['id'],
      where: 'LOWER(artista)=? AND LOWER(album)=?',
      whereArgs: [artista.trim().toLowerCase(), album.trim().toLowerCase()],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  /// Próximo número LP (1,2,3...)
  Future<int> getNextNumero() async {
    final db = await database;
    final res = await db.rawQuery('SELECT MAX(numero) as m FROM $table');
    final m = (res.isNotEmpty ? res.first['m'] : null);
    final maxNum = (m is int) ? m : (m is num ? m.toInt() : 0);
    return maxNum + 1;
  }

  /// Restaurar desde backup (reemplaza todo)
  Future<void> replaceAllFromBackup(List<Map<String, dynamic>> vinyls) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(table);

      vinyls.sort((a, b) {
        final na = (a['numero'] ?? 0) as int;
        final nb = (b['numero'] ?? 0) as int;
        return na.compareTo(nb);
      });

      for (final v in vinyls) {
        final row = Map<String, dynamic>.from(v);
        row.remove('id'); // autoincrement
        await txn.insert(table, row);
      }
    });
  }
}
