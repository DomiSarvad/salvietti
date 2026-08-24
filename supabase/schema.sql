-- =====================================================================
-- SALVIETTI CONTROL — ESQUEMA DE BASE DE DATOS (SUPABASE / POSTGRESQL)
-- Basado en los inventarios reales de la planta (Tapas, Preformas,
-- Materia Prima) y en los Casos de Uso Descriptivos de la PWA.
-- =====================================================================
-- Ejecutar en el SQL Editor de Supabase, en orden, una sola vez.
-- =====================================================================

create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. ROLES Y USUARIOS
-- ---------------------------------------------------------------------
-- Se usa Supabase Auth (auth.users) + tabla de perfil "usuarios" 1:1.
--   almacen          -> control total (único con permisos de eliminación
--                        lógica, edición de fórmulas, gestión de catálogo)
--   gerente          -> solo lectura global (dashboard, reportes) +
--                        puede invitar/crear nuevos usuarios
--   jefe_produccion  -> planifica el día de producción, ve todo el stock
--   jarabes          -> solo ve y opera su propia área (consumo de jarabes)

create table if not exists public.usuarios (
    id uuid primary key references auth.users(id) on delete cascade,
    nombre_completo text not null,
    rol text not null check (rol in ('almacen','gerente','jefe_produccion','jarabes')),
    area text, -- ej. 'Jarabes', 'Almacén Insumos', 'Almacén M.P.' — usado para restringir a 'jarabes'
    activo boolean not null default true,
    creado_por uuid references public.usuarios(id),
    created_at timestamptz not null default now()
);

comment on table public.usuarios is 'Perfil y rol de cada usuario. almacen = control total; gerente = solo observación + alta de usuarios; jarabes = restringido a su área.';

-- ---------------------------------------------------------------------
-- 2. CATÁLOGOS DE INVENTARIO (uno por área, igual que los Excel reales)
-- ---------------------------------------------------------------------

-- 2.1 TAPAS / CÁPSULAS  (hoja "INVENTARIO DE TAPAS")
create table if not exists public.tapas (
    id uuid primary key default uuid_generate_v4(),
    codigo text unique not null,              -- IN-001, IN-002... (autogenerado)
    detalle text not null,                    -- 'Capsulas PET'
    formato text,                             -- 'Long Finish' / 'Short Finish' / 'Tapa Corona'
    color text,
    unidad_medida text not null default 'PZA',
    cantidad_sistema numeric(14,2) not null default 0,
    cantidad_real numeric(14,2) not null default 0,
    cantidad_cajas numeric(10,2) default 0,
    unidades_por_caja numeric(10,2),
    stock_minimo numeric(14,2) not null default 0,
    activo boolean not null default true,     -- soft delete
    updated_at timestamptz not null default now(),
    updated_by uuid references public.usuarios(id)
);

-- 2.2 PREFORMAS (hoja "INVENTARIO DE PREFORMAS")
create table if not exists public.preformas (
    id uuid primary key default uuid_generate_v4(),
    codigo text unique not null,              -- IN-014, IN-015...
    detalle text not null,                    -- 'Preforma de 54.7gr'
    formato text,                             -- 'Short'/'Long'
    tamano text,                              -- '2,5 L' / '2 L' / '600 ml' / '330 ml'
    unidad_medida text not null default 'UN',
    cantidad_sistema numeric(14,2) not null default 0,
    cantidad_real numeric(14,2) not null default 0,
    cantidad_cajas numeric(10,2) default 0,
    unidades_por_caja numeric(10,2),
    stock_minimo numeric(14,2) not null default 0,
    activo boolean not null default true,
    updated_at timestamptz not null default now(),
    updated_by uuid references public.usuarios(id)
);

