import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/vinyl_db.dart'; // ajusta si tu ruta es distinta
import 'google_auth_client.dart';

class DriveBackupService {
  static const _prefsAuto = 'backup_auto_enabled';
  static const _prefsLast = 'backup_last_timestamp';
  static const _backupFileName = 'gabolp_backup.json';

  /// Scope para Drive appDataFolder
  static final GoogleSignIn _gsi = GoogleSignIn(
    scopes: <String>[
      drive.DriveApi.driveAppdataScope,
    ],
  );

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

  /// Asegura login Google y crea DriveApi autenticado
  static Future<drive.DriveApi> _driveApi() async {
    GoogleSignInAccount? acc = _gsi.currentUser;
    acc ??= await _gsi.signInSilently();
    acc ??= await _gsi.signIn();

    if (acc == null) {
      throw Exception('No se pudo iniciar sesión con Google.');
    }

    final headers = normalizeAuthHeaders(await acc.authHeaders);
    final client = GoogleAuthClient(headers);
    return drive.DriveApi(client);
  }

  /// Busca el archivo backup en appDataFolder
  static Future<drive.File?> _findBackupFile(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_backupFileName' and trashed=false",
      $fields: 'files(id,name,modifiedTime,size)',
      pageSize: 1,
    );
    if (res.files == null || res.files!.isEmpty) return null;
    return res.files!.first;
  }

  /// ✅ Guardar lista (sube JSON a Google Drive appDataFolder)
  static Future<void> backupNowToCloud() async {
    final api = await _driveApi();

    // 1) Obtener vinilos de SQLite
    final all = await vinylDb.instance.getAll(); // <- tu DB: vinylDb

    // 2) Crear JSON
    final payload = <String, dynamic>{
      'app': 'GaBoLP',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'vinyls': all,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = utf8.encode(jsonStr);

    // 3) Crear/actualizar archivo en appDataFolder
    final existing = await _findBackupFile(api);

    final media = drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/json');

    if (existing == null) {
      final meta = drive.File()
        ..name = _backupFileName
        ..parents = ['appDataFolder'];

      await api.files.create(meta, uploadMedia: media);
    } else {
      await api.files.update(drive.File(), existing.id!, uploadMedia: media);
    }

    await _setLastBackupNow();
  }

  /// ✅ Restaurar lista desde nube (descarga JSON y reemplaza SQLite)
  static Future<void> restoreFromCloud() async {
    final api = await _driveApi();
    final existing = await _findBackupFile(api);

    if (existing == null) {
      throw Exception('No hay respaldo en la nube todavía.');
    }

    final media = await api.files.get(
      existing.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    // media puede ser drive.Media
    if (media is! drive.Media) {
      throw Exception('No se pudo descargar el respaldo.');
    }

    final chunks = <int>[];
    await for (final c in media.stream) {
      chunks.addAll(c);
    }

    final jsonStr = utf8.decode(chunks);
    final data = jsonDecode(jsonStr);

    if (data is! Map<String, dynamic>) throw Exception('Backup inválido.');
    final vinyls = data['vinyls'];
    if (vinyls is! List) throw Exception('Backup sin lista de vinilos.');

    await vinylDb.instance.replaceAllFromBackup(
      vinyls.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );

    await _setLastBackupNow();
  }

  /// ✅ Automático: llamarlo después de agregar/borrar vinilo
  static Future<void> autoBackupIfEnabled() async {
    if (await isAutoEnabled()) {
      await backupNowToCloud();
    }
  }
}
