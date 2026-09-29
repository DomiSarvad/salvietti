# Salvietti Control — Requerimientos de la reestructuración

Documento de referencia con todo lo pedido para rediseñar el sistema alrededor de la planta
de producción. Se actualiza a medida que se confirman datos.

Estado: **diseño acordado, Módulos 1 a 7 construidos.** La especificación de cada uno (campos,
roles, CRUD) está en la sección 12 bis. Lo que falta confirmar, en la sección 13. Los módulos 8 a
11 siguen como diseño deducido, en la sección 14.

---

## 1. Objetivo

Reemplazar los cuadernos, hojas de Excel y formularios en papel de la planta por un solo sistema
que:

- Registre cada movimiento de materiales, desde que llegan hasta que se convierten en producto.
- **Automatice todo lo que se pueda calcular** (códigos, diferencias, totales, litros, horas de
  inicio y fin, saldos), para que nadie escriba lo que el sistema puede deducir.
- Imprima los mismos documentos que hoy se firman a mano.
- Le dé al Gerente un resumen claro de Producción para tomar decisiones, con detalle por área si
  hace clic.
- Sea **escalable**: agregar áreas, roles o módulos no debe obligar a reescribir lo existente, y el
  modelo de seguridad se mantiene.

## 2. Organigrama

```
Jefe
└── Gerente General
    ├── Producción
    │   ├── Almacén
    │   ├── Jarabes            (Jefe de Jarabes + Ayudante)
    │   ├── Soplado
    │   ├── Llenadora
    │   ├── Codificación
    │   ├── Registro de Salidas
    │   ├── Control de Calidad (área dentro de Producción)
    │   └── Mantenimiento
    ├── Ventas
    │   ├── Jefe de Ventas
    │   ├── Cajas
    │   ├── Almacén (comercial)
    │   └── Encargado de Logística (con choferes a su cargo)
    ├── Marketing
    ├── Finanzas
    │   ├── Jefe de Contabilidad
    │   └── Ayudante de Contabilidad
    └── Talento Humano
```

**Quiénes usan el sistema por ahora:** solo Producción. Ventas, Marketing, Finanzas y Talento
Humano quedan fuera hasta nuevo aviso. Mantenimiento no tiene usuario propio: es una categoría de
insumos de Almacén.

## 3. Roles del sistema

| Rol (id) | Cargo | Qué hace |
|---|---|---|
| `gerente` | Gerente General | Observa Producción, aprueba solicitudes y cambios de receta (con su clave), administra usuarios y permisos |
| `jefe_produccion` | Jefe de Producción | Arma el plan del día, pide suministros a través de Gerencia, aprueba cambios de receta |
| `almacen` | Encargado de Almacén | Recibe, pesa, registra, entrega a las áreas, solicita faltantes a Gerencia |
| `jarabes` | Jefe de Jarabes | Elabora concentrados, maneja su propio almacén, propone recetas |
| `ayudante_jarabes` | Ayudante de Jarabes | Mismo alcance que el Jefe sobre su área |
| `soplado` | Encargado de Soplado | Sopla botellas con ~2 semanas de anticipación, maneja su almacén, hace la segunda recepción |
| `llenadora` | Encargado de Llenadora | Registra llenado y su merma |
| `codificacion` | Encargado de Codificación | Registra codificación y su merma |
| `registro_salidas` | Encargado de Registro de Salidas | Registra el producto terminado del día (palets, paquetes, botellas) |
| `control_calidad` | Encargada de Control de Calidad | Analiza el concentrado (Brix, pH), aprueba cambios de receta |
| `soda_caustica` | Encargado de Soda Cáustica | Registra entregas de soda (producto peligroso) con firma, solicita insumo, registra merma |

Los cargos nuevos arrancan en solo lectura sobre el inventario; sus permisos propios llegan con
el módulo de cada área. El detalle exacto de qué puede hacer cada rol en cada módulo construido
está en la sección 12 bis.

## 4. Proceso de producción

1. **Recepción en Almacén.** Llegan materias e insumos. Se registra el peso de la etiqueta o la
   factura y se **pesa de nuevo** el real. Si en el mes se repite una diferencia (piden 16 kg y
   llegan 15,9), Almacén hace el reclamo al proveedor. Se adjunta foto de la factura o de la
   etiqueta de la caja.
2. **Entrega a las áreas.** Jarabes y Soplado manejan su propio almacén; Almacén les entrega lo
   que van a necesitar. Los demás solicitan a Almacén, que entrega según la orden del día
   (qué ingresa, qué se usa y cuánto hay para producir cada producto).
3. **Conformidad.** El sistema le pasa al área una lista de lo entregado. El área la revisa ítem
   por ítem (tilda), escribe observaciones si algo salió mal (esto notifica a Almacén) y cierra
   con "conforme". Ahí termina la transacción. Para Soplado y Jarabes esta es la **segunda
   recepción**.
4. **Plan del día.** El Jefe de Producción arma la producción. Soplado, con dos semanas de
   anticipación, sopla según las paletas que quedan (si solo quedan 1 o 2 de papaya, se sopla).
5. **Jarabes.** Elige el concentrado del día y cuántos preparados (2, 1, 1/2). La receta se
   multiplica sola. Si falta un insumo, el sistema avisa y ofrece solicitarlo a Almacén antes de
   empezar. Al iniciar se guarda fecha y hora; al finalizar, hora final y **Brix** (% de dulzor),
   y se descuenta el insumo de su almacén. Ve el avance de Soplado para no preparar de más.
6. **Control de Calidad.** Recibe el Brix y hace sus análisis (pH, etc.). Si algo no cumple, notifica.
   El Brix importa porque el jarabe se diluye con agua y eso baja el dulzor.
7. **Llenadora → Codificación → Registro de Salidas.** Salidas anota cuántas paletas, paquetes y
   botellas sueltas se hicieron en el día y en qué horario.
8. **Mermas.** Cada área registra la suya (Soplado, Jarabes, Llenadora, Codificación). El
   ingeniero analiza y, si la merma de producción **pasa del 3 %**, hay que investigar la causa.
9. **Gerente.** Ve un resumen de Producción con detalle por área al hacer clic.

### Ejemplo de receta (Papaya, un preparado)

18 quintales de azúcar · 1 kg benzoato americano · 1 kg sorbato de potasio · 0,976 kg concentrado
de papaya Sapore · 1,22 kg alcohol · 0,004 kg sunset/tartrazina · 9 kg ácido cítrico →
**1220 litros**. Estándar: **12 cajas** por preparado. Se hace todos los días.

Litros por preparado: papaya 1220 · naranja 1050 · piña 1050 · kinotto 1080. Los demás sabores
se completan cuando Jarabes los confirme.

### Causas de merma por área

- Sale con mucha agua → Calidad
- Se quebraron botellas → Soplado
- Rebalse → Llenadora
- Menor volumen → Jarabes
- Brix y volumen → Calidad

