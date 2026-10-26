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
  Suscripcion escucharCambios(void Function() onCambio) => const SuscripcionNula();

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

    test('el año se parte en meses', () {
      final r = RangoInforme.de(PeriodoInforme.anio, DateTime(2026, 10, 23));
      expect(r.desde, DateTime(2026, 1, 1));
      expect(r.hasta, DateTime(2027, 1, 1));
      expect(r.etiquetas.length, 12);
      expect(r.indiceDe(DateTime(2026, 10, 31)), 9);
      expect(r.anterior().titulo, 'Año 2025');
    });

    test('por fechas: las barras dependen del largo del rango', () {
      final corto = RangoInforme.entre(DateTime(2026, 10, 1), DateTime(2026, 10, 10));
      expect(corto.hasta, DateTime(2026, 10, 11)); // el último día se incluye
      expect(corto.etiquetas.length, 10);
      expect(corto.anterior().desde, DateTime(2026, 9, 21)); // mismo largo, justo antes
      final medio = RangoInforme.entre(DateTime(2026, 8, 1), DateTime(2026, 10, 15));
      expect(medio.unidadBarra, 'Semana desde');
      final largo = RangoInforme.entre(DateTime(2025, 11, 15), DateTime(2026, 10, 23));
      expect(largo.etiquetas.first, 'Nov 25');
      expect(largo.indiceDe(DateTime(2025, 11, 20)), 0);
      expect(largo.indiceDe(DateTime(2025, 12, 1)), 1);
    });
  });

  test('proyección: solo en el período en curso, al ritmo por día', () async {
    final repo = _Repo({
      'jarabes_preparados': [
        {'fecha': '2026-10-01', 'estado': 'finalizada', 'litros': 1000, 'sabores': {'nombre': 'Papaya'}},
        {'fecha': '2026-10-20', 'estado': 'finalizada', 'litros': 1300, 'sabores': {'nombre': 'Papaya'}},
      ],
    });
    // 23 días transcurridos (hoy incluido) con 2300 litros → 100 por día; faltan 8.
    final s = InformesService(repo, _gerente, ahora: () => DateTime(2026, 10, 23, 15));
    final mes = await s.construir(AreaInforme.jarabes, RangoInforme.de(PeriodoInforme.mes, DateTime(2026, 10, 23)));
    expect(mes.series.single.totalProyectado, closeTo(3100, 0.001));
    expect(mes.series.single.proyeccion![0], 0); // semana 1 ya pasó
    expect(mes.series.single.proyeccion![3], closeTo(100 * 5, 0.001)); // Sem 4 = 22 al 28/10: faltan 24…28
    final anterior = await s.construir(AreaInforme.jarabes, RangoInforme.de(PeriodoInforme.mes, DateTime(2026, 9, 1)));
    expect(anterior.tieneProyeccion, isFalse);
  });

  test('la búsqueda deja solo lo que coincide (sin tildes) y va al informe', () async {
    final repo = _Repo({
      'soplado_corridas': [
        {'fecha': '2026-10-20', 'estado': 'finalizada', 'botellas_sopladas': 1000, 'merma_soplado': 10,
         'sabores': {'nombre': 'Papaya'}},
        {'fecha': '2026-10-21', 'estado': 'finalizada', 'botellas_sopladas': 500, 'merma_soplado': 5,
         'sabores': {'nombre': 'Limón'}},
      ],
    });
    final s = InformesService(repo, _gerente, ahora: () => DateTime(2026, 10, 23));
    s.busqueda = 'limon';
    final i = await s.construir(AreaInforme.soplado, RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23)));
    expect(i.kpis[0].valor, '1');
    expect(i.filas.map((f) => f.first), ['Limón']);
    expect(i.busqueda, 'limon');
    // La fecha no cuenta como texto: "20" no trae la corrida del 20/10.
    s.busqueda = '20';
    final porFecha = await s.construir(AreaInforme.soplado, RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23)));
    expect(porFecha.filas, isEmpty);
  });

  test('buscar el nombre de un indicador muestra solo ese, con todos los datos', () async {
    final repo = _Repo({
      'soplado_corridas': [
        {'fecha': '2026-10-20', 'estado': 'finalizada', 'botellas_sopladas': 1000, 'merma_soplado': 10,
         'sabores': {'nombre': 'Papaya'}},
      ],
    });
    final s = InformesService(repo, _gerente, ahora: () => DateTime(2026, 10, 30));
    final r = RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23));
    s.busqueda = 'botellas sopladas';
    final i = await s.construir(AreaInforme.soplado, r);
    expect(i.kpis.map((k) => k.etiqueta), ['Botellas sopladas']);
    expect(i.kpis.single.valor, '1.000'); // no se filtraron los registros
    expect(i.series.map((x) => x.nombre), ['Botellas sopladas']);
    expect(i.filas, isNotEmpty); // la tabla por sabor no lo nombra: queda entera
  });

  test('Desde/Hasta pasan a un rango propio y la x vuelve al período del selector', () {
    final s = InformesService(_Repo({}), _gerente, ahora: () => DateTime(2026, 10, 23));
    s.elegirPeriodo(PeriodoInforme.mes);
    s.elegirDesde(DateTime(2026, 10, 5));
    expect(s.rango.periodo, PeriodoInforme.fechas);
    expect(s.rango.desde, DateTime(2026, 10, 5));
    expect(s.rango.ultimoDia, DateTime(2026, 10, 23)); // el mes llegaba al 31: no pasa de hoy
    s.quitarFechas();
    expect(s.rango.periodo, PeriodoInforme.mes);
  });

  test('Plan de producción: una fila por producto, incluye lo pendiente, y se puede buscar', () async {
    final repo = _Repo({
      'plan_produccion': [
        {
          'fecha': '2026-10-20',
          'plan_produccion_detalle': [
            {'litros_planificados': 7200, 'litros_producidos': 7000, 'merma_litros': 50, 'completado': true,
             'formulas': {'sabor': 'Papaya'},
             'productos_terminados': {'nombre': '2,5 L Papaya - Pett', 'litros_por_botella': 2.5, 'botellas_por_paquete': 6}},
            {'litros_planificados': 2160, 'completado': false,
             'formulas': {'sabor': 'Granadina'},
             'productos_terminados': {'nombre': '300 ml Granadina - Vidrio', 'litros_por_botella': 0.3, 'botellas_por_paquete': 24}},
          ],
        },
      ],
    });
    final s = InformesService(repo, _gerente, ahora: () => DateTime(2026, 10, 30));
    final r = RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23));
    final i = await s.construir(AreaInforme.plan, r);
    expect(i.kpis[0].valor, '2'); // planificados (completado o no)
    expect(i.kpis[1].valor, '1');
    expect(i.filas.first.sublist(1, 4), ['2,5 L Papaya - Pett', '480', '2.880']); // 7200/2,5/6
    expect(i.filas.last.last, 'Pendiente');
    expect(i.series[0].valores[1], 9360); // martes 20/10, planificado

    s.busqueda = 'granadina';
    final g = await s.construir(AreaInforme.plan, r);
    expect(g.filas.single[1], '300 ml Granadina - Vidrio');
  });

  test('el año en curso se dibuja hasta el mes actual (no aparece diciembre)', () async {
    final s = InformesService(_Repo({}), _gerente, ahora: () => DateTime(2026, 10, 25));
    final i = await s.construir(AreaInforme.jarabes, RangoInforme.de(PeriodoInforme.anio, DateTime(2026, 10, 25)));
    expect(i.barrasVisibles, 10); // enero…octubre
    final pasado = await s.construir(AreaInforme.jarabes, RangoInforme.de(PeriodoInforme.anio, DateTime(2025, 5, 1)));
    expect(pasado.barrasVisibles, 12); // un año terminado se ve entero
  });

  test('comparar pone al lado el año anterior, mes a mes', () async {
    final repo = _Repo({
      'jarabes_preparados': [
        {'fecha': '2026-03-10', 'estado': 'finalizada', 'litros': 500, 'sabores': {'nombre': 'Papaya'}},
      ],
    });
    final s = InformesService(repo, _gerente, ahora: () => DateTime(2026, 10, 25));
    s.area = AreaInforme.jarabes;
    s.elegirPeriodo(PeriodoInforme.anio);
    s.alternarComparar();
    await Future<void>.delayed(Duration.zero);
    await s.cargar();
    final i = s.informe!;
    expect(i.tituloAnterior, 'Año 2025');
    expect(i.anteriores!.single.valores.length, 12);
    // El repositorio falso devuelve las mismas filas para cualquier rango: el
    // preparado de marzo de 2026 cae fuera del año 2025, así que allá queda en 0.
    expect(i.series.single.valores[2], 500);
    expect(i.anteriores!.single.valores[2], 0);
  });

  test('por fechas no pasa de hoy', () {
    final s = InformesService(_Repo({}), _gerente, ahora: () => DateTime(2026, 10, 23));
    s.elegirFechas(DateTime(2026, 10, 1), DateTime(2026, 12, 31));
    expect(s.rango.ultimoDia, DateTime(2026, 10, 23));
    expect(s.puedeAvanzar, isFalse);
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
