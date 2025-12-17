import 'package:flutter/material.dart';
import '../services/drive_backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool auto = false;
  DateTime? last;
  bool working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await DriveBackupService.isAutoEnabled();
    final l = await DriveBackupService.getLastBackupTime();
    if (!mounted) return;
    setState(() {
      auto = a;
      last = l;
    });
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'Nunca';
    final dd = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dd.day)}/${two(dd.month)}/${dd.year} ${two(dd.hour)}:${two(dd.minute)}';
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _toggleAuto(bool v) async {
    setState(() => auto = v);
    await DriveBackupService.setAutoEnabled(v);
    _snack(v ? 'Automático activado ✅' : 'Automático desactivado');
  }

  Future<void> _guardar() async {
    setState(() => working = true);
    try {
      await DriveBackupService.backupNowToCloud();
      await _load();
      _snack('Respaldo guardado en la nube ✅');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _restaurar() async {
    setState(() => working = true);
    try {
      await DriveBackupService.restoreFromCloud();
      await _load();
      _snack('Restaurado ✅');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Respaldo automático')),
                Switch(value: auto, onChanged: working ? null : _toggleAuto),
              ],
            ),
            const SizedBox(height: 6),
            Text('Último respaldo: ${_fmt(last)}'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: working ? null : _guardar,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Guardar lista'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: working ? null : _restaurar,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Restaurar lista'),
            ),
            const SizedBox(height: 10),
            if (working) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