-- 2.3 MATERIA PRIMA E INSUMOS (hoja "INVENTARIO DE MATERIA PRIMA")
create table if not exists public.materia_prima (
    id uuid primary key default uuid_generate_v4(),
    codigo text unique not null,              -- MP-001, MP-002...
    detalle text not null,                    -- 'AZUCAR', 'ESENCIA DE NARANJA'...
    unidad_medida text not null default 'KG',
    cantidad_sistema numeric(14,3) not null default 0,
    cantidad_real numeric(14,3) not null default 0,
    tipo_envase text,                         -- quintal, bidón, bolsa, cartón, turril
    cantidad_por_envase numeric(10,2),
    proveedor_habitual text,                  -- Sapore, Maprial, San Aurelio, IFF...
    consumo_promedio_dia numeric(14,3) default 0,   -- recalculado por trigger/función
    stock_minimo numeric(14,3) not null default 0,
    activo boolean not null default true,
    updated_at timestamptz not null default now(),
    updated_by uuid references public.usuarios(id)
);

-- Vista unificada de "insumos" (para búsquedas, alertas y kardex genérico)
create or replace view public.v_insumos as
    select id, codigo, detalle, unidad_medida, cantidad_real as stock,
           stock_minimo, 'tapas' as origen from public.tapas where activo
    union all
    select id, codigo, detalle, unidad_medida, cantidad_real as stock,
           stock_minimo, 'preformas' as origen from public.preformas where activo
    union all
    select id, codigo, detalle, unidad_medida, cantidad_real as stock,
           stock_minimo, 'materia_prima' as origen from public.materia_prima where activo;

-- ---------------------------------------------------------------------
-- 3. FÓRMULAS DE PRODUCCIÓN (recetas por sabor de jarabe/gaseosa)
-- ---------------------------------------------------------------------
-- Permiten que, al planificar "hoy hacemos 500 L de Naranja", el sistema
-- descuente automáticamente azúcar, concentrado, ácido cítrico, etc.

create table if not exists public.formulas (
    id uuid primary key default uuid_generate_v4(),
    sabor text not null unique,               -- 'Naranja', 'Lima Limón', 'Piña o Anana'...
    rendimiento_litros numeric(10,2) not null default 1, -- litros que produce 1 "lote base"
    activo boolean not null default true,
    created_at timestamptz not null default now()
);

create table if not exists public.formula_detalle (
    id uuid primary key default uuid_generate_v4(),
    formula_id uuid not null references public.formulas(id) on delete cascade,
    materia_prima_id uuid not null references public.materia_prima(id),
    cantidad_por_lote numeric(14,4) not null,   -- cantidad de esa MP por "rendimiento_litros"
    unique (formula_id, materia_prima_id)
);

comment on table public.formula_detalle is 'Receta: cuánta materia prima se consume por cada lote base de la fórmula.';

-- ---------------------------------------------------------------------
-- 4. PLAN DE PRODUCCIÓN DIARIO (lo que el Jefe de Producción organiza)
-- ---------------------------------------------------------------------

create table if not exists public.plan_produccion (
    id uuid primary key default uuid_generate_v4(),
    fecha date not null default current_date,
    creado_por uuid references public.usuarios(id),
    estado text not null default 'planificado'
        check (estado in ('planificado','en_proceso','completado','cancelado')),
    created_at timestamptz not null default now()
);

create table if not exists public.plan_produccion_detalle (
    id uuid primary key default uuid_generate_v4(),
    plan_id uuid not null references public.plan_produccion(id) on delete cascade,
    formula_id uuid not null references public.formulas(id),
    litros_planificados numeric(12,2) not null check (litros_planificados > 0),
    litros_producidos numeric(12,2) default 0,  -- se marca al "completar" (checklist)
    completado boolean not null default false,
    completado_por uuid references public.usuarios(id),
    completado_en timestamptz
);

comment on table public.plan_produccion_detalle is
    'Cada fila = un sabor a producir en el día. Al marcar completado=true, un trigger descuenta automáticamente la materia prima según formula_detalle (equivalente a "marcar de una lista").';

-- ---------------------------------------------------------------------
-- 5. MOVIMIENTOS (kardex de entradas/salidas — histórico completo)
-- ---------------------------------------------------------------------

