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
`features/mermas/`, `features/soda_caustica/`, `features/informe_gerente/`, `features/dashboard/`.

## Roles (organigrama de Producción)

gerente, jefe_produccion, almacen, jarabes, ayudante_jarabes, soplado, llenadora, codificacion,
registro_salidas, control_calidad, soda_caustica. Definidos en `Rol` (`lib/core/constants.dart`) y
en `rol_valido()` (SQL). Un rol nuevo se agrega en ambos lados.
