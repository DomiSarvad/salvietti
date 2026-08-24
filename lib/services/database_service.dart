import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bitacora_entry.dart';
import '../models/insumo_model.dart';
import '../models/usuario_model.dart';
import 'hive_service.dart';

class DatabaseService {
  static SupabaseClient? _client;

  static Future<void> initSupabase({
    required String url,
    required String publishableKey,
  }) async {
    if (_client == null) {
      await Supabase.initialize(url: url, publishableKey: publishableKey);
      _client = Supabase.instance.client;
    }
  }

  static bool get isInitialized => _client != null;

  static Future<UsuarioModel> login({
    required String email,
    required String password,
  }) async {
    if (!isInitialized) {
      throw Exception('Supabase no está inicializado');
    }

    final result = await _client!.rpc(
      'login_usuario',
      params: {'p_email': email.trim(), 'p_password': password.trim()},
    );

    List<dynamic> rows = [];
    if (result is List) {
      rows = result;
    } else if (result != null) {
      rows = [result];
    }

    if (rows.isEmpty) {
      throw Exception('Credenciales inválidas');
    }

    final perfil = Map<String, dynamic>.from(rows.first as Map);
    final nombre = perfil['nombre']?.toString() ?? 'Usuario';
    final rol = perfil['rol']?.toString() ?? 'encargado_almacen';
    final activo = perfil['estado'] == null
        ? true
        : (perfil['estado'] is bool
              ? perfil['estado'] as bool
              : perfil['estado'].toString() == 'true');

    final usuario = UsuarioModel(
      id: perfil['id']?.toString() ?? '',
      nombre: nombre,
      email: perfil['email']?.toString() ?? email.trim(),
      rol: rol,
      activo: activo,
      fotoUrl: perfil['foto_url']?.toString(),
      telefono: perfil['telefono']?.toString(),
    );

    await saveAuditLog(
      usuarioId: usuario.id,
      evento: 'Inicio de sesión como $rol',
    );

    return usuario;
  }

  static Future<List<InsumoModel>> fetchInsumos() async {
    if (!isInitialized) {
      return HiveService.getInsumos();
    }

    try {
      final data =
          await _client!
                  .from('insumos_materias_primas')
                  .select('*')
                  .eq('activo', true)
                  .order('nombre', ascending: true)
              as List<dynamic>;

      final insumos = data
          .map((item) => InsumoModel.fromMap(Map<String, dynamic>.from(item)))
          .toList();

      await HiveService.cacheInsumos(insumos);
      return insumos;
    } catch (_) {
      return HiveService.getInsumos();
    }
  }

