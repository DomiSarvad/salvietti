# Salvietti Control — convenciones del proyecto

App Flutter (`lib/`) + Supabase (`supabase/`). Las carpetas `app/`, `components/`,
`middleware.ts`, `lib/*.ts(x)` y `lib/supabase/*.ts` son de un proyecto Next.js
aparte: no forman parte de la app Flutter.

## Arquitectura: capas con separación de responsabilidades

Patrón Service–Repository, organizado por módulo (feature-first). Todo módulo
nuevo sigue esta estructura; el código anterior se migra cuando se toca ese módulo.

```
lib/
  core/                     transversal, sin depender de ningún módulo
    constants.dart          roles, áreas, colores, validaciones
    modulos.dart            ids de módulos y acciones (= tabla app_modulos)
  shared/                   widgets y utilidades reutilizables (hoy en lib/widgets, lib/utils)
  features/
    <modulo>/               ej. inventario, recepciones, jarabes, soplado, calidad, mermas
      models/               datos puros: campos, fromMap/toMap. Sin Supabase, sin UI.
      repositories/         ÚNICO lugar que habla con Supabase/Hive. Sin reglas de negocio.
      services/             reglas de negocio, validaciones, permisos; orquesta repositorios.
      screens/              pantallas: solo UI y llamadas al service.
      widgets/              widgets propios del módulo.
supabase/
  schema_vNN_<modulo>.sql   una migración por módulo, re-ejecutable (idempotente).
```

Código legacy (aún por migrar): `lib/models`, `lib/services`, `lib/screens`, `lib/widgets`.

### Reglas de dependencia

`screens → services → repositories → Supabase/Hive`. Los `models` los usan todas las capas.

- Una pantalla **nunca** importa `supabase_flutter` ni un repositorio; habla con su service.
- Un repositorio **no** valida ni decide: consulta, inserta, actualiza, llama RPC y devuelve modelos.
- Un service **no** conoce widgets ni `BuildContext`. Recibe sus repositorios por constructor
  (así se prueba con repositorios falsos).
- Las reglas del negocio viven solo en services o en el servidor (ej. diferencia de
  recepción, merma > 3 %, cantidad de receta × preparados).
- Un módulo no importa las `screens` ni los `repositories` de otro; usa su `service` o un modelo.

### Seguridad (no se negocia)

- **El servidor manda.** Toda regla de acceso se aplica con RLS y `tiene_permiso(módulo, acción)`
  (schema_v17). La app solo oculta lo que el rol no puede usar.
- **Denegar por defecto:** sin fila en `permisos_rol` no hay permiso.
- Un módulo nuevo requiere: id en `Modulo` (`lib/core/modulos.dart`), fila en `app_modulos`,
  filas en `permisos_rol`, y políticas RLS que usen `tiene_permiso`. Nunca `rol_actual() = '...'`
  escrito a mano en tablas nuevas.
- Funciones `security definer`: siempre con `set search_path = public, pg_temp`.
- Cambios de permisos solo los hace el Gerente.

### Checklist para un módulo nuevo

1. `supabase/schema_vNN_<modulo>.sql`: tablas, RLS con `tiene_permiso`, módulo y permisos.
2. `features/<modulo>/models/`.
3. `features/<modulo>/repositories/`: acceso a datos.
4. `features/<modulo>/services/`: validaciones, permisos (`usuario.puede(...)`), reglas.
5. `features/<modulo>/screens/` y `widgets/`.
6. Alta en el menú (`app_sidebar.dart`) y en `home_shell.dart`, visible según permiso.
7. Test del service con repositorio falso.

Automatizar todo lo que se pueda (códigos, diferencias, totales, fechas de inicio/fin):
el usuario no debería escribir lo que el sistema puede calcular.

**Cuidado al editar un `schema_vNN_*.sql` que el usuario ya pudo haber ejecutado:**
`create table if not exists` es un no-op si la tabla ya existe — agregarle una columna nueva
al `CREATE TABLE` de un archivo ya publicado NO la agrega a una base donde esa tabla ya se creó.
Cualquier columna nueva en una tabla que un módulo anterior ya creó va como
`alter table ... add column if not exists ...` (en el mismo archivo si todavía no se ejecutó, o en
un parche nuevo si es dudoso), nunca solo agregada al bloque `create table` original.

## Base de datos

Orden de migraciones: `schema.sql` … v16 (roles) → v17 (permisos por módulo) → v18 (inventario
por almacenes) → v19 (catálogo inicial de Jarabes) → v20 (recepciones) → v21 (pedidos y entregas)
→ v22 (arregla recursión infinita de `rol_actual()`, ejecutar cuanto antes: sin ella nadie puede
iniciar sesión) → v23 (bloqueo de login) → v24 (solicitudes a gerencia) → v25 (soplado) → v26
(jarabes) → v27 (calidad) → v28 (ajustes de soplado) → v29 (privilegios de tabla) → v30 (Almacén
General reordenado por tipo, no por material, y movimientos manuales con reversión) → v31 (migra el
stock real de las tablas legacy `tapas`/`preformas`/`materia_prima` a `inv_items`/`inv_movimientos`;
no las borra, quedan de respaldo; lo que no se puede clasificar automático cae en una categoría
"Sin clasificar (migrado)" para reubicar a mano). El menú "Inventario anterior" ya se sacó de
`app_sidebar.dart`/`home_shell.dart`; el Dashboard (Inicio) todavía lee de las tablas legacy y va a
quedar con números congelados hasta que se lo pase a `inv_existencia` (pendiente).
→ v32 (Llenadora) → v33 (Codificación) → v34 (Registro de salidas). Las tres son "corridas" al
estilo Soplado, pero SIN descontar inventario: las tapas/solvente/tinta que reportan ya se
descontaron de Almacén General cuando Almacén les entregó el pedido (Módulo 3); estas pantallas
solo registran el consumo para el informe de mermas (Módulo 9). `v34` además calcula el total de
botellas del reporte diario con la fórmula de cajas/paletas (PET completo; en Vidrio falta la
equivalencia de "filas" por palet, así que ese total queda parcial hasta tenerla).
→ v35 (Mermas): consolida en una vista (`mermas_consolidado`) la merma que ya sale de
soplado/llenadora/codificacion (cada una con su propio "producido") con un registro nuevo
(`mermas_registros`) para las áreas que no tienen corrida propia (Jarabes, Calidad y "Vidrio" — esta
última sin rol propio en el organigrama, la carga Jefe de Producción o Gerente hasta que se
confirme quién debe hacerlo: es lo menos validado del módulo). Alerta cuando la merma supera el 3 %
de lo producido.
→ v36 (Soda Cáustica): en vez de un stock aparte, Soda Cáustica pasa a ser un almacén más de
`inv_almacenes` (como Jarabes/Soplado) — así reutiliza el Módulo 1 (catálogo, stock) y el Módulo 3
(recibe por pedido) sin código nuevo. Solo agrega `soda_entregas` (a quién se le entregó, con
constancia en PDF obligatoria por ser producto peligroso) y la función `soda_registrar_entrega`,
que descuenta el almacén por lote igual que un pedido. La "merma propia" de Soda Cáustica (sección
14.5) queda pendiente: la tabla de causas por área (14.4) no la define.
→ v37 (doble aprobación de recetas + clave del Gerente): el cambio de receta ya no se aprueba con
un solo visto bueno — Control de Calidad Y Jefe de Producción aprueban por separado
(`jarabes_receta_aprobar_calidad`/`_produccion`, cada una exige el rol exacto) y recién con las dos
el Gerente confirma con `jarabes_receta_confirmar_gerente`, que vuelve a pedir su contraseña
(`_verificar_clave_actual`, compara contra `auth.users.encrypted_password` con `crypt()`/bcrypt —
no alcanza con la sesión abierta). Se borró `jarabes_receta_aprobar` (el de un solo paso); las
recetas ya `activa` con la regla vieja no se tocan. El lado Flutter de Jarabes (repositorio,
service, `ResolverRecetaDialog`) se actualizó junto con esto — no queda ningún call site viejo.
→ v38 (Informe general de Producción): vista de solo lectura (`informe_produccion_resumen`) que
compara lo esperado (`jarabes_preparados` × `sabores.estandar_cajas`) contra lo producido
(`salidas_reporte_detalle` convertido a cajas); el detalle de merma por área sale de
`mermas_consolidado` (v35), al que se le agregó `sabor_id` al final (columna nueva seguro con
`create or replace view`, no rompe lo que ya la usaba). La comparación es por fecha exacta entre
preparado y embotellado — aproximación marcada como pendiente de validar con Producción.
→ v39 (devolución de un pedido, mejora del Módulo 3): `inv_registrar_devolucion` regresa a Almacén
lo que sobró de una línea ya entregada (`inv_devoluciones`); lo hace Almacén (`entregas:crear` +
operar ese almacén), no el área que lo recibió. No puede devolverse más de lo entregado menos lo ya
devuelto. Wireado en Entregas: `LineaPedido.cantidadDevuelta`/`disponibleParaDevolver`, botón por
línea cuando el pedido ya se entregó.
→ v40 (salida directa de Almacén, mejora del Módulo 1): `inv_registrar_salida_directa` para
insumos que salen sin pedido formal ni firma (ej. termocontraíbles) — pide cantidad de rollos
(solo referencia) y peso real (lo que de verdad descuenta el stock, FIFO por lote, igual que una
entrega). Botón "Salida directa" en Almacenes, visible solo en Almacén General.
→ v41 (tiempo real del Inicio): agrega `inv_movimientos`, `mermas_registros`, `mermas_causas`,
`llenadora_corridas`, `soplado_corridas` y `codificacion_corridas` a la publicación
`supabase_realtime` (con un chequeo antes de cada `alter publication ... add table`, porque falla si
la tabla ya está agregada). Sin esto las suscripciones de `DashboardRepository.escucharStock`/
`escucharMermas` quedan abiertas pero nunca reciben nada — hay que correrlo una vez por proyecto de
Supabase (Realtime se habilita a nivel tabla, no alcanza con las políticas RLS).
→ v42 (saldos + presencia + tiempo real de Jarabes): (1) **Saldos mantenidos al día**: hasta v41,
`inv_stock`/`inv_stock_lote` (y por lo tanto `inv_existencia`) sumaban TODO `inv_movimientos` en
cada lectura — más lento cada año. Ahora un trigger (`trg_inv_movimiento_saldo`) suma/resta cada
movimiento a `inv_saldos` (ítem+almacén) e `inv_saldos_lote` (lote+almacén) en la misma transacción
(`on conflict do update set cantidad = cantidad + x`, atómico por fila), y las tres vistas leen de
ahí con las MISMAS columnas (nada de la app cambia). Se eligió esto en vez de un "cierre semanal":
siempre al día, sin proceso programado, y una corrección con fecha vieja no obliga a reabrir
semanas. `inv_movimientos` sigue siendo el historial completo y la fuente de verdad;
`select public.inv_reconstruir_saldos();` reconstruye los saldos desde cero (se corre sola al
ejecutar v42, que es re-ejecutable). Índices nuevos para lo que todavía mira el historial pero
acotado: salidas de los últimos 30 días (consumo) y último conteo por ítem. **Ojo:** volver a correr
v18/v18b/v25 recrea esas vistas sumando el historial — después hay que volver a correr v42. Las
funciones que validan stock (`select sum(...) ... where item_id = ...`) se dejaron como estaban:
filtran por ítem con índice, no crecen con el total. (2) **Presencia**: `app_presencia` +
`presencia_latido`/`presencia_salir`/`presencia_listar` (ver "Presencia de las áreas" más abajo).
(3) Agrega `jarabes_preparados`/`jarabes_recetas` a `supabase_realtime`.

