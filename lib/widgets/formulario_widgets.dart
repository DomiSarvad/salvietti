import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../shared/ayuda/tour_ayuda.dart';

/// Marco común de los formularios (estilo del sistema de reclamos, con los
/// colores de Salvietti): título en mayúsculas con letras espaciadas y "X"
/// arriba, cuerpo que se desplaza, y un botón ancho con degradado FIJO abajo
/// (siempre visible aunque el formulario sea largo).
///
/// [idTour]/[pasosAyuda] son opcionales: si un formulario los pasa, el marco
/// se encarga solo de mostrar el tour la primera vez que se abre y de poner
/// el botón "?" al lado de la "X" — el formulario solo define sus propios
/// `GlobalKey` y su lista de `PasoAyuda`, igual que ya hace cada pantalla
/// con `BotonAyuda`.
class ModalFormulario extends StatefulWidget {
  final String titulo;
  final IconData icono;
  final Widget child;
  final String textoBoton;
  final VoidCallback? onGuardar;
  final bool guardando;
  final double ancho;
  final String? idTour;
  final List<PasoAyuda> Function()? pasosAyuda;
  const ModalFormulario({
    super.key,
    required this.titulo,
    required this.icono,
    required this.child,
    required this.textoBoton,
    required this.onGuardar,
    this.guardando = false,
    this.ancho = 520,
    this.idTour,
    this.pasosAyuda,
  });

  @override
  State<ModalFormulario> createState() => _ModalFormularioState();
}

class _ModalFormularioState extends State<ModalFormulario> {
  @override
  void initState() {
    super.initState();
    final idTour = widget.idTour;
    final pasosAyuda = widget.pasosAyuda;
    if (idTour != null && pasosAyuda != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          TourAyuda.mostrar(context, idTour: idTour, soloSiNoVisto: true, pasos: pasosAyuda());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pantalla = MediaQuery.of(context).size;
    final anchoUtil = (pantalla.width - 32).clamp(280.0, widget.ancho);

    // En el celular: página a pantalla completa con la barra negra y flecha de
    // volver (como Mi perfil), y el botón abajo. En la compu, la ventana.
    if (pantalla.width < 600) {
      return Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: AppColors.negro,
            surfaceTintColor: AppColors.negro,
            foregroundColor: Colors.white,
            leading: IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context, false),
            ),
            titleSpacing: 0,
            title: Text(widget.titulo,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            actions: [
              if (widget.idTour != null && widget.pasosAyuda != null)
                BotonAyuda(idTour: widget.idTour!, pasos: widget.pasosAyuda!),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: widget.child,
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FA),
                border: Border(top: BorderSide(color: Color(0xFFE3E7EB))),
              ),
              child: _BotonDegradado(
                texto: widget.textoBoton,
                cargando: widget.guardando,
                onTap: widget.onGuardar,
              ),
            ),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: anchoUtil,
          minWidth: anchoUtil,
          maxHeight: pantalla.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 4,
              decoration:
                  const BoxDecoration(gradient: AppColors.gradientePrincipal),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              child: Row(
                children: [
                  Icon(widget.icono, color: AppColors.primario, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.titulo.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            color: AppColors.negro)),
                  ),
                  if (widget.idTour != null && widget.pasosAyuda != null)
                    BotonAyuda(idTour: widget.idTour!, pasos: widget.pasosAyuda!),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black38),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: widget.child,
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FA),
                border: Border(top: BorderSide(color: Color(0xFFE3E7EB))),
              ),
              child: _BotonDegradado(
                texto: widget.textoBoton,
                cargando: widget.guardando,
                onTap: widget.onGuardar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonDegradado extends StatelessWidget {
  final String texto;
  final bool cargando;
  final VoidCallback? onTap;
  const _BotonDegradado(
      {required this.texto, required this.cargando, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activo = onTap != null && !cargando;
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 48,
        decoration: BoxDecoration(
          gradient: activo ? AppColors.gradientePrincipal : null,
          color: activo ? null : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(24),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: activo ? onTap : null,
          child: Center(
            child: cargando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Text(texto,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// Banda gris con el nombre de la sección en verde (como "Registro" en el
/// formulario de referencia).
class SeccionFormulario extends StatelessWidget {
  final String titulo;
  const SeccionFormulario(this.titulo, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(titulo,
          style: const TextStyle(
              color: AppColors.primario, fontWeight: FontWeight.w600)),
    );
  }
}

/// Campo con la etiqueta "flotando" sobre el borde superior, dentro de una
/// pastilla con borde (el estilo de los campos del sistema de referencia).
class CampoFormulario extends StatelessWidget {
  final String etiqueta;
  final Widget child;
  const CampoFormulario({super.key, required this.etiqueta, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            left: 12,
            top: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.negro, width: 1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(etiqueta,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primario)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decoración de los campos de texto dentro de [CampoFormulario].
InputDecoration decoracionFormulario({String? hint, Widget? sufijo}) =>
    InputDecoration(
      hintText: hint,
      suffixIcon: sufijo,
      counterText: '',
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primario, width: 1.6)),
    );

/// Valor de solo lectura (datos que el sistema completa solo), con el mismo
/// aspecto que un campo pero en gris.
class ValorFormulario extends StatelessWidget {
  final String valor;
  final VoidCallback? onTap;
  final IconData? icono;
  const ValorFormulario(this.valor, {super.key, this.onTap, this.icono});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFF4F6F8) : Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
                child: Text(valor,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black87))),
            if (icono != null) Icon(icono, size: 18, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}

/// Fila de 2 o más campos lado a lado (ej. "Peso" / "Ancho" / "Micronaje")
/// que en pantallas angostas se apilan en columna: repartir el ancho fijo
/// entre 2-3 `TextField`/`DropdownButtonFormField` deja tan poco espacio a
/// cada uno que la etiqueta se corta ("Unidades po…", "Anch…", "Micro…").
/// [anchoMinimo] es cuánto necesita cada campo para entrar cómodo en una fila.
class FilaCampos extends StatelessWidget {
  final List<Widget> campos;
  final double espacio;
  final double anchoMinimo;
  const FilaCampos(this.campos, {super.key, this.espacio = 10, this.anchoMinimo = 150});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoDisponiblePorCampo =
            (constraints.maxWidth - espacio * (campos.length - 1)) / campos.length;
        if (anchoDisponiblePorCampo >= anchoMinimo) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < campos.length; i++) ...[
                if (i > 0) SizedBox(width: espacio),
                Expanded(child: campos[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < campos.length; i++) ...[
              if (i > 0) SizedBox(height: espacio),
              campos[i],
            ],
          ],
        );
      },
    );
  }
}

/// Confirmación al estilo "¿Eliminar…? Esta acción no se puede deshacer":
/// ícono de advertencia grande, texto centrado y dos botones anchos.
/// Devuelve true si se confirma. [extra] permite agregar un campo (ej. motivo).
Future<bool> confirmarAccion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoConfirmar = 'Sí, eliminar',
  Widget? extra,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFF8BB86), width: 3),
                ),
                child: const Icon(Icons.priority_high,
                    size: 40, color: Color(0xFFF8BB86)),
              ),
              const SizedBox(height: 16),
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF545454))),
              const SizedBox(height: 8),
              Text(mensaje,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              if (extra != null) ...[
                const SizedBox(height: 14),
                extra,
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6E7881),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6))),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC3545),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6))),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(textoConfirmar),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true;
}