create table if not exists public.movimientos (
    id uuid primary key default uuid_generate_v4(),
    tabla_origen text not null check (tabla_origen in ('tapas','preformas','materia_prima')),
    item_id uuid not null,
    tipo text not null check (tipo in ('ingreso','salida','ajuste','produccion')),
    cantidad numeric(14,3) not null,
    unidad_medida text,
    lote text,
    fecha_vencimiento date,
    proveedor text,
    n_factura text,
    transportador text,
    precio_transporte numeric(10,2),
    observacion text,
    plan_produccion_detalle_id uuid references public.plan_produccion_detalle(id),
    usuario_id uuid references public.usuarios(id),
    sincronizado boolean not null default true,  -- lo pone en false el cliente offline
    origen_offline_uuid text,                    -- id generado en el dispositivo (idempotencia)
    created_at timestamptz not null default now()
);

create unique index if not exists ux_movimientos_offline_uuid
    on public.movimientos(origen_offline_uuid) where origen_offline_uuid is not null;

-- ---------------------------------------------------------------------
-- 6. BITÁCORAS (auditoría) — NADA SE BORRA FÍSICAMENTE
-- ---------------------------------------------------------------------

-- 6.1 Bitácora general de acciones (quién entró, qué hizo)
create table if not exists public.bitacora_acciones (
    id uuid primary key default uuid_generate_v4(),
    usuario_id uuid references public.usuarios(id),
    accion text not null,          -- 'login','crear','editar','eliminar','sincronizar','completar_produccion'
    tabla_afectada text,
    registro_id uuid,
    detalle jsonb,
    dispositivo text,
    created_at timestamptz not null default now()
);