→ v43 (pedidos de compra): `compras_pedidos` + `compras_pedido_lineas` (varias líneas por pedido),
módulo `compras` (Almacén ver/crear, Gerente ver/aprobar, Jefe de Producción ver), toda escritura por
`compras_crear_pedido(p_motivo, p_lineas jsonb)` / `compras_resolver` (rechazo exige respuesta) /
`compras_anular` (solo quien lo hizo y pendiente). No mueve stock (eso es Recepciones). Agrega
`compras_pedidos` y `solicitudes_gerencia` a `supabase_realtime` para la campana.

→ v44 (arreglo): pgcrypto vive en el esquema `extensions` de Supabase y las funciones `security definer`
que la usan fijaban `search_path = public, auth, pg_temp`, así que no la encontraban: "Nuevo usuario"
fallaba con `function gen_salt(unknown) does not exist` (`crear_usuario_admin`) y la confirmación de
recetas del Gerente igual (`_verificar_clave_actual`). v44 les agrega `extensions` con `alter function
... set search_path` (v16/v37 también corregidos). Toda función nueva que use `crypt`/`gen_salt` lleva
`extensions` en su search_path.

### Gerente: Informes, campana y menú (2026-10-23)

- **Menú**: `Rol.soloInformes` (`{gerente}`) + `Usuario.soloInformes`: el sidebar oculta las pantallas
  de trabajo de cada área (Almacenes, Recepciones, Entregas, Compras, Solicitudes, Soplado, Jarabes…)
  para esos roles. Es solo presentación: NO se le sacaron permisos `ver` (los informes leen esas
  tablas y las políticas RLS los exigen), y las rutas siguen abriéndose desde la campana.
- **Informes** (`features/informes/`): `InformesService.construir(area, rango)` arma KPIs + series +
  tabla por área, solo con lo FINALIZADO; semana = barra por día (lun…dom), mes = barra por semana,
  año = barra por mes, "Por fechas" (`RangoInforme.entre`, no pasa de hoy) = por día hasta 31 días, por
  semana hasta ~4 meses, por mes si es más largo (`RangoInforme`). **Proyección**
  (`InformesService.proyectar`): si el período está en curso, cada serie se estima al cierre al ritmo
  promedio por día de lo que va (hoy cuenta); se dibuja apilado y claro sobre la barra real, con una
  tarjeta "Proyección al cierre de…" y columnas "(estimado)" en el Excel. Todas las series son sumas,
  por eso se puede proyectar así; una serie nueva que sea un promedio NO se debe proyectar con esto.
  Controles con el mismo aspecto que `BarraFiltros`: buscador de texto + PDF/Excel, selector "Ver por"
  (Semana/Mes/Año, `periodoBase`) con flechas, y Desde/Hasta que siempre muestran el rango visto
  (elegir uno pasa a "Fechas"; la x vuelve al selector, `quitarFechas`). La búsqueda
  (`InformesService.construir`) es dos cosas: si nombra un INDICADOR (etiqueta de KPI o nombre de
  serie, ej. "botellas producidas") se ven solo esos KPIs/series/filas de la tabla que lo nombran, con
  todos los datos (`InformeArea.soloIndicadores`); si no, filtra las FILAS antes de calcular (todo el
  texto de la fila y sus joins, menos la fecha), pasado por una `Zone` (`_zonaTextoFilas`) y no por
  un campo, porque una recarga en tiempo real puede armarse a la vez que otra. `InformeArea.busqueda`
  va al encabezado y al nombre del archivo. Sin texto aclaratorio debajo del buscador (lo pidió el
  usuario). **Gráfico** (2026-10-25): en un período en curso se dibuja solo hasta la barra de hoy
  (`InformeArea.barrasHastaHoy`, lo pone `proyectar`): antes el año mostraba noviembre/diciembre con
  lo estimado y parecía que hubo movimiento; lo que falta del año solo va en la tarjeta de proyección.
  Botón "Ver más grande" (`_Grafico.ampliar`): pantalla completa, en el celular la pone horizontal y
  la restaura al cerrar. **Comparar** (`InformesService.comparar`): arma también `rango.anterior()`
  (mes pasado, año pasado…) y lo pone al lado en el mismo tono claro (`InformeArea.conAnterior`, ajusta
  el largo: un mes tiene 4 o 5 semanas), más la tarjeta `_Comparacion` "a la misma altura" (si el
  período está en curso compara solo hasta hoy en los dos, ej. Ene–Oct contra Ene–Oct). Va al PDF y
  al Excel (columna "(período anterior)").
- **Solicitudes como mensajería** (2026-10-25, solo el aspecto, sin tabla nueva: sigue siendo un
  pedido y una respuesta): la lista es una bandeja de conversaciones (`FilaConversacion`) y cada una se
  abre como chat (`ConversacionSolicitud`, pantalla propia con el mismo service): el pedido es el primer
  mensaje, la respuesta de Gerencia la contestación, lo propio a la derecha; si está pendiente y se
  puede aprobar, abajo hay una caja de respuesta con Rechazar/Aprobar (reemplazó a
  `ResolverSolicitudDialog`, borrado). Pestañas por rol (`SolicitudesService.bandejas`): el Gerente no
  tiene "Mis solicitudes" (no pide, solo tiene `solicitudes:ver`). La constancia PDF solo cuando ya se
  resolvió (`puedeImprimir`), aprobada O rechazada (con "Motivo del rechazo" y el estado en un recuadro
  de color), y es opcional. Áreas: General (resume las demás), Jarabes, Soplado/Llenadora/Codificación
  (`_corridas`, misma forma: producido vs merma, alerta > 3 %), Calidad, Producción terminada
  (`salidas_planilla`), Mermas (`mermas_consolidado`), Almacén (cuenta movimientos, no unidades, +
  pedidos de compra si hay v43), Soda Cáustica. `InformesExportService`: PDF (mismo estilo que el
  reporte de inventario, con `pw.Chart` de barras) y Excel (números como números). Ítem "Informes"
  del menú, con permiso `informe_produccion:ver`. Se actualizan en vivo (`InformesRepository.escucharCambios`
  sobre todas sus tablas, recarga silenciosa con debounce de 1 s); v43 agrega a la publicación las que
  faltaban (`calidad_analisis`, `salidas_reportes`, `salidas_reporte_lineas`, `soda_entregas`).
- **Campana flotante** (`features/notificaciones/`, `CampanaFlotante` como `floatingActionButton`
  de `HomeShell`, abajo a la derecha): `CampanaService` cuenta pendientes por rol (compras por
  aprobar, solicitudes por resolver, recetas que esperan al Gerente / a Calidad / a Producción) y las
  respuestas propias de los últimos 14 días no vistas (vistos por usuario en Hive `preferencias`).
  Realtime sobre `compras_pedidos`/`solicitudes_gerencia`/`jarabes_recetas` + refresco cada 2 min.
  Tocar una fila navega a la ruta donde se resuelve.
- Tests: `compras_service_test`, `informes_service_test`, `informes_export_test`, `campana_service_test`.

### Informe general de Producción interactivo y perfil a pantalla completa (2026-10-26)

- `informe_produccion_resumen` se pedía con `.limit(200)` SIN orden (quedaban 200 filas cualquiera,
  podían faltar los días nuevos): ahora `order(fecha desc, sabor)`, y el service además ordena.
- `InformeService`: `filtro` (BarraFiltros: sabor + Desde/Hasta), `soloDesvio`, `filtrados`, `porDia`
  y `totales` (cajas esperadas/producidas, desviación total, cuántos con desvío > 3 %).
- Pantalla: totales arriba, filtros, lista agrupada por día ("Hoy", "Ayer", fecha) con barra de
  avance producido/esperado; tocar abre `_Detalle` a pantalla completa (desviación grande con su
  explicación, preparados/esperado/producido, aviso de datos incompletos, merma por área con barras
  y motivo). El `PasoAyuda` envuelve solo los totales: antes envolvía la lista y mantener apretada
  una fila mostraba el globo encima de los datos.
- **Páginas en el celular**: `abrirPaginaODialogo` (`lib/shared/pagina_o_dialogo.dart`) abre un formulario
  como página a pantalla completa con barra NEGRA y flecha de volver (< 600 px) o como ventana en la
  compu. Lo usan Mi perfil (`PerfilDialog(comoPantalla:)`) y el alta/edición de Usuarios
  (`UsuarioFormDialog(comoPagina:)`); en modo página `DialogBanner` va sin X (`onCerrar: null`). Las
  pantallas de detalle propias (Informe de Producción, conversación de Solicitudes) usan la misma barra
  negra. Un formulario grande nuevo, igual.

### Solicitudes como mensajería (2026-10-25)

