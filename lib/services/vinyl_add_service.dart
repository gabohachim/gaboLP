import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/vinyl_db.dart';
import 'drive_backup_service.dart';
import 'metadata_service.dart';
import 'discography_service.dart';

class CoverCandidate {
  final String coverUrl250;
  final String coverUrl500;
  final String? year;

  CoverCandidate({
    required this.coverUrl250,
    required this.coverUrl500,
    this.year,
  });
}

class PreparedVinylAdd {
  final String artist;
  final String album;
  final String? year;
  final String? genre;
  final String? country;
  final String? bioEs;

  final List<CoverCandidate> coverCandidates;
  CoverCandidate? selectedCover;

  PreparedVinylAdd({
    required this.artist,
    required this.album,
    required this.coverCandidates,
    this.selectedCover,
    this.year,
    this.genre,
    this.country,
    this.bioEs,
  });

  String? get selectedCover500 => selectedCover?.coverUrl500;
}

class AddResult {
  final bool ok;
  final String message;
  AddResult(this.ok, this.message);
}

class VinylAddService {
  /// Prepara metadata (año, género, país, bio) y hasta 5 carátulas
  static Future<PreparedVinylAdd> prepare({
    required String artist,
    required String album,
    String? artistId,
  }) async {
    // metadata álbum
    final meta = await MetadataService.fetchAutoMetadata(
      artist: artist,
      album: album,
    );

    // info artista (género, país, bio)
    final aInfo = await DiscographyService.getArtistInfo(artist);

    // carátulas (máx 5)
    final covers = await MetadataService.fetchCoverCandidates(
      artist: artist,
      album: album,
      max: 5,
    );

    final prepared = PreparedVinylAdd(
      artist: artist,
      album: album,
      year: meta.year,
      genre: aInfo.genre,
      country: aInfo.country,
      bioEs: aInfo.bioEs,
      coverCandidates: covers,
      selectedCover: covers.isNotEmpty ? covers.first : null,
    );

    return prepared;
  }

  /// Guarda el LP en SQLite + descarga carátula a archivo local
  static Future<AddResult> addPrepared(
    PreparedVinylAdd p, {
    String? overrideYear,
  }) async {
    // Evitar duplicado exacto (artista+album)
    final exists = await vinylDb.instance.existsExact(
      artista: p.artist,
      album: p.album,
    );

    if (exists) return AddResult(false, 'Ya lo tienes (repetido)');

    // Número nuevo (LP N°)
    final nextNumber = await vinylDb.instance.getNextNumero();

    // Descargar carátula (si hay)
    String? coverPath;
    final coverUrl = p.selectedCover500;
    if (coverUrl != null && coverUrl.trim().isNotEmpty) {
      coverPath = await _downloadCoverToFile(
        url: coverUrl.trim(),
        artist: p.artist,
        album: p.album,
      );
    }

    final yearToSave = (overrideYear ?? p.year)?.trim();
    final yearInt = (yearToSave == null || yearToSave.isEmpty)
        ? null
        : int.tryParse(yearToSave);

    await vinylDb.instance.insertVinyl({
      'numero': nextNumber,
      'artista': p.artist,
      'album': p.album,
      'year': yearInt,
      'genre': p.genre,
      'country': p.country,
      'bio': p.bioEs,
      'coverPath': coverPath,
    });

    // ✅ respaldo automático en la nube si está activado
    await DriveBackupService.autoBackupIfEnabled();

    return AddResult(true, 'Agregado ✅ (LP N° $nextNumber)');
  }

  static Future<String?> _downloadCoverToFile({
    required String url,
    required String artist,
    required String album,
  }) async {
    // ⚠️ Aquí asumo que tu MetadataService ya tiene un downloader simple.
    // Si NO lo tiene, dímelo y te pongo el downloader con http.
    final bytes = await MetadataService.downloadImageBytes(url);
    if (bytes == null || bytes.isEmpty) return null;

    final dir = await getApplicationDocumentsDirectory();
    final safeA = artist.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final safeB = album.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');

    final coversDir = Directory('${dir.path}/GaBoLP/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final file = File('${coversDir.path}/${safeA}_$safeB.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
