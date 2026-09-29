-- =====================================================================
-- SALVIETTI CONTROL — v39: devolución de un pedido (mejora del Módulo 3).
-- Ejecutar DESPUÉS de schema_v38_informe_gerente.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Pendiente descubierto con el "PEDIDO INTERNO DE ETIQUETAS" (sección 13):
-- el pedido en sí ya se podía hacer (Módulo 3), pero ese papel también
-- registra la DEVOLUCIÓN — lo que sobra de una entrega se le regresa a
-- Almacén. Aplica a cualquier pedido, no solo a etiquetas (tapas,
-- solvente, lo que sea que un área pidió de más).
--
-- Quién la registra: Almacén, porque es quien recibe físicamente lo que
-- vuelve (mismo permiso que entregar: `entregas:crear` + operar ese
-- almacén). No hace falta que el área destino confirme nada: la
-- devolución es un movimiento de Almacén, como la entrega misma.

create table if not exists public.inv_devoluciones (
    id bigint generated always as identity primary key,
    linea_id bigint not null references public.inv_pedido_lineas(id),
    cantidad numeric not null check (cantidad > 0),
    motivo text check (motivo is null or length(motivo) <= 300),
    movimiento_id bigint references public.inv_movimientos(id),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    creado_en timestamptz not null default now()
);
create index if not exists inv_devoluciones_linea on public.inv_devoluciones (linea_id);

alter table public.inv_devoluciones enable row level security;
drop policy if exists "ver_inv_devoluciones" on public.inv_devoluciones;
create policy "ver_inv_devoluciones" on public.inv_devoluciones for select
    using (exists (select 1 from public.inv_pedido_lineas l where l.id = linea_id));
grant select on public.inv_devoluciones to authenticated;

-- ---------------------------------------------------------------------
-- Registrar la devolución de una línea ya entregada. No puede devolverse
-- más de lo entregado menos lo ya devuelto antes.
-- ---------------------------------------------------------------------
create or replace function public.inv_registrar_devolucion(
    p_linea_id bigint,
    p_cantidad numeric,
    p_motivo text default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_linea public.inv_pedido_lineas;
    v_pedido public.inv_pedidos;
    v_devuelto numeric;
    v_disponible numeric;
    v_mov_id bigint;
    v_id bigint;
    v_nombre text;
begin
    if not public.tiene_permiso('entregas', 'crear') then
        raise exception 'No tenés permiso para registrar devoluciones.';
    end if;
    select * into v_linea from public.inv_pedido_lineas where id = p_linea_id for update;
    if not found then raise exception 'La línea del pedido no existe.'; end if;
    select * into v_pedido from public.inv_pedidos where id = v_linea.pedido_id for update;
    if not public.puede_operar_almacen(v_pedido.almacen_origen) then
        raise exception 'No operás el almacén de origen de este pedido.';
    end if;
    if v_pedido.estado not in ('entregado', 'observado', 'cerrado') then
        raise exception 'Todavía no se entregó nada de este pedido.';
    end if;
    if p_cantidad is null or p_cantidad <= 0 then
        raise exception 'La cantidad a devolver debe ser mayor a cero.';
    end if;
    if length(coalesce(p_motivo, '')) > 300 then
        raise exception 'El motivo es demasiado largo.';
    end if;

    select coalesce(sum(cantidad), 0) into v_devuelto
      from public.inv_devoluciones where linea_id = p_linea_id;
    v_disponible := coalesce(v_linea.cantidad_entregada, 0) - v_devuelto;
    if p_cantidad > v_disponible + 1e-9 then
        raise exception 'No se puede devolver más de lo entregado: quedan % disponibles para devolver.',
            v_disponible;
    end if;

    insert into public.inv_movimientos
        (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
    values (v_linea.item_id, v_pedido.almacen_origen, 'entrada', p_cantidad, 'devolucion', p_linea_id,
            'Devolución de ' || v_pedido.area_destino)
    returning id into v_mov_id;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.inv_devoluciones (linea_id, cantidad, motivo, movimiento_id, responsable_nombre)
    values (p_linea_id, p_cantidad, nullif(trim(coalesce(p_motivo, '')), ''), v_mov_id, v_nombre)
    returning id into v_id;

    return v_id;
end;
$$;

revoke all on function public.inv_registrar_devolucion(bigint, numeric, text) from public;
grant execute on function public.inv_registrar_devolucion(bigint, numeric, text) to authenticated;

-- Devoluciones con el detalle de la línea y el pedido, para listarlas.
create or replace view public.inv_devoluciones_detalle with (security_invoker = true) as
    select d.id, d.linea_id, l.pedido_id, p.area_destino, p.almacen_origen,
           l.item_id, i.codigo, i.detalle, i.unidad,
           l.cantidad_entregada, d.cantidad, d.motivo, d.responsable_nombre, d.creado_en
      from public.inv_devoluciones d
      join public.inv_pedido_lineas l on l.id = d.linea_id
      join public.inv_pedidos p on p.id = l.pedido_id
      join public.inv_items i on i.id = l.item_id;
grant select on public.inv_devoluciones_detalle to authenticated;
