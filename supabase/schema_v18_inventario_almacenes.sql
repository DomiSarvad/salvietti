-- =====================================================================
-- SALVIETTI CONTROL — v18: inventario por almacenes y categorías (Módulo 1).
-- Ejecutar DESPUÉS de schema_v17_permisos_por_modulo.sql, en el SQL Editor
-- de Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- BORRADOR PARA REVISAR. Las tablas nuevas llevan el prefijo inv_ y
-- conviven con tapas / preformas / materia_prima, que NO se tocan hasta
-- migrar sus datos.
--
--  * inv_almacenes    : General, Jarabes y Soplado (cada uno con su stock).
--  * inv_categorias   : árbol de cualquier profundidad
--                       (PET > Tapas > Short > Negro, etc.).
--  * sabores / presentaciones / sabor_presentacion
--                     : matriz de qué sabor existe en qué tamaño; también
--                       guarda el estándar de cajas por preparado y el
--                       rango de Brix objetivo (Calidad).
--  * inv_items        : catálogo. Código automático (IN-0001 / MP-0001).
--  * inv_item_proveedor : SENASAG por producto y proveedor.
--  * inv_recepciones  : ingreso con factura, peso real, diferencia
--                       automática, lote, vencimiento, transporte y foto.
--  * inv_movimientos  : libro de movimientos; el stock es su suma.
--  * inv_conteos      : conteo físico; el ajuste se genera solo.
--  * inv_existencia   : vista con stock, consumo diario y días de existencia.

-- ---------------------------------------------------------------------
-- Permisos: quién opera cada almacén. Sale de permisos_rol (v17): el
-- módulo de cada almacén se llama inventario_<almacén>. Un almacén nuevo
-- solo necesita su módulo y sus filas de permisos.
-- ---------------------------------------------------------------------
create or replace function public.puede_operar_almacen(p_almacen text) returns boolean
language sql stable as $$
    select public.tiene_permiso('inventario_' || p_almacen, 'editar');
$$;

-- ---------------------------------------------------------------------
-- Almacenes y categorías
-- ---------------------------------------------------------------------
create table if not exists public.inv_almacenes (
    id text primary key,
    nombre text not null
);
insert into public.inv_almacenes (id, nombre) values
    ('general', 'Almacén General'),
    ('jarabes', 'Almacén de Jarabes'),
    ('soplado', 'Almacén de Soplado')
on conflict (id) do nothing;

create table if not exists public.inv_categorias (
    id bigint generated always as identity primary key,
    padre_id bigint references public.inv_categorias(id) on delete restrict,
    nombre text not null,
    almacen_id text not null references public.inv_almacenes(id),
    orden int not null default 0
);
create unique index if not exists inv_categorias_unica
    on public.inv_categorias (coalesce(padre_id, 0), nombre);

create table if not exists public.inv_proveedores (
    id bigint generated always as identity primary key,
    nombre text not null unique,
    activo boolean not null default true
);

-- ---------------------------------------------------------------------
-- Sabores, presentaciones y la matriz sabor × tamaño
-- ---------------------------------------------------------------------
create table if not exists public.sabores (
    id bigint generated always as identity primary key,
    nombre text not null unique,
    tipo text not null default 'refresco' check (tipo in ('refresco', 'isotonico', 'agua')),
    litros_por_preparado numeric,                 -- ej. papaya 1220; litros = preparados × esto
    estandar_cajas numeric not null default 10,   -- cajas esperadas por preparado (papaya: 12)
    cajas_por_paleta numeric not null default 2,  -- paletas estándar = estandar_cajas / esto (12 → 6, 10 → 5)
    brix_min numeric,                             -- objetivo para Calidad
    brix_max numeric
);

create table if not exists public.presentaciones (
    id bigint generated always as identity primary key,
    nombre text not null,
    material text not null check (material in ('pet', 'vidrio')),
    ml int,
    unidades_por_caja int,      -- botellas por paquete (PET) o por caja (vidrio)
    empaques_por_palet int,     -- paquetes (PET) o cajas (vidrio) que forman un palet
    unique (nombre, material)
);

