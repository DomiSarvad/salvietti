-- =====================================================================
-- SALVIETTI CONTROL — v36: Soda cáustica (Módulo 10).
-- Ejecutar DESPUÉS de schema_v35_mermas.sql, en el SQL Editor de Supabase.
-- (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- En vez de armar un sistema de stock aparte, Soda Cáustica pasa a ser un
-- almacén más (como Jarabes y Soplado): así reutiliza TODO lo que ya existe
-- de los Módulos 1 y 3, sin código nuevo para eso.
--
--   * El ítem "Soda cáustica" sigue catalogado en Almacén General ›
--     Saneamiento (sección 5 del md: no es una categoría propia). Un ítem
--     catalogado en un almacén puede tener movimientos en otro (arreglo de
--     v25): por eso no hace falta duplicarlo.
--   * Cuando Almacén le entrega un pedido a Soda Cáustica (Módulo 3, ya
--     construido), con este cambio entra solo a su almacén — antes se
--     perdía, porque `almacen_de_area` no conocía a 'soda_caustica'.
--   * "Solicitud de insumo a Almacén" ya funciona (Módulo 3: 'soda_caustica'
--     ya es un área destino válida en `inv_pedidos`).
--   * Lo nuevo de este archivo es el "Registro de entrega": a quién se le
--     entregó, cuánto, para qué, y el saldo que queda — con su constancia
--     en PDF (obligatoria: es un producto peligroso).
--
-- Pendiente, sin resolver acá: la "merma propia" de Soda Cáustica que
-- menciona la sección 14.5 — la tabla de causas por área (sección 14.4) no
-- dice qué mermas le corresponden a Soda Cáustica. Se agrega cuando se
-- confirme, como una nueva área en `mermas_registros` (v35).

-- ---------------------------------------------------------------------
-- 1. Almacén propio y el permiso para operarlo.
-- ---------------------------------------------------------------------
insert into public.inv_almacenes (id, nombre) values
    ('soda_caustica', 'Almacén de Soda Cáustica')
on conflict (id) do nothing;

insert into public.app_modulos (id, nombre, estado) values
    ('inventario_soda_caustica', 'Inventario de Soda Cáustica', 'activo')
on conflict (id) do nothing;

insert into public.permisos_rol (rol, modulo, accion)
select v.rol, 'inventario_soda_caustica', v.accion
  from (values
      ('soda_caustica', 'ver'), ('soda_caustica', 'crear'), ('soda_caustica', 'editar'),
      ('gerente', 'ver'), ('jefe_produccion', 'ver')
  ) as v(rol, accion)
on conflict do nothing;

-- Ahora Soda Cáustica también recibe stock propio al confirmarse la
-- entrega de un pedido (Módulo 3), igual que Jarabes y Soplado.
create or replace function public.almacen_de_area(p_area text) returns text
language sql immutable as $$
    select case p_area
        when 'jarabes' then 'jarabes'
        when 'soplado' then 'soplado'
        when 'soda_caustica' then 'soda_caustica'
        else null
    end;
$$;

-- ---------------------------------------------------------------------
-- 2. Registro de entrega a una persona (lo nuevo de este módulo).
-- ---------------------------------------------------------------------
create table if not exists public.soda_entregas (
    id bigint generated always as identity primary key,
    fecha_hora timestamptz not null default now(),
    item_id bigint not null references public.inv_items(id),
    cantidad numeric not null check (cantidad > 0),
    entregado_a text not null check (length(entregado_a) between 2 and 120),
    area_recibe text check (area_recibe is null or length(area_recibe) <= 80),
    motivo text check (motivo is null or length(motivo) <= 300),
    saldo_restante numeric,
    movimiento_id bigint references public.inv_movimientos(id),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    creado_en timestamptz not null default now()
);
create index if not exists soda_entregas_fecha on public.soda_entregas (fecha_hora desc);

alter table public.soda_entregas enable row level security;
drop policy if exists "ver_soda_entregas" on public.soda_entregas;
create policy "ver_soda_entregas" on public.soda_entregas for select
    using (public.tiene_permiso('soda_caustica', 'ver'));
grant select on public.soda_entregas to authenticated;

-- ---------------------------------------------------------------------
-- 3. Registrar una entrega: descuenta del almacén de Soda Cáustica (FIFO
--    por lote, igual que un pedido) y guarda el saldo que quedó.
-- ---------------------------------------------------------------------
create or replace function public.soda_registrar_entrega(
    p_item_id bigint,
    p_cantidad numeric,
    p_entregado_a text,
    p_area_recibe text default null,
    p_motivo text default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_id bigint;
    v_nombre text;
    v_total numeric;
    v_falta numeric;
    v_toma numeric;
    v_sin_lote numeric;
    v_lote record;
    v_mov_id bigint;
    v_saldo numeric;
begin
    if not public.tiene_permiso('soda_caustica', 'crear') then
        raise exception 'No tenés permiso para registrar entregas de Soda Cáustica.';
    end if;
    if p_cantidad is null or p_cantidad <= 0 then
        raise exception 'La cantidad debe ser mayor a cero.';
    end if;
    if length(trim(coalesce(p_entregado_a, ''))) < 2 then
        raise exception 'Indicá a quién se le entrega.';
    end if;
    if length(coalesce(p_area_recibe, '')) > 80 or length(coalesce(p_motivo, '')) > 300 then
        raise exception 'Alguno de los textos es demasiado largo.';
    end if;
    if not exists (select 1 from public.inv_items where id = p_item_id and activo) then
        raise exception 'El ítem no existe o está eliminado.';
    end if;

    -- Bloquea el ítem: dos entregas simultáneas del mismo producto peligroso
    -- no deben poder leer el mismo saldo y descontar ambas por separado.
    perform 1 from public.inv_items where id = p_item_id for update;

    select coalesce(sum(cantidad), 0) into v_total
      from public.inv_movimientos where item_id = p_item_id and almacen_id = 'soda_caustica';
    if p_cantidad > v_total + 1e-9 then
        raise exception 'No hay suficiente stock: hay %, se quieren entregar %.', v_total, p_cantidad;
    end if;

    v_falta := p_cantidad;

    select greatest(coalesce(sum(cantidad), 0), 0) into v_sin_lote
      from public.inv_movimientos
     where item_id = p_item_id and almacen_id = 'soda_caustica' and lote_recepcion_id is null;
    if v_sin_lote > 0 then
        v_toma := least(v_falta, v_sin_lote);
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (p_item_id, 'soda_caustica', 'salida', -v_toma, 'soda_entrega',
                'Entrega a ' || trim(p_entregado_a))
        returning id into v_mov_id;
        v_falta := v_falta - v_toma;
    end if;

    for v_lote in
        select s.lote_recepcion_id, s.cantidad_disponible
          from public.inv_stock_lote s
         where s.item_id = p_item_id and s.almacen_id = 'soda_caustica' and s.cantidad_disponible > 0
         order by s.fecha_vencimiento nulls last, s.lote_recepcion_id
    loop
        exit when v_falta <= 1e-9;
        v_toma := least(v_falta, v_lote.cantidad_disponible);
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo, lote_recepcion_id)
        values (p_item_id, 'soda_caustica', 'salida', -v_toma, 'soda_entrega',
                'Entrega a ' || trim(p_entregado_a), v_lote.lote_recepcion_id)
        returning id into v_mov_id;
        v_falta := v_falta - v_toma;
    end loop;

    select coalesce(sum(cantidad), 0) into v_saldo
      from public.inv_movimientos where item_id = p_item_id and almacen_id = 'soda_caustica';

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.soda_entregas
        (item_id, cantidad, entregado_a, area_recibe, motivo, saldo_restante, movimiento_id, responsable_nombre)
    values
        (p_item_id, p_cantidad, trim(p_entregado_a),
         nullif(trim(coalesce(p_area_recibe, '')), ''), nullif(trim(coalesce(p_motivo, '')), ''),
         v_saldo, v_mov_id, v_nombre)
    returning id into v_id;

    -- Referencia cruzada: el movimiento de salida apunta a esta entrega.
    update public.inv_movimientos set referencia_id = v_id where id = v_mov_id;

    return v_id;
end;
$$;

revoke all on function public.soda_registrar_entrega(bigint, numeric, text, text, text) from public;
grant execute on function public.soda_registrar_entrega(bigint, numeric, text, text, text) to authenticated;

-- Entregas con el detalle del ítem, para listarlas y armar la constancia.
create or replace view public.soda_entregas_detalle with (security_invoker = true) as
    select e.id, e.fecha_hora, e.item_id, i.codigo, i.detalle, i.unidad,
           e.cantidad, e.entregado_a, e.area_recibe, e.motivo, e.saldo_restante,
           e.responsable_nombre, e.creado_en
      from public.soda_entregas e
      join public.inv_items i on i.id = e.item_id;
grant select on public.soda_entregas_detalle to authenticated;
