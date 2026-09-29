-- =====================================================================
-- SALVIETTI CONTROL — v31: migra el stock real de Tapas, Preformas y
-- Materia Prima (inventario anterior) al Almacenes nuevo (inv_items +
-- inv_movimientos). Ejecutar DESPUÉS de v18 a v30, en el SQL Editor de
-- Supabase. Se puede volver a ejecutar sin problema: no duplica ítems ni
-- vuelve a sumar stock ya migrado.
-- =====================================================================
--
-- NO borra las tablas viejas (`tapas`, `preformas`, `materia_prima`):
-- quedan como respaldo/auditoría. Simplemente dejan de usarse desde la app.
--
-- Cómo clasifica cada ítem:
--   * Tapas: si el detalle o el formato menciona "PET" o "Short" va a
--     Tapas › PET; si menciona "Corona" o "Long" va a Tapas › Vidrio; el
--     resto (no se puede adivinar con certeza) va a
--     Tapas › Sin clasificar (migrado) — alguien de Almacén lo reubica
--     después con "Editar" en Almacenes, un cambio de dos clics.
--   * Preformas: el tamaño (2.5, 2, 600, 330) elige la subcategoría; si no
--     matchea, va a Preformas › Sin clasificar (migrado).
--   * Materia Prima con área "jarabes": se busca una palabra clave del
--     detalle (azúcar, conservante, ácido…) para ubicarlo en la categoría
--     de Jarabes que le corresponde; si no matchea, a
--     Jarabes › Sin clasificar (migrado).
--   * Materia Prima sin área "jarabes": todo a
--     Almacén General › Materia prima (migrado) (no hay forma automática
--     de subdividirla mejor con los datos que trae la tabla vieja).
--
-- Formato, color, tamaño y proveedor originales quedan guardados en
-- `atributos` (jsonb) del ítem nuevo y también se agregan al detalle, así
-- no se pierden aunque la pantalla todavía no tenga columnas para ellos.
--
-- Si el ítem YA existe en Almacenes (mismo nombre en la misma categoría —
-- por ejemplo, algo del catálogo inicial de Jarabes), no se duplica: se le
-- suma el stock que le faltaba para llegar al de la tabla vieja.

-- ---------------------------------------------------------------------
-- 0. Columnas de rastreo (para que este script se pueda repetir sin
--    duplicar) y normalizador de unidad de medida.
-- ---------------------------------------------------------------------
alter table public.inv_items
    add column if not exists origen_tabla text,
    add column if not exists origen_id uuid;
create unique index if not exists inv_items_origen_unico
    on public.inv_items (origen_tabla, origen_id) where origen_tabla is not null;

create or replace function public._legacy_unidad(p text) returns text
language sql immutable as $$
    select case
        when p is null then 'UNI'
        when lower(trim(p)) in ('kg', 'kilo', 'kilos', 'kilogramo', 'kilogramos') then 'KG'
        when lower(trim(p)) in ('g', 'gr', 'grs', 'gramo', 'gramos') then 'GR'
        when lower(trim(p)) in ('pza', 'pzas', 'pieza', 'piezas', 'unidad', 'unidades', 'u', 'und') then 'PZA'
        when lower(trim(p)) = 'uni' then 'UNI'
        when lower(trim(p)) in ('l', 'lt', 'lts', 'litro', 'litros') then 'L'
        when lower(trim(p)) in ('ml', 'mililitro', 'mililitros') then 'ML'
        when lower(trim(p)) in ('caja', 'cajas', 'cja') then 'CJA'
        when lower(trim(p)) in ('m', 'mt', 'mts', 'metro', 'metros') then 'M'
        else 'UNI'
    end;
$$;

-- ---------------------------------------------------------------------
-- 1. Tapas → Almacén General › Tapas.
-- ---------------------------------------------------------------------
do $$
declare
    g text := 'general';
    tapas_root bigint; pet_tapas bigint; vid_tapas bigint; sin_clasif bigint;
    t record;
    v_item bigint;
    v_cat bigint;
    v_detalle text;
    v_ya numeric;
    v_falta numeric;
