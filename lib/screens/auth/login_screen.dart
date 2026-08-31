import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../utils/responsive.dart';
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

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = HiveService.ultimoEmail() ?? '';
  }

  Future<void> _entrar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final error =
        await auth.iniciarSesion(_emailCtrl.text.trim(), _passCtrl.text);
    if (error == null) {
      await HiveService.guardarUltimoEmail(_emailCtrl.text.trim());
    }
    setState(() {
      _cargando = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primario, Color(0xFF0D3B24)],
          ),
        ),
        child: Center(
          child: Card(
            elevation: 12,
            shadowColor: Colors.black45,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              width: anchoDialogo(context, 380, margen: 64),
              padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.jpg', height: 76),
                  const SizedBox(height: 18),
                  const Text('Salvietti Control',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primario)),
                  const SizedBox(height: 4),
                  const Text('Sistema de gestión de inventarios',
                      style: TextStyle(color: Colors.black54, fontSize: 13)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailCtrl,
                    maxLength: 254,
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
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _cargando ? null : _entrar,
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