## 5. Almacenes y categorías

Tres almacenes, cada uno con su propio stock: **General**, **Jarabes** y **Soplado**. Todo lo que
se descuenta va al informe general para que el ingeniero compare contra el estándar.

**Almacén General:**

- **PET** (plástico)
  - Tapas: Tapa Short → Negro, Rojo, Transparente, Celeste, Verde, Gama de colores
    (verde y rojo son los más importantes)
  - Etiquetas: Plástico (por sabor y tamaño) y Sticker (Isotónico: Kiwi, Frutilla, Arándano azul,
    solo 600 ml)
  - Preformas: por tamaño (2,5 L, 2 L, 600 ml, 330 ml) y gramaje (ej. 52,48 g)
  - Termocontraíbles: se clasifican por ancho, peso y micronaje
- **Vidrio**
  - Envases: 1 L, cervecera 620 ml, personal 300 ml, escolar 270 ml, promoción 500 ml
  - Etiquetas de papel (solo cerveceras; entran por kilo, la imprenta vende por unidad)
  - Tapas: Long (verde, amarillo) y corona (con sello y sin sello)
  - Cajas: 12 unidades (1 L, 500 ml, cerveceras) o 24 (300 ml y 270 ml)
- **Material de escritorio**
- **Limpieza** (aseo)
- **Saneamiento** (soda cáustica, cloro chino y americano, Divosan) — categoría aparte
- **Seguridad industrial** (guantes, overoles, botas, cofias, barbijos, protectores auditivos,
  cascos, fajas, gafas)
- **Mantenimiento**, con exactamente 4 subcategorías: **Plomería, Electricidad, Mecánico, Civil**.
  Gomas, tornillos, tuercas, rodamientos, cañerías y herramientas se clasifican dentro de una de
  ellas; no son categorías propias.
- **Laboratorio** (agua destilada, reactivos, guantes de látex; se entrega a Calidad)
- **Codificación** (solvente y tinta)

**Almacén de Jarabes:** azúcar (quintales de 46 kg), conservantes (benzoato americano y chino),
edulcorantes, ácidos (cítrico, fosfórico), colorantes (tartrazina, amaranto, sunset, azul,
verde, caramelo), concentrados por sabor, alcohol (llega en litros, se pesa en kg), sorbato,
natamicina, cafeína, vimix, citrato, telas y filtros de cartucho.

**Almacén de Soplado:** propio; recibe preformas, tapas y termocontraíbles catalogados por
Almacén General (ver "ítems recibidos de otra área" en la sección 12 bis, Módulo 1).

**Unidades de medida:** KG, GR, PZA, UNI, L, ML, CJA, M. Algunos ítems entran en una unidad y se
cuentan en otra (quintal de 46 kg, bidón de 20 kg); el sistema convierte.

**Registro de materia virgen y reciclaje:** porcentaje de botellas usadas.

## 6. Catálogo maestro

### Sabores

Papaya, Kinotto, Granadina, Naranja, Ross, Ginger Ale, Tumbo, Piña, Pomelo, Lima limón,
Achachairú (isotónicos: Kiwi, Frutilla, Arándano azul; agua: H2O). Cada sabor guarda su estándar de
cajas por preparado, litros por preparado y rango de Brix objetivo (para Calidad).

### Matriz sabor × tamaño (PET)

Solo se pueden registrar las combinaciones que existen. El sistema genera solo las etiquetas.

| Sabor | Tamaños |
|---|---|
| Papaya | todos (2,5 L, 2 L, 1 L, 600 ml, 330 ml) |
| Kinotto, Granadina, Naranja | todos menos 1 L |
| Ross, Ginger Ale | 2 L |
| Tumbo | 2,5 L y 600 ml |
| Piña | 2 L y 2,5 L |
| Pomelo, Lima limón | 2 L |
| Isotónicos (Kiwi, Frutilla, Arándano azul) | 600 ml (sticker) |

Pendiente: tamaños de Achachairú y H2O.

### Equivalencia cajas ↔ paletas (confirmada)

**2 cajas = 1 paleta.** Estándar por preparado: papaya **12 cajas = 6 paletas**; los demás sabores
**10 cajas = 5 paletas**. Se guarda por sabor (`estandar_cajas` y `cajas_por_paleta`) como dato
editable.

### Equivalencias por presentación (pendiente de datos, ver sección 13)

Dependen del tamaño de la botella. Cada presentación guarda cuántas botellas trae cada empaque y
cuántos empaques forman un palet.

- **PET:** palet → paquetes → botellas.
- **Vidrio:** palet armado por **filas y columnas** → cajas → botellas (cajas de 12 o de 24).
- En el reporte, "398+3" significa **398 paquetes más 3 botellas sueltas**.

```
total de botellas = palets × empaques por palet × botellas por empaque
                  + empaques libres × botellas por empaque
                  + botellas libres
```

## 7. Solicitudes, aprobaciones y constancias

- **Almacén**, si falta suministro, solicita a Gerencia.
- **Jefe de Producción** solicita a Gerencia.
- **Control de Calidad**, si quiere cambiar lo que se usa en concentrados, debe ser aprobado por
  Gerencia.
- **Gerencia** tiene una bandeja donde recibe y aprueba todas las solicitudes.
- **Cambio de una receta** (afecta a todo el sistema): lo aprueban **Calidad y Producción**, y
  además requiere la **clave de acceso del Gerente**. Implementado en el Módulo 11 — ver sección
  12 bis, Módulo 11.
- **Áreas que necesitan algo** (Jarabes, Soplado, etc.) solicitan a Almacén y llenan un registro de
  entrega. Jarabes lo hace desde el preparado: si falta un insumo, el sistema ofrece
  "¿solicitar a Almacén?" y la solicitud le llega directo.
- Hay además una opción para mandar una solicitud directa a Gerencia.
- **PDF de constancia para firmar** en cada entrega o solicitud (para cualquier trabajador que
  reciba algo). La soda cáustica siempre lleva constancia: es un producto peligroso.

## 8. Informe general para el Gerente (Módulo 11, pendiente)

Resumen de Producción, con detalle por área al hacer clic. Compara cada preparado real contra el
estándar de su sabor (papaya = 12 cajas), muestra la desviación, la atribuye al área según el
motivo registrado y marca en alerta lo que supere el 3 % de merma.

## 9. Permisos y seguridad

Los permisos no están escritos a mano: viven en la tabla `permisos_rol` (rol, módulo, acción).

- **El servidor manda:** las reglas de acceso se aplican con RLS y `tiene_permiso(módulo, acción)`;
  la app solo oculta lo que el rol no puede usar.