begin
    select id into tapas_root from public.inv_categorias
     where nombre = 'Tapas' and padre_id is null and almacen_id = g;
    if tapas_root is null then
        raise notice 'No existe "Tapas" en Almacén General: corré primero v18, v18b y v30.';
        return;
    end if;
    select id into pet_tapas from public.inv_categorias where nombre = 'PET' and padre_id = tapas_root;
    select id into vid_tapas from public.inv_categorias where nombre = 'Vidrio' and padre_id = tapas_root;
    sin_clasif := public._inv_cat('Sin clasificar (migrado)', tapas_root, g);

    for t in
        select * from public.tapas
         where activo
           and not exists (select 1 from public.inv_items i
                             where i.origen_tabla = 'tapas' and i.origen_id = tapas.id)
    loop
        v_detalle := trim(t.detalle)
            || case when coalesce(trim(t.formato), '') <> '' then ' - ' || trim(t.formato) else '' end
            || case when coalesce(trim(t.color), '') not in ('', 'n/a', 'N/A')
                    then ' (' || trim(t.color) || ')' else '' end;

        v_cat := case
            when lower(coalesce(t.detalle, '') || ' ' || coalesce(t.formato, '')) like '%pet%'
                 or lower(coalesce(t.formato, '')) like '%short%' then pet_tapas
            when lower(coalesce(t.formato, '')) like '%corona%'
                 or lower(coalesce(t.formato, '')) like '%long%' then vid_tapas
            else null
        end;
        v_cat := coalesce(v_cat, sin_clasif);

        select id into v_item from public.inv_items where categoria_id = v_cat and detalle = v_detalle;
        if v_item is null then
            insert into public.inv_items
                (categoria_id, detalle, unidad, unidades_por_caja, stock_minimo,
                 atributos, origen_tabla, origen_id)
            values
                (v_cat, v_detalle, public._legacy_unidad(t.unidad_medida),
                 t.unidades_por_caja::int, t.stock_minimo,
                 jsonb_build_object('formato', t.formato, 'color', t.color, 'codigo_anterior', t.codigo),
                 'tapas', t.id)
            returning id into v_item;
        else
            update public.inv_items set origen_tabla = 'tapas', origen_id = t.id
             where id = v_item and origen_tabla is null;
        end if;

        select coalesce(sum(cantidad), 0) into v_ya
          from public.inv_movimientos where item_id = v_item and almacen_id = g;
        v_falta := coalesce(t.cantidad_sistema, 0) - v_ya;
        if v_falta > 0 then
            insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
            values (v_item, g, 'entrada', v_falta, 'migracion_legacy',
                    'Migración del inventario anterior (tapas, código ' || coalesce(t.codigo, '-') || ')');
        end if;
    end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. Preformas → Almacén General › Preformas.
-- ---------------------------------------------------------------------
do $$
declare
    g text := 'general';
    pre_root bigint; sin_clasif bigint;
    p record;
    v_item bigint;
    v_cat bigint;
    v_tam text;
    v_detalle text;
    v_ya numeric;
    v_falta numeric;
begin
    select id into pre_root from public.inv_categorias
     where nombre = 'Preformas' and padre_id is null and almacen_id = g;
    if pre_root is null then
        raise notice 'No existe "Preformas" en Almacén General: corré primero v18, v18b y v30.';
        return;
    end if;
    sin_clasif := public._inv_cat('Sin clasificar (migrado)', pre_root, g);

    for p in
        select * from public.preformas
         where activo
           and not exists (select 1 from public.inv_items i
                             where i.origen_tabla = 'preformas' and i.origen_id = preformas.id)
    loop
        v_tam := lower(coalesce(p.tamano, '') || ' ' || coalesce(p.formato, ''));
        v_cat := case
            when v_tam like '%2.5%' or v_tam like '%2,5%' then
                (select id from public.inv_categorias where nombre = '2.5 L' and padre_id = pre_root)
            when v_tam like '%600%' then
                (select id from public.inv_categorias where nombre = '600 ml' and padre_id = pre_root)
            when v_tam like '%330%' then
                (select id from public.inv_categorias where nombre = '330 ml' and padre_id = pre_root)
            when v_tam like '%2%' then
                (select id from public.inv_categorias where nombre = '2 L' and padre_id = pre_root)
            else null
        end;
        v_cat := coalesce(v_cat, sin_clasif);

        v_detalle := trim(p.detalle)
            || case when coalesce(trim(p.formato), '') <> '' then ' - ' || trim(p.formato) else '' end
            || case when coalesce(trim(p.tamano), '') <> '' then ' (' || trim(p.tamano) || ')' else '' end;

        select id into v_item from public.inv_items where categoria_id = v_cat and detalle = v_detalle;
        if v_item is null then
            insert into public.inv_items
                (categoria_id, detalle, unidad, unidades_por_caja, stock_minimo,
                 atributos, origen_tabla, origen_id)
            values
                (v_cat, v_detalle, public._legacy_unidad(p.unidad_medida),
                 p.unidades_por_caja::int, p.stock_minimo,
                 jsonb_build_object('formato', p.formato, 'tamano', p.tamano, 'codigo_anterior', p.codigo),
                 'preformas', p.id)
            returning id into v_item;
        else
            update public.inv_items set origen_tabla = 'preformas', origen_id = p.id
             where id = v_item and origen_tabla is null;
        end if;

        select coalesce(sum(cantidad), 0) into v_ya
          from public.inv_movimientos where item_id = v_item and almacen_id = g;
        v_falta := coalesce(p.cantidad_sistema, 0) - v_ya;
        if v_falta > 0 then
            insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
            values (v_item, g, 'entrada', v_falta, 'migracion_legacy',
                    'Migración del inventario anterior (preformas, código ' || coalesce(p.codigo, '-') || ')');
        end if;
    end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. Materia Prima → Almacén de Jarabes (área = 'jarabes') o Almacén
