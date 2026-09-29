-- =====================================================================
-- SALVIETTI CONTROL — v24: solicitudes a Gerencia y su bandeja (Módulo 4).
-- Ejecutar DESPUÉS de schema_v18_inventario_almacenes.sql, en el SQL Editor
-- de Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Distinto del Módulo 3 (inv_pedidos): aquello es un área pidiéndole
-- materiales a Almacén. Esto es cualquier área pidiéndole algo a GERENCIA:
-- Almacén que falta un suministro, el Jefe de Producción que necesita
-- autorización, Calidad que quiere cambiar un insumo de una receta, etc.
-- Gerencia tiene una única bandeja para aprobar o rechazar todo.
--
-- Como con los pedidos, la tabla no admite escritura directa: todo pasa
-- por las dos funciones de abajo (crear y resolver), que validan permisos.

create table if not exists public.solicitudes_gerencia (
    id bigint generated always as identity primary key,
    fecha timestamptz not null default now(),
    tipo text not null check (tipo in ('suministro', 'autorizacion', 'cambio_receta', 'otro')),
    asunto text not null check (length(asunto) between 3 and 120),
    detalle text check (detalle is null or length(detalle) <= 500),
    item_id bigint references public.inv_items(id),
    cantidad_sugerida numeric check (cantidad_sugerida is null or cantidad_sugerida > 0),
    estado text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
    solicitante uuid not null default auth.uid(),
    solicitante_nombre text,
    solicitante_rol text,
    resuelta_por uuid,
    resuelta_por_nombre text,
    resuelta_en timestamptz,
    respuesta text check (respuesta is null or length(respuesta) <= 500)
);
create index if not exists solicitudes_gerencia_estado on public.solicitudes_gerencia (estado, fecha desc);

alter table public.solicitudes_gerencia enable row level security;

-- Ve sus propias solicitudes quien puede solicitar; ve todas quien aprueba.
drop policy if exists "ver_solicitudes_gerencia" on public.solicitudes_gerencia;
create policy "ver_solicitudes_gerencia" on public.solicitudes_gerencia for select
    using (
        public.tiene_permiso('solicitudes', 'ver')
        and (solicitante = auth.uid() or public.tiene_permiso('aprobaciones', 'ver'))
    );

-- ---------------------------------------------------------------------
-- Crear una solicitud.
-- ---------------------------------------------------------------------
create or replace function public.solicitud_crear(
    p_tipo text,
    p_asunto text,
    p_detalle text default null,
    p_item_id bigint default null,
    p_cantidad numeric default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_id bigint;
    v_nombre text;
    v_rol text;
begin
    if not public.tiene_permiso('solicitudes', 'crear') then
        raise exception 'No tenés permiso para hacer solicitudes.';
    end if;
    if p_tipo not in ('suministro', 'autorizacion', 'cambio_receta', 'otro') then
        raise exception 'Tipo de solicitud inválido.';
    end if;
    if length(trim(coalesce(p_asunto, ''))) < 3 then
        raise exception 'El asunto es obligatorio (mínimo 3 caracteres).';
    end if;
    if length(p_asunto) > 120 then raise exception 'El asunto es demasiado largo.'; end if;
    if length(coalesce(p_detalle, '')) > 500 then raise exception 'El detalle es demasiado largo.'; end if;
    if p_item_id is not null and not exists (select 1 from public.inv_items where id = p_item_id) then
        raise exception 'El ítem indicado no existe.';
    end if;
    if p_cantidad is not null and p_cantidad <= 0 then
        raise exception 'La cantidad debe ser mayor a cero.';
    end if;

    select nombre_completo, rol into v_nombre, v_rol from public.usuarios where id = auth.uid();

    insert into public.solicitudes_gerencia
        (tipo, asunto, detalle, item_id, cantidad_sugerida, solicitante_nombre, solicitante_rol)
    values
        (p_tipo, trim(p_asunto), nullif(trim(coalesce(p_detalle, '')), ''), p_item_id, p_cantidad,
         v_nombre, v_rol)
    returning id into v_id;

    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Gerencia aprueba o rechaza.
-- ---------------------------------------------------------------------
create or replace function public.solicitud_resolver(p_id bigint, p_aprobar boolean, p_respuesta text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v public.solicitudes_gerencia;
    v_nombre text;
begin
    if not public.tiene_permiso('aprobaciones', 'aprobar') then
        raise exception 'No tenés permiso para resolver solicitudes.';
    end if;
    select * into v from public.solicitudes_gerencia where id = p_id for update;
    if not found then raise exception 'La solicitud no existe.'; end if;
    if v.estado <> 'pendiente' then raise exception 'Esta solicitud ya fue resuelta.'; end if;
    if length(coalesce(p_respuesta, '')) > 500 then raise exception 'La respuesta es demasiado larga.'; end if;
    if not p_aprobar and length(trim(coalesce(p_respuesta, ''))) = 0 then
        raise exception 'Explicá el motivo del rechazo.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();

    update public.solicitudes_gerencia
       set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
           resuelta_por = auth.uid(), resuelta_por_nombre = v_nombre, resuelta_en = now(),
           respuesta = nullif(trim(coalesce(p_respuesta, '')), '')
     where id = p_id;
end;
$$;

revoke all on function public.solicitud_crear(text, text, text, bigint, numeric) from public;
revoke all on function public.solicitud_resolver(bigint, boolean, text) from public;
grant execute on function public.solicitud_crear(text, text, text, bigint, numeric) to authenticated;
grant execute on function public.solicitud_resolver(bigint, boolean, text) to authenticated;
