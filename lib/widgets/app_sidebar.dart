import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/modulos.dart';
import '../services/auth_service.dart';

/// Menú lateral oscuro: ícono + nombre de cada sección, con la sección
/// activa resaltada en verde. El logo, la sincronización y el usuario
/// viven en la barra superior (ver `AppTopBar`).
class AppSidebar extends StatelessWidget {
  final String rutaActual;
  final void Function(String ruta) onNavegar;
  const AppSidebar(
      {super.key, required this.rutaActual, required this.onNavegar});

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;

    final items = <_Item>[
      _Item('dashboard', 'Inicio', Icons.home_outlined, true),
      // Arriba de todo: es lo primero que entra a hacer el Jefe de
      // Producción cada día (armar/revisar el plan), no algo ocasional.
      _Item('produccion', 'Producción del día', Icons.factory_outlined,
          usuario.puedeVerProduccion),
      // Segundo en uso diario después de Producción del día.
      _Item('jarabes', 'Jarabes', Icons.water_drop_outlined,
          usuario.puedeVerModulo(Modulo.jarabesProduccion)),
      // Inventario por almacenes (nuevo): requiere la migración de permisos.
      _Item('almacenes', 'Almacenes', Icons.warehouse_outlined,
          usuario.permisos != null && usuario.puedeVerInventario),
      _Item('recepciones', 'Recepciones', Icons.local_shipping_outlined,
          usuario.puedeVerModulo(Modulo.recepciones)),
      _Item('entregas', 'Entregas', Icons.assignment_turned_in_outlined,
          usuario.puedeVerModulo(Modulo.entregas)),
      _Item('solicitudes', 'Solicitudes', Icons.mark_email_read_outlined,
          usuario.puedeVerModulo(Modulo.solicitudes)),
      _Item('soplado', 'Soplado', Icons.air_outlined,
          usuario.puedeVerModulo(Modulo.soplado)),
      _Item('calidad', 'Control de Calidad', Icons.science_outlined,
          usuario.puedeVerModulo(Modulo.calidad)),
      _Item('llenadora', 'Llenadora', Icons.local_drink_outlined,
          usuario.puedeVerModulo(Modulo.llenado)),
      _Item('codificacion', 'Codificación', Icons.qr_code_2,
          usuario.puedeVerModulo(Modulo.codificacion)),
      _Item('salidas', 'Registro de salidas', Icons.outbox_outlined,
          usuario.puedeVerModulo(Modulo.salidas)),
      _Item('mermas', 'Mermas', Icons.report_problem_outlined,
          usuario.puedeVerModulo(Modulo.mermas)),
      _Item('soda_caustica', 'Soda Cáustica', Icons.science_outlined,
          usuario.puedeVerModulo(Modulo.sodaCaustica)),
      _Item('informe_gerente', 'Informe de Producción', Icons.summarize_outlined,
          usuario.puedeVerModulo(Modulo.informeProduccion)),
      _Item('historial', 'Historial / Bitácora', Icons.history,
          usuario.puedeVerHistorial),
      _Item('usuarios', 'Usuarios', Icons.people_outline,
          usuario.puedeVerUsuarios),
    ];

    return Container(
      width: 240,
      color: const Color(0xFF17221D),
      // Scrollable: en ventanas bajas con muchos ítems de menú visibles,
      // la lista se desplaza en vez de desbordar.
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final item in items.where((i) => i.visible))
            _FilaMenu(
              item: item,
              activa: rutaActual == item.ruta,
              onTap: () => onNavegar(item.ruta),
            ),
        ],
      ),
    );
  }
}

class _FilaMenu extends StatelessWidget {
  final _Item item;
  final bool activa;
  final VoidCallback onTap;
  const _FilaMenu(
      {required this.item, required this.activa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: activa ? AppColors.primario : Colors.transparent,
          border: Border(
            left: BorderSide(
                color: activa ? const Color(0xFF7FE0A5) : Colors.transparent,
                width: 4),
            bottom: const BorderSide(color: Color(0xFF212E27)),
          ),
        ),
        child: Row(
          children: [
            Icon(item.icono,
                size: 22, color: activa ? Colors.white : Colors.white70),
            const SizedBox(width: 14),
            Expanded(
              child: Text(item.titulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: activa ? Colors.white : Colors.white70,
                      fontWeight: activa ? FontWeight.bold : FontWeight.normal)),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: activa ? Colors.white : Colors.white24),
          ],
        ),
      ),
    );
  }
}

class _Item {
  final String ruta;
  final String titulo;
  final IconData icono;
  final bool visible;
  _Item(this.ruta, this.titulo, this.icono, this.visible);
}