  /// Trae los últimos movimientos de la bitácora de auditoría para el
  /// panel de "Historial". Intenta resolver el nombre del usuario contra la
  /// tabla `usuarios`; si esa tabla no existe o falla, muestra el id crudo.
  static Future<List<BitacoraEntry>> fetchBitacora({int limite = 100}) async {
    if (!isInitialized) {
      final pendientes = await HiveService.getPendingBitacoras();
      return pendientes.map((item) => BitacoraEntry.fromMap(item)).toList();
    }

    try {
      final data =
          await _client!
                  .from('bitacora_inventario')
                  .select('*')
                  .order('timestamp', ascending: false)
                  .limit(limite)
              as List<dynamic>;

      final registros = data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      Map<String, String> nombresPorId = {};
      try {
        final usuariosIds = registros
            .map((r) => r['usuario_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        if (usuariosIds.isNotEmpty) {
          final usuariosData =
              await _client!
                      .from('usuarios')
                      .select('id, nombre')
                      .inFilter('id', usuariosIds)
                  as List<dynamic>;
          for (final u in usuariosData) {
            final map = Map<String, dynamic>.from(u as Map);
            nombresPorId[map['id'].toString()] = map['nombre']?.toString() ??
                'Usuario';
          }
        }
      } catch (_) {
        // Si la tabla de usuarios no existe o falla el join, se muestra el id.
      }

      return registros
          .map(
            (item) => BitacoraEntry.fromMap(
              item,
              usuarioNombre: nombresPorId[item['usuario_id']?.toString()],
            ),
          )
          .toList();
    } catch (_) {
      final pendientes = await HiveService.getPendingBitacoras();
      return pendientes.map((item) => BitacoraEntry.fromMap(item)).toList();
    }
  }

  static Future<Map<String, dynamic>> validarStockParaSalida({
    required String insumoId,
    required double cantidadSolicitada,
  }) async {
    if (!isInitialized) {
      return {
        'permitido': true,
        'stockDisponible': 0.0,
        'mensaje': 'Sin conexión, validación local no disponible.',
      };
    }

    try {
      final data = await _client!
          .from('insumos_materias_primas')
          .select('id, nombre, stock_actual, cantidad_minima, unidad_medida')
          .eq('id', insumoId)
          .maybeSingle();

      if (data == null) {
        throw StateError('El insumo no existe en inventario.');
      }

      final stockActual = ((data['stock_actual'] ?? 0) as num).toDouble();
      if (cantidadSolicitada > stockActual) {
        return {
          'permitido': false,
          'stockDisponible': stockActual,
          'mensaje':
              'Stock insuficiente. Solicitud ${cantidadSolicitada.toStringAsFixed(2)} vs disponible ${stockActual.toStringAsFixed(2)}.',
        };
      }

      return {
        'permitido': true,
        'stockDisponible': stockActual,
        'mensaje': 'Stock suficiente para continuar.',
      };
    } catch (e) {
      throw StateError('No fue posible validar el stock del insumo: $e');
    }
  }

  static Future<bool> registrarSalida({
    required String insumoId,
    required String usuarioId,
    required String areaDestino,
    required double cantidadSolicitada,
    required String unidadMedida,
    required String numeroLote,
    required String motivo,
    String? proveedorId,
    String? insumoNombre,
    DateTime? fechaOperacion,
  }) async {
    final validacion = await validarStockParaSalida(
      insumoId: insumoId,
      cantidadSolicitada: cantidadSolicitada,
    );

    final permitido = validacion['permitido'] as bool? ?? false;
    final stockDisponible =
        (validacion['stockDisponible'] as num?)?.toDouble() ?? 0.0;

    if (!permitido) {
      throw StateError(
        'Stock insuficiente: ${validacion['mensaje'] ?? 'No hay disponibilidad.'}',
      );
    }

    final payload = {
      'insumo_id': insumoId,
      'usuario_id': usuarioId,
      'area_destino': areaDestino,
      'cantidad': cantidadSolicitada,
      'unidad_medida': unidadMedida,
      'numero_lote': numeroLote,
      'motivo': motivo,
      'proveedor_id': proveedorId,
      'insumo_nombre': insumoNombre ?? 'Insumo',
      'tipo_movimiento': 'salida',
      'stock_anterior': stockDisponible,
      'stock_resultante': stockDisponible - cantidadSolicitada,
      'fecha_operacion': (fechaOperacion ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'activo': true,
    };

    try {
      await _client!.from('movimientos_inventario').insert(payload);

      await guardarBitacoraInventario(
        usuarioId: usuarioId,
        evento: 'Salida de insumo',
        tipo: 'salida',
        insumoId: insumoId,
        insumoNombre: insumoNombre ?? 'Insumo',
        cantidad: cantidadSolicitada,
        detalle: {
          'area_destino': areaDestino,
          'motivo': motivo,
          'numero_lote': numeroLote,
          'unidad_medida': unidadMedida,
          'stock_anterior': stockDisponible,
          'stock_resultante': stockDisponible - cantidadSolicitada,
          'operacion': 'salida',
        },
      );

      return true;
    } catch (e) {
      final offlineRecord = {
        'tipo': 'salida',
        'sincronizado': false,
        'payload': payload,
        'error': e.toString(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await HiveService.saveOfflineMovimiento(offlineRecord);

      await HiveService.saveOfflineBitacora({
        'usuario_id': usuarioId,
        'evento': 'Salida de insumo (offline)',
        'tipo': 'salida',
        'insumo_id': insumoId,
        'insumo_nombre': insumoNombre ?? 'Insumo',
        'cantidad': cantidadSolicitada,
        'detalle': {
          'area_destino': areaDestino,
          'motivo': motivo,
          'numero_lote': numeroLote,
          'stock_anterior': stockDisponible,
          'stock_resultante': stockDisponible - cantidadSolicitada,
          'sincronizado': false,
          'error': e.toString(),
        },
        'sincronizado': false,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      return false;
    }
  }

  static Future<void> guardarBitacoraInventario({
    required String usuarioId,
    required String evento,
    required String tipo,
    required String insumoId,
    required String insumoNombre,
    required double cantidad,
    required Map<String, dynamic> detalle,
  }) async {
    final log = {
      'usuario_id': usuarioId,
      'evento': evento,
      'tipo': tipo,
      'insumo_id': insumoId,
      'insumo_nombre': insumoNombre,
      'cantidad': cantidad,
      'detalle': detalle,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'sincronizado': true,
      'activo': true,
    };

    if (!isInitialized) {
      await HiveService.saveOfflineBitacora(log);
      return;
    }

    try {
      await _client!.from('bitacora_inventario').insert({
        'usuario_id': usuarioId,
        'evento': evento,
        'tipo': tipo,
        'insumo_id': insumoId,
        'insumo_nombre': insumoNombre,
        'cantidad': cantidad,
        'detalle': detalle,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'sincronizado': true,
        'activo': true,
      });
    } catch (e) {
      await HiveService.saveOfflineBitacora({
        ...log,
        'sincronizado': false,
        'detalle': {...detalle, 'error': e.toString()},
      });
    }
  }

  static Future<void> saveEntrada({
    required String insumoId,
    required String proveedorId,
    required double cantidad,
    required String unidadMedida,
    required String numeroLote,
    required DateTime fechaVencimiento,
  }) async {
    final payload = {
      'insumo_id': insumoId,
      'proveedor_id': proveedorId,
      'cantidad': cantidad,
      'unidad_medida': unidadMedida,
      'numero_lote': numeroLote,
      'fecha_vencimiento': fechaVencimiento.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
      'activo': true,
    };

    if (!isInitialized) {
      await HiveService.saveOfflineEntrada(payload);
      return;
    }

    try {
      await _client!.from('entradas').insert(payload);
    } catch (_) {
      await HiveService.saveOfflineEntrada(payload);
    }
  }

  static Future<bool> registrarEntradaMateriaPrima({
    required String codigoInsumo,
    required String descripcion,
    required double cantidad,
    required String unidadMedida,
    required String numeroLote,
    required DateTime fechaVencimiento,
    required String proveedorId,
    required String usuarioId,
  }) async {
    final normalizedCodigo = codigoInsumo.trim();
    final normalizedDescripcion = descripcion.trim();

    if (normalizedCodigo.isEmpty || normalizedDescripcion.isEmpty) {
      throw StateError('Código y descripción del insumo son obligatorios.');
    }

    final payload = {
      'insumo_id': normalizedCodigo,
      'codigo_insumo': normalizedCodigo,
      'descripcion': normalizedDescripcion,
      'cantidad': cantidad,
      'unidad_medida': unidadMedida,
      'numero_lote': numeroLote,
      'proveedor_id': proveedorId,
      'usuario_id': usuarioId,
      'fecha_vencimiento': fechaVencimiento.toUtc().toIso8601String(),
      'tipo_movimiento': 'entrada',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'activo': true,
    };

    try {
      if (!isInitialized) {
        await HiveService.saveOfflineMovimiento({
          ...payload,
          'sincronizado': false,
        });
        await HiveService.saveOfflineBitacora({
          'usuario_id': usuarioId,
          'evento': 'Entrada de materia prima (offline)',
          'tipo': 'entrada',
          'insumo_id': normalizedCodigo,
          'insumo_nombre': normalizedDescripcion,
          'cantidad': cantidad,
          'detalle': {'proveedor_id': proveedorId, 'numero_lote': numeroLote},
          'sincronizado': false,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        return false;
      }

      await _client!.from('movimientos_inventario').insert(payload);
      await guardarBitacoraInventario(
        usuarioId: usuarioId,
        evento: 'Entrada de materia prima',
        tipo: 'entrada',
        insumoId: normalizedCodigo,
        insumoNombre: normalizedDescripcion,
        cantidad: cantidad,
        detalle: {
          'proveedor_id': proveedorId,
          'numero_lote': numeroLote,
          'unidad_medida': unidadMedida,
          'fecha_vencimiento': fechaVencimiento.toUtc().toIso8601String(),
        },
      );
      return true;
    } catch (e) {
      await HiveService.saveOfflineMovimiento({
        ...payload,
        'sincronizado': false,
        'error': e.toString(),
      });
      await HiveService.saveOfflineBitacora({
        'usuario_id': usuarioId,
        'evento': 'Entrada de materia prima fallida',
        'tipo': 'entrada',
        'insumo_id': normalizedCodigo,
        'insumo_nombre': normalizedDescripcion,
        'cantidad': cantidad,
        'detalle': {
          'proveedor_id': proveedorId,
          'numero_lote': numeroLote,
          'unidad_medida': unidadMedida,
          'error': e.toString(),
        },
        'sincronizado': false,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      return false;
    }
  }

  static Future<void> saveAuditLog({
    required String usuarioId,
    required String evento,
  }) async {
    final log = {
      'usuario_id': usuarioId,
      'evento': evento,
      'timestamp': DateTime.now().toIso8601String(),
      'activo': true,
    };

    if (!isInitialized) {
      await HiveService.saveOfflineAudit(log);
      return;
    }

    try {
      await _client!.from('auditoria').insert(log);
    } catch (_) {
      await HiveService.saveOfflineAudit(log);
    }
  }

  static Future<void> logicalDeleteProveedor(String proveedorId) async {
    if (!isInitialized) {
      return;
    }
    await _client!
        .from('proveedores')
        .update({'activo': false})
        .eq('id', proveedorId);
  }

  static bool puedeEliminar(String rol) {
    return rol == 'Encargado de Almacén';
  }

  static Future<bool> softDeleteInsumo({
    required String insumoId,
    required String usuarioId,
    required String motivo,
  }) async {
    try {
      if (!isInitialized) {
        await HiveService.saveOfflineBitacora({
          'usuario_id': usuarioId,
          'evento': 'Borrado lógico de insumo',
          'tipo': 'borrado_logico',
          'insumo_id': insumoId,
          'insumo_nombre': motivo,
          'cantidad': 0,
          'detalle': {'motivo': motivo, 'activo': false},
          'sincronizado': false,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        return false;
      }

      await _client!
          .from('insumos_materias_primas')
          .update({'activo': false, 'motivo_baja': motivo})
          .eq('id', insumoId);

      await guardarBitacoraInventario(
        usuarioId: usuarioId,
        evento: 'Borrado lógico de insumo',
        tipo: 'borrado_logico',
        insumoId: insumoId,
        insumoNombre: motivo,
        cantidad: 0,
        detalle: {'motivo': motivo, 'activo': false},
      );
      return true;
    } catch (e) {
      await HiveService.saveOfflineBitacora({
        'usuario_id': usuarioId,
        'evento': 'Borrado lógico de insumo',
        'tipo': 'borrado_logico',
        'insumo_id': insumoId,
        'insumo_nombre': motivo,
        'cantidad': 0,
        'detalle': {'motivo': motivo, 'activo': false, 'error': e.toString()},
        'sincronizado': false,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      return false;
    }
  }

  static Future<Map<String, dynamic>> registrarProveedor({
    required String nombreEmpresa,
    required String ruc,
    required String contacto,
    required String telefono,
    required String correo,
    required String catalogo,
    required String usuarioId,
  }) async {
    final nombre = nombreEmpresa.trim();
    final rucNormalized = ruc.trim();
    final correoNormalized = correo.trim();

    if (nombre.isEmpty || rucNormalized.isEmpty || contacto.isEmpty) {
      throw StateError('Complete nombre, RUC y contacto del proveedor.');
    }

    try {
      if (!isInitialized) {
        throw StateError('Supabase no está inicializado.');
      }

      final proveedores =
          await _client!.from('proveedores').select('*') as List<dynamic>;
      final existeDuplicado = proveedores.any((item) {
        final itemRuc = (item['ruc'] ?? '').toString().trim();
        final itemNombre = (item['nombre_empresa'] ?? '').toString().trim();
        return itemRuc == rucNormalized ||
            itemNombre.toLowerCase() == nombre.toLowerCase();
      });

      if (existeDuplicado) {
        throw StateError('Ya existe un proveedor con el mismo nombre o RUC.');
      }

      final payload = {
        'nombre_empresa': nombre,
        'ruc': rucNormalized,
        'persona_contacto': contacto,
        'telefono': telefono,
        'correo': correoNormalized,
        'catalogo_insumos': catalogo,
        'activo': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _client!.from('proveedores').insert(payload);

      await guardarBitacoraInventario(
        usuarioId: usuarioId,
        evento: 'Registro de proveedor',
        tipo: 'proveedor',
        insumoId: 'proveedor-$rucNormalized',
        insumoNombre: nombre,
        cantidad: 0,
        detalle: {
          'nombre_empresa': nombre,
          'ruc': rucNormalized,
          'persona_contacto': contacto,
          'telefono': telefono,
          'correo': correoNormalized,
          'catalogo_insumos': catalogo,
        },
      );

      return {'ok': true, 'mensaje': 'Proveedor registrado correctamente.'};
    } catch (e) {
      await HiveService.saveOfflineBitacora({
        'usuario_id': usuarioId,
        'evento': 'Registro de proveedor fallido',
        'tipo': 'proveedor',
        'insumo_id': 'proveedor-$rucNormalized',
        'insumo_nombre': nombre,
        'cantidad': 0,
        'detalle': {
          'nombre_empresa': nombre,
          'ruc': rucNormalized,
          'persona_contacto': contacto,
          'telefono': telefono,
          'correo': correoNormalized,
          'catalogo_insumos': catalogo,
          'error': e.toString(),
        },
        'sincronizado': false,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      throw StateError(e.toString());
    }
  }

  static Future<bool> registrarConsumoPlanta({
    required String ordenProduccion,
    required String insumoId,
    required String insumoNombre,
    required double cantidadConsumida,
    required String operario,
    required String usuarioId,
  }) async {
    final validacion = await validarStockParaSalida(
      insumoId: insumoId,
      cantidadSolicitada: cantidadConsumida,
    );

    if ((validacion['permitido'] as bool? ?? false) == false) {
      throw StateError(
        validacion['mensaje']?.toString() ?? 'Stock insuficiente.',
      );
    }

    final payload = {
      'orden_produccion': ordenProduccion,
      'insumo_id': insumoId,
      'insumo_nombre': insumoNombre,
      'cantidad_consumida': cantidadConsumida,
      'operario': operario,
      'usuario_id': usuarioId,
      'tipo_movimiento': 'consumo_planta',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'activo': true,
    };

    try {
      await _client!.from('movimientos_inventario').insert(payload);
      await guardarBitacoraInventario(
        usuarioId: usuarioId,
        evento: 'Consumo en planta',
        tipo: 'consumo',
        insumoId: insumoId,
        insumoNombre: insumoNombre,
        cantidad: cantidadConsumida,
        detalle: {
          'orden_produccion': ordenProduccion,
          'operario': operario,
          'insumo_nombre': insumoNombre,
        },
      );
      return true;
    } catch (e) {
      await HiveService.saveOfflineMovimiento({
        ...payload,
        'sincronizado': false,
        'error': e.toString(),
      });
      return false;
    }
  }

  static Future<void> sincronizarPendientes() async {
    if (!isInitialized) {
      return;
    }

    final pendientes = await HiveService.getPendingMovimientos();
    for (final item in pendientes) {
      try {
        final payload = item['payload'] as Map<String, dynamic>;
        await _client!.from('movimientos_inventario').insert(payload);
        await HiveService.marcarMovimientoSincronizado(item['id']);
      } catch (_) {
        break;
      }
    }

    final bitacorasPendientes = await HiveService.getPendingBitacoras();
    for (final item in bitacorasPendientes) {
      try {
        await _client!.from('bitacora_inventario').insert({
          'usuario_id': item['usuario_id'],
          'evento': item['evento'],
          'tipo': item['tipo'],
          'insumo_id': item['insumo_id'],
          'insumo_nombre': item['insumo_nombre'],
          'cantidad': item['cantidad'],
          'detalle': item['detalle'],
          'timestamp': item['timestamp'],
          'sincronizado': true,
          'activo': true,
        });
        await HiveService.marcarBitacoraSincronizada(item['id']);
      } catch (_) {
        break;
      }
    }
  }

  static Future<List<double>> fetchConsumoSemanal() async {
    if (!isInitialized) {
      return [3.0, 5.2, 4.5, 6.0, 4.8, 5.0, 3.3];
    }

    try {
      final data =
          await _client!
                  .from('consumo_semanal')
                  .select('*')
                  .limit(7)
                  .order('dia', ascending: true)
              as List<dynamic>;

      return data
          .map<double>((item) => ((item['valor'] ?? 0) as num).toDouble())
          .toList();
    } catch (_) {
      return [3.0, 5.2, 4.5, 6.0, 4.8, 5.0, 3.3];
    }
  }
}