Solo el aspecto (decisión del usuario): sigue siendo un pedido y UNA respuesta, sin tabla nueva.
La lista es una bandeja de mensajes (`FilaConversacion`: avatar con iniciales, asunto, último
mensaje, hora, punto de color por estado) y tocar una fila abre `ConversacionSolicitud` (pantalla
propia, mismo service con `ChangeNotifierProvider.value`): el pedido es una burbuja, la respuesta de
Gerencia otra (propia a la derecha), y si está pendiente y quien mira aprueba, abajo hay una caja de
texto con Aprobar/Rechazar — reemplazó a `ResolverSolicitudDialog` (borrado). Pestañas según el rol
(`SolicitudesService.bandejas`): el Gerente no tiene "Mis solicitudes" (no pide), quien pide no tiene
"Por aprobar". La constancia PDF solo cuando ya se resolvió (`puedeImprimir`), aprobada O rechazada
(el usuario quiere el rechazo en papel, con "Motivo del rechazo"), y siempre opcional; el PDF
destaca el estado en un recuadro de color.

### Buscador común de las listas (texto + Desde/Hasta + PDF/Excel)

Todas las listas con historial usan el mismo buscador, como pidió el usuario (modelo: un sistema con
"Buscar" arriba, "Desde/Hasta" abajo y botones PDF/Excel):
- `lib/shared/filtros/filtro_lista.dart` — `FiltroLista` (texto: todas las palabras en cualquier orden,
  sin tildes; Desde/Hasta incluyen el día entero; `describir()` para el encabezado del reporte).
- `lib/shared/filtros/barra_filtros.dart` — `BarraFiltros(filtro, onCambio, reporte, hint)`: el widget
  (aplica el texto 250 ms después de dejar de escribir; si Desde > Hasta los da vuelta solo) y
  `SinResultados` (≠ "todavía no hay registros").
- `lib/shared/reportes/reporte_tabla.dart` — `ReporteTabla` con VALORES (num/DateTime/null, no texto)
  + `ReporteTablaExport.pdf/excel`: en el PDF se formatean, en Excel los números quedan como número.
- Cada service tiene `filtro`, `filtrar()`, una lista `…Filtrado(s)` y `reporte()` (lo filtrado = lo
  que se imprime). Puesto en Soplado, Llenadora, Codificación, Jarabes, Calidad, Mermas, Soda Cáustica,
  Pedidos de compra, Solicitudes, Entregas y Recepciones (reemplazó su buscador propio; el filtro "Con
  diferencia" se suma) y Almacenes (ver abajo). En Pedidos de compra el filtro por estado pasó a llamarse `filtroEstado`/`filtrarEstado`.
- `fmtNum` pasó a formato es-BO real: punto para miles, COMA para decimales (antes usaba punto para las
  dos cosas: 1234,5 se veía "1.234.50"). Un campo editable NO se precarga con `fmtNum` (se rompe la
  lectura con separador de miles): ver `devolucion_dialog.dart`.
- El Gerente no ve el filtro "Pedido" de Almacenes (`InventarioService.muestraFiltroPedido`).
- **Almacenes** también usa `BarraFiltros` (se sacó "Ver todo" y el PDF propio; `InventarioPdfService` se
  borró): el texto es la búsqueda de siempre; las FECHAS muestran los ítems que tuvieron movimiento en
  ese período con sus entradas/salidas (`InventarioRepository.movimientosPeriodo`, suma
  `inv_movimientos` por ítem en [desde, hasta+1 día); ajustes según su signo), columnas extra en la
  tabla y en el reporte. Sin filtros, en la raíz se ven solo las categorías, pero el PDF/Excel sale
  con TODO el almacén (eso reemplaza a "Ver todo" para el reporte completo).

### Presencia de las áreas y tiempo real en Jarabes/Soplado

Problema real que lo motivó: si Soplado se queda sin internet y registra que se acabaron las
botellas, eso queda en su compu (cola offline) y Jarabes, con internet, sigue viendo el avance viejo
y decide con un dato que ya no es real. Ningún sistema puede mostrar lo que otra compu no subió, pero
sí puede avisar que existe:
- `features/presencia/`: cada app manda un latido por minuto (`presencia_latido`, con cuántos
  registros tiene sin subir); `PresenciaService` vive toda la sesión (provider en `main.dart`, lee
  `pendientes`/`online` de `SyncService`, y manda un latido extra apenas cambian los pendientes o
  vuelve la red). "Sin señal" = más de 3 min sin latido, calculado con el reloj del SERVIDOR
  (`presencia_listar` devuelve `segundos_sin_senal`: los relojes de las compus pueden estar corridos).
  Se consulta cada minuto, NO por Realtime (un latido por persona por minuto reenviado a todos
  gastaría la cuota de mensajes de Supabase). Cerrar sesión llama `presencia_salir` para no aparecer
  "sin señal"; cerrar la app sin cerrar sesión sí aparece así (el texto lo aclara). En `ClienteOffline`,
  `presencia_latido`/`_salir` están en `_rpcSoloEnLinea` (un latido viejo no sirve, nunca a la cola) y
  `presencia_listar` en `_rpcLectura`.
- `AvisoConexionAreas(roles: [...])`: banda ámbar junto a datos de otra área, no ocupa lugar si todo
  está bien. Puesta en Jarabes (avance de Soplado), Llenadora (Jarabes + Soplado), Codificación
  (Llenadora) e Inicio (todas). No muestra nada si ESTE dispositivo está sin red (lo que sabe de los
  demás es viejo; el aviso propio ya está en la barra).
- **Tiempo real**: Jarabes (`jarabes_preparados`, `jarabes_recetas`, `soplado_corridas`) y Soplado
  (`soplado_corridas`) se refrescan solos como el Inicio: `escucharCambios` en el repositorio,
  recarga silenciosa (sin spinner; si falla, se siguen viendo los datos) con debounce de 400 ms.
  `Suscripcion` y el helper `escucharTablas` se movieron a `lib/shared/realtime.dart` (el Inicio
  también lo usa); además recarga al RECONECTAR el canal, porque lo que cambió durante un corte no
  llega por Realtime. Las demás pantallas siguen cargando al entrar.

El **Inicio** (`features/dashboard/`) ya no lee las tablas legacy (`InventarioService.listarTodo`,
`MovimientoService.listarRecientes`): se migró a datos en vivo de `inv_existencia`/
`inv_movimientos`, agrupados por almacén (General/Jarabes/Soplado/Soda Cáustica) en vez de por las
áreas viejas (tapas/preformas/materia prima). El plan de producción del día sigue con
`ProduccionService`/`plan_produccion` (legacy, sin tocar — es un subsistema aparte, no parte de
esta migración). El botón "Deshacer" de movimientos NO se repitió acá: un movimiento manual se
revierte desde Almacenes (`MovimientosDialog`), no desde el Inicio. Se agregó
`Modulo.inventarioSodaCaustica` a `Modulo.inventarios`, e `InventarioService.iniciar()`/
`AlmacenesScreen` aceptan un almacén inicial, para que una tarjeta del Inicio abra Almacenes ya con
ese almacén seleccionado.

Las tarjetas de almacén del Inicio (`ResumenAlmacen.estado`) ya no se pintan por identidad del
almacén: se pintan en semáforo (verde/amarillo/rojo, con `SemaforoStock.color`) según el peor ítem
de ese almacén — así se ve de un vistazo si hay algo mal, sin entrar. Los colores por almacén
(`_colorDe` en `dashboard_screen.dart`) se mantienen solo en los gráficos (torta de "Movimientos
por almacén" y barras de "Ítems con menor stock"), para poder distinguir de qué almacén es cada
sección. "Ítems con menor stock" (`DashboardService.menorStock`) ordena primero por situación
(crítico → bajo → óptimo → sin datos) y recién dentro de cada grupo por cantidad — antes ordenaba
solo por cantidad absoluta, así que un ítem del catálogo en 0 sin consumo cargado (que no es
necesariamente un problema) tapaba a los que sí estaban realmente críticos.

El Inicio agrega un gráfico de barras de **Mermas por área** (visible solo con permiso
`mermas:ver`, `DashboardService.mermasPorArea`), con el % promedio de merma de cada área sobre
`mermas_consolidado` (v35), una línea de referencia en el 3 % y las barras en rojo cuando esa área
tiene algún evento en alerta. Tanto este gráfico como las tarjetas de stock y los demás gráficos se
actualizan solos, sin refrescar la pantalla: el service
se suscribe con Supabase Realtime (`DashboardRepository.escucharStock`/`escucharMermas`, envueltas
en una `Suscripcion` propia para no acoplar el repositorio a `RealtimeChannel` y poder seguir
probando el service con un repositorio falso) y recarga esa parte del Inicio con un debounce de
400 ms cuando hay un cambio. Requiere haber corrido v41.

En **Almacenes** (`features/inventario/`), el buscador (`InventarioService.visibles`) deja de
limitarse a la categoría abierta apenas hay algo escrito: antes, si estabas dentro de "Tapas" y
buscabas un ítem que en realidad está en "Ácidos", no aparecía nada (parecía que "no buscaba bien").
Ahora, con texto en el buscador, se ignora `categoriaFiltro` y se busca en todo el almacén
(`buscandoEnTodoElAlmacen` lo indica para mostrar el aviso en pantalla); al borrar la búsqueda se
vuelve a ver la categoría de antes. La búsqueda también exige todas las palabras escritas, en
cualquier orden ("tapa negra" encuentra "Tapa Short Negra"). Además, al entrar a una categoría con
subdivisiones, la tabla de abajo ya muestra TODOS los ítems de esa categoría y las que cuelgan de
ella (no hace falta bajar hasta la hoja del árbol) — se agregó un texto aclarando esto, porque no
era obvio y llevaba a creer que había que seguir entrando a cada subcategoría para ver algo.

(Reemplazado por `BarraFiltros`, ver "Buscador común de las listas".) Antes, al lado del buscador de
Almacenes había un botón "Imprimir reporte" (ícono de PDF, `_Cabecera._imprimir`) que generaba un PDF apaisado con EXACTAMENTE lo que se está viendo en la tabla
en ese momento — el buscador (y la categoría, y el filtro "Pedido") funcionan como el filtro del
reporte, no hace falta armar uno aparte. `InventarioPdfService.reporte()`
(`features/inventario/services/`) arma la tabla (código, detalle, ubicación, stock, mínimo, días,
estado) con el mismo estilo que `ReporteService` (legacy, para movimientos: logo de marca de agua,
encabezado con los filtros aplicados, pie con paginado) y se guarda con `ArchivoService.guardar`
(descarga en web, panel de compartir en celular, carpeta Descargas y se abre solo en escritorio).
Deshabilitado (sin ocultarse) cuando no hay una tabla que mostrar (`InventarioService.mostrarTabla`
en falso, ej. parado en la raíz sin buscar nada) — abajo explica por qué con el tooltip.

`features/jarabes/` muestra el plan del día de Producción (`ProduccionService.planDeHoy`, el
subsistema legacy de `lib/screens/produccion/`) como una tarjeta de solo lectura arriba de todo
(`_SeccionPlanDelDia`), y en "Nuevo preparado" (`IniciarPreparadoDialog`) ordena el desplegable de
sabor poniendo primero los que están en ese plan (con un ícono 📅), comparando nombres con
`sinTildes`. Es a propósito solo una referencia visual: NO restringe qué sabor se puede elegir,
porque durante el día puede cambiar lo que hace falta preparar — la única restricción real sigue
siendo la de stock (`VerificacionInsumos`, ya existía: si falta insumo para la receta, bloquea
"Iniciar" y ofrece mandar la solicitud a Almacén ahí mismo). Si falla la carga del plan (sin
conexión, o no hay plan cargado hoy) la tarjeta simplemente no aparece; Jarabes sigue funcionando
igual.

**Plan del día y WhatsApp (2026-10-24)**: el plan se GUARDA en el sistema (las áreas trabajan con
esos datos: Jarabes, Inicio, "Marcar hecho" con su descuento de stock), pero la FOTO de la planilla no:
`ConstructorPlanDialog` ahora termina en "Guardar y compartir", y `ProduccionPlannerScreen._armarPlan`
recarga el plan y abre solo `ProduccionCapturaDialog`, cuyo botón principal es "Compartir por WhatsApp"
(`Share.shareXFiles` con la imagen en memoria, no queda archivo). "Descargar" (`FileSaver`) queda al
costado, solo si la persona lo pide — antes, si no había panel de compartir, se guardaba sola. Pedido
explícito del usuario: es diaria y llenaría el almacenamiento. El historial de planes se ve en
**Informes → Plan de producción** (`InformesService._plan`: una fila por producto de cada día, con
paquetes/botellas/litros planificados vs producidos; a diferencia del resto de Informes incluye lo
pendiente, que es lo que interesa; alerta si el cumplimiento < 90 %). El rol que arma el plan es
`jefe_produccion` (el "ingeniero" de v2; el usuario lo llama "jefe de ingeniería").

El menú lateral tiene "Producción del día" (antes "Producción", a secas) justo después de "Inicio"
en vez de casi al final: es lo que el Jefe de Producción entra a hacer todos los días, no algo
ocasional como Usuarios o Historial.

En "Armar plan de producción" (`constructor_plan_dialog.dart`, legacy), "Total botellas" y "Total
litros" dejaron de ser de solo lectura: siguen calculándose solos a partir de la cantidad, pero se
pueden pisar a mano si el dato real es otro (`_FilaPlan.totalesManuales`); cambiar el producto de
la fila fuerza a recalcular, para no arrastrar un valor manual que ya no corresponde.

Desde "Producción del día" (`ProduccionPlannerScreen`) se puede tocar un producto (o su ícono de
gota) para ir directo a Jarabes con ese sabor ya elegido en "Nuevo preparado", listo para escribir
la cantidad y ver si alcanza el insumo — sin tener que ir a Jarabes y buscarlo de nuevo. El puente
es `HomeShell._abrirJarabesConSabor` (guarda el nombre del sabor en `_saborJarabesInicial`, lo pasa
a `JarabesScreen.saborInicial`); adentro, `_VistaState._abrirAutoSiCorresponde` lo busca por nombre
(`sinTildes`) en `svc.sabores` y abre `IniciarPreparadoDialog` una sola vez por entrada a la
pantalla (con `addPostFrameCallback`, para no disparar el diálogo en medio de un build). Si el
nombre no matchea ningún sabor del catálogo de Jarabes, el diálogo igual se abre pero sin sabor
preseleccionado — no rompe nada, solo no ahorra el paso.

Ese auto-abrir pasa una sola vez por entrada a la pantalla (`_autoAbierto`): si alguien lo cierra
sin querer (tocando afuera, "Cancelar"), no vuelve a abrirse solo. Para eso, la tarjeta "Plan de
hoy" que ya se mostraba en Jarabes ahora tiene cada fila tocable (`_SeccionPlanDelDia.onPreparar`,
repetible las veces que haga falta): tocar un producto del plan abre "Nuevo preparado" con ese
sabor, sin pasar de nuevo por Producción.

El menú lateral tiene "Jarabes" justo después de "Producción del día" (era el octavo ítem, ahora
el segundo): es el módulo que más se usa después del plan del día. La tarjeta "Plan de producción
de hoy" del Inicio (`DashboardScreen._cardPlanDelDia`) ahora es tocable entera (no solo el link
"Ver todo →") para ir a esa pantalla — usa el mismo patrón de callback que `onAbrirInventario`
(`DashboardScreen.onAbrirProduccion` → `HomeShell._abrirProduccion`), en vez del `Navigator.push`
que tenía antes, para quedar dentro del mismo shell (sidebar, migas de pan) en lugar de una
pantalla suelta sin ellos.

