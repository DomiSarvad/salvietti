import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import '../../../utils/texto.dart';
import '../models/item_inventario.dart';
import '../models/unidad_medida.dart';

/// Una fila del Excel ya interpretada: un ítem nuevo, uno que ya existe (solo
/// se le puede cargar el stock), o un error con su motivo.
class FilaExcel {
  final int fila; // número de fila en el Excel (como lo ve la persona)
  final ItemInventario? nuevo;
  final int? existenteId; // ya está en el almacén (por código o detalle)
  final String detalle;
  final double? stock;
  final String? error;
  const FilaExcel({
    required this.fila,
    required this.detalle,
    this.nuevo,
    this.existenteId,
    this.stock,
    this.error,
  });
}

class LecturaExcel {
  final List<FilaExcel> filas;
  final String? errorGeneral;

  /// Columnas que el sistema no tiene (Proveedor, Precio…): se guardan en la
  /// ficha de cada ítem NUEVO como "otros datos", con su nombre tal cual.
  final List<String> columnasExtra;
  const LecturaExcel({this.filas = const [], this.errorGeneral, this.columnasExtra = const []});

  List<FilaExcel> get nuevos => [for (final f in filas) if (f.nuevo != null) f];
  List<FilaExcel> get existentes => [for (final f in filas) if (f.existenteId != null) f];
  List<FilaExcel> get conError => [for (final f in filas) if (f.error != null) f];
  int get conStock => filas.where((f) => f.error == null && f.stock != null).length;
}

/// Lo que hace falta del almacén para leer el Excel.
class ContextoExcel {
  /// id de categoría → su ruta ("Tapas › Negro"). Solo las del almacén.
  final Map<int, String> rutas;

  /// Ítems que ya están: código y detalle → id.
  final Map<String, int> porCodigo;
  final Map<String, int> porDetalle;
  const ContextoExcel({required this.rutas, required this.porCodigo, required this.porDetalle});
}

// Columnas aceptadas (nombre normalizado → campo). Se aceptan sinónimos.
const _alias = <String, List<String>>{
  'codigo': ['codigo', 'cod'],
  'detalle': ['detalle', 'descripcion', 'nombre', 'item', 'producto', 'insumo', 'articulo'],
  'categoria': ['categoria', 'tipo', 'ubicacion', 'rubro'],
  'unidad': ['unidad', 'um', 'unidaddemedida', 'medida'],
  'stock': ['stock', 'cantidad', 'existencia', 'stockactual', 'saldo'],
  'minimo': ['stockminimo', 'minimo', 'min'],
  'consumo': ['consumodiario', 'consumo'],
  'unidadCompra': ['unidaddecompra', 'envase', 'presentacion'],
  'factor': ['factor', 'contenidoporenvase', 'cuantotrae', 'factordecompra'],
  'porCaja': ['unidadesporcaja', 'porcaja'],
  'color': ['color'],
  'formato': ['formato'],
  'peso': ['pesog', 'peso'],
  'ancho': ['anchomm', 'ancho'],
  'micronaje': ['micronaje'],
};

const _encabezados = [
  'Código', 'Detalle', 'Categoría', 'Unidad', 'Stock', 'Stock mínimo', 'Consumo diario',
  'Unidad de compra', 'Factor', 'Unidades por caja', 'Color', 'Formato', 'Peso (g)',
  'Ancho (mm)', 'Micronaje',
];

// Una columna "peso_g" o "micronaje" no es "otro dato": ya tiene campo.
final _atributosConocidos = {for (final a in ItemInventario.atributosConocidos) _norm(a)};

String _norm(String t) => sinTildes(t).replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Ruta comparable: sin tildes, sin mayúsculas, con cualquier separador
/// ("Tapas > Negro", "Tapas/Negro", "Tapas › Negro" dan lo mismo).
String _normRuta(String t) =>
    t.split(RegExp(r'[›>/\\|]')).map((p) => _norm(p)).where((p) => p.isNotEmpty).join('>');

