-- =====================================================================
-- SALVIETTI CONTROL — v21: pedido interno, entrega y conformidad (Módulo 3).
-- Ejecutar DESPUÉS de schema_v20_recepciones.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Flujo:
--   1. Un área pide materiales (o Almacén arma la entrega por su cuenta
--      según el plan del día).                        estado: pendiente
--   2. Almacén entrega. El sistema elige los lotes solo, saliendo primero
--      lo que vence antes, y descuenta del Almacén General.   entregado
--   3. El área revisa ítem por ítem y confirma. Si su almacén tiene stock
--      propio (Jarabes, Soplado), lo recibido entra ahí.
--         todo conforme -> cerrado     con observaciones -> observado
--   4. Almacén resuelve las observaciones.                    cerrado
--
-- SEGURIDAD: las tablas no admiten escritura directa (no hay políticas de
-- insert/update/delete). Todo pasa por las funciones de abajo, que validan
-- permisos y hacen los cambios completos o no los hacen (una sola
-- transacción). Requiere v17 (tiene_permiso) y v18 (inv_*).

-- ---------------------------------------------------------------------
-- Áreas que reciben materiales y su almacén propio (si lo tienen).
-- ---------------------------------------------------------------------
create or replace function public.area_de_rol(p_rol text) returns text
language sql immutable as $$
    select case p_rol
        when 'jarabes' then 'jarabes'
        when 'ayudante_jarabes' then 'jarabes'
        when 'soplado' then 'soplado'
        when 'llenadora' then 'llenadora'
        when 'codificacion' then 'codificacion'
        when 'control_calidad' then 'calidad'
        when 'soda_caustica' then 'soda_caustica'
        when 'registro_salidas' then 'salidas'
        else null
    end;
$$;

create or replace function public.almacen_de_area(p_area text) returns text
language sql immutable as $$
    select case p_area when 'jarabes' then 'jarabes' when 'soplado' then 'soplado' else null end;
$$;

-- ---------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------
create table if not exists public.inv_pedidos (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    area_destino text not null check (area_destino in
        ('jarabes', 'soplado', 'llenadora', 'codificacion', 'calidad', 'soda_caustica', 'salidas')),
    almacen_origen text not null default 'general' references public.inv_almacenes(id),
    almacen_destino text references public.inv_almacenes(id),
    motivo text check (motivo is null or length(motivo) <= 300),
    estado text not null default 'pendiente'
        check (estado in ('pendiente', 'entregado', 'cerrado', 'observado', 'anulado')),
    solicitante uuid not null default auth.uid(),
    solicitante_nombre text,
    creado_en timestamptz not null default now(),
    entregado_por uuid,
    entregado_por_nombre text,
    entregado_en timestamptz,
    confirmado_por uuid,
    confirmado_por_nombre text,
    confirmado_en timestamptz,
    nota_conformidad text,
    resolucion text
);
create index if not exists inv_pedidos_estado on public.inv_pedidos (estado, area_destino);

create table if not exists public.inv_pedido_lineas (
    id bigint generated always as identity primary key,
    pedido_id bigint not null references public.inv_pedidos(id) on delete cascade,
    item_id bigint not null references public.inv_items(id),
    cantidad_pedida numeric not null check (cantidad_pedida > 0),
    cantidad_entregada numeric check (cantidad_entregada >= 0),
    cantidad_recibida numeric check (cantidad_recibida >= 0),
    recibido_ok boolean,
    observacion text check (observacion is null or length(observacion) <= 300),
    unique (pedido_id, item_id)
);

-- Lotes de los que salió cada línea (con copia de N° de lote y vencimiento,
-- para que se lean sin necesitar el permiso de Recepciones).
create table if not exists public.inv_entrega_lotes (
    id bigint generated always as identity primary key,
    linea_id bigint not null references public.inv_pedido_lineas(id) on delete cascade,
    lote_recepcion_id bigint references public.inv_recepciones(id),
    n_lote text,
    fecha_vencimiento date,
    cantidad numeric not null check (cantidad > 0)
);