- **Se deniega por defecto:** sin fila en `permisos_rol` no hay permiso.
- Una cuenta desactivada no tiene rol, y por lo tanto tampoco permisos.
- Solo el Gerente modifica permisos y no puede quitarse el acceso a Usuarios ni a Permisos.
- Funciones `security definer` siempre con `search_path` fijo.
- Un módulo nuevo se agrega con: su id en `Modulo` (`lib/core/modulos.dart`), una fila en
  `app_modulos`, filas en `permisos_rol` y políticas RLS con `tiene_permiso`. Nunca
  `rol_actual() = '...'` escrito a mano en una tabla nueva.
- Si la app no puede leer los permisos (sin conexión, o migración sin ejecutar), usa las reglas
  anteriores por rol, para no dejar a nadie bloqueado a mitad de una migración.
- Muchas escrituras no tienen política de `insert`/`update` en absoluto: pasan por funciones
  `security definer` que validan todo y hacen el cambio en una sola transacción (pedidos, recetas,
  preparados, corridas de soplado, análisis de calidad). Esto es más estricto que el RLS simple,
  necesario cuando una acción mueve stock entre dos almacenes o depende de varios pasos.

Acciones: `ver`, `crear`, `editar`, `eliminar`, `aprobar`.

## 10. Módulos y orden de construcción

| # | Módulo | Qué incluye | Depende de | Estado |
|---|---|---|---|---|
| 1 | Base e inventario | Almacenes por área, catálogo, categorías, sabores, balance de insumos, conteo físico | — | ✅ |
| 2 | Recepción de Almacén | Factura contra peso real, diferencia, lote, vencimiento, transporte, foto, SENASAG automático | 1 | ✅ |
| 3 | Pedido interno, entrega y conformidad | Pedido desde Almacén o el área, lotes en orden de antigüedad, lista de conformidad | 1, 2 | ✅ |
| 4 | Solicitudes y aprobaciones a Gerencia | Pedidos a Gerencia, bandeja del Gerente, PDF | 1 | ✅ |
| 5 | Soplado | Corridas por sabor/presentación en botellas, tres mermas, proveedor/lote de preforma, parada de máquina, avance | 1, 3 | ✅ |
| 6 | Recetas y producción de Jarabes | Receta multiplicable, faltantes, inicio y fin, Brix, tanque, lote | 1, 3, 5 | ✅ |
| 7 | Control de Calidad | Brix, pH, resultado, aprobación de recetas | 6 | ✅ |
| 8 | Llenadora, Codificación y Salidas | Reporte diario de producción, Planilla automática | 6 | ✅ |
| 9 | Mermas | Formularios por área, alerta al 3 %, motivo | 5, 6, 8 | ✅ |
| 10 | Soda cáustica | Entregas con firma, solicitud de insumo, merma | 1, 4 | ✅ (merma propia pendiente) |
| 11 | Informe del Gerente | Resumen de Producción, detalle por área, cambio de recetas con doble aprobación y clave | 6, 7, 9 | ✅ |

Todos los módulos se construyen con la arquitectura de capas de `CLAUDE.md`
(models / repositories / services / screens, por módulo, con test del service).

**Se eliminaron** las pantallas **Reportes** y **Estadísticas** (los reportes ya salen de las
listas y los gráficos van en el inicio).

---

## 11. Convenciones de arquitectura (resumen; el detalle vive en `CLAUDE.md`)

- Capas por módulo: `models/` (datos puros) → `repositories/` (único lugar que habla con
  Supabase) → `services/` (reglas de negocio y permisos) → `screens/`+`widgets/` (solo UI).
- Un módulo no importa las pantallas ni los repositorios de otro; a lo sumo lee una vista/tabla
  compartida (ej. Jarabes lee `soplado_avance`) o usa el `service` de otro módulo.
- Toda acción que escribe queda cubierta por RLS o por una función `security definer`; nunca un
  permiso "de hecho" solo en la app.
- Cada módulo trae su archivo `supabase/schema_vNN_<modulo>.sql`, pensado para poder ejecutarse
  más de una vez sin romper nada.
- **Cuidado con `create table if not exists`:** si se le agrega una columna a una tabla en una
  edición posterior del mismo archivo, y alguien ya ejecutó la versión vieja, esa base se queda
  sin la columna nueva (ver el incidente de v18/v18b en la sección 12 bis). Por eso, una columna
  nueva sobre una tabla de un módulo ya publicado va como `alter table ... add column if not
  exists`, nunca solo agregada al `create table` original.

## 12 bis. Especificación de los módulos implementados: formularios, roles y CRUD

Esta sección es la referencia autoritativa de **cómo quedó construido** cada módulo: qué rol puede
hacer qué, y qué campos tiene cada formulario tal cual se implementó (no lo deducido originalmente).
"Ver" significa que el módulo aparece en el menú y se puede leer; sin esa fila en `permisos_rol`,
ni siquiera se ve.

### Módulo 1 — Inventario por almacenes

**Tablas:** `inv_almacenes`, `inv_categorias`, `inv_items`, `inv_movimientos`, `inv_conteos`,
más la vista `inv_existencia` (stock, consumo diario y días de existencia por ítem y almacén).

**Roles y CRUD** (permiso `inventario_<almacén>`, uno por cada almacén: `general`, `jarabes`,
`soplado`):

| Acción | Quién |
|---|---|
| Ver el almacén | Quien tenga `inventario_<almacén>:ver` (Almacén ve el suyo; Jarabes y Soplado el suyo; el resto de los roles ve Almacén General y Jarabes en solo lectura; el Gerente ve todos) |
| Crear/editar ítems | Solo en categorías **propias** de ese almacén, con `inventario_<almacén>:crear`/`editar` |
| Eliminar (desactivar) un ítem | `inventario_<almacén>:eliminar` |
| Conteo físico y Balance de insumos | Mismo permiso de `editar` |

Un ítem recibido de **otra** área (ej. una preforma que Soplado recibió de Almacén General) se ve
en el almacén que lo recibió, navegable por su **ruta real** de categorías, pero no se puede dar de
alta ahí: solo se crean ítems nuevos en la categoría propia del almacén.

**Formulario "Nuevo/editar ítem":** categoría (solo propias, hoja del árbol), detalle, unidad
(KG/GR/PZA/UNI/L/ML/CJA/M), unidad de compra + cuántas "unidad" trae cada envase (ej. 46 kg por
quintal), unidades por caja, stock mínimo (marca "Pedido" cuando el stock lo alcanza), consumo
diario manual (solo si no hay salidas registradas todavía), atributos libres (color, formato, peso
en gramos, ancho en mm, micronaje).

**Formulario "Conteo" (un ítem):** cantidad real, observaciones. La diferencia contra el sistema
se guarda sola como ajuste.

**Formulario "Balance de insumos" (todo un almacén de una vez):** una fila por ítem con su stock
del sistema y un campo de cantidad real; acepta escribir en gramos o mililitros aunque el ítem se
controle en kilos o litros (convierte solo); guarda solo las filas llenas, todo o nada; nota
general opcional.

