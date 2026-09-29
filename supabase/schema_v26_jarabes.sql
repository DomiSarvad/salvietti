-- =====================================================================
-- SALVIETTI CONTROL — v26: recetas y producción de Jarabes (Módulo 6).
-- Ejecutar DESPUÉS de schema_v21_entregas.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Flujo:
--   1. Jarabes/Ayudante PROPONE una receta para un sabor (jarabes_recetas,
--      estado 'propuesta'). Jefe de Producción, Calidad o Gerente la
--      APRUEBA (queda 'activa'; la anterior activa de ese sabor pasa a
--      'inactiva') o la RECHAZA. Esto es una aprobación simple; el
--      Módulo 11 la reemplaza por la doble aprobación (Calidad Y
--      Producción) + clave del Gerente que pide el proceso real.
--   2. Para preparar: se verifica el stock (jarabes_verificar_insumos) ANTES
--      de iniciar, así Jarabes sabe si le alcanza para la cantidad que
--      quiere hacer. Si falta algo, la app ofrece pedirlo a Almacén con
--      inv_crear_pedido (Módulo 3) — no hay una función nueva para eso.
--   3. Iniciar guarda hora de inicio, litros y N° de lote (correlativo por
--      sabor) automáticos, y saca una "foto" de lo que la receta necesita
--      (jarabes_preparado_insumos). NO descuenta el almacén todavía.
--   4. Finalizar guarda hora de fin y Brix, y ahí SÍ descuenta del almacén
--      de Jarabes lo que la foto dice que se necesitó.
--
-- Límite conocido: entre iniciar y finalizar el insumo no queda "reservado"
-- de verdad (solo son advertencias en el momento de iniciar). Con más de
-- una persona preparando a la vez podría iniciarse más de lo que alcanza;
-- para el uso real (una persona por turno) no hace falta más que esto.

-- ---------------------------------------------------------------------
-- Recetas.
-- ---------------------------------------------------------------------
create table if not exists public.jarabes_recetas (
    id bigint generated always as identity primary key,
    sabor_id bigint not null references public.sabores(id),
    estado text not null default 'propuesta'
        check (estado in ('propuesta', 'activa', 'inactiva', 'rechazada')),
    creada_por uuid not null default auth.uid(),
    creada_por_nombre text,
    creada_en timestamptz not null default now(),
    aprobada_por uuid,
    aprobada_por_nombre text,
    aprobada_en timestamptz,
    motivo_rechazo text check (motivo_rechazo is null or length(motivo_rechazo) <= 300)
);
create index if not exists jarabes_recetas_sabor on public.jarabes_recetas (sabor_id, estado);

create table if not exists public.jarabes_receta_items (
    id bigint generated always as identity primary key,
    receta_id bigint not null references public.jarabes_recetas(id) on delete cascade,
    item_id bigint not null references public.inv_items(id),
    cantidad_por_preparado numeric not null check (cantidad_por_preparado > 0),
    unique (receta_id, item_id)
);

alter table public.jarabes_recetas enable row level security;
alter table public.jarabes_receta_items enable row level security;

drop policy if exists "ver_jarabes_recetas" on public.jarabes_recetas;
create policy "ver_jarabes_recetas" on public.jarabes_recetas for select
    using (public.tiene_permiso('recetas', 'ver'));
drop policy if exists "ver_jarabes_receta_items" on public.jarabes_receta_items;
create policy "ver_jarabes_receta_items" on public.jarabes_receta_items for select
    using (exists (select 1 from public.jarabes_recetas r where r.id = receta_id));

-- ---------------------------------------------------------------------
-- 1. Proponer una receta. p_items: [{"item_id": 5, "cantidad": 18}, ...]
-- ---------------------------------------------------------------------
create or replace function public.jarabes_receta_crear(p_sabor_id bigint, p_items jsonb)
returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_id bigint;
    v_nombre text;
    v_item jsonb;
    v_item_id bigint;
    v_cant numeric;
