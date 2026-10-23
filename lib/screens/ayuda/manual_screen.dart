import 'package:flutter/material.dart';
import '../../core/constants.dart';

/// Una entrada del manual: un módulo, con lo básico de para qué sirve y
/// cómo se usa. Texto simple, sin tecnicismos — es la referencia escrita
/// para cuando el tour interactivo (los globitos con "?") no alcanza o ya
/// se cerró.
class _EntradaManual {
  final String titulo;
  final IconData icono;
  final String resumen;
  final List<String> puntos;
  const _EntradaManual({
    required this.titulo,
    required this.icono,
    required this.resumen,
    required this.puntos,
  });
}

const _entradas = <_EntradaManual>[
  _EntradaManual(
    titulo: 'Inicio',
    icono: Icons.home_outlined,
    resumen: 'Lo primero que ves al entrar: un resumen de todo.',
    puntos: [
      'Las tarjetas de almacén se pintan de rojo/amarillo/verde según el peor ítem de ese '
          'almacén — no hace falta entrar para saber si hay un problema.',
      'Tocar una tarjeta de almacén te lleva directo a Almacenes, ya en ese almacén.',
      '"Ítems con menor stock" muestra primero lo crítico, después lo bajo.',
      'Si tenés permiso de ver Mermas, aparece un gráfico con el % de merma de cada área '
          '(en rojo, lo que superó el 3 %).',
      'Todo se actualiza solo — no hace falta refrescar la pantalla.',
    ],
  ),
  _EntradaManual(
    titulo: 'Producción del día',
    icono: Icons.factory_outlined,
    resumen: 'El plan que arma el Jefe de Producción cada día.',
    puntos: [
      'El Jefe de Producción toca "Armar plan" para cargar qué se va a producir hoy.',
      'Cada producto se marca "hecho" cuando termina de embotellarse (eso descuenta stock '
          'automáticamente: materia prima, preformas y tapas).',
      'Tocar un producto de la lista (o su ícono de gota) te lleva a Jarabes con ese sabor '
          'ya elegido, listo para calcular el preparado.',
      'Un producto ya marcado como completado se puede volver a tocar para corregir la '
          'cantidad real de botellas, si la estimación no fue exacta.',
    ],
  ),
  _EntradaManual(
    titulo: 'Jarabes',
    icono: Icons.water_drop_outlined,
    resumen: 'Donde Jarabes prepara el concentrado de cada sabor.',
    puntos: [
      '"Nuevo preparado": elegís el sabor y la cantidad; el sistema te dice al toque si '
          'alcanza el insumo. Si falta, podés mandar la solicitud a Almacén ahí mismo.',
      '"Plan de hoy" es de referencia — muestra qué planificó Producción, pero podés '
          'preparar cualquier sabor igual si hace falta.',
      'Al finalizar un preparado, se marca solo en el plan de Producción (con una '
          'estimación) y queda un aviso "Jarabes listo" en la tarjeta del plan.',
      'Solo Calidad, Jefe de Producción o Gerente pueden proponer o aprobar un cambio de '
          'receta — necesita el visto bueno de los tres.',
    ],
  ),
  _EntradaManual(
    titulo: 'Almacenes',
    icono: Icons.warehouse_outlined,
    resumen: 'El inventario de cada almacén (General, Jarabes, Soplado, Soda Cáustica).',
    puntos: [
      'Se navega por categorías (Tapas, Preformas, etc.) — al entrar a una, ya se ven '
          'TODOS los ítems de ahí y de sus subdivisiones, no hace falta seguir entrando.',
      'El buscador funciona en todo el almacén, no solo en la categoría donde estás.',
      'Escribir "critico", "bajo" u "óptimo" en el buscador filtra por ese estado.',
      'Cada ítem tiene sus propios movimientos, conteo físico y edición (según tu permiso).',
      'Almacén General tiene además "Salida directa" para lo que sale sin pedido formal '
          '(ej. termocontraíbles).',
    ],
  ),
  _EntradaManual(
    titulo: 'Recepciones',
    icono: Icons.local_shipping_outlined,
    resumen: 'Cuando llega un pedido de un proveedor, se registra acá.',
    puntos: [
      'Se carga cantidad de factura vs. cantidad real recibida — la diferencia queda '
          'registrada sola.',
      'Lote, fecha de vencimiento y SENASAG quedan asociados al ítem para el resto del '
          'sistema (ej. para elegir lotes por vencer primero).',
    ],
  ),
  _EntradaManual(
    titulo: 'Entregas',
    icono: Icons.assignment_turned_in_outlined,
    resumen: 'Pedidos entre áreas: quién pidió qué, y qué entregó Almacén.',
    puntos: [
      'Un área pide insumos; Almacén entrega y descuenta el almacén de origen.',
      'Si entregó de menos, queda una observación hasta que se resuelve.',
      'Se puede devolver a Almacén lo que sobró de una entrega ya hecha.',
    ],
  ),
  _EntradaManual(
    titulo: 'Solicitudes',
    icono: Icons.mark_email_read_outlined,
    resumen: 'Cualquier área le pide algo a Gerencia (no a Almacén).',
    puntos: [
      'Para faltantes de suministro, autorizaciones o cambios de receta.',
      'Gerencia tiene una sola bandeja para aprobar o rechazar todo.',
      'También se puede mandar desde la campana (abajo a la derecha): "Nueva solicitud o pregunta".',
    ],
  ),
  _EntradaManual(
    titulo: 'Pedidos de compra',
    icono: Icons.shopping_cart_outlined,
    resumen: 'Almacén pide permiso al Gerente para comprar a proveedores.',
    puntos: [
      'Un pedido puede tener varios ítems, cada uno con su cantidad y una nota.',
      'El Gerente lo aprueba o lo rechaza entero (si lo rechaza, explica por qué). '
          'La respuesta llega a la campana de quien lo pidió.',
      'Mientras está pendiente, quien lo hizo lo puede anular.',
      'No mueve el stock: el stock entra cuando llega la mercadería, en Recepciones.',
    ],
  ),
  _EntradaManual(
    titulo: 'Campana de notificaciones',
    icono: Icons.notifications_rounded,
    resumen: 'El botón redondo de abajo a la derecha: lo que tenés pendiente.',
    puntos: [
      'El número rojo es cuántas cosas te esperan. Tocá la campana para ver cuáles y '
          'tocá una para ir directo a resolverla.',
      'Gerente: pedidos de compra, solicitudes y recetas por confirmar.',
      'Resto del personal: las respuestas a lo que mandaste (aprobado o rechazado).',
      'Se actualiza sola, sin tener que refrescar.',
    ],
  ),
  _EntradaManual(
    titulo: 'Informes (Gerente)',
    icono: Icons.insights_outlined,
    resumen: 'Resultados de cada área por semana o por mes, con gráficos.',
    puntos: [
      '"General" resume todo; cada área (Jarabes, Soplado, Llenadora, Calidad, Mermas, '
          'Almacén…) muestra sus resultados en detalle.',
      'Semanal: una barra por día. Mensual: una barra por semana. Con las flechas se ven '
          'períodos anteriores.',
      'Solo cuenta lo terminado (las corridas en curso o anuladas no entran).',
      'Los botones PDF y Excel descargan exactamente el informe que estás viendo.',
    ],
  ),
  _EntradaManual(
    titulo: 'Soplado',
    icono: Icons.air_outlined,
    resumen: 'Donde se soplan las preformas para hacer las botellas PET.',
    puntos: [
      'Se inicia una corrida eligiendo sabor, presentación y lote de preforma.',
      'Al finalizar, se cargan botellas sopladas y mermas (preforma, soplado, etiquetado) '
          'con su motivo.',
    ],
  ),
  _EntradaManual(
    titulo: 'Control de Calidad',
    icono: Icons.science_outlined,
    resumen: 'Análisis de cada preparado de Jarabes (Brix, pH, aspecto).',
    puntos: [
      'Calidad también da uno de los tres vistos buenos para cambiar una receta.',
    ],
  ),
  _EntradaManual(
    titulo: 'Llenadora',
    icono: Icons.local_drink_outlined,
    resumen: 'Cuando se llenan las botellas con el jarabe ya preparado.',
    puntos: [
      'No vuelve a descontar preformas ni tapas del almacén — eso ya lo hizo Almacén al '
          'entregar el pedido. Acá solo se registra cuánto se llenó y la merma.',
      'La merma (botellas o tapas desechadas) no puede ser mayor a lo producido.',
    ],
  ),
  _EntradaManual(
    titulo: 'Codificación',
    icono: Icons.qr_code_2,
    resumen: 'Cuando se le imprime el código/fecha de vencimiento a cada botella.',
    puntos: [
      'Se vincula a la corrida de Llenadora correspondiente.',
      'Igual que Llenadora, solo registra consumo (solvente, tinta) — no descuenta stock '
          'de nuevo.',
    ],
  ),
  _EntradaManual(
    titulo: 'Registro de salidas',
    icono: Icons.outbox_outlined,
    resumen: 'El reporte diario de producto terminado que sale (PET y Vidrio).',
    puntos: [
      'Se carga por turno: palets/paquetes/botellas sueltas (PET) o filas/cajas/botellas '
          'sueltas (Vidrio).',
      'El total de botellas se calcula solo.',
    ],
  ),
  _EntradaManual(
    titulo: 'Mermas',
    icono: Icons.report_problem_outlined,
    resumen: 'Todas las mermas juntas, de todas las áreas, en un solo lugar.',
    puntos: [
      'Soplado, Llenadora y Codificación ya aparecen solas (se cargan en su propia '
          'corrida) — acá se agregan las de Jarabes, Calidad y Vidrio.',
      'Se marca en rojo lo que supera el 3 % de lo producido.',
    ],
  ),
  _EntradaManual(
    titulo: 'Soda Cáustica',
    icono: Icons.science_outlined,
    resumen: 'Entregas de soda cáustica (producto peligroso) a Mantenimiento u otra área.',
    puntos: [
      'Cada entrega debería llevar una constancia en PDF (por ahora es opcional, no '
          'obligatoria todavía).',
    ],
  ),
  _EntradaManual(
    titulo: 'Informe de Producción',
    icono: Icons.summarize_outlined,
    resumen: 'Compara lo que se esperaba producir contra lo que realmente se produjo.',
    puntos: [
      'Junto con el detalle de merma por área, para ver dónde se perdió más.',
    ],
  ),
  _EntradaManual(
    titulo: 'Historial / Bitácora',
    icono: Icons.history,
    resumen: 'Quién hizo qué y cuándo, en todo el sistema.',
    puntos: [
      'Solo lo ven Almacén y Gerente.',
    ],
  ),
  _EntradaManual(
    titulo: 'Usuarios',
    icono: Icons.people_outline,
    resumen: 'Alta, edición y bloqueo de las cuentas del sistema. Solo Gerente.',
    puntos: [
      'Al editar o dar de alta a alguien, el botón "Ver permisos" junto al campo Rol abre '
          'qué puede hacer ese rol en cada módulo.',
      'Una cuenta con demasiados intentos fallidos de contraseña queda bloqueada un rato; '
          'Gerente la puede desbloquear antes desde acá.',
    ],
  ),
  _EntradaManual(
    titulo: 'Configuración',
    icono: Icons.settings,
    resumen: 'El engranaje de arriba: ajustes del dispositivo, no de tu cuenta.',
    puntos: [
      'Sin internet se puede seguir trabajando: lo que registres se guarda en esta compu '
          '(aparece el aviso "Sin internet: se guardó en esta compu") y se sube solo cuando '
          'vuelve la conexión. Lo que ves en pantalla mientras tanto es lo de la última vez '
          'que hubo internet.',
      'También se puede ENTRAR sin internet, con tu correo y contraseña de siempre, si ya '
          'entraste al menos una vez con internet en esa misma compu en los últimos 30 días. '
          'Cuando vuelve la conexión, la app termina de conectarse sola y sube lo que '
          'registraste. Si es tu primera vez, te pide tus datos personales igual: se guardan '
          'en la compu y se suben con lo demás.',
      'Si te vas sin cerrar sesión y la app queda más de 1 hora sin usarse, al volver te pide '
          'ingresar de nuevo (las compus se comparten). Lo que habías registrado no se pierde.',
      'Si otra área está sin internet, aparece un aviso amarillo (por ejemplo, en Jarabes: '
          '"Soplado: sin señal desde las 10:32"). Quiere decir que lo que esa área registró '
          'desde entonces todavía no se ve: confirmá con ella antes de decidir con esos datos. '
          'Al cerrar la app, conviene cerrar sesión para no aparecer "sin señal".',
      'Sincronización: ver qué quedó sin subir y forzar "Sincronizar ahora". Si el sistema '
          'no aceptó algo al subirlo (por ejemplo, ya no alcanzaba el stock), aparece ahí con '
          'el motivo, para reintentarlo o descartarlo.',
      'Tamaño de letra: chico, normal o grande, para toda la app.',
      'Tus datos personales (foto, contraseña, celular) se editan en "Mi perfil", desde tu '
          'usuario arriba a la derecha — no acá.',
    ],
  ),
];

/// Manual de usuario dentro de la app: lo básico de cada módulo, para
/// cuando el tour interactivo (los globitos) no alcanza o ya se cerró.
/// Visible para cualquier rol — cada quien ve igual las secciones que no
/// le tocan, así entiende el sistema completo, no solo su parte.
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Manual de usuario', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
            'Lo básico de cada parte del sistema. Si una pantalla tiene un botón "?" arriba, '
            'ese repite el recorrido guiado con globitos — esto de acá es la versión escrita, '
            'para volver a consultar cuando haga falta.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 16),
        for (final e in _entradas) _tarjeta(e),
      ],
    );
  }

  Widget _tarjeta(_EntradaManual e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EB))),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(e.icono, color: AppColors.primario),
          title: Text(e.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(e.resumen, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in e.puntos)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(fontSize: 13, color: Colors.black54)),
                    Expanded(child: Text(p, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
