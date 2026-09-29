import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/inventario/models/almacen.dart';
import 'package:salvietti_control/features/inventario/models/categoria_inv.dart';
import 'package:salvietti_control/features/inventario/models/conteo_nuevo.dart';
import 'package:salvietti_control/features/inventario/models/existencia_item.dart';
import 'package:salvietti_control/features/inventario/services/balance_service.dart';
import 'package:salvietti_control/features/inventario/models/item_inventario.dart';
import 'package:salvietti_control/features/inventario/models/movimiento_inv.dart';
import 'package:salvietti_control/features/inventario/repositories/inventario_repository.dart';
import 'package:salvietti_control/features/inventario/services/inventario_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _RepoFalso implements InventarioRepository {
  final creados = <ItemInventario>[];
  final conteos = <double>[];

  static const _categoriasFijas = [
    CategoriaInv(id: 1, padreId: null, nombre: 'PET', almacenId: 'general'),
    CategoriaInv(id: 2, padreId: 1, nombre: 'Tapas', almacenId: 'general'),
    CategoriaInv(id: 3, padreId: 2, nombre: 'Negro', almacenId: 'general'),
    CategoriaInv(id: 4, padreId: null, nombre: 'Limpieza', almacenId: 'general'),
    CategoriaInv(id: 5, padreId: null, nombre: 'Soplado', almacenId: 'soplado'),
  ];

  @override
  Future<List<Almacen>> almacenes() async => const [
        Almacen(id: 'general', nombre: 'Almacén General'),
        Almacen(id: 'jarabes', nombre: 'Almacén de Jarabes'),
        Almacen(id: 'soplado', nombre: 'Almacén de Soplado'),
      ];

  @override
  Future<List<CategoriaInv>> categorias(String almacenId) async =>
      _categoriasFijas.where((c) => c.almacenId == almacenId).toList();

  @override
  Future<List<CategoriaInv>> categoriasTodas() async => _categoriasFijas;

  @override
  Future<List<ExistenciaItem>> existencias(String almacenId) async {
    // Soplado recibió cápsulas de Almacén General: mismo ítem, catalogado
    // bajo una categoría que no es suya (PET › Tapas › Negro).
    if (almacenId == 'soplado') {
      return const [
        ExistenciaItem(
            itemId: 20, codigo: 'IN-0010', detalle: 'Cápsula PET negra',
            unidad: 'PZA', categoriaId: 3, almacenId: 'soplado', cantidadSistema: 50),
      ];
    }
    return const [
      ExistenciaItem(
          itemId: 10, codigo: 'IN-0010', detalle: 'Cápsula PET negra',
          unidad: 'PZA', categoriaId: 3, almacenId: 'general',
          cantidadSistema: 100, diasExistencia: 2, stockMinimo: 500),
      ExistenciaItem(
          itemId: 11, codigo: 'IN-0011', detalle: 'Jabón en barra',
          unidad: 'UNI', categoriaId: 4, almacenId: 'general',
          cantidadSistema: 900, diasExistencia: 30),
      ExistenciaItem(
          itemId: 12, codigo: 'IN-0012', detalle: 'Escoba',
          unidad: 'UNI', categoriaId: 4, almacenId: 'general', cantidadSistema: 5),
    ];
  }

  @override
  Future<ItemInventario> item(int id) async =>
      const ItemInventario(id: 10, categoriaId: 3, detalle: 'x', unidad: 'PZA');

  @override
  Future<void> crearItem(ItemInventario item) async => creados.add(item);

  @override
  Future<void> actualizarItem(ItemInventario item) async {}

  @override
  Future<void> desactivarItem(int id) async {}

  @override
  Future<void> registrarConteo({
    required int itemId,
    required String almacenId,
    required double cantidadReal,
    double? cajas,
    int? unidadesPorCaja,
    String? observaciones,
  }) async =>
      conteos.add(cantidadReal);

  final movimientosHechos = <Map<String, Object?>>[];
  final reversiones = <int>[];
  String? rechazarCon; // el "servidor" rechaza con este mensaje

  @override
  Future<List<MovimientoInv>> movimientos(int itemId, String almacenId,
          {int limite = 100}) async =>
      [
        MovimientoInv(
            id: 7, fecha: DateTime(2026, 9, 20), itemId: itemId, almacenId: almacenId,
            tipo: 'entrada', cantidad: 10, referenciaTipo: 'manual'),
      ];

  @override
  Future<void> registrarMovimiento({
    required int itemId,
    required String almacenId,
    required String tipo,
    required double cantidad,
    required String motivo,
  }) async {
    if (rechazarCon != null) throw ErrorNegocioInventario(rechazarCon!);
    movimientosHechos.add({'item': itemId, 'tipo': tipo, 'cantidad': cantidad, 'motivo': motivo});
  }

  @override
  Future<void> revertirMovimiento(int movimientoId, String motivo) async {
    if (rechazarCon != null) throw ErrorNegocioInventario(rechazarCon!);
    reversiones.add(movimientoId);
  }

  final lotes = <ConteoNuevo>[];
  bool fallar = false;

  @override
  Future<void> registrarConteos(List<ConteoNuevo> conteos) async {
    if (fallar) throw Exception('sin conexión');
    lotes.addAll(conteos);
  }

  final salidasDirectas = <Map<String, Object?>>[];

  @override
  Future<void> registrarSalidaDirecta({
    required int itemId,
    required String areaDestino,
    required double pesoReal,
    double? cantidadRollos,
    String? motivo,
    String almacenId = 'general',
  }) async {
    if (rechazarCon != null) throw ErrorNegocioInventario(rechazarCon!);
    salidasDirectas.add({
      'item': itemId, 'area': areaDestino, 'peso': pesoReal,
      'rollos': cantidadRollos, 'motivo': motivo, 'almacen': almacenId,
    });
  }
}