String _texto(xls.CellValue? v) {
  if (v == null) return '';
  if (v is xls.TextCellValue) return v.value.toString().trim();
  if (v is xls.IntCellValue) return v.value.toString();
  if (v is xls.DoubleCellValue) {
    final d = v.value;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }
  return v.toString().trim();
}

/// null = vacío; NaN = hay texto que no es un número. Acepta "1.250,5" y "1250.5".
double? _numero(xls.CellValue? v) {
  if (v == null) return null;
  if (v is xls.IntCellValue) return v.value.toDouble();
  if (v is xls.DoubleCellValue) return v.value;
  var t = _texto(v).replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t) ?? double.nan;
}

const maxFilasExcel = 2000;

/// Lee el Excel. Una fila con error no frena a las demás: se lista con su
/// motivo y se importa el resto.
LecturaExcel leerExcelInventario(Uint8List bytes, ContextoExcel ctx) {
  xls.Excel libro;
  try {
    libro = xls.Excel.decodeBytes(bytes);
  } catch (_) {
    return const LecturaExcel(
        errorGeneral: 'No se pudo leer el archivo. Tiene que ser un Excel .xlsx '
            '(si es .xls o .csv, guardalo como "Libro de Excel (.xlsx)").');
  }
  final hoja = libro.tables['Inventario'] ??
      libro.tables.values.where((s) => s.maxRows > 0).firstOrNull;
  if (hoja == null || hoja.maxRows == 0) return const LecturaExcel(errorGeneral: 'El Excel está vacío.');
  final filas = hoja.rows;

  // Encabezados: la primera fila (de las 15 primeras) que tenga "Detalle".
  int? filaEnc;
  final col = <String, int>{};
  final extra = <String, int>{}; // nombre como está escrito → columna
  for (var r = 0; r < filas.length && r < 15 && filaEnc == null; r++) {
    final cand = <String, int>{};
    final sinAlias = <String, int>{};
    for (var c = 0; c < filas[r].length; c++) {
      final nombre = _texto(filas[r][c]?.value);
      final n = _norm(nombre);
      if (n.isEmpty) continue;
      var conocida = false;
      for (final e in _alias.entries) {
        if (e.value.contains(n)) {
          conocida = true;
          if (!cand.containsKey(e.key)) cand[e.key] = c;
        }
      }
      if (!conocida && !_atributosConocidos.contains(n)) {
        final clave = nombre.length > 40 ? nombre.substring(0, 40) : nombre;
        sinAlias.putIfAbsent(clave, () => c);
      }
    }
    if (cand.containsKey('detalle')) {
      filaEnc = r;
      col.addAll(cand);
      extra.addAll(sinAlias);
    }
  }
  if (filaEnc == null) {
    return const LecturaExcel(
        errorGeneral: 'No se encontró la columna "Detalle". Descargá la plantilla y copiá tus datos ahí.');
  }
  if (!col.containsKey('categoria')) {
    return const LecturaExcel(
        errorGeneral: 'Falta la columna "Categoría" (dónde va cada ítem en el almacén).');
  }

  // Categoría por ruta completa y por nombre de la última parte (si no se repite).
  final porRuta = {for (final e in ctx.rutas.entries) _normRuta(e.value): e.key};
  final porHoja = <String, int?>{};
  for (final e in ctx.rutas.entries) {
    final hojaNombre = _normRuta(e.value).split('>').last;
    porHoja[hojaNombre] = porHoja.containsKey(hojaNombre) ? null : e.key; // null = ambigua
  }

  final resultado = <FilaExcel>[];
  final vistos = <String>{}; // detalles repetidos dentro del mismo Excel
  for (var r = filaEnc + 1; r < filas.length; r++) {
    if (resultado.length >= maxFilasExcel) break;
    final fila = filas[r];
    xls.CellValue? celda(String campo) {
      final c = col[campo];
      return (c == null || c >= fila.length) ? null : fila[c]?.value;
    }

    final detalle = _texto(celda('detalle'));
    final codigo = _texto(celda('codigo'));
    if (detalle.isEmpty && codigo.isEmpty) continue; // fila vacía
    final n = r + 1;
    FilaExcel err(String m) => FilaExcel(fila: n, detalle: detalle.isEmpty ? codigo : detalle, error: m);

    final stock = _numero(celda('stock'));
    if (stock != null && (stock.isNaN || stock < 0)) {
      resultado.add(err('El stock tiene que ser un número de 0 para arriba.'));
      continue;
    }

    // ¿Ya existe? Por código, o por detalle (sin tildes ni mayúsculas).
    final existente = (codigo.isNotEmpty ? ctx.porCodigo[codigo.toUpperCase()] : null) ??
        ctx.porDetalle[_norm(detalle)];
    if (existente != null) {
      resultado.add(FilaExcel(fila: n, detalle: detalle.isEmpty ? codigo : detalle, existenteId: existente, stock: stock));
      continue;
    }
    if (detalle.isEmpty) {
      resultado.add(err('El código no existe en este almacén y falta el detalle para crearlo.'));
      continue;
    }
    if (detalle.length > 120) {
      resultado.add(err('El detalle es demasiado largo (máx. 120).'));
      continue;
    }
    if (!vistos.add(_norm(detalle))) {
      resultado.add(err('Está repetido en el Excel.'));
      continue;
    }

    final catTexto = _texto(celda('categoria'));
    if (catTexto.isEmpty) {
      resultado.add(err('Falta la categoría.'));
      continue;
    }
    final ruta = _normRuta(catTexto);
    final categoriaId = porRuta[ruta] ?? (ruta.contains('>') ? null : porHoja[ruta]);
    if (categoriaId == null) {
      resultado.add(err(porHoja.containsKey(ruta) && porHoja[ruta] == null
          ? 'Hay varias categorías "$catTexto": escribí la ruta completa (ej. Tapas › $catTexto).'
          : 'La categoría "$catTexto" no existe en este almacén (ver la hoja "Categorías" de la plantilla).'));
      continue;
    }

    final unidadTexto = _texto(celda('unidad')).toUpperCase().replaceAll('.', '');
    final unidad = unidadTexto.isEmpty
        ? 'UNI'
        : const {'KILO': 'KG', 'KILOS': 'KG', 'LITRO': 'L', 'LITROS': 'L', 'LT': 'L', 'UND': 'UNI', 'UNIDAD': 'UNI', 'PIEZA': 'PZA', 'PZ': 'PZA', 'CAJA': 'CJA', 'G': 'GR'}[unidadTexto] ??
            unidadTexto;
    if (!UnidadMedida.todas.contains(unidad)) {
      resultado.add(err('Unidad "$unidadTexto" no válida (${UnidadMedida.todas.join(', ')}).'));
      continue;
    }

    double? num(String campo, String nombre, List<String> errores) {
      final v = _numero(celda(campo));
      if (v != null && (v.isNaN || v < 0)) errores.add('"$nombre" no es un número válido.');
      return (v == null || v.isNaN) ? null : v;
    }

    final errores = <String>[];
    final minimo = num('minimo', 'Stock mínimo', errores);
    final consumo = num('consumo', 'Consumo diario', errores);
    final factor = num('factor', 'Factor', errores);
    final porCaja = num('porCaja', 'Unidades por caja', errores);
    final peso = num('peso', 'Peso', errores);
    final ancho = num('ancho', 'Ancho', errores);
    final micronaje = num('micronaje', 'Micronaje', errores);
    final unidadCompra = _texto(celda('unidadCompra'));
    if (unidadCompra.isNotEmpty && (factor == null || factor <= 0)) {
      errores.add('Con unidad de compra, poné cuántas $unidad trae cada $unidadCompra (Factor).');
    }
    if (errores.isNotEmpty) {
      resultado.add(err(errores.first));
      continue;
    }

    final color = _texto(celda('color'));
    final formato = _texto(celda('formato'));
    resultado.add(FilaExcel(
      fila: n,
      detalle: detalle,
      stock: stock,
      nuevo: ItemInventario(
        categoriaId: categoriaId,
        detalle: detalle,
        unidad: unidad,
        unidadCompra: unidadCompra.isEmpty ? null : unidadCompra,
        factorCompra: unidadCompra.isEmpty ? null : factor,
        unidadesPorCaja: porCaja?.round(),
        stockMinimo: minimo,
        consumoDiarioManual: consumo,
        atributos: {
          if (color.isNotEmpty) 'color': color,
          if (formato.isNotEmpty) 'formato': formato,
          if (peso != null) 'peso_g': peso,
          if (ancho != null) 'ancho_mm': ancho,
          if (micronaje != null) 'micronaje': micronaje,
          for (final e in extra.entries)
            if (e.value < fila.length && _texto(fila[e.value]?.value).isNotEmpty)
              e.key: _texto(fila[e.value]?.value),
        },
      ),
    ));
  }
  if (resultado.isEmpty) return const LecturaExcel(errorGeneral: 'No hay filas con datos debajo de los encabezados.');
  return LecturaExcel(filas: resultado, columnasExtra: extra.keys.toList());
}

