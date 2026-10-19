# Entrevista — Área de Jarabes

Este documento reconstruye en formato pregunta/respuesta la información reunida sobre el área de
Jarabes, porque la entrevista original no siguió un cuestionario armado de antemano. Las preguntas
son una propuesta de cómo debería haberse estructurado; las respuestas son la información real que
ya se usó para diseñar y construir el Módulo 6 (Recetas y producción de Jarabes). La fuente es
`docs/requerimientos-reestructuracion.md`.

---

## 1. Rol y responsabilidades

**P: ¿Quién está a cargo del área de Jarabes y qué funciones cumple cada persona?**

R: El **Jefe de Jarabes** elabora los concentrados, maneja el almacén propio del área y propone
cambios de receta. El **Ayudante de Jarabes** tiene el mismo alcance que el Jefe sobre esa misma
área — no es un rol de menor nivel, puede hacer todo lo mismo.

**P: ¿Jarabes depende de otra área para trabajar, o es autónoma?**

R: Maneja su propio almacén (igual que Soplado), a diferencia de las demás áreas de Producción, que
piden todo a Almacén General. Aun así, Almacén General es quien le entrega inicialmente los insumos
que después quedan bajo el control de Jarabes.

## 2. Almacén propio de Jarabes

**P: ¿Cómo entran los insumos al almacén de Jarabes?**

R: Almacén General recibe la materia prima (la pesa, la registra) y se la entrega a Jarabes. Esa
entrega funciona como una **segunda recepción**: el sistema le pasa a Jarabes la lista de lo
entregado, Jarabes la revisa ítem por ítem, anota si algo llegó mal (eso avisa a Almacén) y recién
ahí cierra como "conforme". A partir de ese momento, el insumo es del almacén de Jarabes.

**P: ¿Qué insumos se manejan específicamente en el almacén de Jarabes?**

R:
- Azúcar, en quintales de 46 kg.
- Conservantes: benzoato americano y benzoato chino.
- Edulcorantes.
- Ácidos: cítrico y fosfórico.
- Colorantes: tartrazina, amaranto, sunset, azul, verde, caramelo.
- Concentrados, uno por cada sabor.
- Alcohol (llega medido en litros, pero se pesa y controla en kilos).
- Sorbato, natamicina, cafeína, vimix, citrato.
- Telas y filtros de cartucho.

**P: ¿Hay alguna conversión de unidades particular en estos insumos?**

R: Sí — por ejemplo, el azúcar llega en quintales de 46 kg y el alcohol en litros pero se pesa en
kilos; el sistema hace la conversión solo, no hace falta que la persona calcule a mano.

## 3. Catálogo de sabores

**P: ¿Qué sabores produce Jarabes?**

R: Papaya, Kinotto, Granadina, Naranja, Ross, Ginger Ale, Tumbo, Piña, Pomelo, Lima limón,
Achachairú, más los isotónicos (Kiwi, Frutilla, Arándano azul) y agua (H2O).

**P: ¿Cuántos litros produce un preparado, según el sabor?**

R: Confirmado para cuatro sabores: Papaya 1220 L, Naranja 1050 L, Piña 1050 L, Kinotto 1080 L. Para
el resto (Tumbo, Granadina, Pomelo, Ross, Ginger Ale, Lima limón, Achachairú) todavía falta que
Jarabes confirme el dato.

**P: ¿Cuál es la producción esperada ("estándar") de cada preparado?**

R: Depende del sabor: Papaya rinde **12 cajas (6 paletas)**; todos los demás sabores rinden
**10 cajas (5 paletas)**. La equivalencia general es 2 cajas = 1 paleta.

**P: ¿Hay un rango de dulzor (Brix) esperado por sabor?**

R: Sí, cada sabor debería tener su propio rango de Brix objetivo para que Control de Calidad
pueda evaluar si el preparado salió dentro de lo esperado — ese rango puntual por sabor todavía no
se terminó de confirmar con Jarabes.

## 4. La receta

**P: ¿Cómo es una receta en la práctica? ¿Podrías dar un ejemplo?**

R: La de un preparado de Papaya es: 18 quintales de azúcar, 1 kg de benzoato americano, 1 kg de
sorbato de potasio, 0,976 kg de concentrado de papaya Sapore, 1,22 kg de alcohol, 0,004 kg de
sunset/tartrazina y 9 kg de ácido cítrico. Con eso se obtienen 1220 litros.

**P: Si Jarabes decide preparar más de uno (por ejemplo, 2 preparados), ¿hay que calcular la
receta de nuevo a mano?**