-- 6.2 Bitácora exclusiva de eliminaciones lógicas (requisito explícito:
--     "nada se borra, solo se marca eliminado, y eso va en un log aparte")
create table if not exists public.bitacora_eliminaciones (
    id uuid primary key default uuid_generate_v4(),
    tabla_afectada text not null,
    registro_id uuid not null,
    snapshot jsonb not null,        -- copia completa de la fila al momento de eliminar
    eliminado_por uuid references public.usuarios(id),
    motivo text,
    created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7. FUNCIONES Y TRIGGERS — AUTOMATIZACIÓN
-- ---------------------------------------------------------------------

-- 7.1 Generador de códigos automáticos (IN-xxx tapas/preformas, MP-xxx materia prima)
create or replace function public.generar_codigo(prefijo text, tabla regclass)
returns text language plpgsql as $$
declare
    siguiente int;
    consulta text;
begin
    consulta := format(
        'select coalesce(max(substring(codigo from %L)::int),0)+1 from %s where codigo like %L',
        '\d+$', tabla, prefijo || '-%'
    );
    execute consulta into siguiente;
    return prefijo || '-' || lpad(siguiente::text, 3, '0');
end;
$$;

create or replace function public.trg_set_codigo_tapas()
returns trigger language plpgsql as $$
begin
    if new.codigo is null or new.codigo = '' then
        new.codigo := public.generar_codigo('IN', 'public.tapas');
    end if;
    return new;
end; $$;
drop trigger if exists set_codigo_tapas on public.tapas;
create trigger set_codigo_tapas before insert on public.tapas
    for each row execute function public.trg_set_codigo_tapas();

create or replace function public.trg_set_codigo_preformas()
returns trigger language plpgsql as $$
begin
    if new.codigo is null or new.codigo = '' then
        new.codigo := public.generar_codigo('IN', 'public.preformas');
    end if;
    return new;
end; $$;
drop trigger if exists set_codigo_preformas on public.preformas;
create trigger set_codigo_preformas before insert on public.preformas
    for each row execute function public.trg_set_codigo_preformas();

create or replace function public.trg_set_codigo_mp()
returns trigger language plpgsql as $$
begin
    if new.codigo is null or new.codigo = '' then
        new.codigo := public.generar_codigo('MP', 'public.materia_prima');
    end if;
    return new;
end; $$;
drop trigger if exists set_codigo_mp on public.materia_prima;
create trigger set_codigo_mp before insert on public.materia_prima
    for each row execute function public.trg_set_codigo_mp();

-- 7.2 updated_at automático
create or replace function public.trg_touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end; $$;
drop trigger if exists touch_updated_tapas on public.tapas;
create trigger touch_updated_tapas before update on public.tapas
    for each row execute function public.trg_touch_updated_at();
drop trigger if exists touch_updated_preformas on public.preformas;
create trigger touch_updated_preformas before update on public.preformas
    for each row execute function public.trg_touch_updated_at();
drop trigger if exists touch_updated_mp on public.materia_prima;
create trigger touch_updated_mp before update on public.materia_prima
    for each row execute function public.trg_touch_updated_at();

-- 7.3 Aplicar movimiento => actualizar stock automáticamente
create or replace function public.trg_aplicar_movimiento()
returns trigger language plpgsql as $$
declare
    signo numeric;
begin
    signo := case when new.tipo = 'ingreso' then 1
                  when new.tipo in ('salida','produccion') then -1
                  else 1 end; -- 'ajuste' se aplica tal cual (puede ser +/-)

    if new.tabla_origen = 'tapas' then
        update public.tapas set cantidad_real = cantidad_real + (signo * new.cantidad)
            where id = new.item_id;
    elsif new.tabla_origen = 'preformas' then
        update public.preformas set cantidad_real = cantidad_real + (signo * new.cantidad)
            where id = new.item_id;
    elsif new.tabla_origen = 'materia_prima' then
        update public.materia_prima set cantidad_real = cantidad_real + (signo * new.cantidad)
            where id = new.item_id;
    end if;

    insert into public.bitacora_acciones(usuario_id, accion, tabla_afectada, registro_id, detalle)
    values (new.usuario_id, 'movimiento_' || new.tipo, new.tabla_origen, new.item_id,
            jsonb_build_object('cantidad', new.cantidad, 'movimiento_id', new.id));

    return new;
end; $$;
drop trigger if exists aplicar_movimiento on public.movimientos;
create trigger aplicar_movimiento after insert on public.movimientos
    for each row execute function public.trg_aplicar_movimiento();

-- 7.4 "Marcar como lista" un sabor del plan de producción del día =>
--     descuenta automáticamente la materia prima según la fórmula.
--     Esto es el equivalente a "marcar cosas de una lista" pedido.
create or replace function public.trg_completar_plan_detalle()
returns trigger language plpgsql as $$
declare
    r_formula record;
    r_detalle record;
    factor numeric;
begin
    if new.completado = true and (old.completado is distinct from true) then
        select * into r_formula from public.formulas where id = new.formula_id;
        factor := new.litros_planificados / r_formula.rendimiento_litros;

        for r_detalle in
            select * from public.formula_detalle where formula_id = new.formula_id
        loop
            insert into public.movimientos(
                tabla_origen, item_id, tipo, cantidad, unidad_medida,
                plan_produccion_detalle_id, usuario_id, observacion
            ) values (
                'materia_prima', r_detalle.materia_prima_id, 'produccion',
                r_detalle.cantidad_por_lote * factor,
                (select unidad_medida from public.materia_prima where id = r_detalle.materia_prima_id),
                new.id, new.completado_por,
                'Descuento automático por producción de ' || r_formula.sabor
            );
        end loop;

        new.completado_en := now();
        new.litros_producidos := coalesce(new.litros_producidos, new.litros_planificados);
    end if;
    return new;
end; $$;
drop trigger if exists completar_plan_detalle on public.plan_produccion_detalle;
create trigger completar_plan_detalle before update on public.plan_produccion_detalle
    for each row execute function public.trg_completar_plan_detalle();

-- 7.5 Soft delete genérico: nunca DELETE, siempre UPDATE activo=false + bitácora
create or replace function public.eliminar_logico(p_tabla text, p_id uuid, p_usuario uuid, p_motivo text default null)
returns void language plpgsql as $$
declare
    snap jsonb;
begin
    execute format('select to_jsonb(t) from public.%I t where id = $1', p_tabla) into snap using p_id;
    if snap is null then
        raise exception 'Registro no encontrado en %', p_tabla;
    end if;
    execute format('update public.%I set activo = false where id = $1', p_tabla) using p_id;
    insert into public.bitacora_eliminaciones(tabla_afectada, registro_id, snapshot, eliminado_por, motivo)
    values (p_tabla, p_id, snap, p_usuario, p_motivo);
end; $$;

-- ---------------------------------------------------------------------
-- 8. ROW LEVEL SECURITY (RBAC real, no solo de interfaz)
-- ---------------------------------------------------------------------

alter table public.usuarios enable row level security;
alter table public.tapas enable row level security;
alter table public.preformas enable row level security;
alter table public.materia_prima enable row level security;
alter table public.formulas enable row level security;
alter table public.formula_detalle enable row level security;
alter table public.plan_produccion enable row level security;
alter table public.plan_produccion_detalle enable row level security;
alter table public.movimientos enable row level security;
alter table public.bitacora_acciones enable row level security;
alter table public.bitacora_eliminaciones enable row level security;

create or replace function public.rol_actual() returns text language sql stable as $$
    select rol from public.usuarios where id = auth.uid();
$$;

-- Lectura: todos los roles autenticados pueden VER el inventario y planes
create policy "lectura_general_tapas" on public.tapas for select using (auth.uid() is not null);
create policy "lectura_general_preformas" on public.preformas for select using (auth.uid() is not null);
create policy "lectura_general_mp" on public.materia_prima for select using (auth.uid() is not null);
create policy "lectura_general_formulas" on public.formulas for select using (auth.uid() is not null);
create policy "lectura_general_formula_detalle" on public.formula_detalle for select using (auth.uid() is not null);
create policy "lectura_general_plan" on public.plan_produccion for select using (auth.uid() is not null);
create policy "lectura_general_plan_detalle" on public.plan_produccion_detalle for select using (auth.uid() is not null);
create policy "lectura_general_movs" on public.movimientos for select using (auth.uid() is not null);
create policy "lectura_bitacora" on public.bitacora_acciones for select using (public.rol_actual() in ('almacen','gerente'));
create policy "lectura_bitacora_elim" on public.bitacora_eliminaciones for select using (public.rol_actual() in ('almacen','gerente'));

-- Escritura de catálogos (crear/editar): solo almacen y jefe_produccion
create policy "escritura_tapas" on public.tapas for insert with check (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "edicion_tapas" on public.tapas for update using (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "escritura_preformas" on public.preformas for insert with check (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "edicion_preformas" on public.preformas for update using (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "escritura_mp" on public.materia_prima for insert with check (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "edicion_mp" on public.materia_prima for update using (public.rol_actual() in ('almacen','jefe_produccion'));

-- Movimientos: almacen, jefe_produccion y jarabes (jarabes solo se filtra en UI a su área)
create policy "crear_movimientos" on public.movimientos for insert
    with check (public.rol_actual() in ('almacen','jefe_produccion','jarabes'));

-- Fórmulas y planificación: solo almacen y jefe_produccion
create policy "gestion_formulas" on public.formulas for all
    using (public.rol_actual() in ('almacen','jefe_produccion'))
    with check (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "gestion_formula_detalle" on public.formula_detalle for all
    using (public.rol_actual() in ('almacen','jefe_produccion'))
    with check (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "gestion_plan" on public.plan_produccion for all
    using (public.rol_actual() in ('almacen','jefe_produccion'))
    with check (public.rol_actual() in ('almacen','jefe_produccion'));
create policy "gestion_plan_detalle" on public.plan_produccion_detalle for all
    using (public.rol_actual() in ('almacen','jefe_produccion','jarabes'))
    with check (public.rol_actual() in ('almacen','jefe_produccion','jarabes'));

-- Usuarios: almacen y gerente pueden crear/ver; cada usuario ve su propio perfil
create policy "ver_propio_usuario" on public.usuarios for select using (auth.uid() = id or public.rol_actual() in ('almacen','gerente'));
create policy "crear_usuarios" on public.usuarios for insert with check (public.rol_actual() in ('almacen','gerente'));
create policy "editar_usuarios" on public.usuarios for update using (public.rol_actual() = 'almacen');

-- Bitácora: se inserta desde triggers/servidor (usuario autenticado también puede insertar log de su propia sesión)
create policy "insertar_bitacora" on public.bitacora_acciones for insert with check (auth.uid() is not null);
create policy "insertar_bitacora_elim" on public.bitacora_eliminaciones for insert with check (public.rol_actual() = 'almacen');

-- =====================================================================
-- FIN DEL ESQUEMA
-- =====================================================================
