-- =====================================================================
-- SALVIETTI CONTROL — v11: carga inicial de Jarabes a partir de su hoja
-- de "Recepción de Materia Prima" en papel.
-- Ejecutar DESPUÉS de schema_v7_permisos_roles.sql (necesita que exista
-- la columna `area` en materia_prima), en el SQL Editor de Supabase.
-- =====================================================================
--
-- ADVERTENCIA: esto es una TRANSCRIPCIÓN de una foto de la hoja escrita
-- a mano — no una lectura directa de un sistema. Antes de confiar en
-- estos números para producción real, comparen cada fila contra la
-- hoja física. En particular:
--   * Los "quintales" (qq) de Azúcar se pasaron a KG usando 46 kg/qq
--     (la misma conversión que ya usan para el Azúcar general).
--   * Dos fechas de vencimiento no se pudieron leer con confianza
--     (Concentrado Ross y el primer lote de Azúcar) y se dejaron vacías
--     a propósito, en vez de inventar una fecha. Complétenlas a mano
--     desde Inventario cuando puedan confirmarlas en la hoja física.
--   * Cuando la hoja solo indicaba el año de vencimiento (sin día/mes
--     exacto), se usó el 31 de diciembre de ese año como aproximación.
--
-- Cada insumo se crea como una fila NUEVA marcada área = 'jarabes',
-- separada de la materia prima general de Almacén (aunque el nombre se
-- parezca, ej. Azúcar): Jarabes lleva su propio registro de entradas,
-- tal como ya lo hacen en papel.

insert into public.materia_prima (detalle, unidad_medida, stock_minimo, proveedor_habitual, area)
select v.detalle, 'KG', v.stock_minimo, v.proveedor, 'jarabes'
from (values
  ('CONCENTRADO NARANJA', 5.0, 'Sapore'),
  ('CONCENTRADO KINOTTO', 5.0, 'Sapore'),
  ('CONCENTRADO GRANADINA', 5.0, 'Sapore'),
  ('CONCENTRADO ROSS', 5.0, 'Sapore'),
  ('CONCENTRADO PAPAYA', 5.0, 'Sapore'),
  ('ACIDO FOSFORICO (JARABES)', 10.0, 'Mathiesen'),
  ('COLOR CARAMELO', 20.0, 'Alem.Corp'),
  ('CONCENTRADO CHOCOLATE', 1.0, 'Sapore'),
  ('CONCENTRADO MENTA', 1.0, 'Intercom'),
  ('AZUCAR (JARABES)', 500.0, 'San Aurelio'),
  ('CONCENTRADO SIN ESPECIFICAR', 1.0, 'Intercom')
) as v(detalle, stock_minimo, proveedor)
where not exists (
  select 1 from public.materia_prima m
  where m.detalle = v.detalle and m.area = 'jarabes'
);

-- Un movimiento de ingreso por cada entrega registrada en la hoja.
insert into public.movimientos (
    tabla_origen, item_id, tipo, cantidad, unidad_medida, lote,
    fecha_vencimiento, proveedor, observacion, created_at
)
select 'materia_prima', m.id, 'ingreso', v.cantidad, 'KG', v.lote,
       v.vencimiento, v.proveedor, v.observacion, v.fecha_llegada::timestamptz
from (values
  ('CONCENTRADO NARANJA',   40.0,     'BU-0034 2916', date '2026-12-21', 'Sapore',     'Ficha técnica 08-05-03-18 0032',                date '2026-05-19'),
  ('CONCENTRADO KINOTTO',   40.0,     'BU-0034 1427', date '2026-10-09', 'Sapore',     'Ficha técnica 08-05-03-18 0032',                date '2026-05-19'),
  ('CONCENTRADO GRANADINA', 14.950,   'BU-0033 7627', date '2027-01-30', 'Sapore',     'Ficha técnica 08-05-03-18 0032',                date '2026-05-19'),
  ('CONCENTRADO ROSS',      15.0,     'BU-0033 9067', null,              'Sapore',     'Ficha técnica 08-05-03-18 0032. Vencimiento en la hoja ilegible/inconsistente: verificar a mano.', date '2026-05-19'),
  ('CONCENTRADO PAPAYA',    24.9,     'BU0032 7686',  date '2026-08-26', 'Sapore',     'Ficha técnica 08-05-03-18 0032',                date '2026-05-19'),
  ('ACIDO FOSFORICO (JARABES)', 105.0,'-',            date '2028-12-31', 'Mathiesen',  'Ficha técnica 08-05-03-19 0109',                date '2026-05-19'),
  ('COLOR CARAMELO',        265.0,    'DC-1863',      date '2027-12-31', 'Alem.Corp',  'Ficha técnica 08-05-03-19 0125',                date '2026-05-19'),
  ('CONCENTRADO CHOCOLATE', 0.514,    'BU-0033 8241', date '2027-12-31', 'Sapore',     'Ficha técnica 08-05-03-18 0032',                date '2026-05-20'),
  ('CONCENTRADO MENTA',     0.4554,   null,           date '2026-12-15', 'Intercom',   null,                                            date '2026-05-21'),
  ('AZUCAR (JARABES)',      1104.0,   null,           null,              'San Aurelio','24 quintales (a 46 kg/qq). Vencimiento en la hoja ilegible/inconsistente: verificar a mano.', date '2026-05-22'),
  ('AZUCAR (JARABES)',      24610.0,  'G 386890',     date '2026-12-31', 'San Aurelio','535 quintales (a 46 kg/qq). Ficha técnica 08-01-03-09 0004', date '2026-05-26'),
  ('CONCENTRADO SIN ESPECIFICAR', 0.099, '1E-0391',   date '2026-12-15', 'Intercom',   'Ficha técnica 04-04-03-18 0009',                date '2026-05-27')
) as v(detalle, cantidad, lote, vencimiento, proveedor, observacion, fecha_llegada)
join public.materia_prima m on m.detalle = v.detalle and m.area = 'jarabes'
where not exists (
  select 1 from public.movimientos mv
  where mv.item_id = m.id and mv.lote is not distinct from v.lote
    and mv.cantidad = v.cantidad and mv.tabla_origen = 'materia_prima'
);