create table if not exists public.sabor_presentacion (
    sabor_id bigint not null references public.sabores(id) on delete cascade,
    presentacion_id bigint not null references public.presentaciones(id) on delete cascade,
    primary key (sabor_id, presentacion_id)
);

-- ---------------------------------------------------------------------
-- Catálogo de ítems
-- ---------------------------------------------------------------------
create table if not exists public.inv_items (
    id bigint generated always as identity primary key,
    codigo text unique,
    categoria_id bigint not null references public.inv_categorias(id),
    detalle text not null,
    unidad text not null check (unidad in ('KG', 'GR', 'PZA', 'UNI', 'L', 'ML', 'CJA', 'M')),
    unidad_compra text,                 -- quintal, bidón, bolsa, cartón, caja…
    factor_compra numeric,              -- cuántas "unidad" trae cada envase (ej. 46 kg)
    unidades_por_caja int,
    sabor_id bigint references public.sabores(id),
    presentacion_id bigint references public.presentaciones(id),
    -- color, formato (short/long), peso_g, gramaje, ancho_mm, micronaje…
    atributos jsonb not null default '{}'::jsonb,
    consumo_diario_manual numeric,      -- solo si no hay salidas registradas
    stock_minimo numeric,               -- por debajo se marca "Pedido" (Balance de insumos)
    activo boolean not null default true,
    creado_en timestamptz not null default now(),
    unique (categoria_id, detalle)
);

-- Bases creadas con una versión vieja de este archivo ya tienen estas tablas,
-- y `create table if not exists` no les agrega las columnas nuevas. Se agregan
-- acá (no hace nada si ya existen) para que el resto del archivo funcione.
alter table public.inv_items
    add column if not exists sabor_id bigint references public.sabores(id),
    add column if not exists presentacion_id bigint references public.presentaciones(id),
    add column if not exists atributos jsonb not null default '{}'::jsonb,
    add column if not exists consumo_diario_manual numeric,
    add column if not exists stock_minimo numeric;
alter table public.sabores
    add column if not exists litros_por_preparado numeric,
    add column if not exists estandar_cajas numeric not null default 10,
    add column if not exists cajas_por_paleta numeric not null default 2,
    add column if not exists brix_min numeric,
    add column if not exists brix_max numeric;
alter table public.presentaciones
    add column if not exists empaques_por_palet int;

-- sabores.tipo: una base vieja tiene un check sin 'agua' y el default de
-- estandar_cajas en 12. Se reemplazan por los actuales.
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
alter table public.sabores alter column estandar_cajas set default 10;

-- Código automático por almacén: IN-0001 (general/soplado), MP-0001 (jarabes).
create or replace function public.inv_items_preparar() returns trigger
language plpgsql as $$
declare v_almacen text;
begin
    if new.codigo is null then
        select almacen_id into v_almacen from public.inv_categorias where id = new.categoria_id;
        new.codigo := case when v_almacen = 'jarabes' then 'MP-' else 'IN-' end
                      || lpad(new.id::text, 4, '0');
    end if;
    -- Un sabor solo puede llevar los tamaños que realmente existen para él.
    if new.sabor_id is not null and new.presentacion_id is not null
       and not exists (select 1 from public.sabor_presentacion
                        where sabor_id = new.sabor_id and presentacion_id = new.presentacion_id) then
        raise exception 'Ese sabor no se fabrica en esa presentación.';
    end if;
    return new;
end;
$$;
drop trigger if exists trg_inv_items_preparar on public.inv_items;
create trigger trg_inv_items_preparar before insert or update on public.inv_items
    for each row execute function public.inv_items_preparar();

-- SENASAG (registro / ficha técnica): uno por producto y proveedor.
create table if not exists public.inv_item_proveedor (
    item_id bigint not null references public.inv_items(id) on delete cascade,
    proveedor_id bigint not null references public.inv_proveedores(id),
    senasac text,
    primary key (item_id, proveedor_id)
);

