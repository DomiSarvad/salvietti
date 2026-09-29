import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import '../core/constants.dart';

/// Toasts animados y consistentes para toda la app: se usan en vez de
/// `ScaffoldMessenger.showSnackBar` para dar feedback de acciones como
/// registrar o eliminar algo (más visibles que un SnackBar de texto plano
/// y no dependen de que haya un `Scaffold` ancestro).
void mostrarExito(BuildContext context, String mensaje) {
  toastification.show(
    context: context,
    type: ToastificationType.success,
    style: ToastificationStyle.flatColored,
    title: Text(mensaje),
    primaryColor: AppColors.primario,
    autoCloseDuration: const Duration(seconds: 3),
    alignment: Alignment.topCenter,
  );
}

void mostrarError(BuildContext context, String mensaje) {
  toastification.show(
    context: context,
    type: ToastificationType.error,
    style: ToastificationStyle.flatColored,
    title: Text(mensaje),
    autoCloseDuration: const Duration(seconds: 4),
    alignment: Alignment.topCenter,
  );
}

void mostrarInfo(BuildContext context, String mensaje) {
  toastification.show(
    context: context,
    type: ToastificationType.info,
    style: ToastificationStyle.flatColored,
    title: Text(mensaje),
    autoCloseDuration: const Duration(seconds: 3),
    alignment: Alignment.topCenter,
  );
}
