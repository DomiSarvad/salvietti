import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/recepciones/models/recepciones_modelos.dart';
import 'package:salvietti_control/features/recepciones/repositories/recepciones_repository.dart';
import 'package:salvietti_control/features/recepciones/services/recepciones_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements RecepcionesRepository {
  final guardadas = <RecepcionNueva>[];
  final fotos = <String>[];
  final proveedoresCreados = <String>[];
  String? senasac;
  bool fallar = false;

  @override
  Future<List<AlmacenRec>> almacenes() async => const [
        AlmacenRec(id: 'general', nombre: 'Almacén General'),
        AlmacenRec(id: 'jarabes', nombre: 'Almacén de Jarabes'),
      ];

  @override
  Future<List<RecepcionDetalle>> recepciones(String almacenId, {int limite = 200}) async => [
        RecepcionDetalle(
            id: 1, fecha: DateTime(2026, 9, 1), almacenId: almacenId, itemId: 1,
            codigo: 'MP-0001', detalle: 'Azúcar', unidad: 'KG', proveedor: 'San Aurelio',
            nFactura: 'F-10', cantidadFactura: 1000, cantidadReal: 999.5, diferencia: -0.5),
        RecepcionDetalle(
            id: 2, fecha: DateTime(2026, 9, 2), almacenId: almacenId, itemId: 2,
            codigo: 'MP-0002', detalle: 'Concentrado Papaya', unidad: 'KG', proveedor: 'Sapore',
            cantidadFactura: 20, cantidadReal: 20, diferencia: 0),
      ];

  @override
  Future<List<ItemRecepcion>> itemsDelAlmacen(String almacenId) async => [
        ItemRecepcion(id: 1, codigo: 'MP-0001', detalle: 'Azúcar', unidad: 'KG', almacenId: almacenId),
      ];

  @override
  Future<List<Proveedor>> proveedores() async => const [Proveedor(id: 5, nombre: 'San Aurelio')];

  @override
  Future<Proveedor> crearProveedor(String nombre) async {
    proveedoresCreados.add(nombre);
    return Proveedor(id: 9, nombre: nombre);
  }

  @override
  Future<String?> senasacDe(int itemId, int proveedorId) async => senasac;

  @override
  Future<void> crearRecepcion(RecepcionNueva r) async {
    if (fallar) throw Exception('sin conexión');
    guardadas.add(r);
  }

  @override
  Future<String> subirFoto(Uint8List bytes,
      {required String ruta, required String contentType}) async {
    fotos.add(ruta);
    return ruta;
  }

  @override
  Future<String> urlFoto(String ruta) async => 'https://x/$ruta';

  @override
  Future<List<DiferenciaMes>> diferenciasDelMes(String almacenId, DateTime mes) async => [
        DiferenciaMes(
            mes: mes, detalle: 'Azúcar', unidad: 'KG', proveedor: 'San Aurelio',
            recepciones: 3, cantidadFactura: 3000, diferencia: -1.5, porcentaje: -0.05),
        DiferenciaMes(
            mes: mes, detalle: 'Cítrico', unidad: 'KG', proveedor: 'X',
            recepciones: 1, cantidadFactura: 25, diferencia: 0.2, porcentaje: 0.8),
      ];
}

Usuario _usuario(Set<String>? permisos) =>
    Usuario(id: 'u', nombreCompleto: 'P', rol: 'almacen', permisos: permisos);

const _almacenGeneral = {
  'recepciones:ver',
  'recepciones:crear',
  'inventario_general:ver',
  'inventario_general:editar',
  'inventario_jarabes:ver',
};

final _hoy = DateTime(2026, 9, 21);

Future<RecepcionesService> _svc(Set<String>? permisos, [_Repo? repo]) async {
  final s = RecepcionesService(repo ?? _Repo(), _usuario(permisos), ahora: () => _hoy);
  await s.iniciar();
  return s;
}

const _azucar = ItemRecepcion(
    id: 1, codigo: 'MP-0001', detalle: 'Azúcar', unidad: 'KG', almacenId: 'general');

BorradorRecepcion _borrador({
  ItemRecepcion? item = _azucar,
  double? factura = 100,
  double? real = 99.5,
  String unidad = 'KG',
  DateTime? fecha,
  DateTime? fab,
  DateTime? ven,
  String senasac = '',
  FotoAdjunta? foto,
  double? precio,
}) =>
    BorradorRecepcion(
      almacenId: 'general',
      item: item,
      fecha: fecha ?? _hoy,
      unidadEntrada: unidad,
      cantidadFactura: factura,
      cantidadReal: real,
      fechaFabricacion: fab,
      fechaVencimiento: ven,
      senasac: senasac,
      foto: foto,
      precioTransporte: precio,
    );