-- ---------------------------------------------------------------------
-- Movimientos (el stock de cada almacén es la suma de sus movimientos)
-- ---------------------------------------------------------------------
create table if not exists public.inv_movimientos (
    id bigint generated always as identity primary key,
    fecha timestamptz not null default now(),
    item_id bigint not null references public.inv_items(id),
    almacen_id text not null references public.inv_almacenes(id),
    tipo text not null check (tipo in ('entrada', 'salida', 'ajuste', 'transferencia')),
    cantidad numeric not null,          -- con signo: entrada +, salida −
    referencia_tipo text,               -- 'recepcion', 'conteo', 'entrega'…
    referencia_id bigint,
    motivo text,
    usuario_id uuid default auth.uid(),
    constraint inv_movimientos_signo check (
        (tipo = 'entrada' and cantidad > 0)
        or (tipo = 'salida' and cantidad < 0)
        or tipo in ('ajuste', 'transferencia')
    )
);
create index if not exists inv_movimientos_item on public.inv_movimientos (item_id, almacen_id, fecha);

-- ---------------------------------------------------------------------
-- Recepciones: reemplazan el kardex de ingresos y el cuaderno de Jarabes.
-- ---------------------------------------------------------------------
create table if not exists public.inv_recepciones (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    almacen_id text not null references public.inv_almacenes(id),
    item_id bigint not null references public.inv_items(id),
    proveedor_id bigint references public.inv_proveedores(id),
    n_factura text,
    cantidad_factura numeric not null check (cantidad_factura > 0),
    cantidad_real numeric not null check (cantidad_real > 0),
    diferencia numeric generated always as (cantidad_real - cantidad_factura) stored,
    n_lote text,
    fecha_fabricacion date,
    fecha_vencimiento date,
    senasac text,                       -- se completa solo si ya se conoce
    transportador text,
    precio_transporte numeric,
    foto_url text,                      -- factura o etiqueta de la caja
    observaciones text,
    usuario_id uuid default auth.uid(),
    creado_en timestamptz not null default now(),
    constraint inv_recepciones_fechas check (
        fecha_vencimiento is null or fecha_fabricacion is null
        or fecha_vencimiento > fecha_fabricacion
    )
);

-- Cada recepción es un LOTE (ítem + N° de lote + vencimiento). Los movimientos
-- apuntan al lote del que salen o entran: así el "Pedido interno" puede
-- completar solo el N° de lote, sacando primero lo que vence antes (FIFO).
alter table public.inv_movimientos
    add column if not exists lote_recepcion_id bigint references public.inv_recepciones(id);
create index if not exists inv_movimientos_lote on public.inv_movimientos (lote_recepcion_id);

-- Disponible por lote Y por almacén (una entrega lo mueve de un almacén a otro).
create or replace view public.inv_stock_lote with (security_invoker = true) as
    select r.id as lote_recepcion_id, r.item_id, m.almacen_id, r.n_lote,
           r.fecha_fabricacion, r.fecha_vencimiento, r.proveedor_id, r.senasac,
           sum(m.cantidad) as cantidad_disponible
      from public.inv_recepciones r
      join public.inv_movimientos m on m.lote_recepcion_id = r.id
     group by r.id, m.almacen_id;

-- Antes de guardar: completa el SENASAG conocido para ese producto y proveedor.
create or replace function public.inv_recepcion_antes() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    if coalesce(trim(new.senasac), '') = '' then
        select ip.senasac into new.senasac
          from public.inv_item_proveedor ip
         where ip.item_id = new.item_id and ip.proveedor_id = new.proveedor_id;
    end if;
    return new;
end;
$$;
drop trigger if exists trg_inv_recepcion_antes on public.inv_recepciones;
create trigger trg_inv_recepcion_antes before insert on public.inv_recepciones
    for each row execute function public.inv_recepcion_antes();

-- Después de guardar: suma al stock el peso REAL y recuerda el SENASAG.
create or replace function public.inv_recepcion_despues() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    insert into public.inv_movimientos
        (fecha, item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id,
         lote_recepcion_id, usuario_id)
    values
        (now(), new.item_id, new.almacen_id, 'entrada', new.cantidad_real,
         'recepcion', new.id, new.id, new.usuario_id);

    if new.proveedor_id is not null and coalesce(trim(new.senasac), '') <> '' then
        insert into public.inv_item_proveedor (item_id, proveedor_id, senasac)
        values (new.item_id, new.proveedor_id, trim(new.senasac))
        on conflict (item_id, proveedor_id) do update set senasac = excluded.senasac;
    end if;
    return new;