Al **finalizar un preparado en Jarabes** (`FinalizarPreparadoDialog._completarPlanSiCorresponde`),
si su sabor está en el plan de hoy y ese producto todavía no está tildado, se marca solo como
completado en Producción (`ProduccionService.marcarComoCompletado`) — antes había que ir a
Producción del día y tildarlo a mano de nuevo. Las botellas se estiman con los litros del preparado
sobre `litros_por_botella` (mismo cálculo que ya usaba el diálogo manual "Marcar hecho" como
default); si falla (sin plan, sabor no matchea, sin `litros_por_botella` cargado) no avisa error —
cerrar el preparado de Jarabes no depende de este paso. Esto es seguro respecto del descuento de
stock: el trigger `trg_completar_plan_detalle` (schema.sql/v6) solo descuenta materia
prima/preforma/tapa la PRIMERA vez que pasa a `completado` (`old.completado is distinct from
true`), así que la estimación se puede corregir después sin volver a descontar dos veces. Por eso
el chip "Completado" en Producción del día ahora también es tocable (si el rol puede editar) para
reabrir el mismo diálogo precargado con lo guardado y corregir botellas/merma con el dato real de
embotellado, en vez de quedar fijo con la estimación.

Ese cruce automático depende de encontrar una fila sin completar en el plan con el mismo sabor —
si no la encuentra (nadie planificó ese sabor hoy, o ya estaba tildada), no avisa nada. Para que
Jarabes tenga su propia confirmación de "ya hice esto hoy" sin depender de ese cruce (que puede no
aplicar), `_VistaState._saboresYaPreparadosHoy` mira directamente `svc.preparados` (finalizados,
de hoy) y le agrega a cada fila de "Plan de hoy" un aviso "Jarabes listo" en azul cuando corresponde
— aunque el producto siga "pendiente" ahí (eso lo tilda quien termina de embotellar, no Jarabes:
son responsabilidades distintas, a propósito). Además, como el `_plan` que arma esa tarjeta se
cargaba una sola vez al entrar a la pantalla, finalizar un preparado ahora dispara
`_TarjetaPreparado.onFinalizado` → `_VistaState._cargarPlan()` para refrescarlo al toque; si no,
el tilde/aviso solo aparecía recién al salir y volver a entrar a Jarabes.

Corregir botellas/merma de un producto ya `completado` (chip tocable de arriba) NO vuelve a ajustar
el stock: el trigger solo descuenta la primera vez. El diálogo lo avisa en el texto, pero si algún
día se necesita reconciliar stock real contra estimado, hace falta un ajuste manual aparte (no está
automatizado a propósito, para no tocar lógica de descuento de stock sin que Almacén lo revise).

## Bugs encontrados y corregidos (revisión de código, 2026-09-29)

Barrido de 15 agentes en paralelo sobre todo lo tocado esta sesión (tracked + `lib/features/` +
SQL nuevo). Lo que se corrigió:

- **`lib/services/movimiento_service.dart`** (`puedeDeshacerse`): comparaba `cantidad` (con signo)
  contra el límite del 20 % sin `.abs()` — un ajuste NEGATIVO grande (ej. -1000 con 5 de stock)
  siempre pasaba como "chico" y habilitaba deshacerlo con un clic, saltándose el tope de seguridad.
  Nota: esta pantalla (Inventario legacy) está huérfana de navegación hoy (`home_shell.dart` ya no
  la rutea), pero el bug queda corregido igual por si se reconecta.
- **`lib/services/auth_service.dart`**: (1) `confirmarRecuperacion` no cerraba la sesión temporal de
  recuperación si `verifyOTP` funcionaba pero `updateUser` fallaba después — quedaba una sesión
  autenticada viva sin haber cambiado la contraseña. Ahora se hace `signOut()` también en el catch.
  (2) El filtro de "no es un fallo de login, es un problema de red" no reconocía `TimeoutException`
  — alguien con wifi sin salida real podía autoescalarse a un bloqueo por intentos fallidos sin
  haber escrito mal la contraseña ni una vez.
- **`lib/features/dashboard/`**: (1) "Ítems con menor stock" calculaba `cantidad / 0` cuando los 6
  ítems más bajos estaban todos en cero — `NaN.clamp(0,1)` da `1.0` en Dart, así que las barras se
  veían LLENAS justo cuando el stock estaba peor. (2) El semáforo de una tarjeta de almacén
  (`ResumenAlmacen.estado`) no contaba los ítems "sin datos" (sin consumo cargado) como nada,
  así que un almacén cuyo peor ítem estuviera en 0 pero sin historial de consumo se pintaba VERDE.
  Ahora `situacionDe` marca crítico cualquier ítem con `cantidadSistema <= 0`, tenga o no días de
  existencia calculados. (3) Una vez que `error` quedaba seteado (falla de carga inicial), una
  actualización en tiempo real que sí traía datos frescos nunca lo limpiaba — la pantalla se quedaba
  trabada en "No se pudo cargar" con datos ya recuperados atrás. Ahora las recargas silenciosas
  limpian `error`.
