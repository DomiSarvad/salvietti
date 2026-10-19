# Encuesta para Google Forms

Son las mismas 10 preguntas del Apéndice B. Hay dos formas de subirlas.

## Opción A: crear el formulario solo (2 minutos)

1. Entra a <https://script.google.com> con tu cuenta de Google y elige **Nuevo proyecto**.
2. Borra lo que aparece, pega el código de abajo y guarda.
3. Pulsa **Ejecutar**. La primera vez Google pide permiso: acepta con tu cuenta.
4. Abre **Registro de ejecución**: ahí salen dos enlaces, el de edición y el que debes enviar a los trabajadores.

```javascript
function crearEncuestaSalvietti() {
  var form = FormApp.create('Encuesta al personal de la planta Salvietti, Sucre');
  form.setDescription('La encuesta es anónima y sus respuestas se usarán solo para un proyecto de grado. Marque una sola opción en cada pregunta. Toma menos de 5 minutos.');
  form.setCollectEmail(false);

  var preguntas = [
    ['¿En qué área trabaja?',
      ['Almacén', 'Jarabes', 'Soplado', 'Llenado o codificación', 'Control de calidad', 'Otra']],
    ['¿Dónde registra los movimientos o la producción de su área?',
      ['Solo en formularios de papel', 'Solo en Excel', 'En papel y después en Excel', 'No registra']],
    ['¿Cada cuánto se actualiza el registro de su área?',
      ['En el momento de cada movimiento', 'Al final del turno', 'Una vez por semana', 'Una vez al mes']],
    ['¿Con qué frecuencia encuentra diferencias entre lo que dice el registro y lo que hay físicamente?',
      ['Nunca', 'Rara vez', 'Cada mes', 'Cada semana', 'Casi todos los días']],
    ['Cuando hay una diferencia, ¿cuál es la causa más frecuente?',
      ['Error al anotar o al transcribir', 'El movimiento se registró tarde', 'El consumo no se descontó', 'Merma no registrada', 'No sabe']],
    ['En el último año, ¿cuántas veces se detuvo su trabajo porque se agotó un insumo?',
      ['Ninguna', '1 o 2 veces', '3 a 5 veces', 'Más de 5 veces']],
    ['¿Cómo es la conexión a internet en su área de trabajo?',
      ['Estable todo el día', 'Se corta a veces', 'Se corta con frecuencia', 'No hay conexión']],
    ['¿Qué equipo usaría con más facilidad para registrar su trabajo?',
      ['Computadora de escritorio', 'Teléfono celular', 'Tableta', 'Ninguno']],
    ['¿Qué tan necesario considera un sistema para registrar el inventario y la producción?',
      ['Muy necesario', 'Necesario', 'Poco necesario', 'No es necesario']],
    ['¿Estaría dispuesto a aprender a usar un sistema nuevo?',
      ['Sí', 'Sí, con capacitación', 'No estoy seguro', 'No']]
  ];

  preguntas.forEach(function (p) {
    form.addMultipleChoiceItem().setTitle(p[0]).setChoiceValues(p[1]).setRequired(true);
  });

  Logger.log('Editar: ' + form.getEditUrl());
  Logger.log('Enviar a los trabajadores: ' + form.getPublishedUrl());
}
```

## Opción B: copiar a mano

En <https://forms.google.com> crea un formulario en blanco. Cada pregunta es de tipo **Varias opciones** y **Obligatoria**.

**Título:** Encuesta al personal de la planta Salvietti, Sucre

**Descripción:** La encuesta es anónima y sus respuestas se usarán solo para un proyecto de grado. Marque una sola opción en cada pregunta. Toma menos de 5 minutos.

1. ¿En qué área trabaja?
   - Almacén
   - Jarabes
   - Soplado
   - Llenado o codificación
   - Control de calidad
   - Otra
2. ¿Dónde registra los movimientos o la producción de su área?
   - Solo en formularios de papel
   - Solo en Excel
   - En papel y después en Excel
   - No registra
3. ¿Cada cuánto se actualiza el registro de su área?
   - En el momento de cada movimiento
   - Al final del turno
   - Una vez por semana
   - Una vez al mes
4. ¿Con qué frecuencia encuentra diferencias entre lo que dice el registro y lo que hay físicamente?
   - Nunca
   - Rara vez
   - Cada mes
   - Cada semana
   - Casi todos los días
5. Cuando hay una diferencia, ¿cuál es la causa más frecuente?
   - Error al anotar o al transcribir
   - El movimiento se registró tarde
   - El consumo no se descontó
   - Merma no registrada
   - No sabe
6. En el último año, ¿cuántas veces se detuvo su trabajo porque se agotó un insumo?
   - Ninguna
   - 1 o 2 veces
   - 3 a 5 veces
   - Más de 5 veces
7. ¿Cómo es la conexión a internet en su área de trabajo?
   - Estable todo el día
   - Se corta a veces
   - Se corta con frecuencia
   - No hay conexión
8. ¿Qué equipo usaría con más facilidad para registrar su trabajo?
   - Computadora de escritorio
   - Teléfono celular
   - Tableta
   - Ninguno
9. ¿Qué tan necesario considera un sistema para registrar el inventario y la producción?
   - Muy necesario
   - Necesario
   - Poco necesario
   - No es necesario
10. ¿Estaría dispuesto a aprender a usar un sistema nuevo?
    - Sí
    - Sí, con capacitación
    - No estoy seguro
    - No

## Después de enviarla

- Comparte el enlace por WhatsApp con las 12 personas de Producción, Jarabes y Almacenes.
- En la pestaña **Respuestas** de Google Forms, pulsa el ícono de hoja de cálculo para exportarlas a Google Sheets y descarga el archivo como Excel o CSV.
- Con ese archivo se arman los 10 gráficos circulares del Apéndice E y se completa la fecha y el número de respuestas en la técnica de Encuesta del Capítulo I.
