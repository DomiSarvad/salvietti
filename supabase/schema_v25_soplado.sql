-- =====================================================================
-- SALVIETTI CONTROL — v25: Soplado (Módulo 5) + arreglo de inv_existencia.
-- Ejecutar DESPUÉS de schema_v21_entregas.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Lo que ya cubren módulos anteriores y NO se repite acá:
--   * La segunda recepción de Soplado (confirmar lo que le entrega Almacén)
--     ya funciona con inv_pedidos/inv_confirmar_entrega (Módulo 3): al
--     confirmar, lo recibido entra al almacén 'soplado'.
--   * Pedir más botellas/insumos a Almacén ya funciona con inv_crear_pedido
--     y con solicitudes_gerencia (Módulos 3 y 4).
--
-- Lo nuevo de este módulo: el registro de producción de Soplado (corridas:
-- inicio/fin, cajas sopladas, consumo de preforma, merma) y una vista de
-- avance para que Jarabes y Producción vean cuánto sopló hoy.
--
-- Pendiente (no depende de este módulo, así que no se resuelve acá):
--   * El "plan de soplado a 2 semanas" con alerta de paletas restantes
--     necesita el stock de producto TERMINADO, que se registra recién en
--     el Módulo 8 (Registro de Salidas).
--   * "Cajas sopladas menos entregadas a Llenadora" también depende del
--     Módulo 8; por ahora `soplado_avance` muestra el total sopladoy sin
--     descontar lo ya entregado a Llenadora.

