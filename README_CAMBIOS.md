# Salvietti Control — Notas de esta entrega

## Qué se agregó/corrigió en esta sesión

1. **`pubspec.yaml`** (no venía en el .rar original — sin él el proyecto no compila).
2. **Vista "Stock Health"** (`lib/screens/componentes/tabla_inventario.widget.dart`):
   tabla de inventario con buscador y filtros por estado (Crítico / Observación / Seguro),
   igual al estilo de tus capturas de referencia.
3. **Vista "Auditoría"** (`lib/screens/componentes/historial_widget.dart`):
   historial de bitácora con KPIs (ingresos hoy, salidas hoy, pendientes de sync) y tabla
   de movimientos. Requiere el método nuevo `DatabaseService.fetchBitacora()`.
4. **Vista "Tendencias"**: ranking de insumos con mayor consumo diario promedio.
5. **Menú lateral funcional**: antes los botones "Stock Health", "Tendencias" y
   "Auditoría" no hacían nada (`onPressed: () {}`). Ahora cambian de vista.
6. **Campana de notificaciones funcional**: antes no hacía nada. Ahora muestra las
   alertas reales (críticas y de observación) calculadas con `InventarioLogicService`.
7. **Botón "RESOLVER AHORA"** de la tarjeta de alertas críticas: ahora lleva a la vista
   de inventario en vez de no hacer nada, y la tarjeta muestra insumos reales en vez
   de texto fijo de ejemplo.
8. **Bug corregido**: la bitácora rápida mostraba el objeto `Future` sin resolver
   (`Instance of '_Future<int>'`) en lugar del número real de pendientes.
9. **Nuevo: "Plan de Producción del Día"** (`lib/screens/componentes/plan_produccion.widget.dart`
   + `lib/models/receta_model.dart`): esto es lo que pediste de "cuando agreguen cuántas
   sodas naranja van a hacer, que salga automático la cantidad de materia prima e insumos,
   y se pueda ir tickeando para vaciar el stock". El flujo es:
   - Elegir sabor y cuántas unidades se van a producir.
   - El sistema calcula automáticamente la materia prima/insumos necesarios
     (usa las fórmulas ya existentes en `InventarioLogicService.calcularPlanProduccion`).
   - Se muestra un checklist: cada insumo se tickea a medida que el operario lo retira.
   - Al confirmar, se descuenta el stock (vía `registrarConsumoPlanta`) y queda en bitácora.

   ⚠️ **Importante**: las cantidades por unidad en `receta_model.dart` son valores de
   referencia (placeholder) para que el cálculo funcione de inmediato. Debes reemplazarlas
   con la ficha técnica/formulación real de cada sabor antes de usar esto en producción.
   Están todas centralizadas en ese único archivo para que sea fácil de editar.

## Cómo correrlo (yo no tengo acceso a pub.dev/Flutter SDK en este entorno para compilarlo)

```bash
flutter pub get
flutter run -d chrome   # o -d windows / -d android, según tu setup
```

Necesitas un archivo `.env` en la raíz del proyecto con:
```
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_ANON_KEY=tu-anon-key
```

## Supuesto que hice para `fetchBitacora()`

Para mostrar el **nombre** del usuario (no solo su ID) en el historial, intento un
`select` contra una tabla `usuarios` con columnas `id, nombre`. Si esa tabla no existe
o el nombre real es distinto, el `try/catch` lo absorbe silenciosamente y simplemente
se muestra el ID crudo — no rompe nada, pero si tu tabla se llama distinto avísame el
nombre real y lo ajusto.

## Pendiente / siguientes pasos sugeridos

- Reportes imprimibles por fecha (mencionaste que se puedan imprimir informes).
- Pantalla de gestión de usuarios para que el gerente cree cuentas nuevas.
- Calibrar `receta_model.dart` con las fórmulas reales de cada sabor.
- Correr `flutter analyze` de tu lado y mandarme cualquier error de compilación
  que salga — no pude probar el build en este entorno.