begin
    if not public.tiene_permiso('recetas', 'crear') then
        raise exception 'No tenés permiso para proponer recetas.';
    end if;
    if not exists (select 1 from public.sabores where id = p_sabor_id) then
        raise exception 'El sabor indicado no existe.';
    end if;
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
        raise exception 'La receta no puede estar vacía.';
    end if;
    if jsonb_array_length(p_items) > 40 then
        raise exception 'Una receta puede tener hasta 40 insumos.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.jarabes_recetas (sabor_id, creada_por_nombre)
    values (p_sabor_id, v_nombre) returning id into v_id;

    for v_item in select * from jsonb_array_elements(p_items) loop
        v_item_id := (v_item ->> 'item_id')::bigint;
        v_cant := (v_item ->> 'cantidad')::numeric;
        if v_item_id is null or v_cant is null or v_cant <= 0 then
            raise exception 'Cada insumo necesita una cantidad mayor a cero.';
        end if;
        if not exists (
            select 1 from public.inv_items i
              join public.inv_categorias c on c.id = i.categoria_id
             where i.id = v_item_id and i.activo and c.almacen_id = 'jarabes'
        ) then
            raise exception 'Uno de los insumos no pertenece al Almacén de Jarabes.';
        end if;
        insert into public.jarabes_receta_items (receta_id, item_id, cantidad_por_preparado)
        values (v_id, v_item_id, v_cant);
    end loop;

    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Aprobar (queda activa; la anterior activa de ese sabor se retira) o
--    rechazar una receta propuesta.
-- ---------------------------------------------------------------------
create or replace function public.jarabes_receta_aprobar(p_id bigint) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.jarabes_recetas; v_nombre text;
begin
    if not public.tiene_permiso('recetas', 'aprobar') then
        raise exception 'No tenés permiso para aprobar recetas.';
    end if;
    select * into v_r from public.jarabes_recetas where id = p_id for update;
    if not found then raise exception 'La receta no existe.'; end if;
    if v_r.estado <> 'propuesta' then raise exception 'Esta receta ya fue resuelta.'; end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.jarabes_recetas set estado = 'inactiva'
     where sabor_id = v_r.sabor_id and estado = 'activa';
    update public.jarabes_recetas
       set estado = 'activa', aprobada_por = auth.uid(),
           aprobada_por_nombre = v_nombre, aprobada_en = now()
     where id = p_id;
end;
$$;

create or replace function public.jarabes_receta_rechazar(p_id bigint, p_motivo text) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.jarabes_recetas; v_nombre text;
begin
    if not public.tiene_permiso('recetas', 'aprobar') then
        raise exception 'No tenés permiso para rechazar recetas.';
    end if;
    select * into v_r from public.jarabes_recetas where id = p_id for update;
    if not found then raise exception 'La receta no existe.'; end if;
    if v_r.estado <> 'propuesta' then raise exception 'Esta receta ya fue resuelta.'; end if;
    if length(trim(coalesce(p_motivo, ''))) = 0 then
        raise exception 'Explicá el motivo del rechazo.';
    end if;
    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.jarabes_recetas
       set estado = 'rechazada', aprobada_por = auth.uid(), aprobada_por_nombre = v_nombre,
           aprobada_en = now(), motivo_rechazo = trim(p_motivo)
     where id = p_id;
end;
$$;

-- Receta vigente de cada sabor, con sus insumos y lo que hay disponible.
create or replace view public.jarabes_receta_vigente with (security_invoker = true) as
    select r.id as receta_id, r.sabor_id, s.nombre as sabor,
           ri.item_id, i.codigo, i.detalle, i.unidad, ri.cantidad_por_preparado,
           coalesce(st.cantidad_sistema, 0) as disponible
      from public.jarabes_recetas r
      join public.sabores s on s.id = r.sabor_id
      join public.jarabes_receta_items ri on ri.receta_id = r.id
      join public.inv_items i on i.id = ri.item_id
      left join public.inv_stock st on st.item_id = i.id and st.almacen_id = 'jarabes'
     where r.estado = 'activa';

-- ---------------------------------------------------------------------
-- Preparados (las corridas de producción).
-- ---------------------------------------------------------------------
create table if not exists public.jarabes_preparados (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    sabor_id bigint not null references public.sabores(id),
    receta_id bigint not null references public.jarabes_recetas(id),
    n_lote int not null,
    tanque int check (tanque is null or tanque > 0),
    cantidad_preparados numeric not null check (cantidad_preparados > 0),
    litros numeric check (litros is null or litros >= 0),
    estado text not null default 'en_curso' check (estado in ('en_curso', 'finalizada', 'anulada')),
    hora_inicio timestamptz not null default now(),
    hora_fin timestamptz,
    brix numeric check (brix is null or (brix >= 0 and brix <= 100)),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    observaciones text check (observaciones is null or length(observaciones) <= 300),
    creado_en timestamptz not null default now(),
    unique (sabor_id, n_lote)
);
create index if not exists jarabes_preparados_estado on public.jarabes_preparados (estado, fecha desc);