end;
$$;
drop trigger if exists trg_inv_recepcion_despues on public.inv_recepciones;
create trigger trg_inv_recepcion_despues after insert on public.inv_recepciones
    for each row execute function public.inv_recepcion_despues();

-- ---------------------------------------------------------------------
-- Conteos físicos: "cantidad real" del Excel. La diferencia contra el
-- sistema se guarda como ajuste automático.
-- ---------------------------------------------------------------------
create table if not exists public.inv_conteos (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    almacen_id text not null references public.inv_almacenes(id),
    item_id bigint not null references public.inv_items(id),
    cantidad_real numeric not null check (cantidad_real >= 0),
    cantidad_sistema numeric,           -- la fija el trigger
    diferencia numeric generated always as (cantidad_real - cantidad_sistema) stored,
    cajas numeric,
    unidades_por_caja int,
    observaciones text,
    usuario_id uuid default auth.uid(),
    creado_en timestamptz not null default now()
);

create or replace function public.inv_conteo_antes() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    select coalesce(sum(cantidad), 0) into new.cantidad_sistema
      from public.inv_movimientos
     where item_id = new.item_id and almacen_id = new.almacen_id;
    return new;
end;
$$;
drop trigger if exists trg_inv_conteo_antes on public.inv_conteos;
create trigger trg_inv_conteo_antes before insert on public.inv_conteos
    for each row execute function public.inv_conteo_antes();

create or replace function public.inv_conteo_despues() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    if new.cantidad_real is distinct from new.cantidad_sistema then
        insert into public.inv_movimientos
            (fecha, item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo, usuario_id)
        values
            (now(), new.item_id, new.almacen_id, 'ajuste',
             new.cantidad_real - new.cantidad_sistema,
             'conteo', new.id, coalesce(new.observaciones, 'Conteo físico'), new.usuario_id);
    end if;
    return new;
end;
$$;
drop trigger if exists trg_inv_conteo_despues on public.inv_conteos;
create trigger trg_inv_conteo_despues after insert on public.inv_conteos
    for each row execute function public.inv_conteo_despues();

-- ---------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------
create or replace view public.inv_stock with (security_invoker = true) as
    select item_id, almacen_id, sum(cantidad) as cantidad_sistema
      from public.inv_movimientos
     group by item_id, almacen_id;

-- Consumo diario = promedio de salidas de los últimos 30 días; si no hay,
-- se usa el valor manual del ítem. Días de existencia = stock ÷ consumo.
drop view if exists public.inv_existencia;
create view public.inv_existencia with (security_invoker = true) as
    with consumo as (
        select item_id, almacen_id, (-sum(cantidad)) / 30.0 as diario
          from public.inv_movimientos
         where tipo = 'salida' and fecha >= now() - interval '30 days'
         group by item_id, almacen_id
    ),
    base as (
        select i.id as item_id, i.codigo, i.detalle, i.unidad, i.categoria_id,
               i.stock_minimo, c.almacen_id,
               coalesce(s.cantidad_sistema, 0) as cantidad_sistema,
               coalesce(nullif(co.diario, 0), i.consumo_diario_manual) as consumo_diario
          from public.inv_items i
          join public.inv_categorias c on c.id = i.categoria_id
          left join public.inv_stock s on s.item_id = i.id and s.almacen_id = c.almacen_id
          left join consumo co on co.item_id = i.id and co.almacen_id = c.almacen_id
         where i.activo
    )
    select b.*,
           (select k.cantidad_real from public.inv_conteos k
             where k.item_id = b.item_id and k.almacen_id = b.almacen_id
             order by k.fecha desc, k.id desc limit 1) as cantidad_real,
           case when b.consumo_diario > 0
                then b.cantidad_sistema / b.consumo_diario end as dias_existencia
      from base b;

