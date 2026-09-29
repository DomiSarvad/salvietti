import 'package:flutter/material.dart';
import '../models/datos_empleado.dart';
import '../utils/formatters.dart';
import 'formulario_widgets.dart';

/// Controladores de los campos de datos del empleado (lo comparten la pantalla
/// "Completá tus datos", "Mi perfil" y la edición del Gerente).
class DatosEmpleadoCtrl {
  final celular = TextEditingController();
  final carnet = TextEditingController();
  final direccion = TextEditingController();
  DateTime? fechaNacimiento;
  DateTime? fechaIngreso;

  DatosEmpleadoCtrl([DatosEmpleado? d]) {
    celular.text = d?.celular ?? '';
    carnet.text = d?.carnet ?? '';
    direccion.text = d?.direccion ?? '';
    fechaNacimiento = d?.fechaNacimiento;
    fechaIngreso = d?.fechaIngreso;
  }

  DatosEmpleado toDatos() => DatosEmpleado(
        celular: celular.text,
        carnet: carnet.text,
        direccion: direccion.text,
        fechaNacimiento: fechaNacimiento,
        fechaIngreso: fechaIngreso,
      );

  void dispose() {
    celular.dispose();
    carnet.dispose();
    direccion.dispose();
  }
}

/// Campos de celular, carnet, dirección y fecha de nacimiento (y, si
/// [mostrarFechaIngreso], la fecha de ingreso, que solo edita el Gerente).
class CamposDatosEmpleado extends StatefulWidget {
  final DatosEmpleadoCtrl ctrl;
  final bool mostrarFechaIngreso;
  final bool fechaIngresoEditable;
  final VoidCallback? onChanged;
  const CamposDatosEmpleado({
    super.key,
    required this.ctrl,
    this.mostrarFechaIngreso = false,
    this.fechaIngresoEditable = false,
    this.onChanged,
  });

  @override
  State<CamposDatosEmpleado> createState() => _CamposDatosEmpleadoState();
}

class _CamposDatosEmpleadoState extends State<CamposDatosEmpleado> {
  Future<void> _elegirNacimiento() async {
    final hoy = DateTime.now();
    // El calendario abre lo más cerca posible de hoy (el límite de 16 años,
    // si no hay fecha cargada), para que alcance con ir hacia atrás con el
    // selector de año en vez de aparecer en una fecha fija arbitraria.
    final maxima = DateTime(hoy.year - 16, hoy.month, hoy.day);
    var inicial = widget.ctrl.fechaNacimiento ?? maxima;
    if (inicial.isAfter(maxima)) inicial = maxima;
    final f = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(1930),
      lastDate: maxima,
      helpText: 'Fecha de nacimiento',
    );
    if (f != null) {
      setState(() => widget.ctrl.fechaNacimiento = f);
      widget.onChanged?.call();
    }
  }

  Future<void> _elegirIngreso() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: widget.ctrl.fechaIngreso ?? hoy,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoy.year + 1, 12, 31),
      helpText: 'Fecha de ingreso',
    );
    if (f != null) {
      setState(() => widget.ctrl.fechaIngreso = f);
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoFormulario(
          etiqueta: 'Celular *',
          child: TextField(
            controller: c.celular,
            keyboardType: TextInputType.phone,
            maxLength: 30,
            onChanged: (_) => widget.onChanged?.call(),
            decoration: decoracionFormulario(hint: 'Ej. 70012345'),
          ),
        ),
        CampoFormulario(
          etiqueta: 'Carnet de identidad *',
          child: TextField(
            controller: c.carnet,
            maxLength: 30,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => widget.onChanged?.call(),
            decoration: decoracionFormulario(hint: 'Ej. 1234567 LP'),
          ),
        ),
        CampoFormulario(
          etiqueta: 'Dirección *',
          child: TextField(
            controller: c.direccion,
            maxLength: 200,
            onChanged: (_) => widget.onChanged?.call(),
            decoration: decoracionFormulario(hint: 'Calle, número, zona'),
          ),
        ),
        CampoFormulario(
          etiqueta: 'Fecha de nacimiento *',
          child: ValorFormulario(
            c.fechaNacimiento == null ? 'dd/mm/aaaa' : fmtFecha(c.fechaNacimiento),
            icono: Icons.calendar_today,
            onTap: _elegirNacimiento,
          ),
        ),
        if (widget.mostrarFechaIngreso)
          CampoFormulario(
            etiqueta: 'Fecha de ingreso',
            child: ValorFormulario(
              c.fechaIngreso == null ? 'dd/mm/aaaa' : fmtFecha(c.fechaIngreso),
              icono: Icons.calendar_today,
              onTap: widget.fechaIngresoEditable ? _elegirIngreso : null,
            ),
          ),
      ],
    );
  }
}
