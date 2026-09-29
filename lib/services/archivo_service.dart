import 'dart:io';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

/// Guarda archivos generados (PDF, Excel) sin sobrescribir nada: si ya existe
/// uno con el mismo nombre se guarda como "nombre (1).ext", "nombre (2).ext",
/// etc., igual que un navegador. En escritorio queda en la carpeta Descargas
/// y se abre solo; en el celular se abre el panel de compartir; en la web lo
/// descarga el navegador (que ya numera los duplicados).
class ArchivoService {
  /// Quita caracteres que Windows/macOS no admiten en nombres de archivo.
  static String nombreSeguro(String nombre) {
    var n = nombre
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (n.length > 120) n = n.substring(0, 120).trim();
    return n.isEmpty ? 'reporte' : n;
  }

  static String _carpetaDescargas() {
    final env = Platform.environment;
    final base = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
    if (base == null || base.isEmpty) {
      throw Exception('No se pudo ubicar la carpeta de Descargas.');
    }
    return '$base${Platform.pathSeparator}Downloads';
  }

  static String _rutaLibre(String carpeta, String nombre, String ext) {
    final sep = Platform.pathSeparator;
    var ruta = '$carpeta$sep$nombre.$ext';
    var n = 1;
    while (File(ruta).existsSync()) {
      ruta = '$carpeta$sep$nombre ($n).$ext';
      n++;
    }
    return ruta;
  }

  static Future<void> _abrir(String ruta) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [ruta]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [ruta]);
      } else {
        await Process.run('xdg-open', [ruta]);
      }
    } catch (_) {
      // Si no se puede abrir solo, el archivo igual quedó guardado.
    }
  }

  /// Devuelve un texto listo para mostrar al usuario (dónde quedó el archivo).
  static Future<String> guardar(
    Uint8List bytes, {
    required String nombre,
    required String ext,
    required String mimeType,
  }) async {
    final base = nombreSeguro(nombre);

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: base,
        bytes: bytes,
        ext: ext,
        mimeType: ext == 'pdf' ? MimeType.pdf : MimeType.microsoftExcel,
      );
      return 'Descargado: $base.$ext';
    }

    if (Platform.isAndroid || Platform.isIOS) {
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: mimeType, name: '$base.$ext')],
        fileNameOverrides: ['$base.$ext'],
      );
      return 'Listo para guardar o compartir: $base.$ext';
    }

    final carpeta = _carpetaDescargas();
    await Directory(carpeta).create(recursive: true);
    final ruta = _rutaLibre(carpeta, base, ext);
    await File(ruta).writeAsBytes(bytes, flush: true);
    await _abrir(ruta);
    final nombreFinal = ruta.split(Platform.pathSeparator).last;
    return 'Guardado en Descargas: $nombreFinal';
  }
}
