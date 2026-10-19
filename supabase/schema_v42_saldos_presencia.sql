-- =====================================================================
-- v42 · Saldos de stock mantenidos al día + presencia de las áreas
--
-- 1. SALDOS (que el sistema no se ponga lento con los años)
--    Hasta v41, el stock (`inv_stock`, `inv_stock_lote`, y por lo tanto
--    `inv_existencia`, que leen Almacenes, el Inicio y Jarabes) se calculaba
--    SUMANDO TODOS LOS MOVIMIENTOS DE LA HISTORIA cada vez que alguien abría
--    una pantalla: cuantos más años de movimientos, más lento.
--
--    Ahora cada movimiento, al guardarse, suma o resta su cantidad a un
--    saldo guardado (`inv_saldos` por ítem+almacén, `inv_saldos_lote` por
--    lote+almacén), con un trigger. Leer el stock es leer ese saldo: cuesta
--    lo mismo con 100 movimientos que con 10 millones. Es la idea del "corte"
--    semanal, pero llevada a cada movimiento: el saldo siempre está al día,
--    no hace falta esperar al domingo ni correr ningún proceso programado, y
--    una corrección con fecha vieja se refleja igual (en un cierre semanal
--    habría que "reabrir" la semana).
--
--    `inv_movimientos` NO se toca: sigue siendo el historial completo (el
--    kardex) y la fuente de verdad. Si algún día se duda de un saldo, se
--    reconstruye desde cero con `select public.inv_reconstruir_saldos();`
--    (también se puede correr este archivo de nuevo: es idempotente).
--
-- 2. PRESENCIA (saber si un área está trabajando sin internet)
--    Cada app conectada avisa cada minuto "sigo acá, y tengo N registros sin
--    subir" (`presencia_latido`). Si un área deja de avisar, las demás ven
--    "Soplado sin señal desde las 10:32: sus datos pueden estar atrasados".
--    Se consulta cada minuto, NO por Realtime: un latido por persona por
--    minuto, reenviado a todas las demás, gastaría la cuota de mensajes de
--    Realtime de Supabase sin necesidad.
--
-- 3. TIEMPO REAL en Jarabes: agrega sus tablas a `supabase_realtime`
--    (Soplado y su avance ya estaban desde v41).
--
-- Requiere v18…v41. Correr v29 de nuevo NO hace falta: los grants de las
-- tablas nuevas van acá mismo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1a. Tablas de saldos.
-- ---------------------------------------------------------------------
create table if not exists public.inv_saldos (
    item_id bigint not null references public.inv_items(id),
    almacen_id text not null references public.inv_almacenes(id),
    cantidad numeric not null default 0,
    actualizado_en timestamptz not null default now(),
    primary key (item_id, almacen_id)
);

create table if not exists public.inv_saldos_lote (
    lote_recepcion_id bigint not null references public.inv_recepciones(id),
    almacen_id text not null references public.inv_almacenes(id),
    cantidad numeric not null default 0,
    primary key (lote_recepcion_id, almacen_id)
);

-- Mismo criterio de lectura que inv_movimientos (v18): cualquier usuario con
-- sesión. Nadie escribe a mano: solo el trigger (security definer).
alter table public.inv_saldos enable row level security;
alter table public.inv_saldos_lote enable row level security;
drop policy if exists "ver_inv_saldos" on public.inv_saldos;
create policy "ver_inv_saldos" on public.inv_saldos for select using (auth.uid() is not null);
drop policy if exists "ver_inv_saldos_lote" on public.inv_saldos_lote;
create policy "ver_inv_saldos_lote" on public.inv_saldos_lote for select using (auth.uid() is not null);
grant select on public.inv_saldos, public.inv_saldos_lote to authenticated;

