import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/vinyl_db.dart';

class BackupService {
  static const _prefsAuto = 'backup_auto_enabled';
  static const _prefsLast = 'backup_last_timestamp';
  static const _backupFileName = 'gabolp_backup.json';

  static Future<bool> isAutoEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_prefsAuto) ?? false;
  }

  static Future<void> setAutoEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_prefsAuto, v);
  }

  static Future<DateTime?> getLastBackupTime() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(_prefsLast);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> _setLastBackupNow() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_prefsLast, DateTime.now().millisecondsSinceEpoch);
  }

  /// Carpeta: Documentos/GaBoLP
  static Future<Directory> _ensureBackupDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}GaBoLP');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _backupFile() async {
    final dir = await _ensureBackupDir();
    return File('${dir.path}${Platform.pathSeparator}$_backupFileName');
  }

  /// ✅ Guardar lista: exporta SQLite a JSON y lo guarda en gabolp_backup.json
  static Future<String> exportBackupNow() async {
    final all = await VinylDb.instance.getAll(); // List<Map<String,dynamic>>
    final payload = <String, dynamic>{
      'app': 'GaBoLP',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'vinyls': all,
    };

    final f = await _backupFile();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(payload), flush: true);

    await _setLastBackupNow();
    return f.path;
  }

  /// ✅ Restaurar lista desde archivo (elige JSON)
  /// Por seguridad: reemplaza toda la colección actual.
  static Future<void> restoreFromPickedFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      throw Exception('No seleccionaste archivo.');
    }

    final path = result.files.single.path;
    if (path == null) throw Exception('Archivo inválido.');

    final jsonStr = await File(path).readAsString();
    final data = jsonDecode(jsonStr);

    if (data is! Map<String, dynamic>) throw Exception('Formato de backup inválido.');

    final vinyls = data['vinyls'];
    if (vinyls is! List) throw Exception('Backup sin lista de vinilos.');

    // Reemplaza la base: borra todo y re-inserta
    await VinylDb.instance.replaceAllFromBackup(
      vinyls.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );

    // Guardar “última restauración” como última acción
    await _setLastBackupNow();
  }

  /// ✅ Automático: úsalo después de agregar/borrar vinilos
  static Future<void> autoBackupIfEnabled() async {
    if (await isAutoEnabled()) {
      await exportBackupNow();
    }
  }
}