-- ---------------------------------------------------------------------
-- Lectura: Almacén (entregas:crear), quien pidió, el área de destino y
-- quien ve el informe de Producción (Gerente, Jefe de Producción).
-- Sin políticas de escritura: se escribe solo con las funciones.
-- ---------------------------------------------------------------------
alter table public.inv_pedidos enable row level security;
alter table public.inv_pedido_lineas enable row level security;
alter table public.inv_entrega_lotes enable row level security;

drop policy if exists "ver_inv_pedidos" on public.inv_pedidos;
create policy "ver_inv_pedidos" on public.inv_pedidos for select
    using (
        public.tiene_permiso('entregas', 'ver')
        and (
            public.tiene_permiso('entregas', 'crear')
            or solicitante = auth.uid()
            or public.area_de_rol(public.rol_actual()) = area_destino
            or public.tiene_permiso('informe_produccion', 'ver')
        )
    );

drop policy if exists "ver_inv_pedido_lineas" on public.inv_pedido_lineas;
create policy "ver_inv_pedido_lineas" on public.inv_pedido_lineas for select
    using (exists (select 1 from public.inv_pedidos p where p.id = pedido_id));

drop policy if exists "ver_inv_entrega_lotes" on public.inv_entrega_lotes;
create policy "ver_inv_entrega_lotes" on public.inv_entrega_lotes for select
    using (exists (
        select 1 from public.inv_pedido_lineas l where l.id = linea_id
    ));