**Automatizaciones:** código único (`IN-0001` en Almacén General/Soplado, `MP-0001` en Jarabes),
semáforo óptimo/bajo/crítico según días de existencia, marca "Pedido" cuando el stock ≤ mínimo,
consumo diario = promedio de salidas de los últimos 30 días.

**Salida directa (`v40`):** botón aparte en Almacén General, para insumos que salen sin pedido
formal ni firma (ej. termocontraíbles): ítem, área, cantidad de rollos (referencia) y peso real
(lo que descuenta el stock). Ver sección 13, "Resuelto — SALIDA DE TERMOCONTRAIBLES".

**Inicio (`lib/features/dashboard/`):** la pantalla que ve cualquier rol al entrar ya lee datos en
vivo de este módulo (`inv_existencia`/`inv_movimientos`), no las tablas del inventario anterior.
Un resumen por almacén (General/Jarabes/Soplado/Soda Cáustica, según lo que el rol pueda ver), los
ítems con menor stock, los que están en riesgo de desabastecimiento y los movimientos recientes.
El plan de producción del día sigue siendo un subsistema aparte (`ProduccionService`), sin tocar.
Tocar la tarjeta de un almacén abre Almacenes ya con ese almacén seleccionado.

### Módulo 2 — Recepciones

**Tablas:** `inv_recepciones`, `inv_proveedores`, `inv_item_proveedor` (recuerda el SENASAG de
cada ítem por proveedor). Vistas: `inv_recepciones_detalle`, `inv_diferencias_mes`.

**Roles y CRUD** (permiso `recepciones` + `inventario_<almacén>:editar` del almacén de destino):

| Acción | Quién |
|---|---|
| Ver recepciones | `recepciones:ver` |
| Registrar una recepción | `recepciones:crear` y operar ese almacén (Almacén General, Jarabes o Soplado, cada uno en el suyo) |

**Formulario:** almacén, ítem (buscador), proveedor (buscador; si no existe se crea desde ahí,
sin duplicar por mayúsculas o tildes), N° de factura, fecha de recepción, cantidad según factura,
cantidad real (pesada; acepta gramos si el ítem es en kilos), N° de lote, fecha de fabricación,
fecha de vencimiento, SENASAG (se autocompleta si ya se conoce para ese ítem y proveedor),
transportador, precio de transporte, foto de la factura o la etiqueta (JPG/PNG/WEBP, hasta 5 MB,
guardada en un bucket privado), observaciones.

**Vista "Reclamos del mes":** agrupado por proveedor e ítem, solo lo que faltó (diferencia
negativa), con el porcentaje.

**Automatizaciones:** diferencia = real − factura (reemplaza el "FALTA 350 GR" a mano); el stock
sube con el peso **real**, no el de la factura; SENASAG recordado automáticamente; aviso en la
lista si un lote vence en menos de 90 días.

### Módulo 3 — Pedido interno, entrega y conformidad

**Tablas:** `inv_pedidos`, `inv_pedido_lineas`, `inv_entrega_lotes`. Sin políticas de `insert`ni
`update`: todo pasa por funciones (`inv_crear_pedido`, `inv_entregar_pedido`,
`inv_confirmar_entrega`, `inv_resolver_observacion`, `inv_anular_pedido`).

**Roles y CRUD:**

| Acción | Quién |
|---|---|
| Ver el módulo | `entregas:ver` |
| Pedir para la propia área | `solicitudes:crear`, siendo de un área que recibe (Jarabes, Soplado, Llenadora, Codificación, Calidad, Soda Cáustica, Registro de Salidas) |
| Pedir para OTRA área y entregar | Almacén (`entregas:crear`) |
| Confirmar una entrega | `entregas:editar`, siendo del área destino o quien la pidió |
| Resolver una observación | Almacén |
| Anular un pedido pendiente | Quien lo pidió, o Almacén |

**Formulario "Nuevo pedido":** si lo arma Almacén, elige el área destino y puede tildar "Entregar
ahora" (por ejemplo, según el plan del día); si lo arma un área, es siempre para sí misma. Motivo
opcional. Ítems del catálogo de Almacén General, con cantidad.

**Formulario "Confirmar entrega":** por cada línea, Conforme/Con problema, cantidad recibida,
observación (obligatoria si no es conforme o la cantidad difiere), nota general.

**Bandejas:** Por entregar, Por confirmar, Con observaciones, Cerrados (incluye anulados).

**Automatizaciones:** al entregar, el servidor elige los lotes solo — primero lo que no tiene lote
(lo más antiguo), después por fecha de vencimiento, nunca un lote ya vencido — todo en una sola
transacción. Si el área tiene almacén propio (Jarabes, Soplado, y desde `v36` también Soda
Cáustica), lo confirmado como recibido entra solo a su stock.

**Devolución (`v39`):** una vez entregada una línea, Almacén puede registrar que parte (o todo) se
devolvió — no se puede devolver más de lo entregado menos lo ya devuelto. Ver sección 13,
"Resuelto — PEDIDO INTERNO DE ETIQUETAS".

### Módulo 4 — Solicitudes a Gerencia

**Tabla:** `solicitudes_gerencia`. Sin políticas de escritura directa: `solicitud_crear` y
`solicitud_resolver`.

**Roles y CRUD:**

| Acción | Quién |
|---|---|
| Ver el módulo | `solicitudes:ver` |
| Crear una solicitud | `solicitudes:crear` (casi todos los roles operativos) |
| Aprobar o rechazar | `aprobaciones:aprobar` (solo Gerente) |

**Formulario:** tipo (falta de suministro / autorización / cambio de receta / otro), asunto,
detalle, y si es "falta de suministro": ítem de referencia (buscador en el catálogo) y cantidad
sugerida.

**Bandejas:** Mis solicitudes, Por aprobar (Gerente), Resueltas.

**Resolución:** aprobar (respuesta opcional) o rechazar (respuesta **obligatoria**, explica el
motivo). Constancia en PDF con espacio para firma del solicitante y de Gerencia.

*Pendiente: el "cambio de receta" es hoy un tipo de solicitud con texto libre, sin efecto
automático — la aprobación real y vinculante llega con el Módulo 11 (recetas, sección siguiente).*

### Módulo 5 — Soplado

**Tabla:** `soplado_corridas`. Funciones: `soplado_iniciar_corrida`, `soplado_finalizar_corrida`,
`soplado_anular_corrida`. Vista `soplado_avance` (últimos 14 días).

**Roles y CRUD** (permiso `soplado`):

| Acción | Quién |
|---|---|
| Ver corridas y avance | Soplado, Jarabes y su Ayudante, Jefe de Producción, Gerente |
| Iniciar/finalizar/anular una corrida | Soplado |

