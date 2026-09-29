import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/datos_empleado_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/campos_datos_empleado.dart';
import '../../widgets/gradient_text.dart';

/// Pantalla obligatoria del primer ingreso: el Gerente creó el usuario con lo
/// mínimo y cada empleado completa acá SUS datos personales. No se puede pasar
/// al sistema hasta guardarlos (lo único que se puede hacer es cerrar sesión).
class CompletarDatosScreen extends StatefulWidget {
  const CompletarDatosScreen({super.key});

  @override
  State<CompletarDatosScreen> createState() => _CompletarDatosScreenState();
}

class _CompletarDatosScreenState extends State<CompletarDatosScreen> {
  final _ctrl = DatosEmpleadoCtrl();
  bool _guardando = false;
  bool _cargandoPrevios = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _precargar();
  }

  /// Si ya había cargado algo a medias (o el Gerente puso datos), se muestra.
  Future<void> _precargar() async {
    final id = context.read<AuthService>().usuarioActual?.id;
    try {
      if (id != null) {
        final d = await DatosEmpleadoService.obtener(id);
        if (d != null && mounted) {
          _ctrl.celular.text = d.celular ?? '';
          _ctrl.carnet.text = d.carnet ?? '';
          _ctrl.direccion.text = d.direccion ?? '';
          _ctrl.fechaNacimiento = d.fechaNacimiento;
        }
      }
    } catch (_) {
      // Sin datos previos o sin conexión: se empieza en blanco.
    }
    if (mounted) setState(() => _cargandoPrevios = false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final datos = _ctrl.toDatos();
    final error = datos.validar(obligatorios: true);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    try {
      await DatosEmpleadoService.guardar(auth.usuarioActual!.id, datos);
      auth.datosCompletados();
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      setState(() {
        _guardando = false;
        _error = s.contains('datos_empleado') && s.contains('does not exist')
            ? 'Falta ejecutar schema_v15_datos_empleado.sql en Supabase.'
            : 'No se pudieron guardar tus datos. Revisá tu conexión e intentá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nombre = auth.usuarioActual?.nombreCompleto ?? '';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: anchoDialogo(context, 480, margen: 32),
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Image.asset('assets/logo.png', height: 64)),
                    const SizedBox(height: 12),
                    const Center(
                      child: GradientText('Completá tus datos',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 6),
                    Text('Hola, $nombre',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F1E8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Antes de empezar necesitamos tus datos personales. Se piden '
                        'una sola vez, todos son obligatorios y solo los ve el Gerente.',
                        style: TextStyle(fontSize: 12.5, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_cargandoPrevios)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      CamposDatosEmpleado(
                        ctrl: _ctrl,
                        onChanged: () {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDECEA),
                          border: Border.all(color: const Color(0xFFF5C2BE)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primario,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (_guardando || _cargandoPrevios) ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Guardar y continuar',
                              style: TextStyle(fontSize: 16)),
                    ),
                    TextButton(
                      onPressed: _guardando ? null : () => auth.cerrarSesion(),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