-- ---------------------------------------------------------------------
-- Arreglo: inv_existencia solo mostraba el stock de un ítem en SU PROPIO
-- almacén (el de su categoría). Soplado recibe preformas/tapas/etc. que
-- Almacén General catalogó, así que ese stock quedaba invisible. Ahora
-- también se muestra en cualquier almacén donde haya habido movimientos.
-- (Mismas columnas que la vista original: un CREATE OR REPLACE VIEW no
-- puede reordenarlas ni quitarlas, así que se repite toda la vista.)
-- ---------------------------------------------------------------------
drop view if exists public.inv_existencia;
create view public.inv_existencia with (security_invoker = true) as
    with consumo as (
        select item_id, almacen_id, (-sum(cantidad)) / 30.0 as diario
          from public.inv_movimientos
         where tipo = 'salida' and fecha >= now() - interval '30 days'
         group by item_id, almacen_id
    ),
    almacenes_relevantes as (
        -- El almacén "dueño" del ítem, siempre (aunque nunca tuvo movimientos).
        select i.id as item_id, c.almacen_id
          from public.inv_items i
          join public.inv_categorias c on c.id = i.categoria_id
        union
        -- Cualquier otro almacén donde el ítem tuvo movimientos (recepciones,
        -- entregas recibidas, conteos).
        select m.item_id, m.almacen_id from public.inv_movimientos m
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
-- Corridas de soplado.
-- ---------------------------------------------------------------------
create table if not exists public.soplado_corridas (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    sabor_id bigint not null references public.sabores(id),
    presentacion_id bigint not null references public.presentaciones(id),
    item_preforma_id bigint references public.inv_items(id),
    estado text not null default 'en_curso' check (estado in ('en_curso', 'finalizada', 'anulada')),
    hora_inicio timestamptz not null default now(),
    hora_fin timestamptz,
    cajas_sopladas numeric check (cajas_sopladas is null or cajas_sopladas >= 0),
    botellas_sueltas int check (botellas_sueltas is null or botellas_sueltas >= 0),
    preformas_usadas numeric check (preformas_usadas is null or preformas_usadas >= 0),
    botellas_quebradas int not null default 0 check (botellas_quebradas >= 0),
    preformas_desechadas int not null default 0 check (preformas_desechadas >= 0),
    motivo_merma text check (motivo_merma is null or length(motivo_merma) <= 300),
    observaciones text check (observaciones is null or length(observaciones) <= 300),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    creado_en timestamptz not null default now(),
    constraint soplado_corridas_preformas_coherentes
        check (preformas_desechadas = 0 or preformas_usadas is null or preformas_desechadas <= preformas_usadas)
);
create index if not exists soplado_corridas_estado on public.soplado_corridas (estado, fecha desc);

alter table public.soplado_corridas enable row level security;
drop policy if exists "ver_soplado_corridas" on public.soplado_corridas;
create policy "ver_soplado_corridas" on public.soplado_corridas for select
    using (public.tiene_permiso('soplado', 'ver'));

-- ---------------------------------------------------------------------
-- 1. Iniciar una corrida: hora de inicio automática.
-- ---------------------------------------------------------------------
create or replace function public.soplado_iniciar_corrida(
    p_sabor_id bigint, p_presentacion_id bigint, p_item_preforma_id bigint default null
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

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.soplado_corridas (sabor_id, presentacion_id, item_preforma_id, responsable_nombre)
    values (p_sabor_id, p_presentacion_id, p_item_preforma_id, v_nombre)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Finalizar: hora de fin automática, carga lo producido y la merma, y
--    descuenta las preformas usadas del almacén de Soplado.
-- ---------------------------------------------------------------------
create or replace function public.soplado_finalizar_corrida(
    p_id bigint,
    p_cajas_sopladas numeric,
    p_botellas_sueltas int,
    p_preformas_usadas numeric,
    p_botellas_quebradas int default 0,
    p_preformas_desechadas int default 0,
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

    if p_cajas_sopladas is null or p_cajas_sopladas < 0 then
        raise exception 'Las cajas sopladas no pueden ser negativas.';
    end if;
    if coalesce(p_botellas_sueltas, 0) < 0 then
        raise exception 'Las botellas sueltas no pueden ser negativas.';
    end if;
    if coalesce(p_preformas_usadas, 0) < 0 then
        raise exception 'Las preformas usadas no pueden ser negativas.';
    end if;
    if coalesce(p_botellas_quebradas, 0) < 0 or coalesce(p_preformas_desechadas, 0) < 0 then
        raise exception 'La merma no puede ser negativa.';
    end if;
    if p_preformas_usadas is not null and p_preformas_desechadas > p_preformas_usadas then
        raise exception 'No se pueden desechar más preformas de las que se usaron.';
    end if;
    if (coalesce(p_botellas_quebradas, 0) > 0 or coalesce(p_preformas_desechadas, 0) > 0)
       and length(trim(coalesce(p_motivo_merma, ''))) = 0 then
        raise exception 'Indicá el motivo de la merma.';
    end if;
    if length(coalesce(p_motivo_merma, '')) > 300 or length(coalesce(p_observaciones, '')) > 300 then
        raise exception 'El motivo o las observaciones son demasiado largos.';
    end if;

    update public.soplado_corridas
       set estado = 'finalizada', hora_fin = now(),
           cajas_sopladas = p_cajas_sopladas, botellas_sueltas = coalesce(p_botellas_sueltas, 0),
           preformas_usadas = p_preformas_usadas,
           botellas_quebradas = coalesce(p_botellas_quebradas, 0),
           preformas_desechadas = coalesce(p_preformas_desechadas, 0),
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

-- ---------------------------------------------------------------------
-- 3. Anular una corrida iniciada por error (todavía sin finalizar).
-- ---------------------------------------------------------------------
create or replace function public.soplado_anular_corrida(p_id bigint, p_motivo text) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_corrida public.soplado_corridas;
begin
    if not public.tiene_permiso('soplado', 'editar') then
        raise exception 'No tenés permiso para anular una corrida.';
    end if;
    select * into v_corrida from public.soplado_corridas where id = p_id for update;
    if not found then raise exception 'La corrida no existe.'; end if;
    if v_corrida.estado <> 'en_curso' then raise exception 'Solo se anula una corrida en curso.'; end if;
    if length(trim(coalesce(p_motivo, ''))) < 3 then
        raise exception 'Escribí el motivo (mínimo 3 caracteres).';
    end if;
    update public.soplado_corridas
       set estado = 'anulada', hora_fin = now(), observaciones = trim(p_motivo)
     where id = p_id;
end;
$$;

revoke all on function public.soplado_iniciar_corrida(bigint, bigint, bigint) from public;
revoke all on function public.soplado_finalizar_corrida(bigint, numeric, int, numeric, int, int, text, text) from public;
revoke all on function public.soplado_anular_corrida(bigint, text) from public;
grant execute on function public.soplado_iniciar_corrida(bigint, bigint, bigint) to authenticated;
grant execute on function public.soplado_finalizar_corrida(bigint, numeric, int, numeric, int, int, text, text) to authenticated;
grant execute on function public.soplado_anular_corrida(bigint, text) to authenticated;

-- ---------------------------------------------------------------------
-- Avance de Soplado: lo ven Jarabes y Producción para no preparar de más.
-- ---------------------------------------------------------------------
create or replace view public.soplado_avance with (security_invoker = true) as
    select c.sabor_id, s.nombre as sabor, c.presentacion_id, p.nombre as presentacion,
           count(*) filter (where c.estado = 'finalizada') as corridas,
           coalesce(sum(c.cajas_sopladas) filter (where c.estado = 'finalizada'), 0) as cajas_sopladas,
           coalesce(sum(c.botellas_sueltas) filter (where c.estado = 'finalizada'), 0) as botellas_sueltas,
           max(c.hora_fin) filter (where c.estado = 'finalizada') as ultima_corrida
      from public.soplado_corridas c
      join public.sabores s on s.id = c.sabor_id
      join public.presentaciones p on p.id = c.presentacion_id
     where c.fecha >= current_date - interval '14 days'
     group by c.sabor_id, s.nombre, c.presentacion_id, p.nombre;
