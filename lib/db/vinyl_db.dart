import 'package:path/path.dart';
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
    final path = join(dbPath, 'gabolp.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero INTEGER NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            year INTEGER,
            genre TEXT,
            country TEXT,
            coverPath TEXT
          )
        ''');
      },
    );
  }

  // ==========================
  // CONSULTAS
  // ==========================

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await database;
    return db.query(table, orderBy: 'numero ASC');
  }

  // ==========================
  // INSERTAR / BORRAR
  // ==========================

  Future<int> insertVinyl(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(table, row);
  }

  Future<int> deleteById(int id) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // ==========================
  // 🔥 RESTAURAR DESDE BACKUP
  // ==========================

  Future<void> replaceAllFromBackup(List<Map<String, dynamic>> vinyls) async {
    final db = await database;

    await db.transaction((txn) async {
      // borrar todo
      await txn.delete(table);

      // ordenar por número LP
      vinyls.sort((a, b) {
        final na = (a['numero'] ?? 0) as int;
        final nb = (b['numero'] ?? 0) as int;
        return na.compareTo(nb);
      });

      // reinsertar
      for (final v in vinyls) {
        final row = Map<String, dynamic>.from(v);

        // eliminar id antiguo
        row.remove('id');

        await txn.insert(table, row);
      }
    });
  }
}