- **`lib/features/llenadora/` y `lib/features/codificacion/`**: `finalizarCorrida` no comparaba
  desechos contra lo producido (a diferencia de Soplado, que sí lo hace) — se podía cargar
  `botellasDesechadas: 500` con `botellasLlenadas: 100` y quedaba guardado, ensuciando
  `llenadora_avance`/`codificacion_avance` con números negativos. Agregada la validación en el
  service Y en el RPC del servidor (`llenadora_finalizar_corrida`/`codificacion_finalizar_corrida`,
  `create or replace function` — no hace falta un patch nuevo, ya estaba publicada la v32/v33).
- **`supabase/schema_v34_registro_salidas.sql`** (vista `salidas_reporte_detalle`): para Vidrio, el
  total de botellas se calculaba SOLO cuando `vid_filas = 0`; cualquier fila con filas cargadas
  (dato normal, no un caso raro) anulaba TODO el total en vez de usar lo que sí se sabe (cajas y
  botellas libres) — subestimando producción en `salidas_planilla` e `informe_produccion_resumen`.
- **`supabase/schema_v40_salida_directa.sql`**: (1) cuando una salida directa tomaba de más de un
  lote (o sin-lote + lote), solo el ÚLTIMO movimiento insertado quedaba con `referencia_id` —
  cualquier reporte que trace stock por ese id perdía las filas anteriores. Se solucionó insertando
  `inv_salidas_directas` ANTES de mover stock, para poder enlazar cada `insert` a `inv_movimientos`
  directamente. (2) Le faltaba el "catch-all" que sí tiene `inv_registrar_movimiento` (v30) para
  cuando el stock "sin lote" quedó negativo: sin él, la función podía devolver éxito habiendo
  descontado menos de lo que `inv_salidas_directas.peso_real` dice que se sacó.
- **`lib/features/recepciones/`**: `crearProveedor` usaba `null` para dos cosas distintas — "nombre
  inválido" Y "error de red/permiso" — así que el diálogo mostraba siempre el mismo mensaje ("2 a 80
  caracteres") aunque el problema real fuera de conexión. Ahora el service deja subir la excepción y
  el diálogo la distingue con su propio mensaje.
- **`lib/screens/produccion/produccion_planner_screen.dart`**: al reabrir un producto ya completado
  para corregirlo (función agregada esta sesión), si `botellasProducidas` era `null` el campo se
  precargaba con el string `"-"` (lo que devuelve `fmtNum(null)` para mostrar en pantalla) — un
  guardado sin tocar ese campo pisaba la producción real con 0. Ahora, sin dato, el campo queda
  vacío en vez de con ese guion.
- **`lib/screens/inventario/inventario_list_screen.dart`** y **`lib/widgets/selector_rol.dart`**:
  cada uno reimplementaba su propio `_sinTildes` local, más pobre que el `sinTildes()` compartido de
  `lib/utils/texto.dart` (a `inventario_list_screen.dart` le faltaba `ü→u`/`ñ→n`; a
  `selector_rol.dart` solo `ü→u`) — ambos reemplazados por el helper compartido.
- **Concurrencia real (encontrado al preguntar "¿aguanta muchos usuarios a la vez?")**:
  `inv_registrar_movimiento`/`inv_revertir_movimiento` (v30), `soda_registrar_entrega` (v36) e
  `inv_registrar_salida_directa` (v40) chequeaban stock disponible con un `select sum(...)` sin
  bloquear el ítem antes de insertar — dos personas descontando el mismo ítem/almacén a la vez
  podían ambas pasar el chequeo y dejar el saldo negativo entre las dos. Las cuatro ahora hacen
  `perform 1 from public.inv_items where id = ... for update;` antes de leer el total, así la
  segunda transacción espera a que la primera termine en vez de leer el mismo saldo stale. No
  cambia ninguna firma ni columna, son `create or replace function` sobre archivos ya publicados —
  no hace falta parche aparte, correr de nuevo v30/v36/v40 alcanza.
- **La misma concurrencia, encontrada después en una revisión de código aparte (quedaba la excusa
  de que "ya bloqueaban el pedido/línea padre", y esa excusa era el bug)**: `inv_entregar_pedido`
  (v21) bloquea la fila de `inv_pedidos` con `for update`, pero eso protege que dos personas entreguen
  el MISMO pedido a la vez — no evita que dos pedidos DISTINTOS (o una entrega y una salida directa,
  o una entrega y la finalización de una corrida de Soplado que consume preforma) descuenten el
  MISMO ítem+almacén al mismo tiempo. Mismo problema en `soplado_finalizar_corrida` (v28): bloquea
  la corrida, no el ítem de preforma que descuenta. Las dos ahora bloquean también
  `inv_items`/`id = (el ítem que van a descontar)` antes de leer el saldo, igual que las cuatro de
  arriba — la lección repetida es que el `for update` tiene que ir sobre la fila del RECURSO que se
  descuenta (el ítem), no sobre la fila de lo que pidió la operación (pedido, corrida): cualquier
  función nueva que reste de `inv_items`/`inv_movimientos` necesita este lock, sin importar qué otra
  cosa ya bloquee.

**Encontrado pero NO corregido** (queda para decidir con más cuidado, no son de solución obvia):
- La constancia en PDF de Soda Cáustica, documentada como "obligatoria" (v36), no está impuesta en
  ningún lado: se puede registrar una entrega y cerrar el diálogo sin nunca generar el PDF (el botón
  vive aparte, en el historial, opcional). Corregirlo implica decidir el flujo (¿bloquear el cierre
  del diálogo hasta confirmar que se descargó?, ¿generarlo solo automáticamente?) — decisión de
  producto, no un bug de una línea.
- Si `PermisosService.delRol` falla (red, o falta el grant de v29), `Usuario.permisos` queda `null`
  y varias reglas viejas (`puedeVerInventario`, entre otras) caen a un fallback más permisivo que el
  nuevo modelo por módulo — mientras que el ítem "Almacenes" del menú, más nuevo, exige
  `permisos != null` y se oculta directamente. Son dos respuestas distintas a la misma falla
  (mostrar de más vs. esconder de más); cuál es la correcta depende de qué tan seguido falla
  `delRol` en la práctica, no se tocó sin ese dato.
- Los permisos (`Usuario.permisos`) se cargan una sola vez al iniciar sesión y no se refrescan: si
  el Gerente le saca un permiso a un rol mientras alguien de ese rol ya tiene la sesión abierta, esa
  persona sigue viendo botones/menús que ya no debería hasta que cierre sesión y vuelva a entrar
  (los datos reales siguen protegidos por RLS del lado del servidor).

**Encontrado en una revisión de código aparte (2026-09-30), NO corregido** (no son bugs — observaciones
de diseño, quedan para decidir si vale la pena el costo del cambio):
- No hay un widget compartido para "título + botón de ayuda + acciones" — el arreglo del título
  partido letra por letra se aplicó a mano en las 10 pantallas que lo tenían. Si una pantalla nueva
  agrega dos botones condicionales al lado del título sin copiar el patrón `Row(título+"?") +
  Wrap(botones)`, vuelve a aparecer el mismo bug. Un widget `EncabezadoPantalla(titulo, idTour,
  pasos, acciones: [...])` que arme eso solo lo haría estructuralmente difícil de romper, en vez de
  depender de que quien agregue la pantalla se acuerde de esta sección del md.
- `InventarioPdfService` (nuevo) repite casi entero el "chrome" del PDF de `ReporteService` (logo de
  marca de agua, pie paginado, estilos de tabla) en vez de compartirlo — un cambio de marca (color,
  logo, formato de pie) hay que hacerlo en los dos archivos a mano.
- `lib/screens/inventario/inventario_list_screen.dart` (legacy, sin ruta en el menú) todavía tiene el
  bug de "sin consumo cargado = verde" que se corrigió en `dashboard_service.situacionDe` — el fix se
  hizo en el call site nuevo, no en la función compartida (`SemaforoStock.evaluar`/
  `StockStatusBadge`). Si esta pantalla se vuelve a rutear, o si ese widget se reusa en otro lado, el
  bug reaparece. Lo correcto sería que `SemaforoStock.evaluar` mismo tratara "sin datos" como no
  óptimo, en vez de exigirle a cada pantalla que lo filtre antes de llamarlo.
- `PermisosGestionService.alternar` llama `notifyListeners()` dos veces por toque exitoso (una vez
  optimista, otra al confirmar el servidor), y `PermisosScreen` mira el service entero con
  `context.watch` sin `Selector` — cada toque de una casilla reconstruye las ~115 celdas de la
  matriz dos veces. No rompe nada (son widgets chicos), pero si la matriz crece bastante más convendría
  acotar el rebuild por fila/celda.

`v18b` es un parche que se corre justo
después de v18 en bases creadas con una versión vieja de v18 (agrega columnas y recrea
`inv_existencia`); las vistas cuyas columnas cambian se recrean con `drop view` + `create view`,
porque `create or replace view` no permite insertar columnas en el medio.
v29 da el privilegio de tabla a `authenticated` (solo a tablas con RLS): en este proyecto las tablas
creadas por SQL NO lo reciben solas y la app falla con `42501 permission denied`. Correrlo de nuevo
después de crear tablas o vistas nuevas.
`v14` (y `schema.sql`) también definen `rol_actual()`, sin `security definer`: si se vuelven a correr
pisan a v22 y el login falla con "stack depth limit exceeded". Después de correr cualquiera de los
dos, volver a correr v22. Verificar con
`select prosecdef from pg_proc where proname = 'rol_actual'` (debe dar `true`).
Las tablas del inventario nuevo llevan prefijo `inv_`. Los pedidos/entregas (v21) no tienen
políticas de insert/update: toda escritura pasa por funciones `security definer` (`inv_crear_pedido`,
`inv_entregar_pedido`, `inv_confirmar_entrega`, `inv_resolver_observacion`, `inv_anular_pedido`),
así el movimiento de stock entre almacenes y la elección de lotes quedan en una sola transacción.
Módulos ya construidos con esta arquitectura: `features/inventario/`, `features/recepciones/`,
`features/entregas/`, `features/solicitudes/`, `features/soplado/`, `features/jarabes/`,
`features/calidad/`, `features/llenadora/`, `features/codificacion/`, `features/registro_salidas/`,
`features/mermas/`, `features/soda_caustica/`, `features/informe_gerente/`, `features/dashboard/`,
`features/permisos/`.

