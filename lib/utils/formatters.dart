import 'package:intl/intl.dart';

final _fechaFmt = DateFormat('dd/MM/yyyy', 'es_BO');
final _fechaHoraFmt = DateFormat('dd/MM/yyyy HH:mm', 'es_BO');

String fmtNum(num? n, {int decimales = 2}) {
  if (n == null) return '-';
  return n.toStringAsFixed(decimales).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.'); // separador simple es-BO
}

String fmtFecha(DateTime? d) => d == null ? '-' : _fechaFmt.format(d);
String fmtFechaHora(DateTime? d) => d == null ? '-' : _fechaHoraFmt.format(d);