/// Columnas que no todos los ítems usan: la plantilla de una categoría trae
/// solo las que usan sus ítems (Termocontraíbles: ancho, micronaje, peso…).
const columnasOpcionales = [
  'unidadCompra', 'factor', 'porCaja', 'color', 'formato', 'peso', 'ancho', 'micronaje',
];

/// Columnas opcionales que tienen dato en al menos uno de [items].
Set<String> columnasUsadas(Iterable<ItemInventario> items) => {
      for (final i in items) ...[
        if (i.unidadCompra != null) ...['unidadCompra', 'factor'],
        if (i.unidadesPorCaja != null) 'porCaja',
        for (final e in const {
          'color': 'color',
          'formato': 'formato',
          'peso_g': 'peso',
          'ancho_mm': 'ancho',
          'micronaje': 'micronaje'
        }.entries)
          if ((i.atributos[e.key]?.toString() ?? '').isNotEmpty) e.value,
      ],
    };

const _campos = [
  'codigo', 'detalle', 'categoria', 'unidad', 'stock', 'minimo', 'consumo', ...columnasOpcionales,
];

/// Valor de cada columna para la fila de ejemplo (sin stock: si se deja la
/// fila, el ítem ya existe y no se crea ni se le cambia el stock).
Map<String, Object?> _filaEjemplo(ItemInventario i, String ruta) => {
      'codigo': i.codigo,
      'detalle': i.detalle,
      'categoria': ruta,
      'unidad': i.unidad,
      'minimo': i.stockMinimo,
      'consumo': i.consumoDiarioManual,
      'unidadCompra': i.unidadCompra,
      'factor': i.factorCompra,
      'porCaja': i.unidadesPorCaja,
      'color': i.atributos['color'],
      'formato': i.atributos['formato'],
      'peso': i.atributos['peso_g'],
      'ancho': i.atributos['ancho_mm'],
      'micronaje': i.atributos['micronaje'],
    };