**Formulario "Iniciar corrida":** sabor, presentación (solo las que existen para ese sabor, según
la matriz sabor × tamaño; solo PET), preforma a usar (opcional, buscador), proveedor y lote de esa
preforma (opcionales).

**Formulario "Finalizar corrida":** preformas usadas, merma de preforma, botellas sopladas, merma
de soplado, botellas etiquetadas (opcional), merma de etiquetado, motivo de la merma (obligatorio
si hay cualquiera de las tres), tiempo de parada de la máquina en minutos y su motivo (obligatorio
si hay tiempo de parada), observaciones.

**Automatizaciones:** hora de inicio y de fin automáticas; al finalizar, descuenta la preforma
usada del almacén de Soplado (si se indicó); el avance de 14 días muestra botellas buenas y, si se
conocen las unidades por caja de la presentación, su equivalente en cajas.

### Módulo 6 — Recetas y producción de Jarabes

**Tablas:** `jarabes_recetas`, `jarabes_receta_items`, `jarabes_preparados`,
`jarabes_preparado_insumos`. Vista `jarabes_receta_vigente`. Funciones: `jarabes_receta_crear`,
`jarabes_receta_aprobar`, `jarabes_receta_rechazar`, `jarabes_verificar_insumos`,
`jarabes_iniciar_preparado`, `jarabes_finalizar_preparado`, `jarabes_anular_preparado`.

**Roles y CRUD:**

| Acción | Permiso | Quién |
|---|---|---|
| Ver recetas y producción | `recetas:ver`, `jarabes_produccion:ver` | Jarabes, Ayudante, Jefe de Producción, Control de Calidad, Gerente |
| Proponer una receta | `recetas:crear` | Jarabes, Ayudante |
| Aprobar o rechazar una receta | `recetas:aprobar` | Jefe de Producción, Control de Calidad, Gerente (alcanza con **uno** de estos tres; ver nota) |
| Iniciar un preparado | `jarabes_produccion:crear` | Jarabes, Ayudante |
| Finalizar o anular un preparado | `jarabes_produccion:editar` | Jarabes, Ayudante |

**Formulario "Proponer receta":** sabor, lista de insumos (del Almacén de Jarabes) con la cantidad
que usa **un** preparado. Queda "propuesta" hasta que alguien la aprueba; al aprobarse, reemplaza a
la receta activa anterior de ese sabor (que pasa a "reemplazada").

**Formulario "Iniciar preparado":** sabor, cantidad de preparados (2, 1, 0,5...), tanque (opcional).
Mientras se completa, se ve en vivo la verificación de insumos (necesario vs. disponible en el
Almacén de Jarabes); si falta algo, un botón arma el pedido a Almacén con el faltante exacto
(reutiliza el Módulo 3), y el botón de iniciar queda deshabilitado hasta que alcance.

**Formulario "Finalizar preparado":** Brix (obligatorio, 0 a 100 — es lo que recibe Control de
Calidad), observaciones.

**Automatizaciones:** N° de lote correlativo por sabor; litros = preparados × litros del sabor;
el servidor vuelve a validar el stock al iniciar (por si cambió) y bloquea si no alcanza; el
descuento de insumos ocurre recién al **finalizar**, con la cantidad calculada al iniciar; se ve el
avance de Soplado de los últimos 14 días en la misma pantalla.

*La doble aprobación (Calidad **y** Producción) más la clave del Gerente, sobre esta misma tabla,
se implementó en el Módulo 11 — ver sección 12 bis, Módulo 11.*

### Módulo 7 — Control de Calidad

**Tabla:** `calidad_analisis`. Vista `calidad_pendientes` (preparados finalizados sin analizar).
Funciones: `calidad_registrar_analisis`, `calidad_actualizar_analisis`.

**Roles y CRUD** (permiso `calidad`):

| Acción | Quién |
|---|---|
| Ver pendientes e historial | Control de Calidad, Gerente, Jefe de Producción, Jarabes y su Ayudante |
| Registrar un análisis | Control de Calidad |
| Editar acción tomada/observaciones de un análisis ya hecho | Control de Calidad |

**Bandeja "Pendientes de analizar":** todo preparado que Jarabes finalizó y todavía no tiene
análisis, sin que nadie tenga que avisar — aparece solo. Se resalta si el Brix que midió Jarabes
quedó fuera del rango objetivo del sabor.

**Formulario "Registrar análisis":** Brix diluido, pH, aspecto/color (opcional), resultado
(Conforme / No conforme), acción tomada (**obligatoria** si no es conforme — esto es lo que
"notifica" a Jarabes y a Producción, que ya ven este módulo), observaciones.

**Editar un análisis:** solo se puede completar después la acción tomada y las observaciones; el
Brix, el pH y el resultado no se modifican una vez guardados.

---

### Incidentes resueltos durante la construcción (para no repetirlos)

- **Recursión infinita al iniciar sesión** (`schema_v22`): `rol_actual()` no era `security
  definer`, y con las decenas de políticas nuevas que pasaron a depender de ella, terminó
  consultándose a sí misma sin fin. Se resolvió haciéndola `security definer`.
- **Bloqueo de login en memoria** (`schema_v23`): el conteo de intentos fallidos vivía en la
  app y se perdía al reabrirla. Pasó al servidor, por correo, con bloqueo escalonado
  (30 s / 2 min / 10 min / 30 min / bloqueo permanente que solo el Gerente levanta).
- **Stock invisible entre almacenes** (`schema_v25`/`v28`): `inv_existencia` solo mostraba el
  stock de un ítem en el almacén dueño de su categoría. Un ítem recibido de otra área (ej.
  preformas que Soplado recibe de Almacén General) no aparecía en ningún lado. Se corrigió para
  que se vea en cualquier almacén con movimientos, navegable por su ruta real, sin poder darlo de
  alta ahí.
- **Columnas faltantes por ediciones posteriores** (`schema_v18b`): `v18` se fue editando con
  columnas nuevas (`stock_minimo`, `litros_por_preparado`, `cajas_por_paleta`,
  `empaques_por_palet`) después de que algunas bases ya lo habían ejecutado. Como
  `create table if not exists` no actualiza una tabla existente, esas bases quedaron
  desincronizadas. `v18b` las pone al día con `alter table` (no borra nada) — ver el aviso en la
  sección 11 para no repetir el error.

### Orden de ejecución en Supabase

`v14` → `v16` → `v17` → `v18` → **`v18b`** (corre si `v25` da error de columna inexistente) →
`v19` → `v20` → `v21` → **`v22`** (urgente: sin ella nadie inicia sesión) → `v23` → `v24` → `v25`
→ `v26` → `v27` → `v28` → `v29` (privilegios de tabla; correr de nuevo tras crear tablas/vistas
nuevas) → `v30` (Almacén General por tipo, no por material) → `v31` (migra el stock real de
tapas/preformas/materia prima) → `v32` (Llenadora) → `v33` (Codificación) → `v34` (Registro de
salidas) → `v35` (Mermas) → `v36` (Soda Cáustica) → `v37` (doble aprobación de recetas + clave
del Gerente) → `v38` (Informe general de Producción) → `v39` (devolución de un pedido) → `v40`
(salida directa de Almacén).

