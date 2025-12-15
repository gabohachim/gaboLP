import 'dart:io';
import 'package:flutter/material.dart';

import '../services/discography_service.dart';
import '../services/metadata_service.dart';

class VinylDetailSheet extends StatefulWidget {
  final Map<String, dynamic> vinyl; // fila de la BD

  const VinylDetailSheet({super.key, required this.vinyl});

  @override
  State<VinylDetailSheet> createState() => _VinylDetailSheetState();
}

class _VinylDetailSheetState extends State<VinylDetailSheet> {
  bool loading = true;
  String? errorMsg;
  List<TrackItem> tracks = [];

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() {
      loading = true;
      errorMsg = null;
      tracks = [];
    });

    try {
      final artista = (widget.vinyl['artista'] as String?)?.trim() ?? '';
      final album = (widget.vinyl['album'] as String?)?.trim() ?? '';
      String? rgid = (widget.vinyl['mbid'] as String?)?.trim(); // aquí guardamos releaseGroupId

      // Si no tenemos releaseGroupId guardado, lo intentamos obtener desde internet
      if ((rgid == null || rgid.isEmpty) && artista.isNotEmpty && album.isNotEmpty) {
        final options = await MetadataService.fetchCoverCandidates(
          artist: artista,
          album: album,
        );
        if (options.isNotEmpty) {
          rgid = options.first.releaseGroupId;
        }
      }

      if (rgid == null || rgid.isEmpty) {
        setState(() {
          loading = false;
          errorMsg = 'No pude obtener el ID del álbum para buscar canciones.';
        });
        return;
      }

      final list = await DiscographyService.getTracksFromReleaseGroup(rgid);

      setState(() {
        tracks = list;
        loading = false;
        errorMsg = list.isEmpty ? 'No encontré canciones para este álbum.' : null;
      });
    } catch (_) {
      setState(() {
        loading = false;
        errorMsg = 'Error al cargar las canciones.';
      });
    }
  }

  Widget _coverWidget() {
    final cp = (widget.vinyl['coverPath'] as String?)?.trim() ?? '';
    if (cp.isNotEmpty) {
      final f = File(cp);
      if (f.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            f,
            width: 160,
            height: 160,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.album, size: 70),
    );
  }

  @override
  Widget build(BuildContext context) {
    final numero = widget.vinyl['numero'];
    final artista = (widget.vinyl['artista'] as String?) ?? '';
    final album = (widget.vinyl['album'] as String?) ?? '';
    final year = (widget.vinyl['year'] as String?)?.trim() ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra superior
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _coverWidget(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LP N° $numero',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        artista,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if (year.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Año: $year', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _loadTracks,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Actualizar canciones'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Canciones',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(height: 8),

            if (loading) const LinearProgressIndicator(),

            if (!loading && errorMsg != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(errorMsg!, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),

            if (!loading && tracks.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return ListTile(
                      dense: true,
                      title: Text('${t.number}. ${t.title}'),
                      trailing: Text(t.length ?? ''),
                    );
                  },
                ),
              ),

            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