-- ---------------------------------------------------------------------
-- RLS: todos los usuarios ven; cada almacén lo opera quien tenga el
-- permiso de edición sobre él (ver permisos_rol).
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
    foreach t in array array[
        'inv_almacenes', 'inv_categorias', 'inv_proveedores', 'sabores',
        'presentaciones', 'sabor_presentacion', 'inv_items', 'inv_item_proveedor',
        'inv_movimientos', 'inv_recepciones', 'inv_conteos'
    ] loop
        execute format('alter table public.%I enable row level security', t);
        execute format('drop policy if exists "ver_%1$s" on public.%1$I', t);
        execute format('create policy "ver_%1$s" on public.%1$I for select using (auth.uid() is not null)', t);
    end loop;
end $$;

-- Catálogos: los edita Almacén General (y Jarabes en lo suyo).
drop policy if exists "editar_categorias" on public.inv_categorias;
create policy "editar_categorias" on public.inv_categorias for all
    using (public.puede_operar_almacen(almacen_id))
    with check (public.puede_operar_almacen(almacen_id));

drop policy if exists "editar_items" on public.inv_items;
create policy "editar_items" on public.inv_items for all
    using (public.puede_operar_almacen(
        (select almacen_id from public.inv_categorias where id = categoria_id)))
    with check (public.puede_operar_almacen(
        (select almacen_id from public.inv_categorias where id = categoria_id)));

drop policy if exists "editar_item_proveedor" on public.inv_item_proveedor;
create policy "editar_item_proveedor" on public.inv_item_proveedor for all
    using (public.puede_operar_almacen(
        (select c.almacen_id from public.inv_items i
           join public.inv_categorias c on c.id = i.categoria_id where i.id = item_id)))
    with check (public.puede_operar_almacen(
        (select c.almacen_id from public.inv_items i
           join public.inv_categorias c on c.id = i.categoria_id where i.id = item_id)));

drop policy if exists "editar_proveedores" on public.inv_proveedores;
create policy "editar_proveedores" on public.inv_proveedores for all
    using (public.tiene_permiso('recepciones', 'crear'))
    with check (public.tiene_permiso('recepciones', 'crear'));

-- Sabores, presentaciones y matriz: catálogo maestro de Almacén General.
drop policy if exists "editar_sabores" on public.sabores;
create policy "editar_sabores" on public.sabores for all
    using (public.tiene_permiso('inventario_general', 'editar'))
    with check (public.tiene_permiso('inventario_general', 'editar'));

drop policy if exists "editar_presentaciones" on public.presentaciones;
create policy "editar_presentaciones" on public.presentaciones for all
    using (public.tiene_permiso('inventario_general', 'editar'))
    with check (public.tiene_permiso('inventario_general', 'editar'));

drop policy if exists "editar_sabor_presentacion" on public.sabor_presentacion;
create policy "editar_sabor_presentacion" on public.sabor_presentacion for all
    using (public.tiene_permiso('inventario_general', 'editar'))
    with check (public.tiene_permiso('inventario_general', 'editar'));

-- Recepciones: requiere poder recibir Y operar ese almacén.
-- Conteos y movimientos manuales: quien opera ese almacén.
drop policy if exists "crear_recepciones" on public.inv_recepciones;
create policy "crear_recepciones" on public.inv_recepciones for insert
    with check (public.tiene_permiso('recepciones', 'crear')
                and public.puede_operar_almacen(almacen_id));

drop policy if exists "crear_conteos" on public.inv_conteos;
create policy "crear_conteos" on public.inv_conteos for insert
    with check (public.puede_operar_almacen(almacen_id));

drop policy if exists "crear_movimientos_inv" on public.inv_movimientos;
create policy "crear_movimientos_inv" on public.inv_movimientos for insert
    with check (public.puede_operar_almacen(almacen_id));