## Configuración (el engranaje de la barra superior)

El botón de "Configuración" (`AppTopBar`) abría el mismo diálogo que "Mi perfil" — duplicado sin
sentido. Primer intento: hacer que abriera "Permisos por rol" — pero eso tampoco era lo que hacía
falta ahí: el gerente pidió que el engranaje sea la configuración general de la app (como en
cualquier app), y que Permisos se abra desde Usuarios, no desde el menú principal.

Quedó así:
- **El engranaje** (`onNavegar('configuracion')`) abre `lib/screens/configuracion/` —
  **Sincronización** (estado online/pendientes + botón "Sincronizar ahora", que hasta ahora existía
  en `SyncService.sincronizarTodo()` pero no estaba conectado a ningún botón en toda la app) y
  **Tamaño de letra** (chico/normal/grande, `PreferenciasService`, guardado en Hive
  `HiveBoxes.preferencias` y aplicado a toda la app envolviendo `MaterialApp.builder` con un
  `MediaQuery`/`TextScaler` propio en `main.dart` — no hace falta tocar cada pantalla). Es
  configuración del dispositivo, no de la cuenta (eso sigue siendo "Mi perfil").
- **Permisos por rol** (`features/permisos/`) ya no tiene ítem en el menú ni en la barra superior:
  se abre desde **Usuarios**, al editar o dar de alta a alguien — junto al campo "Rol" hay un botón
  "Ver permisos" que abre `PermisosScreen(rolInicial: rol)` en una pantalla nueva (push normal,
  no diálogo), ya con el rol de ese usuario seleccionado. Gerente elige un rol y tilda qué puede
  ver/crear/editar/eliminar/aprobar en cada módulo (`app_modulos`/`permisos_rol`, schema_v17). No
  es una pantalla nueva del lado del servidor — v17 ya traía la tabla, `tiene_permiso()`, la
  política RLS que exige `rol_actual() = 'gerente'` para escribir, y el trigger que impide sacarle
  a Gerente el acceso a Usuarios/Permisos; esta pantalla es la primera interfaz que la usa (antes
  había que editar `permisos_rol` directo en el SQL Editor de Supabase). Cada casilla guarda sola
  al tocarla (actualización optimista con `PermisosGestionService.alternar`, que deshace el cambio
  si el servidor lo rechaza) — no hay un botón "Guardar" aparte. Importante: esto administra los
  PERMISOS de los 11 roles que YA EXISTEN (`Rol.todos`), no crea roles nuevos — agregar un rol
  nuevo sigue siendo un cambio de código en ambos lados (`Rol` en `lib/core/constants.dart` y
  `rol_valido()` en SQL), como dice la sección de Roles más abajo.

## Trabajar sin internet (sincronización automática)

Antes, el modo sin conexión solo cubría el inventario legacy (`HiveService`: catálogo
tapas/preformas/materia prima + cola de `movimientos`); los módulos de `lib/features/` llamaban
directo a Supabase y sin internet fallaban. Ahora lo cubre una sola pieza para TODOS los módulos,
sin tocar ningún repositorio: `ClienteOffline` (`lib/services/cliente_offline.dart`), el
`httpClient` que se le pasa a `Supabase.initialize`.
- **Lecturas** (GET a `/rest/v1/` y las RPC de solo lectura de `_rpcLectura`): cada respuesta buena
  se guarda en Hive (`ColaOffline`, caja `box_cache_lecturas`, por usuario = `sub` del JWT). Sin
  internet se devuelve esa copia; si la red tarda más de 5 s y hay copia, también.
- **Escrituras** (insert/update/delete y RPC): sin internet se encolan en `box_cola_offline` (sin el
  token) y a la app se le contesta como si hubieran salido bien. Si la RPC/insert "crea" algo, se
  devuelve un id provisorio negativo (`-9xxxxxxxxxxx`); al subir se anota el real
  (`box_ids_temporales`) y se reemplaza en todo lo que venga después (ej. finalizar una corrida
  iniciada sin internet). Con algo pendiente de esa persona, lo nuevo también va a la cola, para
  respetar el orden.
- **Subida**: `SyncService` la dispara al volver la conexión, al abrir la app y cada 30 s mientras
  haya pendientes (connectivity_plus no avisa cuando vuelve el wifi sin salida a internet). Sube
  FIFO solo lo del usuario con sesión abierta (lo de otro usuario espera a que vuelva a entrar en esa
  compu, para que quede a su nombre). Las reglas del servidor (stock, permisos) se aplican al
  subir: si el servidor rechaza algo, pasa a `box_errores_offline` y se ve en Configuración →
  Sincronización con su motivo, para Reintentar o Descartar; lo que dependía de eso (id provisorio
  sin resolver) también queda con error.
- **No se encola** (pasa directo y falla como antes): login e intentos, alta/edición de usuarios,
  `permisos_rol`, la clave del Gerente (`jarabes_receta_confirmar_gerente`), la tabla legacy
  `movimientos` y el bucket `avatars` (tienen su propio mecanismo). Tampoco si la conexión se cortó
  DESPUÉS de mandar el pedido (`_ambigua`: "connection closed", timeout): pudo haber llegado y
  encolarlo podría duplicarlo; en la subida, ese caso queda "con error" para que una persona revise.
- Aviso global (`AvisoSincronizacion`, envuelve la app en `main.dart`): "Sin internet: se guardó en
  esta compu" en cada escritura encolada, y cuántas se subieron/rechazaron al volver la conexión.
- **Limitaciones conocidas**: lo hecho sin internet no aparece en las listas hasta que se sube y se
  recarga la pantalla (las lecturas son la copia de la última vez); una consulta que nunca se hizo
  con conexión en esa compu no tiene copia; el login requiere internet (una sesión ya abierta sigue
  funcionando). Una RPC nueva de solo lectura hay que sumarla a `_rpcLectura`, y una que deba exigir
  conexión a `_rpcSoloEnLinea` — si no, se trata como escritura y se encola.
- Test: `test/cliente_offline_test.dart` (cliente HTTP falso, sin red real).
- **Arreglos de la revisión del modo sin internet (2026-10-23)**:
  1. *Doble registro con wifi sin salida*: los repositorios cortan a los 8 s (`timeoutRed`) pero el
     pedido seguía y, al fallar tarde, se encolaba igual — la persona veía error, reintentaba, y se
     subían las dos. Ahora el cliente real (`http_base.dart`, import condicional) tiene
     `connectionTimeout` de 5 s (falla al CONECTAR = nunca salió = seguro encolar), y
     `ClienteOffline.limiteParaEncolar` (7 s): una falla de red después de eso se devuelve como
     error, no se encola. Lo que ve la persona y lo que pasa coinciden.
  2. *Lo iniciado sin internet no aparecía*: `filasSinSubir` (`lib/shared/`) arma, desde la cola
     (`ColaOffline.rpcSinSubir`), las corridas/preparados iniciados sin internet como filas "en curso"
     con id provisorio, y los repositorios de Soplado/Llenadora/Codificación/Jarabes las suman en
     `corridas()`/`preparados()` (mismo `fromMap`, sin cambiar services ni tests). Se pueden finalizar
     sin internet; desaparecen solas al subir o al finalizarlas. Marcadas con `ChipSinSubir`
     (`modelo.sinSubir` = id < 0); en Jarabes el lote dice "Lote al subir" (lo asigna el servidor).
  3. *Rechazos poco visibles* y *pendientes que invitaban a repetir*: `BandaSincronizacion`
     (`aviso_sincronizacion.dart`, puesta por `HomeShell` debajo de las migas): roja en TODAS las
     pantallas mientras haya algo rechazado; ámbar con lo de esa pantalla aún sin subir
     (`HomeShell._pendientesDe`, por prefijo de la descripción). Al agregar una RPC nueva, sumarle
     nombre legible en `ClienteOffline._nombres` con el prefijo de su pantalla.
  4. *Reintentar invertía el orden*: `marcarError` guarda `claveCola` y `reintentar` la devuelve a
     su lugar original en la cola (si está libre).
  5. *Login lento sin red*: sin interfaz, o si `intentos_login_estado` ya falló por red, se entra
     directo con la huella guardada (antes 8 s + 8 s).
  6. *Pantallas con datos viejos al volver la red*: `SyncService.alHaberDatosNuevos` (volvió la red
     tras un corte, o se subió algo) + `RecargarAlReconectar` (`lib/shared/`) debajo del provider de
     cada pantalla sin tiempo real (Almacenes, Recepciones, Entregas, Solicitudes, Calidad, Llenadora,
     Codificación, Registro de salidas, Mermas, Soda Cáustica, Informe de Producción) y en
     Producción del día. Una pantalla nueva sin `escucharTablas` lleva este widget.
- **Entrar sin internet** (`lib/services/sesion_offline.dart`): cada ingreso CON internet guarda
  en Hive (`box_sesion`, clave `offline_<correo>`) una huella PBKDF2-SHA256 (20 000 iteraciones, sal
  propia; nunca la contraseña) + la fila de `usuarios` + los permisos. Si `signInWithPassword`
  falla por red, `AuthService._entrarSinConexion` verifica contra eso: vale 30 días desde el último
  ingreso con internet en ESA compu; 5 errores seguidos bloquean 5 min (el bloqueo del servidor, v23,
  no existe sin red). No hay sesión de Supabase: `ClienteOffline.usuarioSinConexion` hace que sus
  lecturas usen SU copia y que lo que registre quede en la cola a su nombre. La contraseña queda
  solo en memoria mientras tanto, para que `_reconectar` (al volver la red o cada 30 s) abra la
  sesión real sola; si la contraseña cambió con internet, cierra sesión con `avisoLogin` (la cola
  se conserva y se sube al volver a entrar). `recuperarSesion` (app reabierta con sesión) usa el
  perfil guardado si no puede leerlo. Test: `test/sesion_offline_test.dart`.
