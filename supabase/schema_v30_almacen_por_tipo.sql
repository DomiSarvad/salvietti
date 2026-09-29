-- =====================================================================
-- SALVIETTI CONTROL — v30: el Almacén General ordenado por TIPO de
-- artículo, y movimientos manuales de inventario validados en el servidor.
-- Ejecutar DESPUÉS de v18 a v29, en el SQL Editor de Supabase. (Se puede
-- volver a ejecutar sin problema.)
-- =====================================================================
--
-- 1. Categorías. Antes el árbol arrancaba por material (PET › Tapas,
--    Vidrio › Tapas). Un almacenero busca primero POR TIPO: entra a "Tapas"
--    y ahí elige PET o Vidrio. El árbol queda así:
--
--      Tapas        › PET › Tapa Short › (colores)
--                   › Vidrio › Tapa Long › (Verde, Amarillo)
--                            › Tapa corona › (Con sello, Sin sello)
--      Etiquetas    › PET › Plástico, Sticker › Isotónico
--                   › Vidrio › Papel (cerveceras)
--      Preformas    › 2.5 L, 2 L, 600 ml, 330 ml
--      Termocontraíbles, Envases, Cajas
--      Material de escritorio, Limpieza, Saneamiento, Seguridad industrial,
--      Mantenimiento (Plomería, Electricidad, Mecánico, Civil),
--      Laboratorio, Codificación (solvente y tinta)
--
--    No se pierde nada: las categorías y los ítems EXISTENTES se mueven o
--    se fusionan con las nuevas (los ítems conservan su historial).
--
-- 2. Movimientos manuales (ingreso o salida sin factura: saldo inicial,
--    consumo, rotura) y reversión. Igual que en Entregas, no hay
--    escritura directa: pasa por funciones que validan permiso, stock y
--    motivo, y sacan primero lo que vence antes (FIFO por lote).

-- ---------------------------------------------------------------------
-- Auxiliares (se dejan instaladas: las usa también el seed de v18).
-- ---------------------------------------------------------------------
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

-- Mueve TODO lo que cuelga de p_origen (subcategorías e ítems) a p_destino y
-- borra p_origen si queda vacía. Si en el destino ya hay una subcategoría con
-- el mismo nombre, las fusiona (recursivo).
create or replace function public._inv_fusionar(p_origen bigint, p_destino bigint)
returns void language plpgsql as $$
declare h record; ex bigint;
begin
    if p_origen is null or p_destino is null or p_origen = p_destino then return; end if;
    for h in select id, nombre from public.inv_categorias where padre_id = p_origen loop
        select id into ex from public.inv_categorias
         where padre_id = p_destino and nombre = h.nombre;
        if ex is null then
            update public.inv_categorias set padre_id = p_destino where id = h.id;
        else
            perform public._inv_fusionar(h.id, ex);
        end if;
    end loop;
    update public.inv_items i set categoria_id = p_destino
     where i.categoria_id = p_origen
       and not exists (select 1 from public.inv_items j
                        where j.categoria_id = p_destino and j.detalle = i.detalle);
    delete from public.inv_categorias c
     where c.id = p_origen
       and not exists (select 1 from public.inv_categorias hijo where hijo.padre_id = c.id)
       and not exists (select 1 from public.inv_items i where i.categoria_id = c.id);
end;
$$;

-- ---------------------------------------------------------------------
-- 1. Reordenar el Almacén General por tipo.
-- ---------------------------------------------------------------------
do $$
declare
    g text := 'general';
    pet bigint; vid bigint;
    tapas bigint; tapas_pet bigint; tapas_vid bigint;
    etiq bigint; etiq_pet bigint; etiq_vid bigint;
    pre bigint; s text; nuevo bigint; viejo bigint;
