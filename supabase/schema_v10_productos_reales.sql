-- =====================================================================
-- SALVIETTI CONTROL — v10: catálogo real de productos terminados +
-- fórmulas que faltaban (Papaya, Kinotto), a partir del reporte de
-- producción que comparten por WhatsApp.
-- Ejecutar DESPUÉS de schema_v6_productos_terminados.sql, en el SQL
-- Editor de Supabase.
-- =====================================================================
--
-- IMPORTANTE — qué es un supuesto y qué no:
--   * Los PRODUCTOS (nombre, tamaño, envase, botellas por paquete) son
--     los reales del reporte de WhatsApp.
--   * La PREFORMA de cada producto se eligió por tamaño (2,5 L / 2 L),
--     que sí corresponde 1 a 1 con el producto — es información segura.
--   * La TAPA se eligió solo por el formato correcto (Long/Short Finish
--     según el envase), pero el COLOR se asignó sin ningún criterio real
--     porque no hay forma de saber qué color de tapa usa cada sabor a
--     partir de los datos disponibles. Revisen y corrijan el color
--     correcto de cada producto desde el botón "Productos" en la
--     pantalla de Producción antes de usar esto en serio.
--   * Las CANTIDADES de la fórmula (formula_detalle) de Papaya y Kinotto
--     son un supuesto razonable, calcado de la proporción que ya usan
--     Naranja/Granadina en el seed original (10.5 kg azúcar, ~1-1.2 kg
--     esencia, 0.2 kg ácido cítrico, 0.3 kg citrato de sodio por cada
--     100 L de lote). Ajústenlas con el botón "Editar consumo" de
--     Producción en cuanto tengan la receta real.

-- ---------------------------------------------------------------------
-- 1. Fórmulas que faltaban (Granadina ya existía en seed.sql)
-- ---------------------------------------------------------------------
insert into public.formulas (sabor, rendimiento_litros)
select v.sabor, 100
from (values ('Papaya'), ('Kinotto')) as v(sabor)
where not exists (select 1 from public.formulas f where f.sabor = v.sabor);

insert into public.formula_detalle (formula_id, materia_prima_id, cantidad_por_lote)
select f.id, m.id, v.cant
from (values
  ('Papaya','AZUCAR',10.5),
  ('Papaya','ESENCIA DE PAPAYA (SAPORE)',1.2),
  ('Papaya','ACIDO CITRICO',0.2),
  ('Papaya','CITRATO DE SODIO',0.3),
  ('Kinotto','AZUCAR',10.5),
  ('Kinotto','ESENCIA DE KINOTTO COLA',1.0),
  ('Kinotto','ACIDO CITRICO',0.2),
  ('Kinotto','CITRATO DE SODIO',0.3)
) as v(sabor, mp, cant)
join public.formulas f on f.sabor = v.sabor
join public.materia_prima m on m.detalle = v.mp
where not exists (
  select 1 from public.formula_detalle fd
  where fd.formula_id = f.id and fd.materia_prima_id = m.id
);

-- ---------------------------------------------------------------------
-- 2. Catálogo de productos terminados (los 6 del reporte de WhatsApp)
-- ---------------------------------------------------------------------
insert into public.productos_terminados
  (nombre, formula_id, envase, litros_por_botella, botellas_por_paquete, preforma_id, tapa_id)
select
  v.nombre,
  (select id from public.formulas where sabor = v.sabor),
  v.envase,
  v.litros_por_botella,
  v.botellas_por_paquete,
  case when v.envase = 'pett' then
    (select id from public.preformas where detalle = v.preforma_detalle limit 1)
  else null end,
  case when v.envase = 'pett' then
    (select id from public.tapas
       where formato = v.tapa_formato and detalle not ilike '%observado%'
       order by color limit 1)
  else
    -- Ojo: en el seed hay dos filas con "Tapa Corona" en distintos
    -- campos. La de detalle='Tapa Corona' (color Azul) es la tapa
    -- corona genérica para botella de vidrio; la otra ("Tapa Botellón
    -- 20 lt", que tiene 'Tapa Corona' en el campo formato) es para
    -- garrafones de 20 L, no para esto.
    (select id from public.tapas where detalle = 'Tapa Corona' limit 1)
  end
from (values
  ('2,5 L Papaya - Pett',        'Papaya',   'pett',   2.5, 6.0,  'Preforma de 50.8gr', 'Short Finish'),
  ('COLA KINOTTO 2 LT NR - Pett','Kinotto',  'pett',   2.0, 6.0,  'Preforma de 47gr',   'Long Finish'),
  ('2,5 L Granadina - Pett',     'Granadina','pett',   2.5, 6.0,  'Preforma de 50.8gr', 'Short Finish'),
  ('2 L Granadina - Pett',       'Granadina','pett',   2.0, 6.0,  'Preforma de 47gr',   'Long Finish'),
  ('300 ml Granadina - Vidrio',  'Granadina','vidrio', 0.3, 24.0, null,                  null),
  ('300 ml Papaya - Vidrio',     'Papaya',   'vidrio', 0.3, 24.0, null,                  null)
) as v(nombre, sabor, envase, litros_por_botella, botellas_por_paquete, preforma_detalle, tapa_formato)
where not exists (
  select 1 from public.productos_terminados p where p.nombre = v.nombre
);