create table if not exists public.jarabes_preparado_insumos (
    id bigint generated always as identity primary key,
    preparado_id bigint not null references public.jarabes_preparados(id) on delete cascade,
    item_id bigint not null references public.inv_items(id),
    cantidad_necesaria numeric not null check (cantidad_necesaria > 0)
);

alter table public.jarabes_preparados enable row level security;
alter table public.jarabes_preparado_insumos enable row level security;

drop policy if exists "ver_jarabes_preparados" on public.jarabes_preparados;
create policy "ver_jarabes_preparados" on public.jarabes_preparados for select
    using (public.tiene_permiso('jarabes_produccion', 'ver'));
drop policy if exists "ver_jarabes_preparado_insumos" on public.jarabes_preparado_insumos;
create policy "ver_jarabes_preparado_insumos" on public.jarabes_preparado_insumos for select
    using (exists (select 1 from public.jarabes_preparados p where p.id = preparado_id));

-- ---------------------------------------------------------------------
-- Cuánto insumo necesita [p_cantidad] preparados de [p_sabor_id] y cuánto
-- falta. La usa la app ANTES de iniciar, para avisar y ofrecer pedir a
-- Almacén; la función de iniciar la vuelve a evaluar por su cuenta.
-- ---------------------------------------------------------------------
create or replace function public.jarabes_verificar_insumos(p_sabor_id bigint, p_cantidad numeric)
returns table (item_id bigint, detalle text, unidad text, necesario numeric, disponible numeric, falta numeric)
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
    if not public.tiene_permiso('jarabes_produccion', 'ver') then
        raise exception 'No tenés permiso para ver esto.';
    end if;
    if not exists (select 1 from public.jarabes_recetas where sabor_id = p_sabor_id and estado = 'activa') then
        raise exception 'Ese sabor no tiene una receta activa.';
    end if;
    return query
        select v.item_id, v.detalle, v.unidad,
               v.cantidad_por_preparado * p_cantidad as necesario,
               v.disponible,
               greatest(v.cantidad_por_preparado * p_cantidad - v.disponible, 0) as falta
          from public.jarabes_receta_vigente v
         where v.sabor_id = p_sabor_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Iniciar: hora, litros y N° de lote automáticos; guarda la "foto" de