-- ---------------------------------------------------------------------
-- Datos iniciales: presentaciones, sabores, matriz y árbol de categorías.
-- ---------------------------------------------------------------------
insert into public.presentaciones (nombre, material, ml, unidades_por_caja) values
    ('2.5 L', 'pet', 2500, null), ('2 L', 'pet', 2000, null), ('1 L', 'pet', 1000, null),
    ('600 ml', 'pet', 600, null), ('330 ml', 'pet', 330, null),
    ('1 L', 'vidrio', 1000, 12), ('Cervecera 620 ml', 'vidrio', 620, 12),
    ('Personal 300 ml', 'vidrio', 300, 24), ('Escolar 270 ml', 'vidrio', 270, 24),
    ('Promoción 500 ml', 'vidrio', 500, 12)
on conflict (nombre, material) do nothing;

insert into public.sabores (nombre, tipo) values
    ('Papaya', 'refresco'), ('Kinoto', 'refresco'), ('Granadina', 'refresco'),
    ('Naranja', 'refresco'), ('Ross', 'refresco'), ('Ginger Ale', 'refresco'),
    ('Tumbo', 'refresco'), ('Piña', 'refresco'), ('Pomelo', 'refresco'),
    ('Lima limón', 'refresco'), ('Achachairú', 'refresco'),
    ('Kiwi', 'isotonico'), ('Frutilla', 'isotonico'), ('Arándano azul', 'isotonico'),
    ('H2O', 'agua')
on conflict (nombre) do nothing;

-- Estándar de cajas por preparado: papaya 12, los demás sabores 10 (los que
-- quedaron en 12 por el default viejo se corrigen).
update public.sabores set estandar_cajas = 10 where nombre <> 'Papaya' and estandar_cajas = 12;
update public.sabores set estandar_cajas = 12 where nombre = 'Papaya';

-- Litros por preparado (Reporte diario de elaboración de jarabe). Los demás
-- sabores se completan cuando Jarabes los confirme.
update public.sabores s set litros_por_preparado = v.litros
  from (values ('Papaya', 1220), ('Naranja', 1050), ('Kinoto', 1080), ('Piña', 1050))
       as v(nombre, litros)
 where s.nombre = v.nombre and s.litros_por_preparado is null;

-- Matriz sabor × tamaño (PET).
insert into public.sabor_presentacion (sabor_id, presentacion_id)
select s.id, p.id
  from (values
      ('Papaya', '2.5 L'), ('Papaya', '2 L'), ('Papaya', '1 L'), ('Papaya', '600 ml'), ('Papaya', '330 ml'),
      ('Kinoto', '2.5 L'), ('Kinoto', '2 L'), ('Kinoto', '600 ml'), ('Kinoto', '330 ml'),
      ('Granadina', '2.5 L'), ('Granadina', '2 L'), ('Granadina', '600 ml'), ('Granadina', '330 ml'),
      ('Naranja', '2.5 L'), ('Naranja', '2 L'), ('Naranja', '600 ml'), ('Naranja', '330 ml'),
      ('Ross', '2 L'), ('Ginger Ale', '2 L'),
      ('Tumbo', '2.5 L'), ('Tumbo', '600 ml'),
      ('Piña', '2 L'), ('Piña', '2.5 L'),
      ('Pomelo', '2 L'), ('Lima limón', '2 L'),
      ('Kiwi', '600 ml'), ('Frutilla', '600 ml'), ('Arándano azul', '600 ml')
  ) as m(sabor, presentacion)
  join public.sabores s on s.nombre = m.sabor
  join public.presentaciones p on p.nombre = m.presentacion and p.material = 'pet'
on conflict do nothing;

-- Auxiliar para armar el árbol (se elimina al final).
create or replace function public._inv_cat(p_nombre text, p_padre bigint, p_almacen text)
returns bigint language plpgsql as $$
declare v bigint;
begin
    select id into v from public.inv_categorias
     where nombre = p_nombre and padre_id is not distinct from p_padre;
    if v is null then
        insert into public.inv_categorias (nombre, padre_id, almacen_id)
        values (p_nombre, p_padre, p_almacen) returning id into v;
    end if;
    return v;
end;
$$;

do $$
declare
    g text := 'general';
    j text := 'jarabes';
    mant bigint; tapas bigint; tapas_pet bigint; tapas_vid bigint; tshort bigint; tlong bigint;
    etiq bigint; etiq_pet bigint; etiq_vid bigint; plastico bigint; sticker bigint; isot bigint;
    corona bigint; pre bigint;
    c text;
