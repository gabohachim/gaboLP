import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/discography_service.dart';

class DiscographyScreen extends StatefulWidget {
  const DiscographyScreen({super.key});

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {
  final ctrl = TextEditingController();
  bool loading = false;
  List<ArtistHit> results = [];

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> buscar(String q) async {
    final t = q.trim();
    if (t.isEmpty) {
      setState(() => results = []);
      return;
    }
    setState(() => loading = true);
    final r = await DiscographyService.searchArtists(t, limit: 15);
    if (!mounted) return;
    setState(() {
      results = r;
      loading = false;
    });
  }

  Future<bool> _tengoAlgo(String artist) async {
    final list = await vinylDb.instance.search(artista: artist, album: '');
    return list.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discografías')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: ctrl,
              onChanged: buscar,
              decoration: const InputDecoration(
                labelText: 'Busca una banda (autocompletar)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (loading) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final a = results[i];
                  return FutureBuilder<bool>(
                    future: _tengoAlgo(a.name),
                    builder: (context, snap) {
                      final tengo = snap.data ?? false;
                      return ListTile(
                        title: Text(a.name),
                        subtitle: Text(a.country ?? ''),
                        trailing: tengo ? const Icon(Icons.check_circle, color: Colors.green) : null,
                        onTap: () {
                          // Pantalla completa de discografía se puede mejorar después.
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Seleccionaste: ${a.name}')),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
