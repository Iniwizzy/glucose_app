import 'package:flutter/material.dart';

import '../models/glucose_record.dart';
import '../services/glucose_history_db.dart';

class HistoryScreen extends StatefulWidget {
  final String userId;

  const HistoryScreen({super.key, required this.userId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final GlucoseHistoryDb _historyDb = GlucoseHistoryDb.instance;
  late Future<List<GlucoseRecord>> _historyFuture;

  static const Color primaryColor = Color(0xFFB71C1C);
  static const Color secondaryColor = Color(0xFFFDECEC);
  static const Color accentColor = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _historyFuture = _historyDb.getRecentRecords(widget.userId, limit: 100);
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Rendah':
        return accentColor;
      case 'Normal':
        return const Color(0xFF2E7D32);
      case 'Cukup Tinggi':
        return primaryColor;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Future<void> _confirmAndDeleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Konfirmasi'),
            content: const Text('Hapus semua riwayat untuk akun ini?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Hapus'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await _historyDb.deleteAllForUser(widget.userId);
      setState(() => _reload());
    }
  }

  Future<void> _confirmAndDeleteOne(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Konfirmasi'),
            content: const Text('Hapus entry ini?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Hapus'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await _historyDb.deleteById(id);
      setState(() => _reload());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: secondaryColor,
      appBar: AppBar(
        title: const Text('History Glukosa'),
        backgroundColor: Colors.transparent,
        foregroundColor: accentColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Bersihkan semua',
            onPressed: _confirmAndDeleteAll,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              secondaryColor,
              primaryColor.withOpacity(0.12),
              accentColor.withOpacity(0.08),
            ],
          ),
        ),
        child: FutureBuilder<List<GlucoseRecord>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Gagal memuat history: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return const Center(
                child: Text('Belum ada history glukosa tersimpan.'),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final record = records[index];
                final statusColor = _getStatusColor(record.status);

                return Dismissible(
                  key: ValueKey(record.id ?? index),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.redAccent,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    final res = await showDialog<bool>(
                      context: context,
                      builder:
                          (c) => AlertDialog(
                            title: const Text('Konfirmasi'),
                            content: const Text('Hapus entry ini?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(c).pop(false),
                                child: const Text('Batal'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(c).pop(true),
                                child: const Text('Hapus'),
                              ),
                            ],
                          ),
                    );
                    return res == true;
                  },
                  onDismissed: (_) async {
                    if (record.id != null) {
                      await _historyDb.deleteById(record.id!);
                      setState(() => _reload());
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: statusColor.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${record.value.toStringAsFixed(0)} mg/dL',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                record.status,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(record.measuredAt),
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              if (record.notes != null &&
                                  record.notes!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  record.notes!,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hapus',
                          onPressed: () async {
                            if (record.id != null)
                              await _confirmAndDeleteOne(record.id!);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