Usuario _usuario(Set<String>? permisos) => Usuario(
    id: 'u1', nombreCompleto: 'Prueba', rol: 'almacen', permisos: permisos);

const _todoGeneral = {
  'inventario_general:ver',
  'inventario_general:crear',
  'inventario_general:editar',
  'inventario_general:eliminar',
};

Future<InventarioService> _servicio(Set<String>? permisos, [_RepoFalso? repo]) async {
  final s = InventarioService(repo ?? _RepoFalso(), _usuario(permisos));
  await s.iniciar();
  return s;
}

void main() {
  balanceTests();
  test('solo muestra los almacenes que el rol puede ver', () async {
    final s = await _servicio({'inventario_general:ver'});
    expect(s.almacenes.map((a) => a.id), ['general']);
  });

  test('sin permisos cargados no muestra ningún almacén (denegar por defecto)', () async {
    final s = await _servicio(null);
    expect(s.almacenes, isEmpty);
    expect(s.puedeEditar, isFalse);
  });

  test('filtrar una categoría incluye sus subcategorías', () async {
    final s = await _servicio(_todoGeneral);
    s.filtrarCategoria(1); // PET
    expect(s.visibles.map((e) => e.itemId), [10]);
    s.filtrarCategoria(4); // Limpieza
    expect(s.visibles.map((e) => e.itemId), [11, 12]);
  });

  test('la búsqueda ignora tildes y mayúsculas', () async {
    final s = await _servicio(_todoGeneral);
    s.buscar('CAPSULA');
    expect(s.visibles.map((e) => e.itemId), [10]);
  });

  test('la búsqueda de varias palabras las exige todas, en cualquier orden', () async {
    final s = await _servicio(_todoGeneral);
    s.buscar('negra capsula');
    expect(s.visibles.map((e) => e.itemId), [10]);
    s.buscar('capsula verde');
    expect(s.visibles, isEmpty);
  });

  test('al buscar dentro de una categoría, busca en todo el almacén (no solo ahí adentro)', () async {
    final s = await _servicio(_todoGeneral);
    s.filtrarCategoria(4); // Limpieza: acá no está la cápsula (categoría 3)
    expect(s.visibles.map((e) => e.itemId), [11, 12]);
    s.buscar('capsula');
    expect(s.buscandoEnTodoElAlmacen, isTrue);
    expect(s.visibles.map((e) => e.itemId), [10]);
    s.buscar('');
    expect(s.buscandoEnTodoElAlmacen, isFalse);
    expect(s.visibles.map((e) => e.itemId), [11, 12]);
  });

  test('marca "Pedido" cuando el stock llega al mínimo', () async {
    final s = await _servicio(_todoGeneral);
    s.alternarSoloPedido();
    expect(s.visibles.map((e) => e.itemId), [10]);
  });

  test('el semáforo sale de los días de existencia', () async {
    final s = await _servicio(_todoGeneral);
    expect(s.situacion(s.existencias[0]), SituacionStock.critico);
    expect(s.situacion(s.existencias[1]), SituacionStock.optimo);
    expect(s.situacion(s.existencias[2]), SituacionStock.sinDatos);
  });

  test('sin permiso de crear no guarda nada', () async {
    final repo = _RepoFalso();
    final s = await _servicio({'inventario_general:ver'}, repo);
    final error = await s.guardarItem(
        const ItemInventario(categoriaId: 3, detalle: 'Nuevo', unidad: 'PZA'));
    expect(error, isNotNull);
    expect(repo.creados, isEmpty);
  });

  test('valida detalle, categoría y factor de compra', () async {
    final repo = _RepoFalso();
    final s = await _servicio(_todoGeneral, repo);
    expect(
        await s.guardarItem(
            const ItemInventario(categoriaId: 3, detalle: '  ', unidad: 'PZA')),
        contains('detalle'));
    expect(
        await s.guardarItem(
            const ItemInventario(categoriaId: 99, detalle: 'A', unidad: 'PZA')),
        contains('categoría'));
    expect(
        await s.guardarItem(const ItemInventario(
            categoriaId: 3, detalle: 'A', unidad: 'KG', unidadCompra: 'quintal')),
        contains('quintal'));
    expect(repo.creados, isEmpty);
  });

  test('guarda un ítem válido y un conteo', () async {
    final repo = _RepoFalso();
    final s = await _servicio(_todoGeneral, repo);
    expect(
        await s.guardarItem(const ItemInventario(
            categoriaId: 3, detalle: 'Azúcar', unidad: 'KG',
            unidadCompra: 'quintal', factorCompra: 46)),
        isNull);
    expect(repo.creados, hasLength(1));

    expect(await s.registrarConteo(s.existencias.first, cantidadReal: -1), isNotNull);
    expect(await s.registrarConteo(s.existencias.first, cantidadReal: 95), isNull);
    expect(repo.conteos, [95]);
  });

  group('stock recibido de otro almacén', () {
    const permisosSoplado = {
      'inventario_general:ver',
      'inventario_soplado:ver',
      'inventario_soplado:crear',
      'inventario_soplado:editar',
    };

    test('el árbol propio se ve siempre, aunque esté vacío', () async {
      final s = InventarioService(_RepoFalso(), Usuario(
          id: 'u', nombreCompleto: 'Soplado', rol: 'soplado', permisos: permisosSoplado));
      await s.iniciar();
      await s.seleccionarAlmacen('soplado');
      expect(s.categoriasPropias.map((c) => c.id), [5]);
      expect(s.hijosDe(null).map((c) => c.id), contains(5));
    });

    test('un ítem recibido de otra área se ve por su ruta real, sin poder crear ahí', () async {
      final s = InventarioService(_RepoFalso(), Usuario(
          id: 'u', nombreCompleto: 'Soplado', rol: 'soplado', permisos: permisosSoplado));
      await s.iniciar();
      await s.seleccionarAlmacen('soplado');

      // La cápsula recibida aparece en el listado del almacén de Soplado...
      expect(s.visibles.map((e) => e.itemId), [20]);
      // ...con su ruta real de Almacén General, navegable desde la raíz.
      expect(s.textoRuta(3), 'PET › Tapas › Negro');
      expect(s.hijosDe(null).map((c) => c.id), containsAll([1, 5]));
      expect(s.hijosDe(1).map((c) => c.id), [2]);

      // Pero no se puede dar de alta un ítem nuevo en esa categoría ajena.
      expect(
          await s.guardarItem(
              const ItemInventario(categoriaId: 3, detalle: 'Otra cápsula', unidad: 'PZA')),
          contains('propia'));
      // Sí se puede en la categoría propia de Soplado.
      expect(
          await s.guardarItem(
              const ItemInventario(categoriaId: 5, detalle: 'Boquilla', unidad: 'UNI')),
          isNull);
    });
  });

  group('salida directa', () {
    test('solo en Almacén General, y solo con permiso de editar', () async {
      final s = await _servicio({'inventario_general:ver'});
      expect(s.puedeSalidaDirecta, isFalse);

      final soplado = InventarioService(
          _RepoFalso(),
          Usuario(id: 'u', nombreCompleto: 'Soplado', rol: 'soplado',
              permisos: {'inventario_soplado:ver', 'inventario_soplado:editar'}));
      await soplado.iniciar();
      expect(soplado.puedeSalidaDirecta, isFalse); // está viendo Soplado, no General

      final s2 = await _servicio(_todoGeneral);
      expect(s2.puedeSalidaDirecta, isTrue);
    });

    test('exige ítem, área y peso real; valida el stock', () async {
      final s = await _servicio(_todoGeneral);
      final capsula = s.existencias.firstWhere((e) => e.itemId == 10);
      expect(
          await s.registrarSalidaDirecta(item: null, areaDestino: 'llenadora', pesoReal: 5),
          contains('ítem'));
      expect(
          await s.registrarSalidaDirecta(item: capsula, areaDestino: null, pesoReal: 5),
          contains('área'));
      expect(
          await s.registrarSalidaDirecta(item: capsula, areaDestino: 'llenadora', pesoReal: 0),
          contains('mayor a cero'));
      expect(
          await s.registrarSalidaDirecta(item: capsula, areaDestino: 'llenadora', pesoReal: 500),
          contains('insuficiente'));
    });

    test('registra con rollos y peso real, y traduce el error del servidor', () async {
      final repo = _RepoFalso();
      final s = await _servicio(_todoGeneral, repo);
      final capsula = s.existencias.firstWhere((e) => e.itemId == 10);
      expect(
          await s.registrarSalidaDirecta(
              item: capsula, areaDestino: 'llenadora', pesoReal: 12.4, cantidadRollos: 3,
              motivo: 'Pedido verbal del turno'),
          isNull);
      expect(repo.salidasDirectas.single, {
        'item': 10, 'area': 'llenadora', 'peso': 12.4, 'rollos': 3.0,
        'motivo': 'Pedido verbal del turno', 'almacen': 'general',
      });

      repo.rechazarCon = 'No hay suficiente stock: hay 2, se quieren sacar 5.';
      expect(
          await s.registrarSalidaDirecta(item: capsula, areaDestino: 'llenadora', pesoReal: 5),
          'No hay suficiente stock: hay 2, se quieren sacar 5.');
    });
  });
}