/// Plantilla: hoja "Inventario" con los encabezados y un ejemplo, hoja
/// "Categorías" con las rutas válidas, y las instrucciones. Con [columnas]
/// (las opcionales a incluir) es la de una categoría; sin, la general con
/// todas. [ejemplo] es el primer ítem de la lista, con su ruta.
Uint8List plantillaExcelInventario(
  String almacen,
  List<String> rutasCategorias, {
  Set<String>? columnas,
  (ItemInventario, String)? ejemplo,
  String? categoria,
  List<String> extras = const [],
}) {
  final libro = xls.Excel.createExcel();
  libro.rename('Sheet1', 'Inventario');
  final hoja = libro['Inventario'];
  final estilo = xls.CellStyle(
    bold: true,
    fontColorHex: xls.ExcelColor.fromHexString('#FFFFFFFF'),
    backgroundColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'),
  );
  final campos = [
    for (final c in _campos)
      if (columnas == null || !columnasOpcionales.contains(c) || columnas.contains(c)) c
  ];
  for (var c = 0; c < campos.length; c++) {
    hoja.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        xls.TextCellValue(_encabezados[_campos.indexOf(campos[c])]), cellStyle: estilo);
    hoja.setColumnWidth(c, c == 1 ? 34 : (c == 2 ? 28 : 14));
  }
  // Otros datos que ya usan los ítems (columnas que vinieron de otro Excel).
  for (var i = 0; i < extras.length; i++) {
    final c = campos.length + i;
    hoja.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        xls.TextCellValue(extras[i]), cellStyle: estilo);
    hoja.setColumnWidth(c, 16);
  }
  if (ejemplo != null) {
    final valores = {
      ..._filaEjemplo(ejemplo.$1, ejemplo.$2),
      for (final x in extras) 'extra:$x': ejemplo.$1.atributos[x],
    };
    final claves = [...campos, for (final x in extras) 'extra:$x'];
    for (var c = 0; c < claves.length; c++) {
      final v = valores[claves[c]];
      if (v == null || v.toString().isEmpty) continue;
      hoja.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1),
          v is num ? xls.DoubleCellValue(v.toDouble()) : xls.TextCellValue(v.toString()));
    }
  }

  final cats = libro['Categorías'];
  cats.setColumnWidth(0, 50);
  cats.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      xls.TextCellValue('Categorías de ${categoria ?? almacen} (copiá una en la columna "Categoría")'),
      cellStyle: estilo);
  for (var i = 0; i < rutasCategorias.length; i++) {
    cats.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1),
        xls.TextCellValue(rutasCategorias[i]));
  }

  final ayuda = libro['Instrucciones'];
  ayuda.setColumnWidth(0, 100);
  final lineas = [
    'IMPORTAR ÍTEMS · ${almacen.toUpperCase()}${categoria == null ? '' : ' › ${categoria.toUpperCase()}'}',
    '',
    if (ejemplo != null) ...[
      'La fila 2 es de ejemplo: "${ejemplo.$1.detalle}", que ya existe. Si se deja, no se crea',
      'ni se le cambia nada. Escribí los tuyos debajo (o encima de esa fila).',
      '',
    ],
    '1. Un ítem por fila en la hoja "Inventario". Obligatorios: Detalle y Categoría.',
    '2. Categoría: copiala de la hoja "Categorías" (o solo el último nombre, si no se repite).',
    '3. Unidad: ${UnidadMedida.todas.join(', ')}. Si se deja vacía, va UNI.',
    '4. Código: dejalo vacío para ítems nuevos (lo pone el sistema).',
    '5. Si el ítem ya existe (mismo código o mismo detalle) no se modifica.',
    '6. Stock: opcional. Si se elige "Cargar el stock", queda como conteo físico (el',
    '   sistema registra la diferencia con lo que tenía), también para los que ya existen.',
    '7. Guardá como Excel (.xlsx) y elegilo en Almacenes → Importar Excel.',
    '8. Podés agregar columnas propias (Proveedor, Precio…): se guardan en la ficha de cada',
    '   ítem nuevo como "Otros datos".',
  ];
  for (var i = 0; i < lineas.length; i++) {
    ayuda.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i), xls.TextCellValue(lineas[i]));
  }
  return Uint8List.fromList(libro.encode()!);
}
