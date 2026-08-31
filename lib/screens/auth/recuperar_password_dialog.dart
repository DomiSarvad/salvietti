import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';

/// "¿Olvidaste tu contraseña?": pide el correo, envía un código de un
/// solo uso, y con ese código + una contraseña nueva cierra el ciclo.
/// Mismo concepto que usa Google (recuperación por código), adaptado a
/// que esta app no tiene un dominio propio para recibir un link.
class RecuperarPasswordDialog extends StatefulWidget {
  final String emailInicial;
  const RecuperarPasswordDialog({super.key, this.emailInicial = ''});

  @override
  State<RecuperarPasswordDialog> createState() =>
      _RecuperarPasswordDialogState();
}

class _RecuperarPasswordDialogState extends State<RecuperarPasswordDialog> {
  late final TextEditingController _emailCtrl;
  final _codigoCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  int _paso = 1; // 1 = pedir correo, 2 = código + nueva contraseña
  bool _cargando = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.emailInicial);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codigoCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    setState(() {
      _cargando = true;
      _error = null;
      _info = null;
    });
    final auth = context.read<AuthService>();
    final error = await auth.solicitarRecuperacion(_emailCtrl.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (error != null) {
        _error = error;
      } else {
        _paso = 2;
        _info = 'Te enviamos un código a ${_emailCtrl.text.trim()}. '
            'Revisa también la carpeta de spam.';
      }
    });
  }

  Future<void> _confirmar() async {
    if (_nuevaCtrl.text != _confirmarCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final error = await auth.confirmarRecuperacion(
      email: _emailCtrl.text,
      codigo: _codigoCtrl.text,
      nuevaPassword: _nuevaCtrl.text,
    );
    if (!mounted) return;
    setState(() => _cargando = false);
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recuperar contraseña'),
      content: SizedBox(
        width: anchoDialogo(context, 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_paso == 1) ...[
              const Text(
                  'Ingresa tu correo y te enviaremos un código para restablecer tu contraseña.'),
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
            ] else ...[
              if (_info != null)
                Text(_info!, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              TextField(
                controller: _codigoCtrl,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration:
                    const InputDecoration(labelText: 'Código recibido'),
              ),
              TextField(
                controller: _nuevaCtrl,
                obscureText: true,
                maxLength: Validacion.passwordMax,
                decoration:
                    const InputDecoration(labelText: 'Nueva contraseña'),
              ),
              TextField(
                controller: _confirmarCtrl,
                obscureText: true,
                maxLength: Validacion.passwordMax,
                decoration: const InputDecoration(
                    labelText: 'Confirmar nueva contraseña'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _cargando ? null : _enviarCodigo,
                  child: const Text('Reenviar código'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _cargando ? null : (_paso == 1 ? _enviarCodigo : _confirmar),
          child: _cargando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_paso == 1 ? 'Enviar código' : 'Cambiar contraseña'),
        ),
      ],
    );
  }
}
