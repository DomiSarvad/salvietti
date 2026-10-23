-- =====================================================================
-- v43 · Pedidos de compra de Almacén (con aprobación del Gerente)
--
-- Almacén arma un pedido de compra a proveedores con varias líneas (ítem +
-- cantidad + nota) y el Gerente lo aprueba o lo rechaza ENTERO, con una
-- respuesta (obligatoria si rechaza). Mientras está pendiente, quien lo hizo
-- lo puede anular. No mueve stock: el stock entra cuando llega la mercadería
-- (Recepciones). Es la autorización previa a comprar.
--
-- Módulo nuevo `compras` (Almacén: ver/crear; Gerente: ver/aprobar; Jefe de
-- Producción: ver). Toda escritura por funciones `security definer` (como
-- pedidos/entregas, v21): así el pedido y sus líneas quedan en una sola
-- transacción y nadie puede cambiar el estado a mano.
--
-- También agrega `compras_pedidos` y `solicitudes_gerencia` a la publicación
-- de Realtime: la campana flotante se actualiza sola cuando llega algo.
--
-- Re-ejecutable. Requiere v17 (permisos), v18 (inv_items), v24 (solicitudes).
-- =====================================================================

insert into public.app_modulos (id, nombre, estado) values
    ('compras', 'Pedidos de compra', 'activo')
on conflict (id) do nothing;

insert into public.permisos_rol (rol, modulo, accion)
select v.rol, 'compras', v.accion
  from (values
      ('almacen', 'ver'), ('almacen', 'crear'),
      ('gerente', 'ver'), ('gerente', 'aprobar'),
      ('jefe_produccion', 'ver')
  ) as v(rol, accion)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Tablas.
-- ---------------------------------------------------------------------
create table if not exists public.compras_pedidos (
    id bigint generated always as identity primary key,
    fecha timestamptz not null default now(),
    motivo text check (motivo is null or length(motivo) <= 500),
    estado text not null default 'pendiente'
        check (estado in ('pendiente', 'aprobado', 'rechazado', 'anulado')),
    solicitante uuid not null default auth.uid(),
    solicitante_nombre text,
    resuelto_por uuid,
    resuelto_por_nombre text,
    resuelto_en timestamptz,
    respuesta text check (respuesta is null or length(respuesta) <= 500)
);
create index if not exists compras_pedidos_estado on public.compras_pedidos (estado, fecha desc);

create table if not exists public.compras_pedido_lineas (
    id bigint generated always as identity primary key,
    pedido_id bigint not null references public.compras_pedidos(id) on delete cascade,
    item_id bigint not null references public.inv_items(id),
    cantidad numeric not null check (cantidad > 0),
    nota text check (nota is null or length(nota) <= 200)
);
create index if not exists compras_pedido_lineas_pedido on public.compras_pedido_lineas (pedido_id);

alter table public.compras_pedidos enable row level security;
alter table public.compras_pedido_lineas enable row level security;

drop policy if exists "ver_compras_pedidos" on public.compras_pedidos;
create policy "ver_compras_pedidos" on public.compras_pedidos for select
    using (public.tiene_permiso('compras', 'ver'));

drop policy if exists "ver_compras_pedido_lineas" on public.compras_pedido_lineas;
create policy "ver_compras_pedido_lineas" on public.compras_pedido_lineas for select
    using (public.tiene_permiso('compras', 'ver'));

grant select on public.compras_pedidos, public.compras_pedido_lineas to authenticated;

-- ---------------------------------------------------------------------
-- Crear: p_lineas = [{"item_id": 1, "cantidad": 10, "nota": "..."}, ...]
-- ---------------------------------------------------------------------
create or replace function public.compras_crear_pedido(p_motivo text, p_lineas jsonb)
returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_id bigint;
    v_nombre text;
    l jsonb;
    v_item bigint;
    v_cant numeric;