begin
    -- El almacén se ordena por TIPO de artículo (Tapas, Etiquetas, Preformas…)
    -- y dentro de cada uno por material (PET / Vidrio). Ver v30.
    tapas := public._inv_cat('Tapas', null, g);
    tapas_pet := public._inv_cat('PET', tapas, g);
    tshort := public._inv_cat('Tapa Short', tapas_pet, g);
    foreach c in array array['Negro', 'Rojo', 'Transparente', 'Celeste', 'Verde', 'Gama de colores'] loop
        perform public._inv_cat(c, tshort, g);
    end loop;
    tapas_vid := public._inv_cat('Vidrio', tapas, g);
    tlong := public._inv_cat('Tapa Long', tapas_vid, g);
    perform public._inv_cat('Verde', tlong, g);
    perform public._inv_cat('Amarillo', tlong, g);
    corona := public._inv_cat('Tapa corona', tapas_vid, g);
    perform public._inv_cat('Con sello', corona, g);
    perform public._inv_cat('Sin sello', corona, g);

    etiq := public._inv_cat('Etiquetas', null, g);
    etiq_pet := public._inv_cat('PET', etiq, g);
    plastico := public._inv_cat('Plástico', etiq_pet, g);
    sticker := public._inv_cat('Sticker', etiq_pet, g);
    isot := public._inv_cat('Isotónico', sticker, g);
    etiq_vid := public._inv_cat('Vidrio', etiq, g);
    perform public._inv_cat('Papel (cerveceras)', etiq_vid, g);

    pre := public._inv_cat('Preformas', null, g);
    foreach c in array array['2.5 L', '2 L', '600 ml', '330 ml'] loop
        perform public._inv_cat(c, pre, g);
    end loop;
    perform public._inv_cat('Termocontraíbles', null, g);
    perform public._inv_cat('Envases', null, g);
    perform public._inv_cat('Cajas', null, g);

    -- Resto de Almacén General
    perform public._inv_cat('Material de escritorio', null, g);
    perform public._inv_cat('Limpieza', null, g);
    perform public._inv_cat('Saneamiento', null, g);
    perform public._inv_cat('Seguridad industrial', null, g);
    mant := public._inv_cat('Mantenimiento', null, g);
    foreach c in array array['Plomería', 'Electricidad', 'Mecánico', 'Civil'] loop
        perform public._inv_cat(c, mant, g);
    end loop;
    perform public._inv_cat('Laboratorio', null, g);
    perform public._inv_cat('Codificación (solvente y tinta)', null, g);

    -- Almacén de Jarabes
    foreach c in array array['Azúcar', 'Conservantes', 'Edulcorantes', 'Ácidos', 'Colorantes',
                             'Concentrados', 'Alcohol', 'Aditivos', 'Filtros'] loop
        perform public._inv_cat(c, null, j);
    end loop;

    -- Almacén de Soplado
    perform public._inv_cat('Soplado', null, 'soplado');

    -- Etiquetas plásticas: un ítem por cada sabor × tamaño que existe.
    insert into public.inv_items (categoria_id, detalle, unidad, sabor_id, presentacion_id)
    select plastico, 'Etiqueta ' || s.nombre || ' ' || p.nombre, 'UNI', s.id, p.id
      from public.sabor_presentacion sp
      join public.sabores s on s.id = sp.sabor_id and s.tipo = 'refresco'
      join public.presentaciones p on p.id = sp.presentacion_id
    on conflict (categoria_id, detalle) do nothing;

    -- Stickers de los isotónicos (solo 600 ml).
    insert into public.inv_items (categoria_id, detalle, unidad, sabor_id, presentacion_id)
    select isot, 'Sticker ' || s.nombre || ' ' || p.nombre, 'UNI', s.id, p.id
      from public.sabor_presentacion sp
      join public.sabores s on s.id = sp.sabor_id and s.tipo = 'isotonico'
      join public.presentaciones p on p.id = sp.presentacion_id
    on conflict (categoria_id, detalle) do nothing;
end $$;

drop function if exists public._inv_cat(text, bigint, text);