begin
    select id into pet from public.inv_categorias
     where nombre = 'PET' and padre_id is null and almacen_id = g;
    select id into vid from public.inv_categorias
     where nombre = 'Vidrio' and padre_id is null and almacen_id = g;

    -- Tapas › PET / Vidrio
    tapas := public._inv_cat('Tapas', null, g);
    tapas_pet := public._inv_cat('PET', tapas, g);
    tapas_vid := public._inv_cat('Vidrio', tapas, g);
    perform public._inv_fusionar(
        (select id from public.inv_categorias where nombre = 'Tapas' and padre_id = pet), tapas_pet);
    perform public._inv_fusionar(
        (select id from public.inv_categorias where nombre = 'Tapas' and padre_id = vid), tapas_vid);

    -- Etiquetas › PET (Plástico, Sticker) / Vidrio (Papel)
    etiq := public._inv_cat('Etiquetas', null, g);
    etiq_pet := public._inv_cat('PET', etiq, g);
    etiq_vid := public._inv_cat('Vidrio', etiq, g);
    perform public._inv_fusionar(
        (select id from public.inv_categorias where nombre = 'Etiquetas' and padre_id = pet), etiq_pet);
    perform public._inv_fusionar(
        (select id from public.inv_categorias
          where nombre like 'Etiquetas de papel%' and padre_id = vid),
        public._inv_cat('Papel (cerveceras)', etiq_vid, g));

    -- Preformas › tamaños
    pre := public._inv_cat('Preformas', null, g);
    foreach s in array array['2.5 L', '2 L', '600 ml', '330 ml'] loop
        nuevo := public._inv_cat(s, pre, g);
        select id into viejo from public.inv_categorias
         where nombre = 'Preformas ' || s and padre_id = pet;
        perform public._inv_fusionar(viejo, nuevo);
    end loop;

    -- Termocontraíbles, Envases y Cajas pasan a ser categorías de primer nivel.
    perform public._inv_fusionar(
        (select id from public.inv_categorias where nombre = 'Termocontraíbles' and padre_id = pet),
        public._inv_cat('Termocontraíbles', null, g));
    perform public._inv_fusionar(
        (select id from public.inv_categorias where nombre = 'Envases' and padre_id = vid),
        public._inv_cat('Envases', null, g));
    perform public._inv_fusionar(
        (select id from public.inv_categorias where nombre = 'Cajas' and padre_id = vid),
        public._inv_cat('Cajas', null, g));

    -- Las raíces viejas PET y Vidrio se borran si quedaron vacías.
    delete from public.inv_categorias c
     where c.id in (pet, vid)
       and not exists (select 1 from public.inv_categorias h where h.padre_id = c.id)
       and not exists (select 1 from public.inv_items i where i.categoria_id = c.id);
end $$;

-- ---------------------------------------------------------------------
-- 2. Movimientos: vista con el nombre de quien lo hizo y su lote.
-- ---------------------------------------------------------------------
drop view if exists public.inv_movimientos_detalle;
create view public.inv_movimientos_detalle with (security_invoker = true) as
    select m.id, m.fecha, m.item_id, m.almacen_id, m.tipo, m.cantidad,
           m.referencia_tipo, m.referencia_id, m.motivo, m.usuario_id,
           u.nombre_completo as usuario_nombre,
           r.n_lote, r.fecha_vencimiento,
           exists (select 1 from public.inv_movimientos x
                    where x.referencia_tipo = 'reversion' and x.referencia_id = m.id) as revertido
      from public.inv_movimientos m
      left join public.usuarios u on u.id = m.usuario_id
      left join public.inv_recepciones r on r.id = m.lote_recepcion_id;