### Dónde está cada cosa en el código

| Módulo | Carpeta / archivos |
|---|---|
| Roles y permisos | `lib/core/constants.dart`, `lib/core/modulos.dart`, `lib/models/usuario.dart`, `lib/services/permisos_service.dart`, `lib/widgets/app_sidebar.dart`, `lib/widgets/selector_rol.dart` |
| 1. Inventario | `lib/features/inventario/`, `test/inventario_service_test.dart` |
| 2. Recepciones | `lib/features/recepciones/`, `test/recepciones_service_test.dart` |
| 3. Entregas | `lib/features/entregas/`, `test/entregas_service_test.dart` |
| 4. Solicitudes | `lib/features/solicitudes/`, `test/solicitudes_service_test.dart` |
| 5. Soplado | `lib/features/soplado/`, `test/soplado_service_test.dart` |
| 6. Jarabes | `lib/features/jarabes/`, `test/jarabes_service_test.dart` |
| 7. Calidad | `lib/features/calidad/`, `test/calidad_service_test.dart` |
| 8. Llenadora | `lib/features/llenadora/`, `test/llenadora_service_test.dart` |
| 8. Codificación | `lib/features/codificacion/`, `test/codificacion_service_test.dart` |
| 8. Registro de salidas | `lib/features/registro_salidas/`, `test/salidas_service_test.dart` |
| 9. Mermas | `lib/features/mermas/`, `test/mermas_service_test.dart` |
| 10. Soda Cáustica | `lib/features/soda_caustica/`, `test/soda_service_test.dart` |
| 11. Informe del Gerente | `lib/features/informe_gerente/`, `test/informe_service_test.dart`; doble aprobación en `lib/features/jarabes/` (mismo módulo de siempre) |
| Inicio (Dashboard) | `lib/features/dashboard/`, `test/dashboard_service_test.dart` |
| Login y bloqueo | `lib/services/auth_service.dart`, `lib/screens/auth/login_screen.dart` |
| Convenciones | `CLAUDE.md` |

### Módulo 8 — Llenadora, Codificación y Registro de salidas

**Tablas:** `llenadora_corridas`, `codificacion_corridas` (con `corrida_llenadora_id` opcional
para trazar de qué corrida de Llenadora salieron esas botellas), `salidas_reportes` +
`salidas_reporte_lineas`. Vistas: `llenadora_avance`, `codificacion_avance`,
`salidas_reporte_detalle` (con el total de botellas ya calculado), `salidas_planilla` (agrupado
por fecha/sabor/formato: la Planilla se arma sola).

**Decisión de diseño:** las tapas (Llenadora) y el solvente/tinta (Codificación) que se consumen
en una corrida NO generan un nuevo movimiento de inventario acá — ya se descontaron de Almacén
General cuando Almacén le entregó el pedido a esa área (Módulo 3, `inv_entregar_pedido`). Volver a
descontar en la corrida duplicaría la salida. Estas pantallas solo **registran** cuánto se usó,
como insumo para el informe de mermas (Módulo 9).

**Roles y CRUD** (permisos `llenado`, `codificacion`, `salidas`; ya seedeados en `v17`):

| Acción | Quién |
|---|---|
| Ver Llenadora / Codificación / Salidas | El propio rol, más Jefe de Producción y Gerente (solo ver) |
| Iniciar/finalizar/anular una corrida de Llenadora | Llenadora |
| Iniciar/finalizar/anular una corrida de Codificación | Codificación |
| Abrir, agregar líneas y cerrar el reporte de salidas | Registro de Salidas |

**Formulario "Iniciar corrida" (Llenadora):** turno, sabor, formato, preparado de Jarabes
(opcional, buscador por sabor) o lote/tanque a mano si no está en el sistema, tapa a usar
(opcional, solo para identificarla en el reporte).

**Formulario "Finalizar corrida" (Llenadora):** botellas llenadas; merma: botellas desechadas,
tapas usadas y desechadas, rebalse, motivo (obligatorio si hay cualquiera de las tres).

**Formulario "Iniciar corrida" (Codificación):** turno, sabor, formato, corrida de Llenadora de
origen (opcional), N° de lote, solvente y tinta a usar (opcionales, buscador).

**Formulario "Finalizar corrida" (Codificación):** botellas codificadas, código o fecha impresa;
merma: botellas y tapas mal tapadas, impurezas, motivo (obligatorio si hay cualquiera); consumo de
solvente y tinta (unidades).

**Formulario "Reporte de salidas":** se abre un reporte por fecha+turno (uno solo); dentro, se
agrega una línea por cada sabor/formato que salió, con su hora de inicio/fin y, según el
material, PET (palets, paquetes libres, botellas libres) o Vidrio (filas, cajas libres, botellas
libres); se cierra con observaciones opcionales.

**Automatizaciones:** hora de inicio/fin automáticas en las tres; N° de lote de Llenadora/
Codificación es texto libre (no correlativo, a diferencia del lote de Jarabes); el total de
botellas de cada línea del reporte se calcula solo con la fórmula de la sección 6 — completo para
PET (necesita que la presentación tenga `empaques_por_palet` y `unidades_por_caja` cargados, dato
pendiente, sección 13); parcial para Vidrio (cajas libres + botellas libres; las "filas" no
convierten a botellas hasta definir cuántas cajas arma un palet). La Planilla de producción
(`salidas_planilla`) se arma sola agrupando los reportes, sin que nadie la escriba a mano.

### Módulo 9 — Mermas

**Tablas:** `mermas_registros` + `mermas_causas` (cabecera y causas, solo para Jarabes/Calidad/
Vidrio). Vistas: `mermas_registros_detalle` (con el total y el % ya calculados) y
`mermas_consolidado`, que junta ese registro con la merma que **ya existía** en
`soplado_corridas`, `llenadora_corridas` y `codificacion_corridas` — esas tres áreas no repiten
nada acá, siguen cargando su merma dentro de su propia corrida, con su propio "producido"
(botellas sopladas/llenadas/codificadas) para el porcentaje.

**"Vidrio" no es un rol del organigrama.** La sección 14.4 lo menciona como área de la línea de
envasado en vidrio, sin decir quién la carga. Hasta confirmarlo, la registran Jefe de Producción
o Gerente (`_mermas_area_de_rol` en `v35`); **es lo menos validado de todo el módulo.**

**Roles y CRUD** (permiso `mermas`, ya seedeado en `v17`; `v35` le agrega `crear` a Control de
Calidad, que solo tenía `ver`):