-- ---------------------------------------------------------------------
-- 1. Crear un pedido (y, si es Almacén, entregarlo en el acto).
--    p_lineas: [{"item_id": 12, "cantidad": 5.5}, ...]
-- ---------------------------------------------------------------------
create or replace function public.inv_crear_pedido(
    p_area text,
    p_motivo text,
    p_lineas jsonb,
    p_entregar boolean default false
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_area text;
    v_origen text := 'general';
    v_id bigint;
    v_linea jsonb;
    v_item bigint;
    v_cant numeric;
    v_nombre text;
begin
    if not public.tiene_permiso('solicitudes', 'crear') then
        raise exception 'No tenés permiso para hacer pedidos.';
    end if;

    v_area := coalesce(nullif(trim(p_area), ''), public.area_de_rol(public.rol_actual()));
    if v_area is null or v_area not in
        ('jarabes', 'soplado', 'llenadora', 'codificacion', 'calidad', 'soda_caustica', 'salidas') then
        raise exception 'Área de destino inválida.';
    end if;
    -- Solo Almacén arma pedidos para otra área.
    if not public.tiene_permiso('entregas', 'crear')
       and v_area is distinct from public.area_de_rol(public.rol_actual()) then
        raise exception 'Solo podés hacer pedidos para tu propia área.';
    end if;
    if p_entregar and not public.tiene_permiso('entregas', 'crear') then
        raise exception 'Solo Almacén puede entregar.';
    end if;

    if jsonb_typeof(p_lineas) is distinct from 'array' or jsonb_array_length(p_lineas) = 0 then
        raise exception 'El pedido no tiene ítems.';
    end if;
    if jsonb_array_length(p_lineas) > 60 then
        raise exception 'Un pedido puede tener hasta 60 ítems.';
    end if;
    if length(coalesce(p_motivo, '')) > 300 then
        raise exception 'El motivo es demasiado largo.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();

    insert into public.inv_pedidos (area_destino, almacen_origen, almacen_destino, motivo, solicitante_nombre)
    values (v_area, v_origen, public.almacen_de_area(v_area), nullif(trim(p_motivo), ''), v_nombre)
    returning id into v_id;

    for v_linea in select * from jsonb_array_elements(p_lineas) loop
        v_item := (v_linea ->> 'item_id')::bigint;
        v_cant := (v_linea ->> 'cantidad')::numeric;
        if v_item is null or v_cant is null or v_cant <= 0 then
            raise exception 'Cada ítem necesita una cantidad mayor a cero.';
        end if;
        if not exists (
            select 1 from public.inv_items i
              join public.inv_categorias c on c.id = i.categoria_id
             where i.id = v_item and i.activo and c.almacen_id = v_origen
        ) then
            raise exception 'Uno de los ítems no existe en el almacén de origen.';
        end if;
        insert into public.inv_pedido_lineas (pedido_id, item_id, cantidad_pedida)
        values (v_id, v_item, v_cant);
    end loop;

    if p_entregar then
        perform public.inv_entregar_pedido(v_id, null);
    end if;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Entregar. p_lineas (opcional): [{"linea_id": 3, "cantidad": 4}] para
--    entregar menos de lo pedido; sin él se entrega todo.
-- ---------------------------------------------------------------------
create or replace function public.inv_entregar_pedido(p_pedido bigint, p_lineas jsonb)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_p public.inv_pedidos;
    v_l public.inv_pedido_lineas;
    v_lote record;
    v_cant numeric;
    v_over numeric;
    v_falta numeric;
    v_toma numeric;
    v_total numeric;
    v_sin_lote numeric;
    v_nombre text;
begin
    if not public.tiene_permiso('entregas', 'crear') then
        raise exception 'No tenés permiso para entregar.';
    end if;

    select * into v_p from public.inv_pedidos where id = p_pedido for update;
    if not found then raise exception 'El pedido no existe.'; end if;
    if not public.puede_operar_almacen(v_p.almacen_origen) then
        raise exception 'No operás el almacén de origen de este pedido.';
    end if;
    if v_p.estado <> 'pendiente' then
        raise exception 'El pedido ya no está pendiente.';
    end if;

    for v_l in select * from public.inv_pedido_lineas where pedido_id = p_pedido order by id loop
        v_cant := v_l.cantidad_pedida;
        if p_lineas is not null then
            v_over := null;
            select (e ->> 'cantidad')::numeric into v_over
              from jsonb_array_elements(p_lineas) e
             where (e ->> 'linea_id')::bigint = v_l.id;
            if v_over is not null then
                if v_over < 0 then raise exception 'La cantidad a entregar no puede ser negativa.'; end if;
                v_cant := v_over;
            end if;
        end if;

        if v_cant > 0 then
            select coalesce(sum(cantidad), 0) into v_total
              from public.inv_movimientos
             where item_id = v_l.item_id and almacen_id = v_p.almacen_origen;
            if v_cant > v_total + 1e-9 then
                raise exception 'Stock insuficiente de "%": hay %, se piden %.',
                    (select detalle from public.inv_items where id = v_l.item_id), v_total, v_cant;
            end if;

            v_falta := v_cant;

            -- Primero el stock sin lote (saldo inicial o ajustes): es el más antiguo.
            select greatest(coalesce(sum(cantidad), 0), 0) into v_sin_lote
              from public.inv_movimientos
             where item_id = v_l.item_id and almacen_id = v_p.almacen_origen
               and lote_recepcion_id is null;
            if v_sin_lote > 0 then
                v_toma := least(v_falta, v_sin_lote);
                insert into public.inv_movimientos
                    (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
                values (v_l.item_id, v_p.almacen_origen, 'salida', -v_toma, 'entrega', p_pedido,
                        'Entrega a ' || v_p.area_destino);
                insert into public.inv_entrega_lotes (linea_id, cantidad) values (v_l.id, v_toma);
                v_falta := v_falta - v_toma;
            end if;

            -- Después los lotes: primero el que vence antes; se saltan los vencidos.
            for v_lote in
                select s.lote_recepcion_id, s.n_lote, s.fecha_vencimiento, s.cantidad_disponible
                  from public.inv_stock_lote s
                 where s.item_id = v_l.item_id and s.almacen_id = v_p.almacen_origen
                   and s.cantidad_disponible > 0
                   and (s.fecha_vencimiento is null or s.fecha_vencimiento >= current_date)
                 order by s.fecha_vencimiento nulls last, s.lote_recepcion_id
            loop
                exit when v_falta <= 1e-9;
                v_toma := least(v_falta, v_lote.cantidad_disponible);
                insert into public.inv_movimientos
                    (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id,
                     lote_recepcion_id, motivo)
                values (v_l.item_id, v_p.almacen_origen, 'salida', -v_toma, 'entrega', p_pedido,
                        v_lote.lote_recepcion_id, 'Entrega a ' || v_p.area_destino);
                insert into public.inv_entrega_lotes
                    (linea_id, lote_recepcion_id, n_lote, fecha_vencimiento, cantidad)
                values (v_l.id, v_lote.lote_recepcion_id, v_lote.n_lote, v_lote.fecha_vencimiento, v_toma);
                v_falta := v_falta - v_toma;
            end loop;

            if v_falta > 1e-9 then
                raise exception 'No alcanza stock vigente de "%" (los lotes vencidos no se entregan): faltan %.',
                    (select detalle from public.inv_items where id = v_l.item_id), v_falta;
            end if;
        end if;

        update public.inv_pedido_lineas set cantidad_entregada = v_cant where id = v_l.id;
    end loop;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.inv_pedidos
       set estado = 'entregado', entregado_por = auth.uid(),
           entregado_por_nombre = v_nombre, entregado_en = now()
     where id = p_pedido;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Conformidad del área.
--    p_lineas: [{"linea_id": 3, "recibido_ok": true,
--                "cantidad_recibida": 4, "observacion": "..."}]  (una por línea)
-- ---------------------------------------------------------------------
create or replace function public.inv_confirmar_entrega(p_pedido bigint, p_lineas jsonb, p_nota text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_p public.inv_pedidos;
    v_l public.inv_pedido_lineas;
    v_e jsonb;
    v_ok boolean;
    v_rec numeric;
    v_obs text;
    v_conforme boolean := true;
    v_nombre text;
begin
    select * into v_p from public.inv_pedidos where id = p_pedido for update;
    if not found then raise exception 'El pedido no existe.'; end if;
    if not public.tiene_permiso('entregas', 'editar')
       or not (public.area_de_rol(public.rol_actual()) = v_p.area_destino or v_p.solicitante = auth.uid()) then
        raise exception 'No podés confirmar esta entrega.';
    end if;
    if v_p.estado <> 'entregado' then
        raise exception 'Este pedido no está esperando conformidad.';
    end if;
    if length(coalesce(p_nota, '')) > 300 then raise exception 'La nota es demasiado larga.'; end if;
    if jsonb_typeof(p_lineas) is distinct from 'array' then raise exception 'Faltan las líneas.'; end if;

    for v_l in select * from public.inv_pedido_lineas where pedido_id = p_pedido order by id loop
        select e into v_e from jsonb_array_elements(p_lineas) e
         where (e ->> 'linea_id')::bigint = v_l.id;
        if v_e is null then
            raise exception 'Falta confirmar uno de los ítems.';
        end if;

        v_ok := coalesce((v_e ->> 'recibido_ok')::boolean, false);
        v_rec := coalesce((v_e ->> 'cantidad_recibida')::numeric, v_l.cantidad_entregada);
        v_obs := nullif(trim(coalesce(v_e ->> 'observacion', '')), '');
        if v_rec < 0 or v_rec > v_l.cantidad_entregada + 1e-9 then
            raise exception 'La cantidad recibida no puede superar lo entregado.';
        end if;
        if v_obs is not null and length(v_obs) > 300 then
            raise exception 'Una observación es demasiado larga.';
        end if;
        if (not v_ok or abs(v_rec - v_l.cantidad_entregada) > 1e-9) and v_obs is null then
            raise exception 'Explicá con una observación qué pasó con cada ítem que no está conforme.';
        end if;

        if not v_ok or abs(v_rec - v_l.cantidad_entregada) > 1e-9 or v_obs is not null then
            v_conforme := false;
        end if;

        update public.inv_pedido_lineas
           set recibido_ok = v_ok, cantidad_recibida = v_rec, observacion = v_obs
         where id = v_l.id;

        -- Si el área tiene almacén propio, lo recibido entra a su stock.
        if v_p.almacen_destino is not null and v_rec > 0 then
            insert into public.inv_movimientos
                (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
            values (v_l.item_id, v_p.almacen_destino, 'entrada', v_rec, 'entrega', p_pedido,
                    'Recibido de Almacén');
        end if;
    end loop;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.inv_pedidos
       set estado = case when v_conforme then 'cerrado' else 'observado' end,
           confirmado_por = auth.uid(), confirmado_por_nombre = v_nombre,
           confirmado_en = now(), nota_conformidad = nullif(trim(coalesce(p_nota, '')), '')
     where id = p_pedido;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Almacén resuelve una entrega observada.
-- ---------------------------------------------------------------------
create or replace function public.inv_resolver_observacion(p_pedido bigint, p_resolucion text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_p public.inv_pedidos;
begin
    select * into v_p from public.inv_pedidos where id = p_pedido for update;
    if not found then raise exception 'El pedido no existe.'; end if;
    if not public.tiene_permiso('entregas', 'crear') or not public.puede_operar_almacen(v_p.almacen_origen) then
        raise exception 'No tenés permiso para resolver esta observación.';
    end if;
    if v_p.estado <> 'observado' then raise exception 'Este pedido no tiene observaciones abiertas.'; end if;
    if length(trim(coalesce(p_resolucion, ''))) < 3 or length(p_resolucion) > 300 then
        raise exception 'Escribí cómo se resolvió (3 a 300 caracteres).';
    end if;
    update public.inv_pedidos set estado = 'cerrado', resolucion = trim(p_resolucion) where id = p_pedido;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Anular un pedido que todavía no se entregó.
-- ---------------------------------------------------------------------
create or replace function public.inv_anular_pedido(p_pedido bigint, p_motivo text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_p public.inv_pedidos;
begin
    select * into v_p from public.inv_pedidos where id = p_pedido for update;
    if not found then raise exception 'El pedido no existe.'; end if;
    if not (v_p.solicitante = auth.uid()
            or (public.tiene_permiso('entregas', 'crear') and public.puede_operar_almacen(v_p.almacen_origen))) then
        raise exception 'No podés anular este pedido.';
    end if;
    if v_p.estado <> 'pendiente' then raise exception 'Solo se anulan pedidos pendientes.'; end if;
    if length(trim(coalesce(p_motivo, ''))) < 3 or length(p_motivo) > 300 then
        raise exception 'Escribí el motivo (3 a 300 caracteres).';
    end if;
    update public.inv_pedidos set estado = 'anulado', resolucion = trim(p_motivo) where id = p_pedido;
end;
$$;

-- Solo usuarios con sesión pueden ejecutarlas (las funciones validan el resto).
revoke all on function public.inv_crear_pedido(text, text, jsonb, boolean) from public;
revoke all on function public.inv_entregar_pedido(bigint, jsonb) from public;
revoke all on function public.inv_confirmar_entrega(bigint, jsonb, text) from public;
revoke all on function public.inv_resolver_observacion(bigint, text) from public;
revoke all on function public.inv_anular_pedido(bigint, text) from public;
grant execute on function public.inv_crear_pedido(text, text, jsonb, boolean) to authenticated;
grant execute on function public.inv_entregar_pedido(bigint, jsonb) to authenticated;
grant execute on function public.inv_confirmar_entrega(bigint, jsonb, text) to authenticated;
grant execute on function public.inv_resolver_observacion(bigint, text) to authenticated;
grant execute on function public.inv_anular_pedido(bigint, text) to authenticated;
