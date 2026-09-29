-- =====================================================================
-- SALVIETTI CONTROL — v28: ajusta Soplado (Módulo 5) al reporte real de
-- planta. Ejecutar DESPUÉS de schema_v25_soplado.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- El Módulo 5 se armó deduciendo el formulario; con el "REPORTE DE
-- PRODUCCIÓN DE SOPLADO" real aparecen diferencias que se corrigen acá:
--
--   * Se cuenta en BOTELLAS, no en cajas ("CANTIDAD DE BOTELLAS SOPLADAS").
--     `cajas_sopladas` y `botellas_sueltas` se sacan del formulario (nadie
--     las llena a mano); el equivalente en cajas se sigue mostrando en
--     `soplado_avance`, calculado solo cuando se conocen las unidades por
--     caja de la presentación.
--   * El papel distingue TRES mermas, no dos: preforma (antes de soplar),
--     soplado (al soplar) y etiquetado (al etiquetar, que en la planta se
--     hace en la misma línea, justo después). Se agrega merma_etiquetado y
--     se renombran las dos columnas existentes para que coincidan con el
--     papel: botellas_quebradas -> merma_soplado, preformas_desechadas ->
--     merma_preforma.
--   * Se agrega cuántas botellas quedaron ETIQUETADAS (además de sopladas).
--   * Se agrega el proveedor y el lote de la preforma que se cargó (para
--     saber de dónde vino si después hay un reclamo).
--   * Se agrega el tiempo de parada de la máquina y su motivo.
--
-- Pendiente, fuera de este módulo: el papel "PEDIDO INTERNO DE ETIQUETAS"
-- muestra que el área también pide etiquetas a Almacén con devolución y
-- desperdicio. El pedido en sí ya se puede hacer con inv_crear_pedido
-- (Módulo 3): lo único que falta ahí es el concepto de "devolución" (lo
-- que sobra se le regresa a Almacén), que ese módulo no tiene todavía.

-- La vista de v25 depende de cajas_sopladas y botellas_sueltas: hay que
-- borrarla ANTES de sacar esas columnas (se recrea al final del archivo).
drop view if exists public.soplado_avance;

-- ---------------------------------------------------------------------
-- Renombra las columnas que ya existían, para que el nombre coincida con
-- el papel (solo si no se renombraron ya, para poder correr esto de nuevo).
-- ---------------------------------------------------------------------
do $$
begin
    if exists (
        select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'soplado_corridas'
           and column_name = 'botellas_quebradas'
    ) then
        alter table public.soplado_corridas rename column botellas_quebradas to merma_soplado;
    end if;
    if exists (
        select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'soplado_corridas'
           and column_name = 'preformas_desechadas'
    ) then
        alter table public.soplado_corridas rename column preformas_desechadas to merma_preforma;
    end if;
end $$;

alter table public.soplado_corridas
    add column if not exists proveedor_id bigint references public.inv_proveedores(id),
    add column if not exists lote_preforma text check (lote_preforma is null or length(lote_preforma) <= 40),
    add column if not exists botellas_sopladas numeric check (botellas_sopladas is null or botellas_sopladas >= 0),
    add column if not exists botellas_etiquetadas numeric check (botellas_etiquetadas is null or botellas_etiquetadas >= 0),
    add column if not exists merma_etiquetado int not null default 0 check (merma_etiquetado >= 0),
    add column if not exists tiempo_parada_minutos int check (tiempo_parada_minutos is null or tiempo_parada_minutos >= 0),
    add column if not exists motivo_parada text check (motivo_parada is null or length(motivo_parada) <= 300),
    drop column if exists cajas_sopladas,
    drop column if exists botellas_sueltas;