| Acción | Quién |
|---|---|
| Ver el consolidado | Casi todos los roles operativos, Jefe de Producción y Gerente |
| Registrar merma de Jarabes | Jarabes, Ayudante de Jarabes |
| Registrar merma de Calidad | Control de Calidad |
| Registrar merma de "Vidrio" | Jefe de Producción, Gerente (por validar) |

**Formulario "Registrar merma":** área (según lo que el rol puede cargar), sabor, formato
(opcional), cantidad producida (opcional — sin ella no se calcula el %), una cantidad por cada
causa del área (Jarabes: menor volumen del esperado, diferencia de peso de insumos · Calidad:
exceso de agua · Vidrio: botellas quebradas, de ración, descarte por suciedad, tapas usadas),
motivo.

**Automatizaciones:** total de merma = suma de las causas; porcentaje = total ÷ producido; alerta
(fila en rojo) cuando supera el 3 % — ese 3 % es el "estándar" parejo para todos los sabores que
menciona la sección 14.4, no hay una tolerancia distinta guardada por sabor.

### Módulo 10 — Soda Cáustica

**Decisión de diseño:** en vez de armar un sistema de stock aparte, Soda Cáustica pasa a ser un
almacén más de `inv_almacenes` (junto a General, Jarabes y Soplado). Así reutiliza sin código
nuevo lo que ya construyeron los Módulos 1 y 3: el ítem "Soda cáustica" sigue catalogado en
Almacén General › Saneamiento (sección 5), y cuando Almacén le entrega un pedido (Módulo 3), con
`almacen_de_area` actualizado en `v36` entra solo a su almacén propio — antes de este cambio se
perdía. La "Solicitud de insumo a Almacén" de la sección 14.5 ya funcionaba: `soda_caustica` ya
era un área destino válida en `inv_pedidos`.

**Tablas:** solo `soda_entregas` es nueva (el registro de a quién se le entrega). El stock se ve
en Almacenes, como cualquier otro almacén — esta pantalla no repite esa vista.

**Roles y CRUD** (permiso `soda_caustica`, más `inventario_soda_caustica` para el almacén, ambos
seedeados en `v17`/`v36`):

| Acción | Quién |
|---|---|
| Ver el almacén de Soda Cáustica y sus entregas | Soda Cáustica, Jefe de Producción, Gerente |
| Registrar una entrega | Soda Cáustica |

**Formulario "Registrar entrega":** producto (buscador), cantidad, entregado a (persona), área
que recibe (opcional), motivo o uso (opcional).

**Automatizaciones:** descuenta el almacén de Soda Cáustica por lote, igual que una entrega del
Módulo 3 (primero lo que no tiene lote, después por vencimiento); guarda el saldo restante después
de esa entrega; constancia en PDF con los dos campos de firma (quien recibe / encargado) y un
recuadro de manejo seguro, porque es un producto peligroso.

**Pendiente:** la "merma propia" que menciona la sección 14.5 no se resolvió — la tabla de causas
por área de Mermas (sección 14.4, Módulo 9) no incluye a Soda Cáustica. Se agrega como una nueva
área en `mermas_registros` cuando se confirmen sus causas.

### Módulo 11 — Informe del Gerente

Tiene dos partes independientes, sobre módulos ya construidos.

**A. Doble aprobación de recetas + clave del Gerente** (sobre `jarabes_recetas`, Módulo 6).

El Módulo 6 aprobaba una receta con un solo visto bueno, de cualquiera de Producción, Calidad o
Gerencia. Ahora: Control de Calidad Y Jefe de Producción dan su visto bueno por separado
(`jarabes_receta_aprobar_calidad`/`jarabes_receta_aprobar_produccion`, cada función exige el rol
exacto — Calidad no puede dar el visto de Producción ni viceversa); recién con las dos, el Gerente
la activa con `jarabes_receta_confirmar_gerente(id, clave)`, que **vuelve a pedir la contraseña**
aunque ya esté con la sesión abierta (`_verificar_clave_actual`, compara contra
`auth.users.encrypted_password` con `crypt()`, el mismo mecanismo bcrypt que ya se usa para crear
cuentas desde v3/v8/v14). Se borró `jarabes_receta_aprobar` (el de un solo paso). Las recetas que
ya estaban `activa` con la regla vieja no se tocan; las que sigan `propuesta` desde ahora —
incluidas las que ya estuvieran pendientes al momento de correr `v37` — necesitan el proceso
nuevo. Rechazar sigue igual: cualquiera de los tres roles, en cualquier momento, con motivo
obligatorio.

| Acción | Quién |
|---|---|
| Ver la bandeja de recetas por resolver | Control de Calidad, Jefe de Producción, Gerente (cualquiera con `recetas:aprobar`) |
| Dar el visto bueno de Calidad | Control de Calidad, únicamente |
| Dar el visto bueno de Producción | Jefe de Producción, únicamente |
| Confirmar y activar (pide la clave) | Gerente, únicamente, y solo si ya están las dos anteriores |
| Rechazar | Cualquiera de los tres roles, en cualquier momento |

**B. Informe general de Producción** (solo lectura; junta datos que ya registraron otros módulos).

**Vista:** `informe_produccion_resumen` — por sabor y día, compara lo esperado
(`jarabes_preparados.cantidad_preparados` × `sabores.estandar_cajas`) contra lo producido
(`salidas_reporte_detalle`, convertido a cajas con `presentaciones.unidades_por_caja`), con la
desviación en cajas y en porcentaje. El detalle de merma por área (al hacer clic en una fila) sale
directamente de `mermas_consolidado` (Módulo 9), filtrado por esa fecha y ese sabor — no hizo
falta una vista nueva para eso, solo agregarle `sabor_id` a `mermas_consolidado` para poder
filtrar sin depender del nombre.

**Roles:** `informe_produccion:ver`, hoy solo el Gerente (ya seedeado en `v17`). Si Jefe de
Producción también necesita verlo, es un cambio de permisos desde la pantalla de Usuarios/Permisos,
no de código.

**Aproximación pendiente de validar con Producción:** el resumen compara por **fecha exacta**
(el día que se preparó el jarabe contra el día que salió embotellado). En la práctica el jarabe de
un día puede embotellarse otro día distinto; si eso pasa seguido, hay que ajustar la comparación
(por ejemplo, a una ventana de varios días). Además, "producido" solo cuenta las presentaciones que
ya tienen cargada la equivalencia en cajas (dato pendiente para varias, sección 13): la fila avisa
con "datos incompletos" cuándo el número puede estar de menos por eso.

## 13. Pendientes y dudas abiertas

**Datos que faltan**

- Botellas por empaque y empaques por palet de cada presentación PET (2,5 L, 2 L, 1 L, 600 ml,
  330 ml), y empaques por palet de vidrio.