void main() {
  group('permisos', () {
    test('sin permisos cargados no ve ni recibe nada (denegar por defecto)', () async {
      final s = await _svc(null);
      expect(s.almacenes, isEmpty);
      expect(s.puedeRecibirEn('general'), isFalse);
    });

    test('ve los almacenes que puede ver y recibe solo donde opera', () async {
      final s = await _svc(_almacenGeneral);
      expect(s.almacenes.map((a) => a.id), ['general', 'jarabes']);
      expect(s.puedeRecibirEn('general'), isTrue);
      expect(s.puedeRecibirEn('jarabes'), isFalse); // solo lo ve
    });

    test('sin permiso de recepciones no carga nada', () async {
      final s = await _svc({'inventario_general:ver'});
      expect(s.almacenes, isEmpty);
    });

    test('quien solo ve no puede guardar', () async {
      final repo = _Repo();
      final s = await _svc({'recepciones:ver', 'inventario_general:ver'}, repo);
      expect(await s.guardar(_borrador()), contains('permiso'));
      expect(repo.guardadas, isEmpty);
    });
  });

  group('lista y filtros', () {
    test('filtra por texto y por diferencia', () async {
      final s = await _svc(_almacenGeneral);
      expect(s.visibles, hasLength(2));
      s.buscar('SAPORE');
      expect(s.visibles.map((r) => r.id), [2]);
      s.buscar('');
      s.alternarSoloConDiferencia();
      expect(s.visibles.map((r) => r.id), [1]);
    });

    test('los reclamos muestran solo lo que faltó', () async {
      final s = await _svc(_almacenGeneral);
      await s.cambiarVista(VistaRecepciones.reclamos);
      expect(s.reclamosConFaltante.map((d) => d.detalle), ['Azúcar']);
    });
  });

  group('validación', () {
    Future<String?> guardar(BorradorRecepcion b, [_Repo? repo]) async =>
        (await _svc(_almacenGeneral, repo)).guardar(b);

    test('exige ítem y cantidades mayores a cero', () async {
      expect(await guardar(_borrador(item: null)), contains('ítem'));
      expect(await guardar(_borrador(factura: null)), contains('factura'));
      expect(await guardar(_borrador(real: 0)), contains('real'));
      expect(await guardar(_borrador(real: -1)), contains('real'));
    });

    test('rechaza fechas incoherentes', () async {
      expect(await guardar(_borrador(fecha: DateTime(2026, 9, 25))), contains('futura'));
      expect(
          await guardar(_borrador(fab: DateTime(2026, 5, 1), ven: DateTime(2026, 4, 1))),
          contains('posterior'));
      expect(await guardar(_borrador(ven: DateTime(2026, 9, 1))), contains('vencido'));
    });

    test('valida SENASAG, precio y foto', () async {
      expect(await guardar(_borrador(senasac: 'ab<>cd')), contains('SENASAG'));
      expect(await guardar(_borrador(precio: -5)), contains('negativo'));
      expect(
          await guardar(_borrador(
              foto: FotoAdjunta(bytes: Uint8List(10), nombre: 'factura.pdf'))),
          contains('JPG'));
      expect(
          await guardar(_borrador(
              foto: FotoAdjunta(
                  bytes: Uint8List(RecepcionesService.maxFotoBytes + 1), nombre: 'a.jpg'))),
          contains('5 MB'));
    });

    test('no deja elegir una unidad que no corresponde al ítem', () async {
      expect(await guardar(_borrador(unidad: 'L')), contains('Unidad'));
    });
  });

  group('guardado', () {
    test('guarda en la unidad del ítem: gramos se pasan a kilos', () async {
      final repo = _Repo();
      final s = await _svc(_almacenGeneral, repo);
      final error =
          await s.guardar(_borrador(factura: 15000, real: 14900, unidad: 'GR'));
      expect(error, isNull);
      expect(repo.guardadas.single.cantidadFactura, 15);
      expect(repo.guardadas.single.cantidadReal, closeTo(14.9, 1e-9));
    });

    test('calcula la diferencia mientras se escribe', () {
      expect(RecepcionesService.diferenciaDe(_borrador(factura: 16, real: 15.9)),
          closeTo(-0.1, 1e-9));
      expect(RecepcionesService.diferenciaDe(_borrador(real: null)), isNull);
    });

    test('sube la foto y guarda su ruta; los textos vacíos van como null', () async {
      final repo = _Repo();
      final s = await _svc(_almacenGeneral, repo);
      final error = await s.guardar(_borrador(
          foto: FotoAdjunta(bytes: Uint8List(100), nombre: 'Factura.JPG')));
      expect(error, isNull);
      expect(repo.fotos.single, matches(RegExp(r'^general/2026-09/\d+_[0-9a-f]+\.jpg$')));
      final g = repo.guardadas.single;
      expect(g.fotoUrl, repo.fotos.single);
      expect(g.nFactura, isNull);
      expect(g.senasac, isNull);
    });

    test('si falla el guardado avisa y no pierde datos', () async {
      final repo = _Repo()..fallar = true;
      final s = await _svc(_almacenGeneral, repo);
      expect(await s.guardar(_borrador()), contains('No se pudo guardar'));
      expect(repo.guardadas, isEmpty);
    });
  });

  group('proveedores y SENASAG', () {
    test('no duplica un proveedor que ya existe (sin importar tildes ni mayúsculas)', () async {
      final repo = _Repo();
      final s = await _svc(_almacenGeneral, repo);
      final p = await s.crearProveedor('  san   AURELIO ');
      expect(p?.id, 5);
      expect(repo.proveedoresCreados, isEmpty);
    });

    test('crea uno nuevo y valida el largo del nombre', () async {
      final repo = _Repo();
      final s = await _svc(_almacenGeneral, repo);
      expect((await s.crearProveedor('Naturex'))?.nombre, 'Naturex');
      expect(await s.crearProveedor('x'), isNull);
    });

    test('sugiere el SENASAG conocido', () async {
      final repo = _Repo()..senasac = '08-05-03-18-0032';
      final s = await _svc(_almacenGeneral, repo);
      expect(await s.senasacSugerido(1, 5), '08-05-03-18-0032');
    });
  });
}