-- ---------------------------------------------------------------------
-- 1. Iniciar: ahora también registra proveedor y lote de la preforma.
-- ---------------------------------------------------------------------
drop function if exists public.soplado_iniciar_corrida(bigint, bigint, bigint);
create or replace function public.soplado_iniciar_corrida(
    p_sabor_id bigint, p_presentacion_id bigint, p_item_preforma_id bigint default null,
    p_proveedor_id bigint default null, p_lote_preforma text default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_id bigint;
    v_nombre text;
begin
    if not public.tiene_permiso('soplado', 'crear') then
        raise exception 'No tenés permiso para registrar producción de Soplado.';
    end if;
    if not exists (
        select 1 from public.presentaciones where id = p_presentacion_id and material = 'pet'
    ) then
        raise exception 'Soplado solo trabaja presentaciones de PET.';
    end if;
    if not exists (
        select 1 from public.sabor_presentacion
         where sabor_id = p_sabor_id and presentacion_id = p_presentacion_id
    ) then
        raise exception 'Ese sabor no se fabrica en esa presentación.';
    end if;
    if p_item_preforma_id is not null
       and not exists (select 1 from public.inv_items where id = p_item_preforma_id) then
        raise exception 'La preforma indicada no existe.';
    end if;
    if p_lote_preforma is not null and length(p_lote_preforma) > 40 then
        raise exception 'El lote de la preforma es demasiado largo.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.soplado_corridas
        (sabor_id, presentacion_id, item_preforma_id, proveedor_id, lote_preforma, responsable_nombre)
    values
        (p_sabor_id, p_presentacion_id, p_item_preforma_id, p_proveedor_id,
         nullif(trim(coalesce(p_lote_preforma, '')), ''), v_nombre)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Finalizar: botellas sopladas y etiquetadas, las tres mermas, y la
--    parada de máquina si la hubo.
-- ---------------------------------------------------------------------
drop function if exists public.soplado_finalizar_corrida(bigint, numeric, int, numeric, int, int, text, text);
create or replace function public.soplado_finalizar_corrida(
    p_id bigint,
    p_botellas_sopladas numeric,
    p_preformas_usadas numeric,
    p_merma_soplado int default 0,
    p_merma_preforma int default 0,
    p_botellas_etiquetadas numeric default null,
    p_merma_etiquetado int default 0,
    p_tiempo_parada_minutos int default null,
    p_motivo_parada text default null,
    p_motivo_merma text default null,
    p_observaciones text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_corrida public.soplado_corridas;
begin
    if not public.tiene_permiso('soplado', 'editar') then
        raise exception 'No tenés permiso para finalizar producción de Soplado.';
    end if;
    select * into v_corrida from public.soplado_corridas where id = p_id for update;
    if not found then raise exception 'La corrida no existe.'; end if;
    if v_corrida.estado <> 'en_curso' then raise exception 'Esa corrida ya se cerró.'; end if;

    if p_botellas_sopladas is null or p_botellas_sopladas < 0 then
        raise exception 'La cantidad de botellas sopladas no puede ser negativa.';
    end if;
    if coalesce(p_preformas_usadas, 0) < 0 then
        raise exception 'Las preformas usadas no pueden ser negativas.';
    end if;
    if coalesce(p_merma_soplado, 0) < 0 or coalesce(p_merma_preforma, 0) < 0
       or coalesce(p_merma_etiquetado, 0) < 0 then
        raise exception 'La merma no puede ser negativa.';
    end if;
    if p_botellas_etiquetadas is not null and p_botellas_etiquetadas < 0 then
        raise exception 'Las botellas etiquetadas no pueden ser negativas.';
    end if;
    if p_preformas_usadas is not null and p_merma_preforma > p_preformas_usadas then
        raise exception 'No se pueden desechar más preformas de las que se usaron.';
    end if;
    if p_merma_soplado > p_botellas_sopladas then
        raise exception 'La merma de soplado no puede ser mayor a lo soplado.';
    end if;
    if (coalesce(p_merma_soplado, 0) > 0 or coalesce(p_merma_preforma, 0) > 0
        or coalesce(p_merma_etiquetado, 0) > 0)
       and length(trim(coalesce(p_motivo_merma, ''))) = 0 then
        raise exception 'Indicá el motivo de la merma.';
    end if;
    if p_tiempo_parada_minutos is not null and p_tiempo_parada_minutos > 0
       and length(trim(coalesce(p_motivo_parada, ''))) = 0 then
        raise exception 'Indicá el motivo de la parada.';
    end if;
    if length(coalesce(p_motivo_merma, '')) > 300 or length(coalesce(p_observaciones, '')) > 300
       or length(coalesce(p_motivo_parada, '')) > 300 then
        raise exception 'Alguno de los textos es demasiado largo.';
    end if;

    update public.soplado_corridas
       set estado = 'finalizada', hora_fin = now(),
           botellas_sopladas = p_botellas_sopladas,
           preformas_usadas = p_preformas_usadas,
           merma_soplado = coalesce(p_merma_soplado, 0),
           merma_preforma = coalesce(p_merma_preforma, 0),
           botellas_etiquetadas = p_botellas_etiquetadas,
           merma_etiquetado = coalesce(p_merma_etiquetado, 0),
           tiempo_parada_minutos = p_tiempo_parada_minutos,
           motivo_parada = nullif(trim(coalesce(p_motivo_parada, '')), ''),
           motivo_merma = nullif(trim(coalesce(p_motivo_merma, '')), ''),
           observaciones = nullif(trim(coalesce(p_observaciones, '')), '')
     where id = p_id;

    if v_corrida.item_preforma_id is not null and coalesce(p_preformas_usadas, 0) > 0 then
        if p_preformas_usadas > (
            select coalesce(sum(cantidad), 0) from public.inv_movimientos
             where item_id = v_corrida.item_preforma_id and almacen_id = 'soplado'
        ) then
            raise exception 'No hay suficiente stock de esa preforma en el almacén de Soplado.';
        end if;
        insert into public.inv_movimientos
            (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
        values (v_corrida.item_preforma_id, 'soplado', 'salida', -p_preformas_usadas,
                'soplado_corrida', p_id, 'Consumo de soplado');
    end if;
end;
$$;

revoke all on function public.soplado_iniciar_corrida(bigint, bigint, bigint, bigint, text) from public;
revoke all on function public.soplado_finalizar_corrida(bigint, numeric, numeric, int, int, numeric, int, int, text, text, text) from public;
grant execute on function public.soplado_iniciar_corrida(bigint, bigint, bigint, bigint, text) to authenticated;
grant execute on function public.soplado_finalizar_corrida(bigint, numeric, numeric, int, int, numeric, int, int, text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Avance: ahora en botellas, con el equivalente en cajas cuando se conoce
-- la presentación (columna `cajas_sopladas` se mantiene con ese nombre
-- para no tener que tocar el módulo de Jarabes, que ya lee de acá).
-- ---------------------------------------------------------------------
drop view if exists public.soplado_avance;
create view public.soplado_avance with (security_invoker = true) as
    select c.sabor_id, s.nombre as sabor, c.presentacion_id, p.nombre as presentacion,
           count(*) filter (where c.estado = 'finalizada') as corridas,
           coalesce(sum(c.botellas_sopladas - c.merma_soplado - c.merma_etiquetado)
                    filter (where c.estado = 'finalizada'), 0) as botellas_buenas,
           case when p.unidades_por_caja > 0 then
               coalesce(sum(c.botellas_sopladas - c.merma_soplado - c.merma_etiquetado)
                        filter (where c.estado = 'finalizada'), 0) / p.unidades_por_caja
           end as cajas_sopladas,
           max(c.hora_fin) filter (where c.estado = 'finalizada') as ultima_corrida
      from public.soplado_corridas c
      join public.sabores s on s.id = c.sabor_id
      join public.presentaciones p on p.id = c.presentacion_id
     where c.fecha >= current_date - interval '14 days'
     group by c.sabor_id, s.nombre, c.presentacion_id, p.nombre, p.unidades_por_caja;
