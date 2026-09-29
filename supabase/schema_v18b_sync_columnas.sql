-- =====================================================================
-- SALVIETTI CONTROL — v18b: sincroniza columnas de v18 que faltan.
-- Ejecutar AHORA, antes de continuar con v25 en adelante (o de re-intentar
-- cualquiera de ellos si dieron error de columna inexistente). Se puede
-- volver a ejecutar sin problema.
-- =====================================================================
--
-- Causa: v18 se escribió y después se le agregaron columnas con varias
-- ediciones a lo largo de la conversación (stock_minimo, litros_por_preparado,
-- cajas_por_paleta, empaques_por_palet...). `create table if not exists` NO
-- actualiza una tabla que ya existe, así que si esa tabla se creó ANTES de
-- alguna de esas ediciones, a tu base le faltan esas columnas — por eso el
-- error "column i.stock_minimo does not exist" al correr v25.
--
-- Este archivo agrega, con ALTER TABLE ... ADD COLUMN IF NOT EXISTS
-- (seguro: no borra ni pisa nada), todo lo que pueda faltar según el v18
-- actual. Si una columna ya existe, esa línea no hace nada.

alter table public.inv_items
    add column if not exists sabor_id bigint references public.sabores(id),
    add column if not exists presentacion_id bigint references public.presentaciones(id),
    add column if not exists atributos jsonb not null default '{}'::jsonb,
    add column if not exists consumo_diario_manual numeric,
    add column if not exists stock_minimo numeric;

alter table public.presentaciones
    add column if not exists empaques_por_palet int;

-- Cada movimiento apunta al lote (recepción) del que sale o entra.
alter table public.inv_movimientos
    add column if not exists lote_recepcion_id bigint references public.inv_recepciones(id);
create index if not exists inv_movimientos_lote on public.inv_movimientos (lote_recepcion_id);

-- sabores: agrega lo que falte y NO ROMPE si 'tipo' ya existía con un check
-- viejo (sin 'agua'); se lo reemplaza por el actual.
alter table public.sabores
    add column if not exists tipo text not null default 'refresco',
    add column if not exists litros_por_preparado numeric,
    add column if not exists estandar_cajas numeric not null default 10,
    add column if not exists cajas_por_paleta numeric not null default 2,
    add column if not exists brix_min numeric,
    add column if not exists brix_max numeric;

do $$
declare c text;
begin
    for c in
        select conname from pg_constraint
         where conrelid = 'public.sabores'::regclass and contype = 'c'
           and pg_get_constraintdef(oid) ilike '%tipo%'
    loop
        execute format('alter table public.sabores drop constraint %I', c);
    end loop;
end $$;
alter table public.sabores
    add constraint sabores_tipo_check check (tipo in ('refresco', 'isotonico', 'agua'));

-- El default de estandar_cajas cambió de 12 a 10 (papaya sigue en 12) DESPUÉS
-- de que algunas bases ya hubieran creado sabores con el default viejo.
-- Corrige cualquier sabor que no sea papaya y haya quedado en 12 por eso.
update public.sabores set estandar_cajas = 10
 where nombre <> 'Papaya' and estandar_cajas = 12;
update public.sabores set estandar_cajas = 12 where nombre = 'Papaya' and estandar_cajas <> 12;

-- Con las columnas ya al día, se recrea la vista. Se borra primero porque
-- `create or replace view` no permite meter una columna (stock_minimo) en el
-- medio de una vista que ya existe con menos columnas. Una vista no guarda
-- datos: borrarla y recrearla no pierde nada.
drop view if exists public.inv_existencia;
create view public.inv_existencia with (security_invoker = true) as
    with consumo as (
        select item_id, almacen_id, (-sum(cantidad)) / 30.0 as diario
          from public.inv_movimientos
         where tipo = 'salida' and fecha >= now() - interval '30 days'
         group by item_id, almacen_id
    ),
    almacenes_relevantes as (
        select i.id as item_id, c.almacen_id
          from public.inv_items i
          join public.inv_categorias c on c.id = i.categoria_id
        union
        select m.item_id, m.almacen_id from public.inv_movimientos m
    ),
    base as (
        select i.id as item_id, i.codigo, i.detalle, i.unidad, i.categoria_id,
               i.stock_minimo, ar.almacen_id,
               coalesce(s.cantidad_sistema, 0) as cantidad_sistema,
               coalesce(nullif(co.diario, 0), i.consumo_diario_manual) as consumo_diario
          from public.inv_items i
          join almacenes_relevantes ar on ar.item_id = i.id
          left join public.inv_stock s on s.item_id = i.id and s.almacen_id = ar.almacen_id
          left join consumo co on co.item_id = i.id and co.almacen_id = ar.almacen_id
         where i.activo
    )
    select b.*,
           (select k.cantidad_real from public.inv_conteos k
             where k.item_id = b.item_id and k.almacen_id = b.almacen_id
             order by k.fecha desc, k.id desc limit 1) as cantidad_real,
           case when b.consumo_diario > 0
                then b.cantidad_sistema / b.consumo_diario end as dias_existencia
      from base b;
