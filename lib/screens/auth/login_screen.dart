import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/gradient_text.dart';
import '../../widgets/video_background.dart';
import 'recuperar_password_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  /// Cuenta regresiva de un bloqueo temporal (null = no hay ninguno en curso).
  int? _segundosEspera;
  Timer? _timerEspera;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = HiveService.ultimoEmail() ?? '';
  }

  @override
  void dispose() {
    _timerEspera?.cancel();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _iniciarCuentaRegresiva(int segundos) {
    _timerEspera?.cancel();
    setState(() => _segundosEspera = segundos);
    _timerEspera = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        final restante = (_segundosEspera ?? 1) - 1;
        if (restante <= 0) {
          _segundosEspera = null;
          t.cancel();
        } else {
          _segundosEspera = restante;
        }
      });
    });
  }

  String _formatoEspera(int segundos) {
    if (segundos < 60) return '$segundos segundo${segundos == 1 ? '' : 's'}';
    final min = segundos ~/ 60;
    final seg = segundos % 60;
    final texto = '$min minuto${min == 1 ? '' : 's'}';
    return seg == 0 ? texto : '$texto $seg segundo${seg == 1 ? '' : 's'}';
  }

  Future<void> _entrar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final resultado =
        await auth.iniciarSesion(_emailCtrl.text.trim(), _passCtrl.text);
    if (resultado.ok) {
      await HiveService.guardarUltimoEmail(_emailCtrl.text.trim());
      if (auth.sinConexion) {
        // Sin context: esta pantalla ya se reemplazó por el menú.
        toastification.show(
          type: ToastificationType.warning,
          style: ToastificationStyle.flatColored,
          title: const Text('Entraste sin internet'),
          description: const Text('Ves los datos de la última vez que hubo conexión en esta compu. '
              'Lo que registres se guarda acá y se sube solo cuando vuelva internet.'),
          autoCloseDuration: const Duration(seconds: 7),
          alignment: Alignment.topCenter,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = resultado.error;
    });
    if (resultado.segundosEspera != null) {
      _iniciarCuentaRegresiva(resultado.segundosEspera!);
    } else {
      _timerEspera?.cancel();
      _segundosEspera = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradiente de respaldo: se ve mientras el video carga o si la
          // plataforma no puede reproducirlo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primario, Color(0xFF0D3B24)],
              ),
            ),
          ),
          const VideoBackground(asset: 'assets/videos/login_bg.mp4'),
          _buildContenido(context),
        ],
      ),
    );
  }

  Widget _buildContenido(BuildContext context) {
    return
        // SingleChildScrollView + ConstrainedBox: si el contenido (ej. un
        // mensaje de error largo) no entra en la altura de la pantalla,
        // se puede desplazar en vez de desbordar; si entra, se centra
        // igual que antes.
        SingleChildScrollView(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: MediaQuery.of(context).size.height),
            child: Center(
              child: Card(
                elevation: 12,
                shadowColor: Colors.black45,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Container(
                  width: anchoDialogo(context, 380, margen: 64),
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Image.asset('assets/logo.png', height: 76),
                  const SizedBox(height: 18),
                  const GradientText('Salvietti Control',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('Sistema de gestión de inventarios',
                      style: TextStyle(color: Colors.black54, fontSize: 13)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailCtrl,
                    maxLength: Validacion.emailMax,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Correo',
                      prefixIcon: const Icon(Icons.mail_outline),
                      filled: true,
                      fillColor: AppColors.fondo,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    maxLength: Validacion.passwordMax,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: AppColors.fondo,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _entrar(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => RecuperarPasswordDialog(
                            emailInicial: _emailCtrl.text.trim()),
                      ).then((exito) {
                        if (exito == true && mounted) {
                          setState(() => _error = null);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Contraseña actualizada. Ya puedes iniciar sesión.')));
                        }
                      }),
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                  ),
                  if (_segundosEspera != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Demasiados intentos fallidos. Esperá '
                      '${_formatoEspera(_segundosEspera!)} e intentá de nuevo.',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ] else if ((_error ?? context.watch<AuthService>().avisoLogin) != null) ...[
                    const SizedBox(height: 4),
                    // El error del último intento o, si no hubo, por qué se
                    // cerró la sesión (ausencia, contraseña cambiada…). Se
                    // escucha en vivo: la revisión de la sesión al abrir la
                    // app puede terminar después de que esta pantalla aparece.
                    // Un error va en rojo; un aviso (sesión cerrada por ausencia) es
                    // informativo: recuadro claro con ícono, no parece una falla.
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red))
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.lock_clock_outlined, size: 18, color: Color(0xFFB26A00)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(context.watch<AuthService>().avisoLogin!,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF7A4A00))),
                          ),
                        ]),
                      ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          (_cargando || _segundosEspera != null) ? null : _entrar,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primario,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: _cargando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Ingresar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