--    General › "Materia prima (migrado)" (el resto).
-- ---------------------------------------------------------------------
do $$
declare
    j text := 'jarabes';
    g text := 'general';
    mp_general bigint;
    sin_clasif_j bigint;
    m record;
    v_item bigint;
    v_cat bigint;
    v_almacen text;
    v_clave text;
    v_ya numeric;
    v_falta numeric;
begin
    mp_general := public._inv_cat('Materia prima (migrado)', null, g);
    sin_clasif_j := public._inv_cat('Sin clasificar (migrado)', null, j);

    for m in
        select * from public.materia_prima
         where activo
           and not exists (select 1 from public.inv_items i
                             where i.origen_tabla = 'materia_prima' and i.origen_id = materia_prima.id)
    loop
        v_clave := lower(coalesce(m.detalle, ''));
        if coalesce(m.area, '') = 'jarabes' then
            v_almacen := j;
            v_cat := case
                when v_clave like '%azucar%' or v_clave like '%azúcar%' then
                    (select id from public.inv_categorias where nombre = 'Azúcar' and padre_id is null and almacen_id = j)
                when v_clave like '%conservante%' then
                    (select id from public.inv_categorias where nombre = 'Conservantes' and padre_id is null and almacen_id = j)
                when v_clave like '%edulcorante%' then
                    (select id from public.inv_categorias where nombre = 'Edulcorantes' and padre_id is null and almacen_id = j)
                when v_clave like '%acido%' or v_clave like '%ácido%' then
                    (select id from public.inv_categorias where nombre = 'Ácidos' and padre_id is null and almacen_id = j)
                when v_clave like '%colorante%' then
                    (select id from public.inv_categorias where nombre = 'Colorantes' and padre_id is null and almacen_id = j)
                when v_clave like '%concentrado%' or v_clave like '%esencia%' or v_clave like '%sabor%' then
                    (select id from public.inv_categorias where nombre = 'Concentrados' and padre_id is null and almacen_id = j)
                when v_clave like '%alcohol%' then
                    (select id from public.inv_categorias where nombre = 'Alcohol' and padre_id is null and almacen_id = j)
                when v_clave like '%aditivo%' then
                    (select id from public.inv_categorias where nombre = 'Aditivos' and padre_id is null and almacen_id = j)
                when v_clave like '%filtro%' then
                    (select id from public.inv_categorias where nombre = 'Filtros' and padre_id is null and almacen_id = j)
                else null
            end;
            v_cat := coalesce(v_cat, sin_clasif_j);
        else
            v_almacen := g;
            v_cat := mp_general;
        end if;

        select id into v_item from public.inv_items where categoria_id = v_cat and detalle = trim(m.detalle);
        if v_item is null then
            insert into public.inv_items
                (categoria_id, detalle, unidad, unidad_compra, factor_compra,
                 consumo_diario_manual, stock_minimo, atributos, origen_tabla, origen_id)
            values
                (v_cat, trim(m.detalle), public._legacy_unidad(m.unidad_medida),
                 m.tipo_envase, m.cantidad_por_envase, m.consumo_promedio_dia, m.stock_minimo,
                 jsonb_build_object('proveedor_habitual', m.proveedor_habitual, 'codigo_anterior', m.codigo),
                 'materia_prima', m.id)
            returning id into v_item;
        else
            update public.inv_items set origen_tabla = 'materia_prima', origen_id = m.id
             where id = v_item and origen_tabla is null;
        end if;

        select coalesce(sum(cantidad), 0) into v_ya
          from public.inv_movimientos where item_id = v_item and almacen_id = v_almacen;
        v_falta := coalesce(m.cantidad_sistema, 0) - v_ya;
        if v_falta > 0 then
            insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
            values (v_item, v_almacen, 'entrada', v_falta, 'migracion_legacy',
                    'Migración del inventario anterior (materia prima, código ' || coalesce(m.codigo, '-') || ')');
        end if;
    end loop;
end $$;

-- ---------------------------------------------------------------------
-- Resumen: cuánto se migró y cuánto quedó "Sin clasificar" para reubicar
-- a mano desde Almacenes (Editar ítem → cambiar categoría).
-- ---------------------------------------------------------------------
select c.almacen_id, c.nombre as categoria, count(*) as items
  from public.inv_items i
  join public.inv_categorias c on c.id = i.categoria_id
 where i.origen_tabla is not null
 group by c.almacen_id, c.nombre
 order by c.almacen_id, categoria;
