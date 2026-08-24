import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersistenciaOfflineService {
  static const String _boxName = 'inventario_salvietti';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  static Box<dynamic> get _box => Hive.box(_boxName);

  static Future<void> guardarRegistroLocal({
    required String tipo,
    required Map<String, dynamic> registro,
  }) async {
    final payload = <String, dynamic>{
      ...registro,
      'tipo': tipo,
      'sincronizado': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'offline': true,
    };

    await _box.add(payload);
  }

  static Future<List<Map<String, dynamic>>> obtenerPendientes() async {
    final items = _box.values.toList();
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['sincronizado'] != true)
        .toList();
  }

  static Future<int> get pendientesCount async =>
      (await obtenerPendientes()).length;

  static Future<void> sincronizarPendientes() async {
    final pendientes = await obtenerPendientes();
    if (pendientes.isEmpty) {
      return;
    }

    final client = Supabase.instance.client;

    for (final item in pendientes) {
      try {
        final tipo = (item['tipo'] ?? '').toString();

        if (tipo == 'movimiento' || tipo == 'entrada' || tipo == 'salida') {
          await client.from('movimientos_inventario').insert(item);
        } else if (tipo == 'bitacora') {
          await client.from('bitacora_inventario').insert(item);
        } else if (tipo == 'auditoria') {
          await client.from('auditoria').insert(item);
        }

        item['sincronizado'] = true;
        item['offline'] = false;
      } catch (_) {
        return;
      }
    }

    final keys = <dynamic>[];
    for (final entry in _box.toMap().entries) {
      final value = entry.value;
      if (value is Map && value['sincronizado'] == true) {
        keys.add(entry.key);
      }
    }

    for (final key in keys) {
      await _box.delete(key);
    }
  }

  static Future<void> registrarTransaccionConAuditoria({
    required String tipo,
    required Map<String, dynamic> payload,
    required String usuarioId,
  }) async {
    final registro = <String, dynamic>{
      ...payload,
      'usuario_id': usuarioId,
      'tipo': tipo,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sincronizado': false,
    };

    try {
      final client = Supabase.instance.client;
      await client.from('movimientos_inventario').insert(registro);

      await client.from('bitacora_inventario').insert({
        'usuario_id': usuarioId,
        'evento': 'Transacción $tipo registrada',
        'tipo': tipo,
        'detalle': registro,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'sincronizado': true,
        'activo': true,
      });
    } catch (_) {
      await guardarRegistroLocal(tipo: tipo, registro: registro);
    }
  }
}
