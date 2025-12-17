import '../db/vinyl_db.dart';
import 'drive_backup_service.dart';

class VinylActions {
  /// ✅ Agregar vinilo + (si está activo) respaldo automático a la nube
  static Future<int> addVinyl({
    required int numero,
    required String artist,
    required String album,
    int? year,
    String? genre,
    String? country,
    String? coverPath,
  }) async {
    final row = <String, dynamic>{
      'numero': numero,
      'artist': artist,
      'album': album,
      'year': year,
      'genre': genre,
      'country': country,
      'coverPath': coverPath,
    };

    final id = await vinylDb.instance.insertVinyl(row);

    // ✅ RESPALDO AUTOMÁTICO (solo si el switch está activado)
    await DriveBackupService.autoBackupIfEnabled();

    return id;
  }

  /// ✅ Borrar vinilo + (si está activo) respaldo automático a la nube
  static Future<void> deleteVinylById(int id) async {
    await vinylDb.instance.deleteById(id);

    // ✅ RESPALDO AUTOMÁTICO (solo si el switch está activado)
    await DriveBackupService.autoBackupIfEnabled();
  }
}