- Filas y columnas de un palet de vidrio, y cuántas botellas por fila.
- Litros por preparado de los demás sabores (Tumbo, Granadina, Pomelo, Ross, Ginger Ale,
  Lima limón, Achachairú).
- Tamaños de Achachairú y H2O.
- Rango de Brix objetivo por sabor.

**A confirmar**

- Los números de lote de preparado, ¿empiezan de nuevo cada año o son correlativos permanentes?
- Firmas del responsable y del jefe de planta: ¿basta una confirmación en el sistema (usuario y
  hora) en lugar de la firma manuscrita? (Hoy el sistema registra usuario y hora automáticos, sin
  firma manuscrita, en todos los módulos construidos.)
- Quién hace el Balance de insumos mensual y si la marca ✓ debe quedar en el sistema.

**Decisiones tomadas por defecto (fáciles de cambiar)**

- Los roles nuevos ven Almacén General y Jarabes en solo lectura.
- Almacén no puede modificar el inventario de Jarabes (queda exclusivo de Jarabes).
- El Gerente ve el inventario en solo lectura.
- La tapa Long va en Vidrio.
- Soda cáustica está catalogada dentro de Saneamiento, no como categoría propia (el encargado de
  Soda Cáustica es un rol de todas formas, ver sección 3).

**Fotos por sumar:** registros de Llenadora, Codificación y Calidad, y los formularios de merma.

**Resuelto — "PEDIDO INTERNO DE ETIQUETAS" (devolución):** el concepto de **devolución** que le
faltaba a `inv_pedidos` se agregó en `v39` (mejora del Módulo 3): `inv_registrar_devolucion`
regresa a Almacén lo que sobró de una línea ya entregada, con su propia tabla
(`inv_devoluciones`). La entiende Almacén (no el área que lo recibió); no se puede devolver más de
lo entregado menos lo ya devuelto. En la pantalla de Entregas aparece un botón "Devolver" por
línea, una vez que el pedido ya se entregó.

**Resuelto — "SALIDA DE TERMOCONTRAIBLES" (salida directa):** se agregó en `v40` (mejora del
Módulo 1): `inv_registrar_salida_directa` registra fecha (automática), ítem, área, cantidad de
rollos (solo de referencia) y peso real — el peso real es lo que descuenta el stock, por lote,
igual que una entrega. Botón "Salida directa" en Almacenes, visible solo en Almacén General.

---

## 14. Formularios deducidos de los módulos pendientes (por validar)

**14.1 a 14.5 (Módulos 8, 9 y 10) ya se construyeron** con estos mismos campos — ver la
especificación "as-built" en la sección 12 bis, Módulos 8, 9 y 10. El texto original queda abajo
sin tocar, como registro de lo que se dedujo antes de construir; **todavía debe validarse con
Llenadora/Codificación/Registro de Salidas/Soda Cáustica** cuando puedan revisarlo. La "salida
directa" de tapas y solvente/tinta que Llenadora/Codificación reciben de Almacén sigue sin una
pantalla propia para ELLOS (`v40` la resolvió del lado de Almacén, sección 13); si hace falta que
Llenadora/Codificación también la vean desde su pantalla, es un agregado menor sobre lo ya
construido. En 14.4, el área "Vidrio" es lo menos validado: no tiene rol propio y quedó asignada a
Jefe de Producción/Gerente hasta que se confirme. En 14.5, la "merma propia" de Soda Cáustica
tampoco se resolvió, por la misma razón (14.4 no define sus causas).

No se pudo acceder a estos registros. Los campos salen de lo descrito en las entrevistas, de los
formularios que sí se vieron (que usan el mismo estilo) y de la lógica del proceso. **Cada uno debe
validarse con su encargado antes de construirse.** Convenciones comunes a todos, iguales a como
quedaron los módulos ya construidos: fecha, turno y responsable se completan solos (usuario y hora
de la sesión); lo calculable no se escribe; llevan observaciones.

### 14.1 Llenadora (Módulo 8)

- Fecha, turno, responsable.
- Por corrida: sabor, formato, N° de lote del preparado y tanque, **hora de inicio y final**,
  botellas llenadas.
- **Merma:** botellas desechadas, tapas usadas y desechadas, **rebalse** (cantidad), motivo.
- Observaciones.

### 14.2 Codificación (Módulo 8)

- Fecha, turno, responsable.
- Por corrida: sabor, formato, N° de lote, **hora de inicio y final**, botellas codificadas,
  código o fecha impresa.
- **Merma:** botellas y tapas mal tapadas, impurezas, motivo.
- **Consumo:** solvente y tinta usados (unidades), que descuenta de Almacén.
- Observaciones.

### 14.3 Registro de salidas (Módulo 8)

Reporte diario de producción: hora de inicio y final del día, turno, y por sabor y formato la hora
de inicio y final, más vidrio (filas, cajas libres, botellas libres) y PET (palets, paquetes
libres, botellas libres). El total de botellas se calcula con la fórmula de la sección 6, y la
Planilla de producción se genera sola desde estos registros.

### 14.4 Mermas (Módulo 9)

Un formulario base, con campos según el área.

- **Cabecera:** fecha, área, responsable (automáticos), sabor, formato, material (PET o vidrio).
- **Por causa:** cantidad de cada causa, según el área (ver abajo) y motivo.
- **Cálculo automático:** total de merma, **porcentaje sobre lo producido** y comparación con el
  estándar del sabor. Si supera el **3 %**, se marca en rojo y queda como alerta para el ingeniero.

| Área | Causas que registra |
|---|---|
| Soplado | botellas quebradas o deformes, preformas desechadas (**ya implementado en el Módulo 5**) |
| Jarabes | menor volumen del esperado, diferencia de peso de insumos |
| Llenadora | rebalse, botellas y tapas desechadas |
| Codificación | botellas y tapas mal tapadas, impurezas |
| Calidad | exceso de agua (Brix o volumen fuera de rango) |
| Vidrio | botellas quebradas, de ración, descarte por suciedad, tapas usadas |

Cada causa alimenta el informe general del Gerente (Módulo 11), atribuida al área que la originó.
La reposición o el desecho de lo perdido también se registra (con descuento del almacén cuando
aplica). Este módulo consolida en un solo lugar lo que Soplado ya registra por su cuenta.

### 14.5 Soda cáustica (Módulo 10)

- **Registro de entrega:** fecha y hora, entregado a (persona y área), cantidad, motivo o uso,
  saldo restante (automático), firma del que recibe y del encargado.
- **Constancia en PDF** en cada entrega (producto peligroso).
- **Solicitud de insumo** a Almacén y **merma** propia.

### 14.6 Plan de producción del día (existente, se mantiene)

Lo arma el Jefe de Producción. Todas las áreas lo ven; Jarabes lo usa para elegir los concentrados
del día y Soplado para adelantar botellas.
