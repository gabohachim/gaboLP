import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/vinyl_db.dart';
import '../models/cover_candidate.dart';
import 'discography_service.dart';
import 'drive_backup_service.dart';
import 'metadata_service.dart';

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
  static Future<PreparedVinylAdd> prepare({
    required String artist,
    required String album,
    String? artistId,
  }) async {
    final meta = await MetadataService.fetchAutoMetadata(artist: artist, album: album);
    final aInfo = await DiscographyService.getArtistInfo(artist);

    final covers = await MetadataService.fetchCoverCandidates(
      artist: artist,
      album: album,
      max: 5,
    );

    return PreparedVinylAdd(
      artist: artist,
      album: album,
      year: meta.year,
      genre: aInfo.genre,
      country: aInfo.country,
      bioEs: aInfo.bioEs,
      coverCandidates: covers,
      selectedCover: covers.isNotEmpty ? covers.first : null,
    );
  }

  static Future<AddResult> addPrepared(
    PreparedVinylAdd p, {
    String? overrideYear,
  }) async {
    final exists = await vinylDb.instance.existsExact(artista: p.artist, album: p.album);
    if (exists) return AddResult(false, 'Ya lo tienes (repetido)');

    final nextNumber = await vinylDb.instance.getNextNumero();

    String? coverPath;
    final coverUrl = p.selectedCover500;
    if (coverUrl != null && coverUrl.trim().isNotEmpty) {
      coverPath = await _downloadCoverToFile(url: coverUrl.trim(), artist: p.artist, album: p.album);
    }

    final y = (overrideYear ?? p.year)?.trim();
    final yearInt = (y == null || y.isEmpty) ? null : int.tryParse(y);

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

    await DriveBackupService.autoBackupIfEnabled();

    return AddResult(true, 'Agregado ✅ (LP N° $nextNumber)');
  }

  static Future<String?> _downloadCoverToFile({
    required String url,
    required String artist,
    required String album,
  }) async {
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