--    insumos necesarios; bloquea si no alcanza el stock.
-- ---------------------------------------------------------------------
create or replace function public.jarabes_iniciar_preparado(
    p_sabor_id bigint, p_cantidad numeric, p_tanque int default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_receta bigint;
    v_litros_unitarios numeric;
    v_lote int;
    v_id bigint;
    v_nombre text;
    v_falta record;
begin
    if not public.tiene_permiso('jarabes_produccion', 'crear') then
        raise exception 'No tenés permiso para iniciar una producción de Jarabes.';
    end if;
    if p_cantidad is null or p_cantidad <= 0 then
        raise exception 'La cantidad de preparados debe ser mayor a cero.';
    end if;
    if p_tanque is not null and p_tanque <= 0 then raise exception 'Tanque inválido.'; end if;

    select id into v_receta from public.jarabes_recetas
     where sabor_id = p_sabor_id and estado = 'activa';
    if v_receta is null then raise exception 'Ese sabor no tiene una receta activa.'; end if;

    for v_falta in select * from public.jarabes_verificar_insumos(p_sabor_id, p_cantidad)
    loop
        if v_falta.falta > 0 then
            raise exception 'No alcanza el stock de "%": faltan % %.',
                v_falta.detalle, v_falta.falta, v_falta.unidad;
        end if;
    end loop;

    select litros_por_preparado into v_litros_unitarios from public.sabores where id = p_sabor_id;
    select coalesce(max(n_lote), 0) + 1 into v_lote
      from public.jarabes_preparados where sabor_id = p_sabor_id;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.jarabes_preparados
        (sabor_id, receta_id, n_lote, tanque, cantidad_preparados, litros, responsable_nombre)
    values
        (p_sabor_id, v_receta, v_lote, p_tanque, p_cantidad,
         case when v_litros_unitarios is null then null else v_litros_unitarios * p_cantidad end,
         v_nombre)
    returning id into v_id;

    insert into public.jarabes_preparado_insumos (preparado_id, item_id, cantidad_necesaria)
    select v_id, ri.item_id, ri.cantidad_por_preparado * p_cantidad
      from public.jarabes_receta_items ri where ri.receta_id = v_receta;

    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Finalizar: hora y Brix; descuenta del almacén de Jarabes lo que la
--    foto de insumos dice que se necesitó.
-- ---------------------------------------------------------------------
create or replace function public.jarabes_finalizar_preparado(
    p_id bigint, p_brix numeric, p_observaciones text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_p public.jarabes_preparados; v_ins record; v_disponible numeric;
begin
    if not public.tiene_permiso('jarabes_produccion', 'editar') then
        raise exception 'No tenés permiso para finalizar una producción de Jarabes.';
    end if;
    select * into v_p from public.jarabes_preparados where id = p_id for update;
    if not found then raise exception 'El preparado no existe.'; end if;
    if v_p.estado <> 'en_curso' then raise exception 'Ese preparado ya se cerró.'; end if;
    if p_brix is null or p_brix < 0 or p_brix > 100 then
        raise exception 'Ingresá un Brix válido (0 a 100).';
    end if;
    if length(coalesce(p_observaciones, '')) > 300 then
        raise exception 'Las observaciones son demasiado largas.';
    end if;

    for v_ins in select * from public.jarabes_preparado_insumos where preparado_id = p_id loop
        select coalesce(sum(cantidad), 0) into v_disponible
          from public.inv_movimientos where item_id = v_ins.item_id and almacen_id = 'jarabes';
        if v_ins.cantidad_necesaria > v_disponible then
            raise exception 'Ya no alcanza el stock de "%" para descontarlo (cambió desde que se inició).',
                (select detalle from public.inv_items where id = v_ins.item_id);
        end if;
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
        values (v_ins.item_id, 'jarabes', 'salida', -v_ins.cantidad_necesaria,
                'jarabes_preparado', p_id, 'Consumo de preparado de jarabes');
    end loop;

    update public.jarabes_preparados
       set estado = 'finalizada', hora_fin = now(), brix = p_brix,
           observaciones = nullif(trim(coalesce(p_observaciones, '')), '')
     where id = p_id;
end;
$$;

create or replace function public.jarabes_anular_preparado(p_id bigint, p_motivo text) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_p public.jarabes_preparados;
begin
    if not public.tiene_permiso('jarabes_produccion', 'editar') then
        raise exception 'No tenés permiso para anular un preparado.';
    end if;
    select * into v_p from public.jarabes_preparados where id = p_id for update;
    if not found then raise exception 'El preparado no existe.'; end if;
    if v_p.estado <> 'en_curso' then raise exception 'Solo se anula un preparado en curso.'; end if;
    if length(trim(coalesce(p_motivo, ''))) < 3 then
        raise exception 'Escribí el motivo (mínimo 3 caracteres).';
    end if;
    update public.jarabes_preparados
       set estado = 'anulada', hora_fin = now(), observaciones = trim(p_motivo)
     where id = p_id;
end;
$$;

revoke all on function public.jarabes_receta_crear(bigint, jsonb) from public;
revoke all on function public.jarabes_receta_aprobar(bigint) from public;
revoke all on function public.jarabes_receta_rechazar(bigint, text) from public;
revoke all on function public.jarabes_verificar_insumos(bigint, numeric) from public;
revoke all on function public.jarabes_iniciar_preparado(bigint, numeric, int) from public;
revoke all on function public.jarabes_finalizar_preparado(bigint, numeric, text) from public;
revoke all on function public.jarabes_anular_preparado(bigint, text) from public;
grant execute on function public.jarabes_receta_crear(bigint, jsonb) to authenticated;
grant execute on function public.jarabes_receta_aprobar(bigint) to authenticated;
grant execute on function public.jarabes_receta_rechazar(bigint, text) to authenticated;
grant execute on function public.jarabes_verificar_insumos(bigint, numeric) to authenticated;
grant execute on function public.jarabes_iniciar_preparado(bigint, numeric, int) to authenticated;
grant execute on function public.jarabes_finalizar_preparado(bigint, numeric, text) to authenticated;
grant execute on function public.jarabes_anular_preparado(bigint, text) to authenticated;