- **Datos personales sin internet**: la huella guarda también `datosCompletos` (lo que dijo el
  servidor en el último ingreso). Al entrar sin internet, si es `false` se muestra igual
  "Completá tus datos"; el `upsert` a `datos_empleado` va a la cola y `datosCompletados()` marca la
  huella (`SesionOffline.marcarDatosCompletos`) para no volver a pedirlos.
- **Cierre por ausencia** (`SesionInactividad`, `VigilanteSesion` en `main.dart`): se anota la última
  actividad (cada minuto con sesión abierta y al pasar a segundo plano, en `box_sesion`). Al volver a
  la app (`resumed`) o al abrirla (`recuperarSesion`), si pasó más de `limite` (1 h) se cierra la
  sesión con `avisoLogin`. Sin registro previo no se da por vencida. El login muestra `avisoLogin`
  escuchándolo en vivo (la revisión al abrir termina después de que el login ya se dibujó).

## Rendimiento (búsquedas y listas, 2026-10-15)

- **Buscadores de los formularios** (elegir insumo/tapa/preforma/proveedor al iniciar una corrida,
  Soda Cáustica, Solicitudes): antes cada letra era una consulta `ilike` al servidor (una ida y
  vuelta por red por tecla). Ahora el service usa `CatalogoLocal` (`lib/shared/busqueda_local.dart`):
  trae el catálogo UNA vez (`SupabaseService.todasLasFilas`, pagina de a 1000 porque Supabase corta
  ahí), lo guarda 5 min y filtra en memoria con `IndiceBusqueda` (texto sin tildes precalculado,
  todas las palabras en cualquier orden, busca también por código, primero lo que empieza con lo
  escrito, máximo 30). Los repositorios mantienen la firma `({String? busqueda})`: sin texto devuelven
  el catálogo entero, con texto siguen funcionando como antes. Un buscador nuevo de este tipo va con
  `CatalogoLocal`, nunca con una consulta por letra.
- Los formularios que ya filtraban en memoria (Pedido, Recepción, Proponer receta) usan
  `IndiceBusqueda` (antes quitaban tildes a todo el catálogo y dibujaban todas las opciones, sin
  límite, a cada letra). "Proponer receta" cargaba el catálogo con `buscarItems('')`, que el servidor
  cortaba en 30 ítems — ahora usa `JarabesService.catalogoItems()` (todo).
- **Almacenes** (`InventarioService`): índices armados una vez por carga (`_asegurarIndices`:
  categoría por id, hijos por padre, descendientes, rutas, resúmenes de tarjetas, texto de búsqueda
  por ítem con `Expando`) en vez de búsquedas lineales por cada fila/tarjeta en cada dibujado;
  `visibles` memoizado por filtros; `buscar` aplica el filtro al toque pero redibuja recién tras
  200 ms sin escribir; la tabla se dibuja de a 100 filas (`limiteTabla`, botón "Mostrar más") — el
  PDF sigue usando `visibles` completo. Balance memoiza su filtro igual (cada número escrito
  redibujaba y volvía a filtrar todo).
- `ClienteOffline` guarda la copia de cada lectura en segundo plano (`unawaited`), sin demorar la
  respuesta. Recepciones carga recepciones y reclamos en paralelo.
- Test: `test/busqueda_local_test.dart`.
- **Historiales con `ListView.builder`** (Soplado, Llenadora, Codificación, Calidad, Jarabes,
  Mermas, Soda Cáustica): el encabezado es el ítem 0 (sigue construyéndose entero, para el tour) y
  cada tarjeta se crea recién al aparecer en pantalla. Antes era `ListView(children: [... for ...])`,
  que creaba las ~200 tarjetas de entrada. Una lista nueva de datos va con `.builder`, nunca con
  `children` + `for`.
- **Arranque**: la caché sin conexión es una `LazyBox` (`box_cache_lecturas`, con las fechas en
  `box_cache_fechas` para podar sin leer todo): antes Hive cargaba hasta 800 respuestas en memoria
  al abrir la app. `_cargarPerfil` pide permisos y datos personales a la vez; el login ya no espera
  la bitácora ni `intentos_login_registrar_exito` (y un error de la bitácora ya no se cuenta como
  intento fallido de contraseña — era un bug).
- **Memoria de catálogos en `ClienteOffline`** (`_catalogos`: almacenes, categorías, sabores,
  presentaciones, matriz, módulos): 2 minutos en memoria. Muchas pantallas piden la lista de
  almacenes ANTES que lo demás, así que era un viaje al servidor en serie en cada pantalla.
  Cualquier escritura a esa tabla la borra (una RPC borra toda la memoria); `olvidarMemoria()` al
  cerrar sesión. Lo que cambia OTRA persona en un catálogo tarda hasta 2 min en verse.

## Respaldos

`.github/workflows/backup.yml` (GitHub Actions): `pg_dump` diario de `public`/`auth`/`storage`
(03:00 Bolivia) + fotos de Storage los domingos (`scripts/backup/descargar_storage.mjs`, sin
dependencias), todo cifrado con `openssl` (secreto `BACKUP_PASSWORD`) y guardado 30 días como
artifact. Usa el **Session pooler** de Supabase (GitHub no tiene IPv6 para la conexión directa).
Configuración, restauración y la recomendación de plan Pro para producción: `docs/backups.md`.
Si se agrega un schema propio fuera de `public`, sumarlo al `pg_dump`.

## Ayuda dentro de la app (tours guiados)

"Shepherd" es una librería de tours para páginas web (HTML/JS); esta app es Flutter, así que el
equivalente es el paquete `tutorial_coach_mark`. `lib/shared/ayuda/tour_ayuda.dart` tiene la
infraestructura reutilizable: `PasoAyuda` (qué `GlobalKey` señalar + título + texto),
`TourAyuda.mostrar()` (arma los `TargetFocus` y los muestra) y el widget `BotonAyuda` (el ícono "?"
que repite el tour a pedido). Qué tour ya se vio se guarda en Hive (`HiveBoxes.preferencias`, caja
nueva) **por dispositivo, no por usuario** — a propósito, porque en la fábrica suele ser la misma
computadora para varios turnos/roles. `TourAyuda.mostrar` descarta solo los pasos cuyo `GlobalKey`
no está montado en ese momento (ej. una tarjeta que ese rol no ve), en vez de romper.

**Textos de los recorridos: una línea, lo mínimo** (pedido del usuario, 2026-10-25; se acortaron
los 51). Un paso nuevo va igual de corto. Si una pantalla la usan roles que hacen cosas distintas,
los pasos dependen del rol: en Producción del día, quien no puede editar no ve "Armar plan" ni
"Marcar como completado" sino "Plan de hoy" (`_pasoListaVer`), y solo ve la lista, sin botones.

Cada `PasoAyuda` también sirve de `Tooltip` permanente: `PasoAyuda.envolver(child)` devuelve el
mismo `KeyedSubtree` de antes pero adentro de un `Tooltip` con el título y el texto del paso —
así no hace falta repetir el recorrido completo para acordarse de qué hace un campo puntual: al
pasar el mouse por encima (o mantener presionado en el celular) aparece la misma explicación.
Como el texto sale del mismo `PasoAyuda` que usa el tour, no hay una copia aparte que se pueda
desincronizar. Por esto cada pantalla guarda sus pasos como CAMPOS (`final _pasoX = PasoAyuda(...)`)
en vez de reconstruirlos cada vez dentro de `_pasosAyuda()` — `_pasosAyuda()` ahora solo devuelve
`[_pasoX, _pasoY, ...]`, y cada lugar que antes hacía `KeyedSubtree(key: _claveX, child: Y)` pasó a
`_pasoX.envolver(Y)`. Todos los tours ya listados arriba tienen esto.

Cada pantalla principal del menú lateral tiene su propio tour: se reproduce solo una vez por
pantalla (`soloSiNoVisto: true`, guardado en Hive por dispositivo) y después queda un botón "?"
(`BotonAyuda`) en el encabezado para repetirlo las veces que haga falta — es la app entera, no solo
Inicio y Jarabes. Están: `inicio`, `jarabes`, `almacenes`, `recepciones`, `entregas`, `solicitudes`,
`soplado`, `calidad`, `llenadora`, `codificacion`, `salidas`, `mermas`, `soda_caustica`,
`informe_produccion`, `produccion_del_dia`, `historial`, `usuarios` (los `idTour` de cada una).
Configuración, Manual de usuario y Permisos no tienen tour: son pantallas de referencia/ajuste, no
flujos de trabajo diarios con varios pasos que valga la pena señalar. Agregar uno a una pantalla
nueva es mecánico: unos `GlobalKey` como campos del `State`, envolver cada sección con
`KeyedSubtree(key: ..., child: ...)` (o pasarle `key:` directo si el widget lo acepta, como
`Text`), una lista `_pasosAyuda()` con `PasoAyuda` por cada uno, llamar
`TourAyuda.mostrar(context, idTour: '<algo único>', soloSiNoVisto: true, pasos: _pasosAyuda())`
en un `addPostFrameCallback` dentro de `initState`, y agregar `BotonAyuda(idTour: ..., pasos:
_pasosAyuda)` en el encabezado.