R: No, la receta se multiplica sola según la cantidad de preparados que se elija (2, 1, 1/2, etc.).

**P: ¿Qué pasa si al momento de preparar falta algún insumo de la receta?**

R: El sistema avisa que falta y ofrece, en el momento, solicitarlo a Almacén antes de empezar —
no hace falta salir de la pantalla de Jarabes para pedirlo. Mientras no alcance el insumo, no se
puede iniciar el preparado.

**P: ¿Las recetas se pueden modificar? ¿Quién tiene que autorizarlo?**

R: Sí, mediante una propuesta: Jarabes (el Jefe o el Ayudante) propone el cambio, pero no queda
activo solo con eso — hace falta la aprobación por separado de **Control de Calidad** y del
**Jefe de Producción**, y recién con las dos aprobaciones el **Gerente** confirma el cambio con su
propia contraseña. Es un cambio que afecta a todo el sistema (receta activa de ese sabor), por eso
el control es tan estricto. Rechazar el cambio, en cambio, lo puede hacer cualquiera de los tres
roles en cualquier momento, explicando el motivo.

## 5. El proceso diario de preparado

**P: ¿Cómo decide Jarabes qué va a preparar cada día?**

R: Según el plan de producción que arma el Jefe de Producción (ese plan lo ven todas las áreas).
Jarabes elige el sabor del día y cuántos preparados va a hacer.

**P: ¿Qué datos quedan registrados al empezar un preparado?**

R: La fecha y la hora de inicio, de forma automática (no se escriben a mano).

**P: ¿Y al terminarlo?**

R: La hora final, también automática, y el **Brix** (porcentaje de dulzor) que mide Jarabes. Ese
dato es importante porque el jarabe se diluye con agua antes de embotellarse, y eso baja el dulzor
— por eso Control de Calidad lo necesita para decidir si hace falta ajustar algo. Al finalizar
también se descuenta del almacén de Jarabes el insumo que efectivamente se usó.

**P: ¿El lote de un preparado tiene algún número o código?**

R: Sí, un número correlativo por sabor (por ejemplo, para papaya: lote 27, 28, 29-30, 31...). Cada
recepción de materia prima también se trata como un lote aparte, y se consume en orden FIFO
(primero el que llegó hace más tiempo).

**P: ¿Jarabes tiene que estar pendiente de lo que hacen otras áreas al planificar su producción?**

R: Sí, en especial de Soplado: Jarabes revisa el avance de botellas sopladas para no preparar más
jarabe del que hay botellas disponibles para embotellar.

## 6. Relación con Control de Calidad

**P: ¿Qué pasa con el dato de Brix que registra Jarabes al finalizar un preparado?**

R: Pasa directo a Control de Calidad, que hace sus propios análisis (pH, entre otros) sobre ese
mismo preparado. Si algo no cumple con lo esperado, se notifica — tanto a Jarabes como a
Producción.

## 7. Mermas propias de Jarabes

**P: ¿Qué causas de merma son específicas del área de Jarabes?**

R: Dos: que el preparado rinda **menos volumen del esperado**, y **diferencias de peso** en los
insumos usados.

**P: ¿A partir de qué punto una merma se considera un problema?**

R: Cuando la merma de producción supera el **3 %** del volumen esperado — ese umbral es el mismo
para todos los sabores, no hay un porcentaje distinto definido por sabor.

---

## Preguntas que quedaron abiertas (pendientes de confirmar con Jarabes)

- Litros por preparado de los sabores que todavía no se confirmaron: Tumbo, Granadina, Pomelo,
  Ross, Ginger Ale, Lima limón, Achachairú.
- Rango de Brix objetivo, sabor por sabor.
- Los números de lote de preparado, ¿arrancan de nuevo cada año o son correlativos para siempre?

## Cómo quedó resuelto en el sistema (Módulo 6, ya construido)

- **Tablas:** `jarabes_recetas`, `jarabes_receta_items`, `jarabes_preparados`,
  `jarabes_preparado_insumos`.
- **Pantallas:** "Proponer receta", "Iniciar preparado" (con verificación de insumos en vivo y
  botón para solicitar el faltante a Almacén) y "Finalizar preparado" (pide el Brix).
- El plan del día de Producción aparece dentro de Jarabes como una tarjeta de referencia: ordena
  primero los sabores que ya están planificados (no restringe elegir otro si hace falta) y, al
  finalizar un preparado de un sabor que está en el plan, lo marca solo como completado en
  Producción.
- La doble aprobación de recetas (Calidad + Producción + clave del Gerente) se terminó de
  implementar en el Módulo 11.