-- ---------------------------------------------------------------------
-- 3. Registrar un movimiento manual.
--    p_tipo: 'entrada' (suma) o 'salida' (resta). Las salidas descuentan
--    primero el stock sin lote y después los lotes que vencen antes.
-- ---------------------------------------------------------------------
create or replace function public.inv_registrar_movimiento(
    p_item bigint,
    p_almacen text,
    p_tipo text,
    p_cantidad numeric,
    p_motivo text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_motivo text := trim(coalesce(p_motivo, ''));
    v_total numeric;
    v_falta numeric;
    v_toma numeric;
    v_sin_lote numeric;
    v_lote record;
    v_nombre text;
begin
    if not public.puede_operar_almacen(p_almacen) then
        raise exception 'No tenés permiso para mover stock en este almacén.';
    end if;
    if p_tipo not in ('entrada', 'salida') then
        raise exception 'El tipo de movimiento debe ser entrada o salida.';
    end if;
    if p_cantidad is null or p_cantidad <= 0 then
        raise exception 'La cantidad debe ser mayor a cero.';
    end if;
    if length(v_motivo) < 3 or length(v_motivo) > 300 then
        raise exception 'Escribí el motivo (3 a 300 caracteres).';
    end if;
    if not exists (select 1 from public.inv_almacenes where id = p_almacen) then
        raise exception 'El almacén no existe.';
    end if;
    select detalle into v_nombre from public.inv_items where id = p_item and activo;
    if not found then
        raise exception 'El ítem no existe o está eliminado.';
    end if;

    if p_tipo = 'entrada' then
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (p_item, p_almacen, 'entrada', p_cantidad, 'manual', v_motivo);
        return;
    end if;

    select coalesce(sum(cantidad), 0) into v_total
      from public.inv_movimientos where item_id = p_item and almacen_id = p_almacen;
    if p_cantidad > v_total + 1e-9 then
        raise exception 'Stock insuficiente de "%": hay %, se sacan %.', v_nombre, v_total, p_cantidad;
    end if;

    v_falta := p_cantidad;

    select greatest(coalesce(sum(cantidad), 0), 0) into v_sin_lote
      from public.inv_movimientos
     where item_id = p_item and almacen_id = p_almacen and lote_recepcion_id is null;
    if v_sin_lote > 0 then
        v_toma := least(v_falta, v_sin_lote);
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (p_item, p_almacen, 'salida', -v_toma, 'manual', v_motivo);
        v_falta := v_falta - v_toma;
    end if;

    for v_lote in
        select s.lote_recepcion_id, s.cantidad_disponible
          from public.inv_stock_lote s
         where s.item_id = p_item and s.almacen_id = p_almacen and s.cantidad_disponible > 0
         order by s.fecha_vencimiento nulls last, s.lote_recepcion_id
    loop
        exit when v_falta <= 1e-9;
        v_toma := least(v_falta, v_lote.cantidad_disponible);
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo, lote_recepcion_id)
        values (p_item, p_almacen, 'salida', -v_toma, 'manual', v_motivo, v_lote.lote_recepcion_id);
        v_falta := v_falta - v_toma;
    end loop;

    -- Si aún falta, el stock era "sin lote" negativo compensado: se descuenta sin lote.
    if v_falta > 1e-9 then
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (p_item, p_almacen, 'salida', -v_falta, 'manual', v_motivo);
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Revertir un movimiento manual (contra-asiento: el original no se borra).
-- ---------------------------------------------------------------------
create or replace function public.inv_revertir_movimiento(p_id bigint, p_motivo text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_m public.inv_movimientos;
    v_motivo text := trim(coalesce(p_motivo, ''));
    v_total numeric;
begin
    select * into v_m from public.inv_movimientos where id = p_id for update;
    if not found then raise exception 'El movimiento no existe.'; end if;
    if not public.puede_operar_almacen(v_m.almacen_id) then
        raise exception 'No tenés permiso para revertir movimientos de este almacén.';
    end if;
    if v_m.referencia_tipo is distinct from 'manual' then
        raise exception 'Solo se revierten movimientos manuales. Los de recepción, entrega o conteo se corrigen desde su propio módulo.';
    end if;
    if exists (select 1 from public.inv_movimientos
                where referencia_tipo = 'reversion' and referencia_id = p_id) then
        raise exception 'Ese movimiento ya fue revertido.';
    end if;
    if length(v_motivo) < 3 or length(v_motivo) > 300 then
        raise exception 'Escribí el motivo (3 a 300 caracteres).';
    end if;

    if v_m.cantidad > 0 then
        select coalesce(sum(cantidad), 0) into v_total
          from public.inv_movimientos where item_id = v_m.item_id and almacen_id = v_m.almacen_id;
        if v_m.cantidad > v_total + 1e-9 then
            raise exception 'No se puede revertir: ese stock ya se usó (hay %, se restan %).', v_total, v_m.cantidad;
        end if;
    end if;

    insert into public.inv_movimientos
        (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo, lote_recepcion_id)
    values (v_m.item_id, v_m.almacen_id,
            case when v_m.cantidad > 0 then 'salida' else 'entrada' end,
            -v_m.cantidad, 'reversion', p_id, 'Reversión: ' || v_motivo, v_m.lote_recepcion_id);
end;
$$;

revoke all on function public.inv_registrar_movimiento(bigint, text, text, numeric, text) from public;
revoke all on function public.inv_revertir_movimiento(bigint, text) from public;
grant execute on function public.inv_registrar_movimiento(bigint, text, text, numeric, text) to authenticated;
grant execute on function public.inv_revertir_movimiento(bigint, text) to authenticated;
grant select on public.inv_movimientos_detalle to authenticated;
