import 'package:hive_flutter/hive_flutter.dart';

import '../models/insumo_model.dart';

class HiveService {
  static const String _insumoBox = 'insumos';
  static const String _pendingEntradasBox = 'entradas_offline';
  static const String _pendingMovimientosBox = 'movimientos_offline';
  static const String _pendingBitacorasBox = 'bitacora_offline';
  static const String _auditBox = 'auditoria_offline';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_insumoBox);
    await Hive.openBox(_pendingEntradasBox);
    await Hive.openBox(_pendingMovimientosBox);
    await Hive.openBox(_pendingBitacorasBox);
    await Hive.openBox(_auditBox);
  }

  static Future<bool> saveOfflineEntrada(Map<String, dynamic> record) async {
    final box = Hive.box(_pendingEntradasBox);
    box.add({
      ...record,
      'sincronizado': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  static Future<void> saveOfflineMovimiento(Map<String, dynamic> record) async {
    final box = Hive.box(_pendingMovimientosBox);
    box.add({
      ...record,
      'sincronizado': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> saveOfflineBitacora(Map<String, dynamic> record) async {
    final box = Hive.box(_pendingBitacorasBox);
    box.add({
      ...record,
      'sincronizado': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> saveOfflineAudit(Map<String, dynamic> record) async {
    final box = Hive.box(_auditBox);
    box.add({
      ...record,
      'sincronizado': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingMovimientos() async {
    final box = Hive.box(_pendingMovimientosBox);
    final stored = box.values.toList();
    return stored
        .whereType<Map<String, dynamic>>()
        .where((item) => item['sincronizado'] != true)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getPendingBitacoras() async {
    final box = Hive.box(_pendingBitacorasBox);
    final stored = box.values.toList();
    return stored
        .whereType<Map<String, dynamic>>()
        .where((item) => item['sincronizado'] != true)
        .toList();
  }

  static Future<void> marcarMovimientoSincronizado(dynamic key) async {
    final box = Hive.box(_pendingMovimientosBox);
    final record = box.get(key);
    if (record is Map) {
      record['sincronizado'] = true;
      await box.put(key, record);
    }
  }

  static Future<void> marcarBitacoraSincronizada(dynamic key) async {
    final box = Hive.box(_pendingBitacorasBox);
    final record = box.get(key);
    if (record is Map) {
      record['sincronizado'] = true;
      await box.put(key, record);
    }
  }

  static Future<List<InsumoModel>> getInsumos() async {
    final box = Hive.box(_insumoBox);
    final stored = box.values.toList();
    return stored
        .whereType<Map<String, dynamic>>()
        .map((item) => InsumoModel.fromMap(item))
        .toList();
  }

  static Future<int> getPendingEntradasCount() async {
    final box = Hive.box(_pendingEntradasBox);
    return box.length;
  }

  static Future<int> getPendingMovimientosCount() async {
    final box = Hive.box(_pendingMovimientosBox);
    return box.length;
  }

  static Future<void> cacheInsumos(List<InsumoModel> insumos) async {
    final box = Hive.box(_insumoBox);
    await box.clear();
    for (final insumo in insumos) {
      await box.add(insumo.toMap());
    }
  }
}