begin
    if not public.tiene_permiso('compras', 'crear') then
        raise exception 'No tenés permiso para hacer pedidos de compra.';
    end if;
    if p_lineas is null or jsonb_typeof(p_lineas) <> 'array' or jsonb_array_length(p_lineas) = 0 then
        raise exception 'El pedido necesita al menos un ítem.';
    end if;
    if jsonb_array_length(p_lineas) > 100 then
        raise exception 'Demasiados ítems en un solo pedido (máximo 100).';
    end if;
    if length(coalesce(p_motivo, '')) > 500 then raise exception 'El motivo es demasiado largo.'; end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.compras_pedidos (motivo, solicitante_nombre)
    values (nullif(trim(coalesce(p_motivo, '')), ''), v_nombre)
    returning id into v_id;

    for l in select * from jsonb_array_elements(p_lineas) loop
        v_item := (l->>'item_id')::bigint;
        v_cant := (l->>'cantidad')::numeric;
        if v_item is null or not exists (select 1 from public.inv_items where id = v_item and activo) then
            raise exception 'Uno de los ítems no existe o está dado de baja.';
        end if;
        if v_cant is null or v_cant <= 0 then
            raise exception 'Todas las cantidades tienen que ser mayores a cero.';
        end if;
        if length(coalesce(l->>'nota', '')) > 200 then
            raise exception 'Una de las notas es demasiado larga (máximo 200).';
        end if;
        insert into public.compras_pedido_lineas (pedido_id, item_id, cantidad, nota)
        values (v_id, v_item, v_cant, nullif(trim(coalesce(l->>'nota', '')), ''));
    end loop;

    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- El Gerente aprueba o rechaza el pedido entero.
-- ---------------------------------------------------------------------
create or replace function public.compras_resolver(p_id bigint, p_aprobar boolean, p_respuesta text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v public.compras_pedidos;
    v_nombre text;
begin
    if not public.tiene_permiso('compras', 'aprobar') then
        raise exception 'No tenés permiso para aprobar pedidos de compra.';
    end if;
    select * into v from public.compras_pedidos where id = p_id for update;
    if not found then raise exception 'El pedido no existe.'; end if;
    if v.estado <> 'pendiente' then raise exception 'Este pedido ya fue resuelto o anulado.'; end if;
    if length(coalesce(p_respuesta, '')) > 500 then raise exception 'La respuesta es demasiado larga.'; end if;
    if not p_aprobar and length(trim(coalesce(p_respuesta, ''))) = 0 then
        raise exception 'Explicá el motivo del rechazo.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.compras_pedidos
       set estado = case when p_aprobar then 'aprobado' else 'rechazado' end,
           resuelto_por = auth.uid(), resuelto_por_nombre = v_nombre, resuelto_en = now(),
           respuesta = nullif(trim(coalesce(p_respuesta, '')), '')
     where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Quien lo hizo lo puede anular mientras está pendiente.
-- ---------------------------------------------------------------------
create or replace function public.compras_anular(p_id bigint)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v public.compras_pedidos;
begin
    select * into v from public.compras_pedidos where id = p_id for update;
    if not found then raise exception 'El pedido no existe.'; end if;
    if v.solicitante <> auth.uid() then raise exception 'Solo quien hizo el pedido lo puede anular.'; end if;
    if v.estado <> 'pendiente' then raise exception 'Solo se puede anular un pedido pendiente.'; end if;
    update public.compras_pedidos set estado = 'anulado' where id = p_id;
end;
$$;

revoke all on function public.compras_crear_pedido(text, jsonb) from public;
revoke all on function public.compras_resolver(bigint, boolean, text) from public;
revoke all on function public.compras_anular(bigint) from public;
grant execute on function public.compras_crear_pedido(text, jsonb) to authenticated;
grant execute on function public.compras_resolver(bigint, boolean, text) to authenticated;
grant execute on function public.compras_anular(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- Tiempo real para la campana (con chequeo: falla si ya estaba agregada).
-- ---------------------------------------------------------------------
do $$
declare
    t text;
begin
    foreach t in array array['compras_pedidos', 'solicitudes_gerencia'] loop
        if not exists (
            select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
        ) then
            execute format('alter publication supabase_realtime add table public.%I', t);
        end if;
    end loop;
end $$;
