import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:salvietti_control/features/informes/models/informes_modelos.dart';
import 'package:salvietti_control/features/informes/repositories/informes_repository.dart';
import 'package:salvietti_control/features/informes/services/informes_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements InformesRepository {
  final Map<String, List<Map<String, dynamic>>> tablas;
  _Repo(this.tablas);

  @override
  Future<List<Map<String, dynamic>>> filas({
    required String tabla,
    required String select,
    required String columnaFecha,
    required DateTime desde,
    required DateTime hasta,
    bool fechaEsDia = true,
  }) async =>
      tablas[tabla] ?? const [];
}

final _gerente = Usuario(
    id: 'g', nombreCompleto: 'Gerente', rol: 'gerente', permisos: {'informe_produccion:ver'});

void main() {
  setUpAll(() => initializeDateFormatting('es_BO'));

  group('períodos', () {
    test('la semana va de lunes a domingo, una barra por día', () {
      final r = RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23)); // jueves
      expect(r.desde, DateTime(2026, 10, 19));
      expect(r.hasta, DateTime(2026, 10, 26));
      expect(r.etiquetas.first, 'Lun 19');
      expect(r.indiceDe(DateTime(2026, 10, 25, 23, 59)), 6);
      expect(r.indiceDe(DateTime(2026, 10, 26)), isNull);
    });

    test('el mes se parte en semanas', () {
      final r = RangoInforme.de(PeriodoInforme.mes, DateTime(2026, 10, 23));
      expect(r.desde, DateTime(2026, 10, 1));
      expect(r.hasta, DateTime(2026, 11, 1));
      expect(r.etiquetas, ['Sem 1', 'Sem 2', 'Sem 3', 'Sem 4', 'Sem 5']);
      expect(r.indiceDe(DateTime(2026, 10, 8)), 1);
      expect(r.anterior().desde, DateTime(2026, 9, 1));
    });
  });

  test('Soplado: solo cuenta lo finalizado, calcula % de merma y marca la alerta', () async {
    final repo = _Repo({
      'soplado_corridas': [
        {'fecha': '2026-10-20', 'estado': 'finalizada', 'botellas_sopladas': 1000, 'merma_soplado': 30,
         'merma_preforma': 10, 'merma_etiquetado': 0, 'tiempo_parada_minutos': 15, 'sabores': {'nombre': 'Papaya'}},
        {'fecha': '2026-10-21', 'estado': 'finalizada', 'botellas_sopladas': 1000, 'merma_soplado': 20,
         'merma_preforma': 0, 'merma_etiquetado': 0, 'tiempo_parada_minutos': 0, 'sabores': {'nombre': 'Ross'}},
        {'fecha': '2026-10-21', 'estado': 'en_curso', 'botellas_sopladas': null, 'sabores': {'nombre': 'Ross'}},
        {'fecha': '2026-10-22', 'estado': 'anulada', 'botellas_sopladas': 500, 'merma_soplado': 500,
         'sabores': {'nombre': 'Ross'}},
      ],
    });
    final s = InformesService(repo, _gerente, ahora: () => DateTime(2026, 10, 23));
    final i = await s.construir(AreaInforme.soplado, RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23)));
    expect(i.kpis[0].valor, '2'); // corridas finalizadas
    expect(i.kpis[3].alerta, isFalse); // 60 / 2000 = 3 % (no supera)
    expect(i.series[0].valores[1], 1000); // martes 20/10
    expect(i.series[1].valores[1], 40); // merma del martes 20/10
    expect(i.filas.map((f) => f.first), ['Papaya', 'Ross']);
  });

  test('Calidad: alerta si hubo no conformes', () async {
    final repo = _Repo({
      'calidad_analisis': [
        {'fecha': '2026-10-20T14:00:00Z', 'resultado': 'conforme', 'ph': 3.0},
        {'fecha': '2026-10-21T14:00:00Z', 'resultado': 'no_conforme', 'ph': 4.0, 'aspecto': 'turbio'},
      ],
    });
    final s = InformesService(repo, _gerente);
    final i = await s.construir(AreaInforme.calidad, RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23)));
    expect(i.kpis[2].alerta, isTrue);
    expect(i.filas.single.last, 'turbio');
  });

  test('no deja avanzar más allá del período actual', () {
    final s = InformesService(_Repo({}), _gerente, ahora: () => DateTime(2026, 10, 23));
    expect(s.puedeAvanzar, isFalse);
    s.anterior();
    expect(s.puedeAvanzar, isTrue);
  });

  test('sin permiso no arma nada', () async {
    final s = InformesService(_Repo({}),
        Usuario(id: 'x', nombreCompleto: 'X', rol: 'soplado', permisos: {'soplado:ver'}));
    await s.cargar();
    expect(s.informe, isNull);
    expect(s.puedeVer, isFalse);
  });
}
