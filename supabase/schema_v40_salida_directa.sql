-- =====================================================================
-- SALVIETTI CONTROL — v40: salida directa de Almacén (mejora del Módulo 1).
-- Ejecutar DESPUÉS de schema_v39_devoluciones.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Pendiente descubierto con "SALIDA DE TERMOCONTRAIBLES" (sección 13):
-- Almacén también lleva un registro de salida directa (sin pedido formal
-- ni firma) de algunos insumos hacia un área — fecha, ítem, área, cantidad
-- en rollos y PESO REAL en kg. El peso varía rollo a rollo (no es una
-- conversión fija), así que hacen falta los dos datos, parecido a
-- "cantidad de factura vs. pesado" de Recepciones pero para una salida: acá
-- lo que descuenta el stock es el peso real, no la cantidad de rollos (que
-- queda solo como referencia).
--
-- No se limita a termocontraíbles: cualquier ítem de Almacén General se
-- puede sacar así (Almacén ya tiene el "Registrar movimiento" genérico de
-- v30 para eso); esto agrega el campo de rollos + peso real que ese
-- formulario no tiene, y dónde/quién lo recibió.

create table if not exists public.inv_salidas_directas (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    item_id bigint not null references public.inv_items(id),
    almacen_id text not null default 'general' references public.inv_almacenes(id),
    area_destino text not null check (area_destino in
        ('jarabes', 'soplado', 'llenadora', 'codificacion', 'calidad', 'soda_caustica', 'salidas')),
    cantidad_rollos numeric check (cantidad_rollos is null or cantidad_rollos > 0),
    peso_real numeric not null check (peso_real > 0),
    motivo text check (motivo is null or length(motivo) <= 300),
    movimiento_id bigint references public.inv_movimientos(id),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    creado_en timestamptz not null default now()
);
create index if not exists inv_salidas_directas_fecha on public.inv_salidas_directas (fecha desc);

alter table public.inv_salidas_directas enable row level security;
drop policy if exists "ver_inv_salidas_directas" on public.inv_salidas_directas;
create policy "ver_inv_salidas_directas" on public.inv_salidas_directas for select
    using (public.puede_operar_almacen(almacen_id));
grant select on public.inv_salidas_directas to authenticated;

