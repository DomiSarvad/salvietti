import 'package:intl/intl.dart';

final _fechaFmt = DateFormat('dd/MM/yyyy', 'es_BO');
final _fechaHoraFmt = DateFormat('dd/MM/yyyy HH:mm', 'es_BO');

/// Formato es-BO: punto para los miles y coma para los decimales
/// (1234.5 → "1.234,50"). Antes usaba punto para las dos cosas y "1.234.50"
/// se leía como ciento veintitrés mil.
String fmtNum(num? n, {int decimales = 2}) {
  if (n == null) return '-';
  final s = n.toStringAsFixed(decimales);
  final negativo = s.startsWith('-');
  final partes = (negativo ? s.substring(1) : s).split('.');
  final entero = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '${negativo ? '-' : ''}$entero${partes.length > 1 ? ',${partes[1]}' : ''}';
}

String fmtFecha(DateTime? d) => d == null ? '-' : _fechaFmt.format(d);
String fmtFechaHora(DateTime? d) => d == null ? '-' : _fechaHoraFmt.format(d);