Future<BalanceService> _balance(Set<String>? permisos, _RepoFalso repo) async {
  final b = BalanceService(repo, _usuario(permisos), 'general');
  await b.cargar();
  return b;
}

void balanceTests() {
  group('Balance de insumos', () {
    test('agrupa por categoría raíz y arranca sin nada contado', () async {
      final b = await _balance(_todoGeneral, _RepoFalso());
      expect(b.filas, hasLength(3));
      expect(b.filas.first.categoriaRaiz, 'Limpieza'); // ordenadas por raíz
      expect(b.contados, 0);
    });

    test('convierte gramos a kilos y calcula la diferencia', () async {
      final b = await _balance(_todoGeneral, _RepoFalso());
      // Un ítem en KG: se escribe en gramos.
      final fila = b.filas.firstWhere((f) => f.item.itemId == 11);
      expect(fila.unidadesPosibles, ['UNI']); // UNI no se convierte
      final kg = FilaBalance(
          const ExistenciaItem(
              itemId: 99, codigo: 'MP-1', detalle: 'Color azul', unidad: 'KG',
              categoriaId: 1, almacenId: 'jarabes', cantidadSistema: 1),
          'Colorantes');
      kg.unidadEntrada = 'GR';
      kg.texto = '791,6';
      expect(kg.valorEnUnidadItem, closeTo(0.7916, 1e-9));
      expect(kg.diferencia, closeTo(-0.2084, 1e-9));
    });

    test('guarda solo las filas llenas, en un solo envío', () async {
      final repo = _RepoFalso();
      final b = await _balance(_todoGeneral, repo);
      b.escribir(b.filas[0], '10');
      b.escribir(b.filas[2], '7,5');
      expect(b.contados, 2);
      expect(await b.guardar(nota: 'Cierre agosto'), isNull);
      expect(repo.lotes, hasLength(2));
      expect(repo.lotes.map((c) => c.cantidadReal), containsAll([10.0, 7.5]));
      expect(repo.lotes.first.observaciones, 'Balance de insumos · Cierre agosto');
    });

    test('rechaza valores inválidos y balance vacío', () async {
      final repo = _RepoFalso();
      final b = await _balance(_todoGeneral, repo);
      expect(await b.guardar(), contains('ninguna cantidad'));
      b.escribir(b.filas[0], 'abc');
      expect(await b.guardar(), contains('inválidos'));
      b.escribir(b.filas[0], '-3');
      expect(await b.guardar(), contains('inválidos'));
      expect(repo.lotes, isEmpty);
    });

    test('sin permiso de editar no guarda; si falla el envío avisa', () async {
      final repo = _RepoFalso();
      final sinPermiso = await _balance({'inventario_general:ver'}, repo);
      sinPermiso.escribir(sinPermiso.filas[0], '1');
      expect(await sinPermiso.guardar(), contains('permiso'));

      repo.fallar = true;
      final b = await _balance(_todoGeneral, repo);
      b.escribir(b.filas[0], '1');
      expect(await b.guardar(), contains('No se registró ningún conteo'));
      expect(repo.lotes, isEmpty);
    });
  });
}