-- ---------------------------------------------------------------------
-- 1b. Trigger: cada movimiento ajusta su saldo en la misma transacción.
--     `insert ... on conflict do update set cantidad = cantidad + x` es
--     atómico por fila: dos movimientos simultáneos del mismo ítem no se
--     pisan (el segundo espera el bloqueo de la fila del saldo).
-- ---------------------------------------------------------------------
create or replace function public._inv_saldo_sumar(
    p_item bigint, p_almacen text, p_lote bigint, p_cantidad numeric
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
    if p_cantidad = 0 then return; end if;
    insert into public.inv_saldos as s (item_id, almacen_id, cantidad)
    values (p_item, p_almacen, p_cantidad)
    on conflict (item_id, almacen_id)
    do update set cantidad = s.cantidad + excluded.cantidad, actualizado_en = now();

    if p_lote is not null then
        insert into public.inv_saldos_lote as s (lote_recepcion_id, almacen_id, cantidad)
        values (p_lote, p_almacen, p_cantidad)
        on conflict (lote_recepcion_id, almacen_id)
        do update set cantidad = s.cantidad + excluded.cantidad;
    end if;
end $$;

create or replace function public.inv_movimiento_saldo() returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op in ('UPDATE', 'DELETE') then
        -- Un UPDATE que no cambia cantidad/ítem/almacén/lote (ej. v36, que
        -- completa referencia_id) no toca los saldos.
        if tg_op = 'UPDATE'
           and new.cantidad = old.cantidad and new.item_id = old.item_id
           and new.almacen_id = old.almacen_id
           and new.lote_recepcion_id is not distinct from old.lote_recepcion_id then
            return new;
        end if;
        perform public._inv_saldo_sumar(old.item_id, old.almacen_id, old.lote_recepcion_id, -old.cantidad);
    end if;
    if tg_op in ('INSERT', 'UPDATE') then
        perform public._inv_saldo_sumar(new.item_id, new.almacen_id, new.lote_recepcion_id, new.cantidad);
        return new;
    end if;
    return old;
end $$;

drop trigger if exists trg_inv_movimiento_saldo on public.inv_movimientos;
create trigger trg_inv_movimiento_saldo
    after insert or update or delete on public.inv_movimientos
    for each row execute function public.inv_movimiento_saldo();

-- ---------------------------------------------------------------------
-- 1c. Reconstrucción desde el historial (carga inicial, y "por si acaso").
--     Bloquea inv_movimientos mientras corre para que ningún movimiento
--     nuevo se cuele entre el borrado y la recarga.
-- ---------------------------------------------------------------------
create or replace function public.inv_reconstruir_saldos() returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
    lock table public.inv_movimientos in share row exclusive mode;
    delete from public.inv_saldos;
    delete from public.inv_saldos_lote;
    insert into public.inv_saldos (item_id, almacen_id, cantidad)
        select item_id, almacen_id, sum(cantidad)
          from public.inv_movimientos group by item_id, almacen_id;
    insert into public.inv_saldos_lote (lote_recepcion_id, almacen_id, cantidad)
        select lote_recepcion_id, almacen_id, sum(cantidad)
          from public.inv_movimientos
         where lote_recepcion_id is not null
         group by lote_recepcion_id, almacen_id;
end $$;
revoke all on function public.inv_reconstruir_saldos() from public, anon, authenticated;

select public.inv_reconstruir_saldos();

-- ---------------------------------------------------------------------
-- 1d. Las vistas de siempre, ahora leyendo el saldo (mismas columnas, en el
--     mismo orden: nada de la app ni de otras vistas cambia).
-- ---------------------------------------------------------------------
create or replace view public.inv_stock with (security_invoker = true) as
    select item_id, almacen_id, cantidad as cantidad_sistema
      from public.inv_saldos;

create or replace view public.inv_stock_lote with (security_invoker = true) as
    select r.id as lote_recepcion_id, r.item_id, s.almacen_id, r.n_lote,
           r.fecha_fabricacion, r.fecha_vencimiento, r.proveedor_id, r.senasac,
           s.cantidad as cantidad_disponible
      from public.inv_recepciones r
      join public.inv_saldos_lote s on s.lote_recepcion_id = r.id;

-- inv_existencia: igual a v25, salvo "en qué almacenes tuvo movimientos" el
-- ítem, que ahora sale de inv_saldos (una fila por ítem+almacén) en vez de
-- recorrer todos los movimientos.
create or replace view public.inv_existencia with (security_invoker = true) as
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
        select s.item_id, s.almacen_id from public.inv_saldos s
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

-- ---------------------------------------------------------------------
-- 1e. Índices para lo que todavía mira el historial, acotado en el tiempo:
--     el consumo de los últimos 30 días y el último conteo de cada ítem.
--     Con ellos esas partes cuestan lo mismo con 1 año que con 10.
-- ---------------------------------------------------------------------
create index if not exists inv_movimientos_salidas_fecha
    on public.inv_movimientos (fecha) where tipo = 'salida';
create index if not exists inv_conteos_ultimo
    on public.inv_conteos (item_id, almacen_id, fecha desc, id desc);

-- ---------------------------------------------------------------------
-- 2. Presencia: el último "sigo acá" de cada usuario.
-- ---------------------------------------------------------------------
create table if not exists public.app_presencia (
    usuario_id uuid primary key references auth.users(id) on delete cascade,
    rol text not null,
    nombre text,
    ultima_senal timestamptz not null default now(),
    pendientes int not null default 0 check (pendientes >= 0),
    -- false = cerró sesión a propósito (no es "sin internet").
    activa boolean not null default true
);
create index if not exists app_presencia_rol on public.app_presencia (rol, ultima_senal desc);

alter table public.app_presencia enable row level security;
-- Cualquiera con sesión puede ver el estado de las áreas (es lo que se
-- muestra en los avisos); nadie escribe directo, solo por las funciones.
drop policy if exists "ver_app_presencia" on public.app_presencia;
create policy "ver_app_presencia" on public.app_presencia for select using (auth.uid() is not null);
grant select on public.app_presencia to authenticated;

create or replace function public.presencia_latido(p_pendientes int default 0) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then raise exception 'Sin sesión.'; end if;
    insert into public.app_presencia (usuario_id, rol, nombre, ultima_senal, pendientes, activa)
    select v_uid, u.rol, u.nombre_completo, now(), greatest(coalesce(p_pendientes, 0), 0), true
      from public.usuarios u where u.id = v_uid
    on conflict (usuario_id) do update
        set rol = excluded.rol, nombre = excluded.nombre, ultima_senal = now(),
            pendientes = excluded.pendientes, activa = true;
end $$;

-- Al cerrar sesión: que no aparezca como "sin señal" (no es un corte de red).
create or replace function public.presencia_salir() returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
    update public.app_presencia set activa = false where usuario_id = auth.uid();
end $$;

grant execute on function public.presencia_latido(int), public.presencia_salir() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Tiempo real de Jarabes (Soplado ya estaba en v41).
-- ---------------------------------------------------------------------
do $$
declare
    t text;
begin
    foreach t in array array['jarabes_preparados', 'jarabes_recetas', 'soplado_corridas'] loop
        if not exists (
            select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
        ) then
            execute format('alter publication supabase_realtime add table public.%I', t);
        end if;
    end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2b. Lectura de la presencia con los segundos sin señal calculados ACÁ,
--     con el reloj del servidor: el reloj de cada compu puede estar
--     adelantado o atrasado varios minutos, y eso haría ver "sin señal" a
--     un área que está bien (o al revés). Solo lo de las últimas 12 horas.
-- ---------------------------------------------------------------------
create or replace function public.presencia_listar()
returns table (usuario_id uuid, rol text, nombre text, ultima_senal timestamptz,
               pendientes int, activa boolean, segundos_sin_senal int)
language sql stable security definer
set search_path = public, pg_temp
as $$
    select p.usuario_id, p.rol, p.nombre, p.ultima_senal, p.pendientes, p.activa,
           extract(epoch from (now() - p.ultima_senal))::int
      from public.app_presencia p
     where auth.uid() is not null
       and p.ultima_senal >= now() - interval '12 hours'
     order by p.rol, p.ultima_senal desc;
$$;
grant execute on function public.presencia_listar() to authenticated;
