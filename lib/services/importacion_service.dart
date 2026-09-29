import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import '../core/constants.dart';
import '../models/insumo.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../models/movimiento.dart';
import 'bitacora_service.dart';
import 'inventario_service.dart';
import 'supabase_service.dart';

/// Una fila del Excel ya interpretada: o es un ítem válido para crear, o
/// trae el motivo por el que no se importa.
class FilaImportada {
  final int fila; // número de fila tal como se ve en Excel
  final String detalle;
  final Insumo? insumo;
  final String? error; // dato inválido
  final String? repetido; // ya existe / está repetido en el archivo
  const FilaImportada(this.fila, this.detalle,
      {this.insumo, this.error, this.repetido});

  bool get esNueva => insumo != null;
}

class ResultadoLectura {
  final List<FilaImportada> filas;
  final List<String> columnasReconocidas;
  final String? errorGeneral;
  const ResultadoLectura(
      {this.filas = const [],
      this.columnasReconocidas = const [],
      this.errorGeneral});

  List<FilaImportada> get nuevas => filas.where((f) => f.esNueva).toList();
  List<FilaImportada> get repetidas =>
      filas.where((f) => f.repetido != null).toList();
  List<FilaImportada> get conError =>
      filas.where((f) => f.error != null).toList();
}

class ResultadoImportacion {
  final int creados;
  final int fallidos;
  final String? primerError;
  const ResultadoImportacion(this.creados, this.fallidos, this.primerError);
}

/// Importa inventario desde un Excel (.xlsx): reconoce las columnas por su
/// nombre (sin importar tildes, mayúsculas ni orden), valida cada fila,
/// omite los ítems que ya existen y crea los nuevos en el área elegida. El
/// código de cada ítem lo genera el servidor, igual que en "Nuevo ítem".
class ImportacionService {
  static const _hojaDatos = 'Inventario';

  static String _norm(String t) => t
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ü', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  // Campo → nombres de columna aceptados (ya normalizados).
  static const _alias = <String, List<String>>{
    'detalle': ['detalle', 'descripcion', 'nombre', 'insumo', 'producto', 'item', 'articulo'],
    'formato': ['formato'],
    'color': ['color'],
    'tamano': ['tamano', 'medida'],
    'unidad': ['unidad', 'unidadmedida', 'unidaddemedida', 'um'],
    'cantidad': ['cantidad', 'cantidadreal', 'stock', 'stockreal', 'existencia', 'existencias', 'saldo'],
    'minimo': ['stockminimo', 'minimo', 'stockmin', 'alerta'],
    'proveedor': ['proveedor', 'proveedorhabitual'],
    'codigo': ['codigo', 'cod'],
  };

  static const _etiquetaCampo = {
    'detalle': 'Detalle',
    'formato': 'Formato',
    'color': 'Color',
    'tamano': 'Tamaño',
    'unidad': 'Unidad',
    'cantidad': 'Cantidad',
    'minimo': 'Stock mínimo',
    'proveedor': 'Proveedor',
    'codigo': 'Código (se ignora: lo genera el sistema)',
  };

  /// Campos que tienen sentido en cada área (el resto de columnas se ignora).
  static Set<String> _camposDe(AreaInventario area) => switch (area.id) {
        'tapas' => {'detalle', 'formato', 'color', 'unidad', 'cantidad', 'minimo', 'codigo'},
        'preformas' => {'detalle', 'formato', 'tamano', 'unidad', 'cantidad', 'minimo', 'codigo'},
        _ => {'detalle', 'unidad', 'cantidad', 'minimo', 'proveedor', 'codigo'},
      };