-- ---------------------------------------------------------------------
-- Registrar una salida directa: descuenta el peso real por lote (FIFO,
-- igual que una entrega), no la cantidad de rollos.
-- ---------------------------------------------------------------------
create or replace function public.inv_registrar_salida_directa(
    p_item_id bigint,
    p_area_destino text,
    p_peso_real numeric,
    p_cantidad_rollos numeric default null,
    p_motivo text default null,
    p_almacen_id text default 'general'
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_id bigint;
    v_mov_id bigint;
    v_primer_mov_id bigint;
    v_nombre text;
    v_total numeric;
    v_falta numeric;
    v_toma numeric;
    v_sin_lote numeric;
    v_lote record;
begin
    if not public.puede_operar_almacen(p_almacen_id) then
        raise exception 'No operás ese almacén.';
    end if;
    if p_area_destino not in
        ('jarabes', 'soplado', 'llenadora', 'codificacion', 'calidad', 'soda_caustica', 'salidas') then
        raise exception 'Área de destino inválida.';
    end if;
    if p_peso_real is null or p_peso_real <= 0 then
        raise exception 'El peso real debe ser mayor a cero.';
    end if;
    if p_cantidad_rollos is not null and p_cantidad_rollos <= 0 then
        raise exception 'La cantidad de rollos debe ser mayor a cero.';
    end if;
    if length(coalesce(p_motivo, '')) > 300 then
        raise exception 'El motivo es demasiado largo.';
    end if;
    if not exists (select 1 from public.inv_items where id = p_item_id and activo) then
        raise exception 'El ítem no existe o está eliminado.';
    end if;

    select coalesce(sum(cantidad), 0) into v_total
      from public.inv_movimientos where item_id = p_item_id and almacen_id = p_almacen_id;
    if p_peso_real > v_total + 1e-9 then
        raise exception 'No hay suficiente stock: hay %, se quieren sacar %.', v_total, p_peso_real;
    end if;

    -- Se crea el registro de la salida directa ANTES de mover stock, para
    -- poder enlazar cada movimiento (puede ser más de uno: sin-lote + uno o
    -- varios lotes) directo en su propio insert. Antes se guardaba solo
    -- v_mov_id (se pisaba en cada vuelta del loop) y se enlazaba recién al
    -- final, así que una salida que tocaba más de un lote dejaba las
    -- filas anteriores con referencia_id null — invisibles para cualquier
    -- reporte que las busque por ese id.
    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.inv_salidas_directas
        (item_id, almacen_id, area_destino, cantidad_rollos, peso_real, motivo, responsable_nombre)
    values
        (p_item_id, p_almacen_id, p_area_destino, p_cantidad_rollos, p_peso_real,
         nullif(trim(coalesce(p_motivo, '')), ''), v_nombre)
    returning id into v_id;

    v_falta := p_peso_real;

    select greatest(coalesce(sum(cantidad), 0), 0) into v_sin_lote
      from public.inv_movimientos
     where item_id = p_item_id and almacen_id = p_almacen_id and lote_recepcion_id is null;
    if v_sin_lote > 0 then
        v_toma := least(v_falta, v_sin_lote);
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
        values (p_item_id, p_almacen_id, 'salida', -v_toma, 'salida_directa', v_id,
                'Salida directa a ' || p_area_destino)
        returning id into v_mov_id;
        v_primer_mov_id := coalesce(v_primer_mov_id, v_mov_id);
        v_falta := v_falta - v_toma;
    end if;

    for v_lote in
        select s.lote_recepcion_id, s.cantidad_disponible
          from public.inv_stock_lote s
         where s.item_id = p_item_id and s.almacen_id = p_almacen_id and s.cantidad_disponible > 0
         order by s.fecha_vencimiento nulls last, s.lote_recepcion_id
    loop
        exit when v_falta <= 1e-9;
        v_toma := least(v_falta, v_lote.cantidad_disponible);
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo, lote_recepcion_id)
        values (p_item_id, p_almacen_id, 'salida', -v_toma, 'salida_directa', v_id,
                'Salida directa a ' || p_area_destino, v_lote.lote_recepcion_id)
        returning id into v_mov_id;
        v_primer_mov_id := coalesce(v_primer_mov_id, v_mov_id);
        v_falta := v_falta - v_toma;
    end loop;

    -- Si aún falta, el stock era "sin lote" negativo compensado (mismo caso
    -- que ya contempla inv_registrar_movimiento en v30): se descuenta sin
    -- lote en vez de dejar la salida a medio registrar sin avisar.
    if v_falta > 1e-9 then
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
        values (p_item_id, p_almacen_id, 'salida', -v_falta, 'salida_directa', v_id,
                'Salida directa a ' || p_area_destino)
        returning id into v_mov_id;
        v_primer_mov_id := coalesce(v_primer_mov_id, v_mov_id);
    end if;

    update public.inv_salidas_directas set movimiento_id = v_primer_mov_id where id = v_id;

    return v_id;
end;
$$;

revoke all on function public.inv_registrar_salida_directa(bigint, text, numeric, numeric, text, text) from public;
grant execute on function public.inv_registrar_salida_directa(bigint, text, numeric, numeric, text, text) to authenticated;

create or replace view public.inv_salidas_directas_detalle with (security_invoker = true) as
    select s.id, s.fecha, s.item_id, i.codigo, i.detalle, i.unidad, s.almacen_id, s.area_destino,
           s.cantidad_rollos, s.peso_real, s.motivo, s.responsable_nombre, s.creado_en
      from public.inv_salidas_directas s
      join public.inv_items i on i.id = s.item_id;
grant select on public.inv_salidas_directas_detalle to authenticated;
