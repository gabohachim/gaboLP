import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/vinyl_db.dart';
import 'google_auth_client.dart';

class DriveBackupService {
  static const _prefsAuto = 'backup_auto_enabled';
  static const _prefsLast = 'backup_last_timestamp';
  static const _backupFileName = 'gabolp_backup.json';

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

  static Future<drive.DriveApi> _driveApi() async {
    GoogleSignInAccount? acc = _gsi.currentUser;
    acc ??= await _gsi.signInSilently();
    acc ??= await _gsi.signIn();

    if (acc == null) {
      throw Exception('No se pudo iniciar sesión con Google.');
    }

    final headers = await acc.authHeaders;
    final client = GoogleAuthClient(headers);
    return drive.DriveApi(client);
  }

  static Future<drive.File?> _findBackupFile(drive.DriveApi api) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_backupFileName' and trashed=false",
      pageSize: 1,
      $fields: 'files(id,name,modifiedTime,size)',
    );
    final files = res.files ?? [];
    return files.isEmpty ? null : files.first;
  }

  static Future<void> backupNowToCloud() async {
    final api = await _driveApi();
    final all = await vinylDb.instance.getAll();

    final payload = <String, dynamic>{
      'app': 'GaBoLP',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'vinyls': all,
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = utf8.encode(jsonStr);

    final existing = await _findBackupFile(api);

    final media = drive.Media(
      Stream<List<int>>.fromIterable([bytes]),
      bytes.length,
      contentType: 'application/json',
    );

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

    if (media is! drive.Media) {
      throw Exception('No se pudo descargar el respaldo.');
    }

    final buffer = <int>[];
    await for (final chunk in media.stream) {
      buffer.addAll(chunk);
    }

    final jsonStr = utf8.decode(buffer);
    final data = jsonDecode(jsonStr);

    if (data is! Map<String, dynamic>) throw Exception('Backup inválido.');
    final vinyls = data['vinyls'];
    if (vinyls is! List) throw Exception('Backup sin lista de vinilos.');

    await vinylDb.instance.replaceAllFromBackup(
      vinyls.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );

    await _setLastBackupNow();
  }

  static Future<void> autoBackupIfEnabled() async {
    if (await isAutoEnabled()) {
      await backupNowToCloud();
    }
  }
}