  static String _texto(xls.CellValue? v) {
    if (v == null) return '';
    if (v is xls.TextCellValue) return v.value.toString().trim();
    if (v is xls.IntCellValue) return v.value.toString();
    if (v is xls.DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString().trim();
  }

  /// null = vacío; NaN = hay texto pero no es un número.
  static double? _numero(xls.CellValue? v) {
    if (v == null) return null;
    if (v is xls.IntCellValue) return v.value.toDouble();
    if (v is xls.DoubleCellValue) return v.value;
    final t = _texto(v);
    if (t.isEmpty) return null;
    // Acepta "1.250,5" (es-BO) y "1250.5".
    var limpio = t.replaceAll(RegExp(r'\s'), '');
    if (limpio.contains(',')) {
      limpio = limpio.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(limpio) ?? double.nan;
  }

  static String _clave(String detalle, String? extra) =>
      '${_norm(detalle)}|${_norm(extra ?? '')}';

  static ResultadoLectura leer(
      Uint8List bytes, AreaInventario area, List<Insumo> existentes) {
    xls.Excel libro;
    try {
      libro = xls.Excel.decodeBytes(bytes);
    } catch (_) {
      return const ResultadoLectura(
          errorGeneral: 'No se pudo leer el archivo. Tiene que ser un Excel '
              '.xlsx (si es .xls o .csv, guardalo como "Libro de Excel (.xlsx)").');
    }

    // Prefiere la hoja "Inventario" (la de la plantilla); si no, la primera
    // con datos.
    xls.Sheet? hoja = libro.tables[_hojaDatos];
    hoja ??= libro.tables.values.where((s) => s.maxRows > 0).firstOrNull;
    if (hoja == null || hoja.maxRows == 0) {
      return const ResultadoLectura(errorGeneral: 'El Excel está vacío.');
    }
    final filas = hoja.rows;

    // Fila de encabezados: la primera (entre las 15 primeras) que tenga una
    // columna de Detalle.
    final permitidos = _camposDe(area);
    int? filaEncabezado;
    final columnas = <String, int>{}; // campo → índice de columna
    for (var r = 0; r < filas.length && r < 15 && filaEncabezado == null; r++) {
      final candidatas = <String, int>{};
      for (var c = 0; c < filas[r].length; c++) {
        final nombre = _norm(_texto(filas[r][c]?.value));
        if (nombre.isEmpty) continue;
        for (final e in _alias.entries) {
          if (e.value.contains(nombre) && !candidatas.containsKey(e.key)) {
            candidatas[e.key] = c;
          }
        }
      }
      if (candidatas.containsKey('detalle')) {
        filaEncabezado = r;
        columnas.addAll(candidatas);
      }
    }
    if (filaEncabezado == null) {
      return const ResultadoLectura(
          errorGeneral: 'No se encontró la columna "Detalle" (o Descripción / '
              'Nombre). Descargá la plantilla y copiá tus datos ahí.');
    }

    columnas.removeWhere((campo, _) => !permitidos.contains(campo));
    final reconocidas = [for (final k in columnas.keys) _etiquetaCampo[k]!];

    // Claves de lo que ya existe en esta área.
    final existentesClaves = <String>{};
    final existentesCodigos = <String>{};
    for (final i in existentes) {
      existentesClaves.add(_clave(i.detalle, i.color ?? i.tamano ?? i.formato));
      existentesCodigos.add(_norm(i.codigo));
    }
    final vistosEnArchivo = <String>{};

    xls.CellValue? celda(List<xls.Data?> fila, String campo) {
      final c = columnas[campo];
      if (c == null || c >= fila.length) return null;
      return fila[c]?.value;
    }

    final resultado = <FilaImportada>[];
    for (var r = filaEncabezado + 1; r < filas.length; r++) {
      final fila = filas[r];
      if (fila.every((d) => _texto(d?.value).isEmpty)) continue; // fila vacía
      final numeroFila = r + 1;

      final detalle = _texto(celda(fila, 'detalle'));
      if (detalle.isEmpty) {
        resultado.add(FilaImportada(numeroFila, '(sin detalle)',
            error: 'Falta el Detalle.'));
        continue;
      }

      final cantidad = _numero(celda(fila, 'cantidad'));
      final minimo = _numero(celda(fila, 'minimo'));
      if ((cantidad != null && (cantidad.isNaN || cantidad < 0)) ||
          (minimo != null && (minimo.isNaN || minimo < 0))) {
        resultado.add(FilaImportada(numeroFila, detalle,
            error: 'Cantidad o stock mínimo no es un número válido.'));
        continue;
      }

      final formato = _texto(celda(fila, 'formato'));
      final color = _texto(celda(fila, 'color'));
      final tamano = _texto(celda(fila, 'tamano'));
      final unidad = _texto(celda(fila, 'unidad'));
      final proveedor = _texto(celda(fila, 'proveedor'));
      final codigo = _texto(celda(fila, 'codigo'));

      final clave = _clave(detalle, color.isNotEmpty ? color : (tamano.isNotEmpty ? tamano : formato));
      if (codigo.isNotEmpty && existentesCodigos.contains(_norm(codigo))) {
        resultado.add(FilaImportada(numeroFila, detalle,
            repetido: 'Ya existe el código $codigo.'));
        continue;
      }
      if (existentesClaves.contains(clave)) {
        resultado.add(FilaImportada(numeroFila, detalle,
            repetido: 'Ya existe en el inventario.'));
        continue;
      }
      if (!vistosEnArchivo.add(clave)) {
        resultado.add(FilaImportada(numeroFila, detalle,
            repetido: 'Repetido en el archivo.'));
        continue;
      }

      final stock = cantidad ?? 0;
      resultado.add(FilaImportada(
        numeroFila,
        detalle,
        insumo: Insumo(
          id: '',
          tabla: area.tabla,
          codigo: '',
          detalle: detalle,
          formato: area.tabla == 'materia_prima' || formato.isEmpty ? null : formato,
          color: area.id == 'tapas' && color.isNotEmpty ? color : null,
          tamano: area.id == 'preformas' && tamano.isNotEmpty ? tamano : null,
          unidadMedida: unidad.isNotEmpty
              ? unidad
              : (area.tabla == 'materia_prima' ? 'KG' : 'PZA'),
          cantidadSistema: stock,
          cantidadReal: stock,
          stockMinimo: minimo ?? 0,
          proveedorHabitual:
              area.tabla == 'materia_prima' && proveedor.isNotEmpty ? proveedor : null,
          area: area.id == 'jarabes' ? 'jarabes' : null,
        ),
      ));
    }

    if (resultado.isEmpty) {
      return ResultadoLectura(
          columnasReconocidas: reconocidas,
          errorGeneral: 'El Excel tiene los encabezados pero ninguna fila de datos.');
    }
    return ResultadoLectura(filas: resultado, columnasReconocidas: reconocidas);
  }

  /// Excel vacío con los encabezados de esta área (hoja "Inventario") y una
  /// hoja "Instrucciones" con un ejemplo, para que no se importe por error.
  static Uint8List plantilla(AreaInventario area) {
    final encabezados = switch (area.id) {
      'tapas' => ['Detalle', 'Formato', 'Color', 'Unidad', 'Cantidad', 'Stock mínimo'],
      'preformas' => ['Detalle', 'Formato', 'Tamaño', 'Unidad', 'Cantidad', 'Stock mínimo'],
      _ => ['Detalle', 'Unidad', 'Cantidad', 'Stock mínimo', 'Proveedor'],
    };
    final ejemplo = switch (area.id) {
      'tapas' => ['Tapa 28 mm', 'Short Finish', 'Azul', 'PZA', '5000', '1000'],
      'preformas' => ['Preforma PET', 'Long Finish', '2,5 L', 'PZA', '3000', '500'],
      _ => ['Esencia de limón', 'KG', '120', '20', 'Proveedor S.A.'],
    };

    final libro = xls.Excel.createExcel();
    libro.rename('Sheet1', _hojaDatos);
    final hoja = libro[_hojaDatos];
    final estilo = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.fromHexString('#FFFFFFFF'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'),
      horizontalAlign: xls.HorizontalAlign.Center,
    );
    for (var c = 0; c < encabezados.length; c++) {
      hoja.updateCell(
          xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
          xls.TextCellValue(encabezados[c]),
          cellStyle: estilo);
      hoja.setColumnWidth(c, c == 0 ? 34 : 16);
    }

    final ayuda = libro['Instrucciones'];
    ayuda.setColumnWidth(0, 90);
    final lineas = [
      'IMPORTAR INVENTARIO · ${area.etiqueta.toUpperCase()}',
      '',
      '1. Escribí un ítem por fila en la hoja "Inventario", debajo de los encabezados.',
      '2. Solo "Detalle" es obligatorio. Unidad, Cantidad y Stock mínimo son opcionales.',
      '3. El código (IN-xxx / MP-xxx) lo genera el sistema; no lo escribas.',
      '4. Los ítems que ya existen en el inventario se omiten (no se modifican).',
      '5. Guardá el archivo como Excel (.xlsx) y elegilo en "Importar Excel".',
      '',
      'Ejemplo de una fila:',
      encabezados.join('  |  '),
      ejemplo.join('  |  '),
    ];
    for (var i = 0; i < lineas.length; i++) {
      ayuda.updateCell(
          xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
          xls.TextCellValue(lineas[i]),
          cellStyle: i == 0
              ? xls.CellStyle(
                  bold: true,
                  fontSize: 13,
                  fontColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'))
              : null);
    }
    return Uint8List.fromList(libro.save() ?? []);
  }

  /// Crea los ítems uno por uno (el código lo genera el servidor con el
  /// máximo actual, así que no se puede insertar en lote sin riesgo de
  /// códigos repetidos). Si falla varias veces seguidas (ej. sin conexión)
  /// se detiene. Registra UNA sola entrada en la bitácora.
  static Future<ResultadoImportacion> importar(
    List<Insumo> nuevos,
    String usuarioId,
    AreaInventario area, {
    void Function(int hechos, int total)? onProgreso,
  }) async {
    var creados = 0;
    var fallidos = 0;
    var seguidos = 0;
    String? primerError;
    for (final item in nuevos) {
      try {
        await InventarioService.crear(item, usuarioId, registrarBitacora: false);
        creados++;
        seguidos = 0;
      } catch (e) {
        fallidos++;
        seguidos++;
        primerError ??= e.toString();
      }
      onProgreso?.call(creados + fallidos, nuevos.length);
      if (seguidos >= 3) {
        fallidos += nuevos.length - (creados + fallidos);
        break;
      }
    }
    if (creados > 0) {
      try {
        await BitacoraService.registrarAccion(
          usuarioId: usuarioId,
          accion: 'importar_excel',
          tablaAfectada: area.tabla,
          detalle: {'area': area.id, 'creados': creados, 'fallidos': fallidos},
        );
      } catch (_) {}
    }
    return ResultadoImportacion(creados, fallidos, primerError);
  }
}

// ======================================================================
// IMPORTACIÓN DE MOVIMIENTOS (historial / kardex)
// ======================================================================

/// Una fila del Excel de movimientos ya interpretada.
class FilaMovimiento {
  final int fila;
  final String etiquetaItem; // "Detalle (color/tamaño)" para mostrar
  final String claveItem;
  final Insumo? itemExistente;
  final Insumo? itemNuevo; // se crea al importar (uno por ítem, compartido)
  final String tipo; // ingreso | salida | ajuste
  final double cantidad;
  final String? unidad;
  final String? lote;
  final String? proveedor;
  final String? nFactura;
  final String? observacion;
  final DateTime? fecha;
  final DateTime? vencimiento;
  final String claveMov; // identifica la fila para no importarla dos veces
  final String? error;
  bool yaImportado;

  FilaMovimiento({
    required this.fila,
    required this.etiquetaItem,
    this.claveItem = '',
    this.itemExistente,
    this.itemNuevo,
    this.tipo = '',
    this.cantidad = 0,
    this.unidad,
    this.lote,
    this.proveedor,
    this.nFactura,
    this.observacion,
    this.fecha,
    this.vencimiento,
    this.claveMov = '',
    this.error,
    this.yaImportado = false,
  });

  bool get sePuedeImportar => error == null && !yaImportado;
}

class ResultadoLecturaMov {
  final List<FilaMovimiento> filas;
  final List<Insumo> itemsNuevos;
  final List<String> columnasReconocidas;
  final String? errorGeneral;
  const ResultadoLecturaMov({
    this.filas = const [],
    this.itemsNuevos = const [],
    this.columnasReconocidas = const [],
    this.errorGeneral,
  });

  List<FilaMovimiento> get importables =>
      filas.where((f) => f.sePuedeImportar).toList();
  List<FilaMovimiento> get yaImportadas =>
      filas.where((f) => f.yaImportado).toList();
  List<FilaMovimiento> get conError =>
      filas.where((f) => f.error != null).toList();

  /// Ítems nuevos que realmente se van a crear (los que tienen al menos una
  /// fila importable).
  List<Insumo> get itemsPorCrear {
    final usados = importables.map((f) => f.itemNuevo).whereType<Insumo>().toSet();
    return itemsNuevos.where(usados.contains).toList();
  }
}

class ResultadoImportacionMov {
  final int itemsCreados;
  final int movimientos;
  final int repetidos;
  final int fallidos;
  final String? primerError;
  const ResultadoImportacionMov(this.itemsCreados, this.movimientos,
      this.repetidos, this.fallidos, this.primerError);
}

class ImportacionMovService {
  static const hojaMovimientos = 'Movimientos';

  static const _alias = <String, List<String>>{
    'codigo': ['codigo', 'cod'],
    'detalle': ['detalle', 'descripcion', 'nombre', 'insumo', 'producto', 'item', 'articulo'],
    'formato': ['formato'],
    'color': ['color'],
    'tamano': ['tamano', 'medida'],
    'unidad': ['unidad', 'unidadmedida', 'unidaddemedida', 'um'],
    'cantidad': ['cantidad', 'cant'],
    'entrada': ['entrada', 'entradas', 'ingreso', 'ingresos'],
    'salida': ['salida', 'salidas', 'egreso', 'egresos'],
    'tipo': ['tipo', 'tipomovimiento', 'tipodemovimiento', 'movimiento', 'operacion'],
    'fecha': ['fecha', 'fechamovimiento', 'fechadelmovimiento', 'fecharegistro'],
    'lote': ['lote', 'nlote'],
    'proveedor': ['proveedor'],
    'factura': ['factura', 'nfactura', 'nrofactura', 'nrodefactura', 'remision', 'nfacturaremision'],
    'observacion': ['observacion', 'observaciones', 'obs', 'comentario', 'comentarios'],
    'vencimiento': ['vencimiento', 'fechavencimiento', 'fechadevencimiento', 'vence'],
  };

  static const _etiquetaCampo = {
    'codigo': 'Código',
    'detalle': 'Detalle',
    'formato': 'Formato',
    'color': 'Color',
    'tamano': 'Tamaño',
    'unidad': 'Unidad',
    'cantidad': 'Cantidad',
    'entrada': 'Entrada',
    'salida': 'Salida',
    'tipo': 'Tipo',
    'fecha': 'Fecha',
    'lote': 'Lote',
    'proveedor': 'Proveedor',
    'factura': 'N° factura',
    'observacion': 'Observación',
    'vencimiento': 'Vencimiento',
  };

  /// Hash estable (FNV-1a de 64 bits) para armar la clave de cada fila sin
  /// caracteres raros ni longitudes enormes. BigInt para que dé lo mismo en
  /// escritorio, celular y web.
  static String _hash(String s) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final primo = BigInt.parse('100000001b3', radix: 16);
    final mascara = (BigInt.one << 64) - BigInt.one;
    for (final u in s.codeUnits) {
      h = ((h ^ BigInt.from(u)) * primo) & mascara;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  /// ingreso | salida | ajuste, o null si no se reconoce.
  static String? _tipoDe(String bruto) {
    final t = bruto.trim();
    if (t == '+') return 'ingreso';
    if (t == '-') return 'salida';
    final n = ImportacionService._norm(t);
    if (n.isEmpty) return null;
    if (n.startsWith('entr') || n.startsWith('ingr') || n.startsWith('compr') || n == 'e') {
      return 'ingreso';
    }
    if (n.startsWith('sal') || n.startsWith('egr') || n.startsWith('consum') || n == 's') {
      return 'salida';
    }
    if (n.startsWith('ajust')) return 'ajuste';
    return null;
  }

  /// (fecha, inválida). Acepta celdas de fecha de Excel, números de serie y
  /// texto dd/mm/aaaa, dd-mm-aaaa o aaaa-mm-dd (con hora opcional).
  static (DateTime?, bool) _leerFecha(xls.CellValue? v) {
    if (v == null) return (null, false);
    if (v is xls.DateCellValue) return (v.asDateTimeLocal(), false);
    if (v is xls.DateTimeCellValue) return (v.asDateTimeLocal(), false);
    if (v is xls.IntCellValue || v is xls.DoubleCellValue) {
      final n = v is xls.IntCellValue ? v.value.toDouble() : (v as xls.DoubleCellValue).value;
      if (n >= 20000 && n <= 80000) {
        final dias = n.floor();
        final seg = ((n - dias) * 86400).round();
        return (DateTime(1899, 12, 30).add(Duration(days: dias, seconds: seg)), false);
      }
      return (null, true);
    }
    final t = ImportacionService._texto(v);
    if (t.isEmpty) return (null, false);
    int hora = 0, minuto = 0;
    final h = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (h != null) {
      hora = int.parse(h.group(1)!);
      minuto = int.parse(h.group(2)!);
    }
    var a = 0, m = 0, d = 0;
    var ok = false;
    final iso = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(t);
    final lat = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})').firstMatch(t);
    if (iso != null) {
      a = int.parse(iso.group(1)!);
      m = int.parse(iso.group(2)!);
      d = int.parse(iso.group(3)!);
      ok = true;
    } else if (lat != null) {
      d = int.parse(lat.group(1)!);
      m = int.parse(lat.group(2)!);
      a = int.parse(lat.group(3)!);
      if (a < 100) a += 2000;
      ok = true;
    }
    if (!ok || m < 1 || m > 12 || d < 1 || d > 31 || hora > 23 || minuto > 59) {
      return (null, true);
    }
    return (DateTime(a, m, d, hora, minuto), false);
  }

  static ResultadoLecturaMov leer(
    Uint8List bytes,
    AreaInventario area,
    List<Insumo> existentes, {
    required bool crearItems,
  }) {
    xls.Excel libro;
    try {
      libro = xls.Excel.decodeBytes(bytes);
    } catch (_) {
      return const ResultadoLecturaMov(
          errorGeneral: 'No se pudo leer el archivo. Tiene que ser un Excel '
              '.xlsx (si es .xls o .csv, guardalo como "Libro de Excel (.xlsx)").');
    }
    xls.Sheet? hoja = libro.tables[hojaMovimientos];
    hoja ??= libro.tables.values.where((s) => s.maxRows > 0).firstOrNull;
    if (hoja == null || hoja.maxRows == 0) {
      return const ResultadoLecturaMov(errorGeneral: 'El Excel está vacío.');
    }
    final filas = hoja.rows;

    // Encabezados: primera fila (de las 15 primeras) con un ítem (Código o
    // Detalle) y una cantidad (Cantidad, o Entrada/Salida).
    int? filaEncabezado;
    final columnas = <String, int>{};
    for (var r = 0; r < filas.length && r < 15 && filaEncabezado == null; r++) {
      final cand = <String, int>{};
      for (var c = 0; c < filas[r].length; c++) {
        final nombre = ImportacionService._norm(ImportacionService._texto(filas[r][c]?.value));
        if (nombre.isEmpty) continue;
        for (final e in _alias.entries) {
          if (e.value.contains(nombre) && !cand.containsKey(e.key)) cand[e.key] = c;
        }
      }
      final tieneItem = cand.containsKey('detalle') || cand.containsKey('codigo');
      final tieneCantidad = cand.containsKey('cantidad') ||
          cand.containsKey('entrada') ||
          cand.containsKey('salida');
      if (tieneItem && tieneCantidad) {
        filaEncabezado = r;
        columnas.addAll(cand);
      }
    }
    if (filaEncabezado == null) {
      return const ResultadoLecturaMov(
          errorGeneral: 'No se encontraron las columnas necesarias: un ítem '
              '(Código o Detalle) y la Cantidad (o Entrada/Salida). Descargá la '
              'plantilla de movimientos y copiá tus datos ahí.');
    }
    final reconocidas = [for (final k in columnas.keys) _etiquetaCampo[k]!];
    final usaEntradaSalida = columnas.containsKey('entrada') || columnas.containsKey('salida');

    final porCodigo = {for (final i in existentes) ImportacionService._norm(i.codigo): i};
    final porClave = {
      for (final i in existentes)
        ImportacionService._clave(i.detalle, i.color ?? i.tamano ?? i.formato): i
    };
    final nuevosPorClave = <String, Insumo>{};
    final ocurrencias = <String, int>{};

    xls.CellValue? celda(List<xls.Data?> fila, String campo) {
      final c = columnas[campo];
      if (c == null || c >= fila.length) return null;
      return fila[c]?.value;
    }

    String t(List<xls.Data?> fila, String campo) =>
        ImportacionService._texto(celda(fila, campo));

    final resultado = <FilaMovimiento>[];
    for (var r = filaEncabezado + 1; r < filas.length; r++) {
      final fila = filas[r];
      if (fila.every((d) => ImportacionService._texto(d?.value).isEmpty)) continue;
      final n = r + 1;

      // --- Ítem ---
      final codigo = t(fila, 'codigo');
      final detalle = t(fila, 'detalle');
      final formato = t(fila, 'formato');
      final color = t(fila, 'color');
      final tamano = t(fila, 'tamano');
      final extra = color.isNotEmpty ? color : (tamano.isNotEmpty ? tamano : formato);

      Insumo? existente;
      if (codigo.isNotEmpty) existente = porCodigo[ImportacionService._norm(codigo)];
      if (existente == null && detalle.isNotEmpty) {
        existente = porClave[ImportacionService._clave(detalle, extra)];
      }
      final etiqueta = detalle.isNotEmpty
          ? (extra.isNotEmpty ? '$detalle ($extra)' : detalle)
          : (codigo.isNotEmpty ? codigo : '(sin ítem)');

      FilaMovimiento fallo(String motivo) =>
          FilaMovimiento(fila: n, etiquetaItem: etiqueta, error: motivo);

      if (existente == null && detalle.isEmpty) {
        resultado.add(fallo(codigo.isEmpty
            ? 'Falta el ítem (Código o Detalle).'
            : 'El código $codigo no existe en esta área (y no hay Detalle para crearlo).'));
        continue;
      }
      final claveItem = existente != null
          ? ImportacionService._clave(
              existente.detalle, existente.color ?? existente.tamano ?? existente.formato)
          : ImportacionService._clave(detalle, extra);

      Insumo? nuevo;
      if (existente == null) {
        if (!crearItems) {
          resultado.add(fallo('El ítem no existe en el inventario.'));
          continue;
        }
        final unidadFila = t(fila, 'unidad');
        final proveedorFila = t(fila, 'proveedor');
        nuevo = nuevosPorClave.putIfAbsent(
          claveItem,
          () => Insumo(
            id: '',
            tabla: area.tabla,
            codigo: '',
            detalle: detalle,
            formato: area.tabla == 'materia_prima' || formato.isEmpty ? null : formato,
            color: area.id == 'tapas' && color.isNotEmpty ? color : null,
            tamano: area.id == 'preformas' && tamano.isNotEmpty ? tamano : null,
            unidadMedida: unidadFila.isNotEmpty
                ? unidadFila
                : (area.tabla == 'materia_prima' ? 'KG' : 'PZA'),
            cantidadSistema: 0,
            cantidadReal: 0,
            proveedorHabitual:
                area.tabla == 'materia_prima' && proveedorFila.isNotEmpty ? proveedorFila : null,
            area: area.id == 'jarabes' ? 'jarabes' : null,
          ),
        );
      }

      // --- Tipo y cantidad ---
      String? tipo;
      double cantidad;
      if (usaEntradaSalida) {
        final e = ImportacionService._numero(celda(fila, 'entrada'));
        final s = ImportacionService._numero(celda(fila, 'salida'));
        if ((e != null && e.isNaN) || (s != null && s.isNaN)) {
          resultado.add(fallo('Entrada o Salida no es un número válido.'));
          continue;
        }
        final hayE = e != null && e != 0;
        final hayS = s != null && s != 0;
        if (hayE && hayS) {
          resultado.add(fallo('La fila tiene Entrada y Salida a la vez.'));
          continue;
        }
        if (!hayE && !hayS) {
          resultado.add(fallo('Sin cantidad de entrada ni de salida.'));
          continue;
        }
        tipo = hayE ? 'ingreso' : 'salida';
        cantidad = (hayE ? e : s)!.abs();
      } else {
        final c = ImportacionService._numero(celda(fila, 'cantidad'));
        if (c == null || c.isNaN || c == 0) {
          resultado.add(fallo('La cantidad falta, es 0 o no es un número.'));
          continue;
        }
        final tipoTexto = t(fila, 'tipo');
        if (tipoTexto.isNotEmpty) {
          tipo = _tipoDe(tipoTexto);
          if (tipo == null) {
            resultado.add(fallo('Tipo "$tipoTexto" no reconocido (usá Entrada, Salida o Ajuste).'));
            continue;
          }
          cantidad = tipo == 'ajuste' ? c : c.abs();
          if (tipo != 'ajuste' && c < 0) {
            resultado.add(fallo('Cantidad negativa: usá Tipo "Ajuste" para corregir en negativo.'));
            continue;
          }
        } else {
          // Sin columna/valor de Tipo: positivo = entrada, negativo = salida.
          tipo = c > 0 ? 'ingreso' : 'salida';
          cantidad = c.abs();
        }
      }

      // --- Fecha y vencimiento ---
      final (fecha, fechaMala) = _leerFecha(celda(fila, 'fecha'));
      if (fechaMala) {
        resultado.add(fallo('La fecha no es válida (usá dd/mm/aaaa).'));
        continue;
      }
      final (venc, vencMala) = _leerFecha(celda(fila, 'vencimiento'));
      if (vencMala) {
        resultado.add(fallo('La fecha de vencimiento no es válida.'));
        continue;
      }

      final unidad = t(fila, 'unidad');
      final lote = t(fila, 'lote');
      final proveedor = t(fila, 'proveedor');
      final factura = t(fila, 'factura');
      final obs = t(fila, 'observacion');

      // Clave única de la fila: mismo ítem + fecha + tipo + cantidad + datos.
      // Si el archivo trae dos filas idénticas (dos compras iguales el mismo
      // día) se numeran para que ambas cuenten; pero volver a importar el
      // mismo archivo (o uno que se superpone) da las mismas claves y se omite.
      final base = '${area.tabla}|$claveItem|${fecha?.toIso8601String() ?? 'sin-fecha'}|'
          '$tipo|$cantidad|$lote|$factura|$proveedor|$obs';
      final veces = (ocurrencias[base] ?? 0) + 1;
      ocurrencias[base] = veces;

      resultado.add(FilaMovimiento(
        fila: n,
        etiquetaItem: etiqueta,
        claveItem: claveItem,
        itemExistente: existente,
        itemNuevo: nuevo,
        tipo: tipo,
        cantidad: cantidad,
        unidad: unidad.isEmpty ? null : unidad,
        lote: lote.isEmpty ? null : lote,
        proveedor: proveedor.isEmpty ? null : proveedor,
        nFactura: factura.isEmpty ? null : factura,
        observacion: obs.isEmpty ? null : obs,
        fecha: fecha,
        vencimiento: venc,
        claveMov: 'imp:${area.tabla}:${_hash('$base|$veces')}',
      ));
    }

    if (resultado.isEmpty) {
      return ResultadoLecturaMov(
          columnasReconocidas: reconocidas,
          errorGeneral: 'El Excel tiene los encabezados pero ninguna fila de datos.');
    }
    return ResultadoLecturaMov(
      filas: resultado,
      itemsNuevos: nuevosPorClave.values.toList(),
      columnasReconocidas: reconocidas,
    );
  }

  /// Marca las filas que YA se importaron antes (misma clave en la base), para
  /// no duplicarlas. Requiere conexión.
  static Future<void> marcarYaImportados(List<FilaMovimiento> filas) async {
    final pendientes = filas.where((f) => f.error == null).toList();
    final porClave = <String, List<FilaMovimiento>>{};
    for (final f in pendientes) {
      porClave.putIfAbsent(f.claveMov, () => []).add(f);
    }
    final claves = porClave.keys.toList();
    for (var i = 0; i < claves.length; i += 100) {
      final lote = claves.sublist(i, i + 100 > claves.length ? claves.length : i + 100);
      final data = await SupabaseService.client
          .from('movimientos')
          .select('origen_offline_uuid')
          .inFilter('origen_offline_uuid', lote)
          .timeout(SupabaseService.timeoutRed);
      for (final fila in List<Map<String, dynamic>>.from(data)) {
        for (final f in porClave[fila['origen_offline_uuid']] ?? const <FilaMovimiento>[]) {
          f.yaImportado = true;
        }
      }
    }
  }

  static String _mensajeError(Object e) {
    final t = e.toString();
    if (t.contains('solo_historial') || t.contains('importacion_id') || t.contains("'origen'")) {
      return 'Falta ejecutar schema_v13_importacion_movimientos.sql en Supabase.';
    }
    if (t.toLowerCase().contains('row-level security')) {
      return 'No tenés permiso para registrar movimientos en esta área.';
    }
    return t;
  }

  static Future<ResultadoImportacionMov> importar(
    ResultadoLecturaMov lectura,
    String usuarioId,
    AreaInventario area, {
    required bool soloHistorial,
    void Function(int hechos, int total)? onProgreso,
  }) async {
    final importables = lectura.importables;
    final porCrear = lectura.itemsPorCrear;
    final total = porCrear.length + importables.length;
    var hechos = 0;
    var itemsCreados = 0;
    var movimientos = 0;
    var repetidos = 0;
    var fallidos = 0;
    String? primerError;
    final idImportacion = 'imp-${DateTime.now().millisecondsSinceEpoch}';

    // 1) Ítems que faltan (uno por ítem, aunque tenga muchas filas).
    final idNuevo = <Insumo, String>{};
    for (final item in porCrear) {
      try {
        idNuevo[item] =
            await InventarioService.crear(item, usuarioId, registrarBitacora: false);
        itemsCreados++;
      } catch (e) {
        primerError ??= _mensajeError(e);
      }
      onProgreso?.call(++hechos, total);
    }

    // 2) Movimientos, del más viejo al más nuevo, en lotes.
    final movs = <Movimiento>[];
    for (final f in importables) {
      final String? itemId = f.itemExistente?.id ?? idNuevo[f.itemNuevo];
      if (itemId == null) {
        fallidos++; // su ítem no se pudo crear
        onProgreso?.call(++hechos, total);
        continue;
      }
      movs.add(Movimiento(
        offlineUuid: f.claveMov,
        tablaOrigen: area.tabla,
        itemId: itemId,
        tipo: f.tipo,
        cantidad: f.cantidad,
        unidadMedida: f.unidad ?? f.itemExistente?.unidadMedida ?? f.itemNuevo?.unidadMedida,
        lote: f.lote,
        fechaVencimiento: f.vencimiento,
        proveedor: f.proveedor,
        nFactura: f.nFactura,
        observacion: f.observacion,
        usuarioId: usuarioId,
        creadoEn: f.fecha ?? DateTime.now(),
        origen: 'importacion_excel',
        soloHistorial: soloHistorial,
        importacionId: idImportacion,
      ));
    }
    movs.sort((a, b) => a.creadoEn.compareTo(b.creadoEn));

    for (var i = 0; i < movs.length; i += 100) {
      final lote = movs.sublist(i, i + 100 > movs.length ? movs.length : i + 100);
      try {
        await SupabaseService.client
            .from('movimientos')
            .insert([for (final m in lote) m.toSupabaseMap()])
            .timeout(SupabaseService.timeoutRed);
        movimientos += lote.length;
        hechos += lote.length;
      } catch (_) {
        // Un lote falló: se reintenta fila por fila para aislar la mala.
        for (final m in lote) {
          try {
            await SupabaseService.client
                .from('movimientos')
                .insert(m.toSupabaseMap())
                .timeout(SupabaseService.timeoutRed);
            movimientos++;
          } on PostgrestException catch (e) {
            if (e.code == '23505') {
              repetidos++; // ya estaba importada
            } else {
              fallidos++;
              primerError ??= _mensajeError(e);
            }
          } catch (e) {
            fallidos++;
            primerError ??= _mensajeError(e);
          }
          hechos++;
        }
      }
      onProgreso?.call(hechos, total);
    }

    if (itemsCreados > 0 || movimientos > 0) {
      try {
        await BitacoraService.registrarAccion(
          usuarioId: usuarioId,
          accion: 'importar_movimientos_excel',
          tablaAfectada: area.tabla,
          detalle: {
            'area': area.id,
            'importacion_id': idImportacion,
            'movimientos': movimientos,
            'items_nuevos': itemsCreados,
            'solo_historial': soloHistorial,
            'omitidos_por_repetidos': repetidos + lectura.yaImportadas.length,
          },
        );
      } catch (_) {}
    }
    return ResultadoImportacionMov(
        itemsCreados, movimientos, repetidos + lectura.yaImportadas.length, fallidos, primerError);
  }

  /// Excel vacío con los encabezados de movimientos de esta área y una hoja
  /// "Instrucciones".
  static Uint8List plantilla(AreaInventario area) {
    final extra = switch (area.id) {
      'tapas' => ['Color'],
      'preformas' => ['Tamaño'],
      _ => <String>[],
    };
    final encabezados = [
      'Fecha',
      'Código',
      'Detalle',
      ...extra,
      'Tipo',
      'Cantidad',
      'Unidad',
      'Lote',
      'Proveedor',
      'N° Factura',
      'Vencimiento',
      'Observación',
    ];
    final libro = xls.Excel.createExcel();
    libro.rename('Sheet1', hojaMovimientos);
    final hoja = libro[hojaMovimientos];
    final estilo = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.fromHexString('#FFFFFFFF'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'),
      horizontalAlign: xls.HorizontalAlign.Center,
    );
    for (var c = 0; c < encabezados.length; c++) {
      hoja.updateCell(
          xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
          xls.TextCellValue(encabezados[c]),
          cellStyle: estilo);
      hoja.setColumnWidth(c, encabezados[c] == 'Detalle' ? 32 : 15);
    }
    final ayuda = libro['Instrucciones'];
    ayuda.setColumnWidth(0, 100);
    final lineas = [
      'IMPORTAR MOVIMIENTOS · ${area.etiqueta.toUpperCase()}',
      '',
      '1. Una fila por movimiento, en la hoja "Movimientos", debajo de los encabezados.',
      '2. Identificá el ítem por Código (ej. MP-001) o por Detalle${extra.isEmpty ? '' : ' (+ ${extra.first} si hay varios iguales)'}.',
      '3. Tipo: Entrada, Salida o Ajuste. Si dejás el Tipo vacío: cantidad positiva = Entrada, negativa = Salida.',
      '4. También podés usar dos columnas "Entrada" y "Salida" en vez de Tipo + Cantidad.',
      '5. Fecha como dd/mm/aaaa (con hora opcional). Sin fecha se usa el momento de la importación.',
      '6. Los ítems que no existan se crean automáticamente (una sola vez, aunque tengan muchas filas).',
      '7. Volver a importar el mismo archivo (o uno que repita filas) NO duplica: lo ya importado se omite.',
      '8. "Solo historial" guarda los movimientos sin cambiar el stock; "Aplicar al stock" además lo suma/resta.',
      '',
      'Ejemplo de dos filas:',
      encabezados.join('  |  '),
      ['15/08/2026', 'MP-001', 'Esencia de limón', ...extra.map((_) => ''), 'Entrada', '50', 'KG', 'L-23', 'Proveedor S.A.', 'F-1001', '', 'Compra'].join('  |  '),
      ['16/08/2026', 'MP-001', 'Esencia de limón', ...extra.map((_) => ''), 'Salida', '12', 'KG', '', '', '', '', 'Producción'].join('  |  '),
    ];
    for (var i = 0; i < lineas.length; i++) {
      ayuda.updateCell(
          xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
          xls.TextCellValue(lineas[i]),
          cellStyle: i == 0
              ? xls.CellStyle(
                  bold: true,
                  fontSize: 13,
                  fontColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'))
              : null);
    }
    return Uint8List.fromList(libro.save() ?? []);
  }
}
