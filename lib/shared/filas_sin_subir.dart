import '../services/cliente_offline.dart';
import '../services/cola_offline.dart';
import '../services/supabase_service.dart';

/// Lo que esta persona INICIÓ sin internet (una corrida, un preparado) y
/// todavía está en la cola, armado como una fila "en curso" con las mismas
/// columnas que devolvería el servidor — así el repositorio lo pasa por el
/// mismo `fromMap` y lo suma a la lista. Sin esto, lo iniciado sin internet no
/// aparecía hasta subirse, y no se podía finalizar (ni se veía que ya estaba,
/// lo que invitaba a iniciarlo de nuevo). Tiene id provisorio (negativo):
/// finalizarlo o anularlo también va a la cola, y al subir se usa el id real.
///
/// Cada `p_xxx` que se mandó queda como columna `xxx` ([renombrar] cambia las
/// que se llaman distinto en la tabla). Desaparece sola de la lista cuando se
/// sube, o cuando ya hay en la cola una de [cierran] (finalizar/anular) para
/// ese id. Solo para usar desde un repositorio.
List<Map<String, dynamic>> filasSinSubir(
  String funcion, {
  List<String> cierran = const [],
  Map<String, String> renombrar = const {},
}) {
  final usuario = SupabaseService.client.auth.currentUser?.id ?? ClienteOffline.usuarioSinConexion;
  final registros = ColaOffline.rpcSinSubir(funcion, usuario: usuario, cierran: cierran);
  String dia(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return [
    // Lo más nuevo primero, como la lista del servidor.
    for (final r in registros.reversed)
      {
        for (final e in r.datos.entries)
          (renombrar[e.key] ?? e.key.replaceFirst(RegExp('^p_'), '')): e.value,
        'id': r.id,
        'fecha': dia(r.creadoEn),
        'estado': 'en_curso',
        'hora_inicio': r.creadoEn.toUtc().toIso8601String(),
      },
  ];
}