**Cuidado al agregar un tour a una pantalla nueva** — dos bugs reales que salieron al construir
los primeros (los arreglé, quedan documentados para no repetirlos, y se repitieron a propósito bien
en el resto):
1. Si el contenedor con las secciones es un `ListView` (o cualquier `Sliver` perezoso), lo que
   está fuera de la pantalla al momento de entrar TODAVÍA NO EXISTE en el árbol — su `GlobalKey`
   da `currentContext: null` y `TourAyuda.mostrar` lo descarta en silencio (`pasosVisibles`), así
   que ese paso del tour nunca aparece. Patrón usado en todas las pantallas con historial/lista sin
   límite (Soplado, Calidad, Llenadora, Codificación, Registro de salidas, Mermas, Soda Cáustica,
   Jarabes): las secciones "cortas" (encabezado, botón de acción, título de la lista) se agrupan en
   un método `_encabezado(...)` que devuelve una `Column` (siempre se construye entera) y va como
   PRIMER ítem del `ListView`; lo que sí puede crecer sin límite (el historial) se deja como ítems
   sueltos del `ListView`, después de ese primer ítem. En pantallas sin `ListView` (Recepciones,
   Entregas, Solicitudes, Informe de Producción, Producción del día, Historial, Usuarios — ya
   usaban `Column`/`Expanded` de entrada, o el tour apunta a algo siempre visible arriba de una
   lista chica) no hace falta este paso.
   **Ojo con "Almacenes": SÍ usa `ListView`** (una corrección anterior de esta sección decía lo
   contrario — estaba mal). Se encontró en una revisión de código que su sección de categorías
   (`_pasoCategorias`) vivía como ítem SUELTO del `ListView`, después de `_Cabecera` (que de por sí
   es alta: título, botones, chips de almacén, buscador, migas de pan) — en una pantalla angosta o
   baja, esa sección podía no estar montada todavía cuando arrancaba el tour solo. Se arregló
   moviendo esa sección DENTRO de `_Cabecera` (que ya recibe `svc` y puede calcular `hijos` ella
   misma), igual que el resto de los pasos de Almacenes.
   **Caso especial: "Registro de salidas"** tiene contenido eager DESPUÉS de la lista sin límite
   (la Planilla de producción, que va después del historial de reportes cerrados) — ahí un `Column`
   como primer ítem no alcanza, porque el problema está al FINAL, no al principio. Se resolvió con
   un `CustomScrollView` de tres slivers: `SliverToBoxAdapter` para el encabezado,
   `SliverList`/`SliverChildBuilderDelegate` de verdad para el historial (perezoso), y otro
   `SliverToBoxAdapter` para la Planilla — a diferencia de los hijos de un `SliverList`, el hijo de
   un `SliverToBoxAdapter` se monta siempre, sin importar cuántos ítems haya antes en la lista.
   **Caso especial: tours que dependen de una carga asíncrona** (Jarabes: `_pasoPlanDelDia` apunta a
   una tarjeta que solo existe si `_plan != null`, y `_plan` se carga con `ProduccionService.
   planDeHoy` recién en `initState`) — lanzar el tour en el mismo `addPostFrameCallback` del
   `initState` corre una carrera casi segura de perder contra esa carga (una llamada a red/DB no
   termina en un frame), así que ese paso se salteaba casi siempre, no como caso raro. Se arregló
   encadenando `_cargarPlan().then((_) => ...)` para recién ahí programar el `addPostFrameCallback`
   del tour — así espera a que el estado (y por lo tanto el árbol) ya esté resuelto, para bien o
   para mal (si no hay plan hoy, ese paso se sigue salteando correctamente, como ya documentaba
   la sección de arriba).
2. Al armar esa `Column`, hay que usar `crossAxisAlignment: CrossAxisAlignment.stretch`, NUNCA
   `.start`: un `ListView` siempre le da a cada hijo el ancho completo (restricción fija), pero un
   `Column` con `.start` solo alinea a la izquierda sin forzar el ancho — cualquier tarjeta sin un
   `width` propio (`Card`, o un `Container` sin `width: double.infinity`) queda angosta, del ancho
   de su contenido, en vez de ocupar toda la pantalla como antes.

Como respaldo para cuando el tour con globitos no alcanza (o ya se cerró y nadie se acuerda cómo
volver a abrirlo), `lib/screens/ayuda/manual_screen.dart` es un **manual de usuario escrito**, con
lo básico de CADA módulo (no solo los que tienen tour) en lenguaje simple, sin tecnicismos. Es una
lista de `_EntradaManual` (título + resumen + puntos) fija en el propio archivo — no sale de
ninguna tabla. Tiene su propio ítem en el menú lateral ("Manual de usuario", siempre visible, para
cualquier rol — a propósito no depende de permisos, porque es justamente la referencia para
entender el sistema). Al agregar un módulo nuevo, sumarle también su entrada acá.

**Bugs reales de la primera tanda de tours, encontrados por el usuario probando en el celular
(2026-09-29), y su arreglo:**
- El globo de un paso podía quedar tapado o cortado abajo de la pantalla, sin forma de bajar a
  verlo: `TourAyuda.mostrar` elegía `ContentAlign.bottom` siempre, y si el objetivo estaba en la
  mitad de abajo (ej. "Movimientos por almacén" del Inicio, casi al final) el globo se dibujaba más
  abajo todavía, fuera de lo visible. Arreglado con `_alineacion()`: mira si el objetivo está en la
  mitad de arriba o de abajo de la pantalla y elige `ContentAlign.top`/`.bottom` según corresponda,
  más un `ConstrainedBox`+`SingleChildScrollView` por las dudas de que el texto de un paso sea largo.
- Aun eligiendo bien el lado del globo, el objetivo en sí podía seguir fuera de lo visible (el
  usuario tenía que scrollear la pantalla A MANO antes de que el tour lo señalara, algo que un tour
  automático no debería pedir). Arreglado con `beforeFocus` en el `TutorialCoachMark`: antes de
  iluminar cada paso, hace `Scrollable.ensureVisible(..., alignment: 0.5)` sobre el `GlobalKey` de
  ese paso — centra el objetivo en la pantalla (o el diálogo) scrolleando solo, así el tour "se
  mueve con lo que mira la persona" en vez de señalar algo fuera de vista.

`ModalFormulario` (`lib/widgets/formulario_widgets.dart`, el marco común de casi todos los
formularios "Nuevo X" — 24 diálogos lo usan) ahora acepta `idTour`/`pasosAyuda` opcionales: si un
formulario los pasa, el marco se encarga solo de mostrar el tour la primera vez que se abre y de
poner el botón "?" al lado de la "X" — el formulario solo define sus `GlobalKey` y su
`_pasosAyuda()`, igual que ya hacía cada pantalla con `BotonAyuda`. Implementado como ejemplo en
`features/inventario/widgets/item_form_dialog.dart` ("Nuevo ítem", `idTour: 'item_form'`); el resto
de los formularios no tiene tour todavía — agregarlo a otro es tan mecánico como en una pantalla.

## Errores de layout en móvil (encontrados probando en celular, 2026-09-29)

- **Título partido letra por letra** ("Al" / "m" / "ac" / "en" / "es"): en el encabezado de
  Almacenes, un `Row` con el título en `Expanded` y TRES botones más al lado (Balance, Salida
  directa, Nuevo ítem) sin ningún `Expanded`/`Flexible` en ellos — en un teléfono angosto los tres
  botones ya ocupaban más ancho que la pantalla, así que al `Expanded` del título le quedaba un
  ancho negativo (Flutter lo deja en 0) y el texto, sin espacio para ni una letra por línea, se
  partía carácter por carácter. Como los permisos por rol ahora son configurables desde la pantalla
  Permisos (no fijos en el código), CUALQUIER pantalla con dos o más botones condicionales al lado
  del título corre el mismo riesgo para algún rol que el Gerente configure con varios permisos a la
  vez — se corrigió en las 10 pantallas que tenían esto (Almacenes, Jarabes, Entregas, Recepciones,
  Solicitudes, Soplado, Llenadora, Codificación, Mermas, Soda Cáustica, Registro de salidas): el
  título queda solo con el botón "?" en su `Row`, y los botones de acción pasan a un `Wrap` (si son
  dos o más, como Almacenes/Jarabes) o a un botón solo en la línea de abajo (si es uno) — nunca los
  tres en el mismo `Row` que el título.
- **Etiquetas cortadas con "…"** ("Unidades po…", "Peso …", "Anch…", "Micro…"): varios formularios
  ponían 2 o 3 campos lado a lado con `Row([Expanded(campo), SizedBox, Expanded(campo)])` de ancho
  fijo — en un diálogo angosto (`ModalFormulario` va hasta 520px pero se achica a lo que entre en la
  pantalla) cada campo quedaba con menos de 100px, y la etiqueta del `TextField` (que no hace wrap,
  se corta con "…") no entraba. Se agregó `FilaCampos` (`lib/widgets/formulario_widgets.dart`): mismo
  `Row` de 2-3 campos cuando hay ancho de sobra, pero se apila en `Column` (uno debajo del otro, a
  todo el ancho) cuando no — mide con `LayoutBuilder`, no con un breakpoint fijo. Aplicado en todos
  los formularios donde se encontró el patrón: `item_form_dialog` (Nuevo ítem), `linea_form_dialog`
  (Registro de salidas), `recepcion_form_dialog`, los tres `finalizar_corrida_dialog`
  (Soplado/Llenadora/Codificación), `analisis_form_dialog` (Calidad), `iniciar_preparado_dialog`
  (Jarabes), `salida_directa_dialog`, y el selector de solvente/tinta de `iniciar_corrida_dialog`
  (Codificación). La fila de "Cantidades" de Recepciones (factura/real + un desplegable de unidad de
  ancho fijo) es un caso aparte con su propio `LayoutBuilder` inline, porque la unidad no necesita
  repartirse el ancho como un campo más.
- **Franja de advertencia de Flutter tapando los botones** ("Cancelar" / "Guardar contraseña" en
  Mi perfil, y "Cancelar" / "Guardar cambios" en Usuarios): la barra de acciones de estos dos
  diálogos (NO usan `ModalFormulario`, tienen su propia barra) era un `Row` con los dos botones sin
  `Expanded` — en un teléfono angosto "Guardar contraseña" no entraba y Flutter dibujaba encima la
  franja diagonal amarilla/negra de "RenderFlex overflowed". Reemplazado por `OverflowBar` (el
  widget de Flutter pensado justo para esto, el mismo que usa `AlertDialog.actions` por dentro): los
  acomoda en fila si entran, y si no, los apila en columna — sin overflow posible.

## Roles (organigrama de Producción)

gerente, jefe_produccion, almacen, jarabes, ayudante_jarabes, soplado, llenadora, codificacion,
registro_salidas, control_calidad, soda_caustica. Definidos en `Rol` (`lib/core/constants.dart`) y
en `rol_valido()` (SQL). Un rol nuevo se agrega en ambos lados.
