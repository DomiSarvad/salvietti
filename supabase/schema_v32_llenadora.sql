-- =====================================================================
-- SALVIETTI CONTROL — v32: Llenadora (Módulo 8, parte 1 de 3).
-- Ejecutar DESPUÉS de schema_v26_jarabes.sql, en el SQL Editor de Supabase.
-- (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Formulario deducido (sección 14.1 del md): por corrida, sabor, formato,
-- N° de lote del preparado y tanque, hora de inicio y final, botellas
-- llenadas; merma de botellas desechadas, tapas usadas y desechadas,
-- rebalse, motivo.
--
-- Las tapas que se usan acá salen del pedido que Llenadora ya le hizo a
-- Almacén (Módulo 3): el descuento del Almacén General ocurre cuando
-- Almacén ENTREGA ese pedido, no acá. Esta pantalla solo REGISTRA cuántas
-- se usaron y desecharon en la corrida (para el informe de mermas del
-- Módulo 9); volver a descontar acá duplicaría la salida.

create table if not exists public.llenadora_corridas (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    turno text not null check (turno in ('manana', 'tarde', 'noche')),
    sabor_id bigint not null references public.sabores(id),
    presentacion_id bigint not null references public.presentaciones(id),
    preparado_id bigint references public.jarabes_preparados(id),
    n_lote_preparado text check (n_lote_preparado is null or length(n_lote_preparado) <= 40),
    tanque text check (tanque is null or length(tanque) <= 40),
    estado text not null default 'en_curso' check (estado in ('en_curso', 'finalizada', 'anulada')),
    hora_inicio timestamptz not null default now(),
    hora_fin timestamptz,
    botellas_llenadas numeric check (botellas_llenadas is null or botellas_llenadas >= 0),
    botellas_desechadas numeric not null default 0 check (botellas_desechadas >= 0),
    item_tapa_id bigint references public.inv_items(id),
    tapas_usadas numeric not null default 0 check (tapas_usadas >= 0),
    tapas_desechadas numeric not null default 0 check (tapas_desechadas >= 0),
    rebalse numeric not null default 0 check (rebalse >= 0),
    motivo_merma text check (motivo_merma is null or length(motivo_merma) <= 300),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    observaciones text check (observaciones is null or length(observaciones) <= 300),
    creado_en timestamptz not null default now()
);
create index if not exists llenadora_corridas_estado on public.llenadora_corridas (estado, fecha desc);

alter table public.llenadora_corridas enable row level security;
drop policy if exists "ver_llenadora_corridas" on public.llenadora_corridas;
create policy "ver_llenadora_corridas" on public.llenadora_corridas for select
    using (public.tiene_permiso('llenado', 'ver'));
grant select on public.llenadora_corridas to authenticated;

-- ---------------------------------------------------------------------
-- 1. Iniciar corrida.
-- ---------------------------------------------------------------------
create or replace function public.llenadora_iniciar_corrida(
    p_turno text,
    p_sabor_id bigint,
    p_presentacion_id bigint,
    p_preparado_id bigint default null,
    p_n_lote_preparado text default null,
    p_tanque text default null,
    p_item_tapa_id bigint default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_id bigint; v_nombre text;
begin
    if not public.tiene_permiso('llenado', 'crear') then
        raise exception 'No tenés permiso para registrar producción de Llenadora.';
    end if;
    if p_turno not in ('manana', 'tarde', 'noche') then
        raise exception 'Elegí un turno válido.';
    end if;
    if not exists (
        select 1 from public.sabor_presentacion
         where sabor_id = p_sabor_id and presentacion_id = p_presentacion_id
    ) then
        raise exception 'Ese sabor no se fabrica en esa presentación.';
    end if;
    if p_preparado_id is not null and not exists (
        select 1 from public.jarabes_preparados where id = p_preparado_id and sabor_id = p_sabor_id
    ) then
        raise exception 'Ese preparado no existe o es de otro sabor.';
    end if;
    if p_item_tapa_id is not null and not exists (select 1 from public.inv_items where id = p_item_tapa_id) then
        raise exception 'La tapa indicada no existe.';
    end if;
    if length(coalesce(p_n_lote_preparado, '')) > 40 or length(coalesce(p_tanque, '')) > 40 then
        raise exception 'El lote o el tanque son demasiado largos.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.llenadora_corridas
        (turno, sabor_id, presentacion_id, preparado_id, n_lote_preparado, tanque,
         item_tapa_id, responsable_nombre)
    values
        (p_turno, p_sabor_id, p_presentacion_id, p_preparado_id,
         nullif(trim(coalesce(p_n_lote_preparado, '')), ''),
         nullif(trim(coalesce(p_tanque, '')), ''), p_item_tapa_id, v_nombre)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Finalizar corrida.
-- ---------------------------------------------------------------------
create or replace function public.llenadora_finalizar_corrida(
    p_id bigint,
    p_botellas_llenadas numeric,
    p_botellas_desechadas numeric default 0,
    p_tapas_usadas numeric default 0,
    p_tapas_desechadas numeric default 0,
    p_rebalse numeric default 0,
    p_motivo_merma text default null,
    p_observaciones text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_c public.llenadora_corridas;
begin
    if not public.tiene_permiso('llenado', 'editar') then
        raise exception 'No tenés permiso para finalizar producción de Llenadora.';
    end if;
    select * into v_c from public.llenadora_corridas where id = p_id for update;
    if not found then raise exception 'La corrida no existe.'; end if;
    if v_c.estado <> 'en_curso' then raise exception 'Esa corrida ya se cerró.'; end if;

    if p_botellas_llenadas is null or p_botellas_llenadas < 0 then
        raise exception 'La cantidad de botellas llenadas no puede ser negativa.';
    end if;
    if coalesce(p_botellas_desechadas, 0) < 0 or coalesce(p_tapas_usadas, 0) < 0
       or coalesce(p_tapas_desechadas, 0) < 0 or coalesce(p_rebalse, 0) < 0 then
        raise exception 'La merma no puede ser negativa.';
    end if;
    if coalesce(p_botellas_desechadas, 0) > p_botellas_llenadas then
        raise exception 'No se pueden desechar más botellas de las que se llenaron.';
    end if;
    if coalesce(p_tapas_desechadas, 0) > coalesce(p_tapas_usadas, 0) then
        raise exception 'No se pueden desechar más tapas de las que se usaron.';
    end if;
    if (coalesce(p_botellas_desechadas, 0) > 0 or coalesce(p_tapas_desechadas, 0) > 0
        or coalesce(p_rebalse, 0) > 0)
       and length(trim(coalesce(p_motivo_merma, ''))) = 0 then
        raise exception 'Indicá el motivo de la merma.';
    end if;
    if length(coalesce(p_motivo_merma, '')) > 300 or length(coalesce(p_observaciones, '')) > 300 then
        raise exception 'Alguno de los textos es demasiado largo.';
    end if;

    update public.llenadora_corridas
       set estado = 'finalizada', hora_fin = now(),
           botellas_llenadas = p_botellas_llenadas,
           botellas_desechadas = coalesce(p_botellas_desechadas, 0),
           tapas_usadas = coalesce(p_tapas_usadas, 0),
           tapas_desechadas = coalesce(p_tapas_desechadas, 0),
           rebalse = coalesce(p_rebalse, 0),
           motivo_merma = nullif(trim(coalesce(p_motivo_merma, '')), ''),
           observaciones = nullif(trim(coalesce(p_observaciones, '')), '')
     where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Anular una corrida en curso.
-- ---------------------------------------------------------------------
create or replace function public.llenadora_anular_corrida(p_id bigint, p_motivo text) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_c public.llenadora_corridas;
begin
    if not public.tiene_permiso('llenado', 'editar') then
        raise exception 'No tenés permiso para anular una corrida de Llenadora.';
    end if;
    select * into v_c from public.llenadora_corridas where id = p_id for update;
    if not found then raise exception 'La corrida no existe.'; end if;
    if v_c.estado <> 'en_curso' then raise exception 'Solo se anula una corrida en curso.'; end if;
    if length(trim(coalesce(p_motivo, ''))) < 3 then
        raise exception 'Escribí el motivo (mínimo 3 caracteres).';
    end if;
    update public.llenadora_corridas
       set estado = 'anulada', hora_fin = now(), observaciones = trim(p_motivo)
     where id = p_id;
end;
$$;

revoke all on function public.llenadora_iniciar_corrida(text, bigint, bigint, bigint, text, text, bigint) from public;
revoke all on function public.llenadora_finalizar_corrida(bigint, numeric, numeric, numeric, numeric, numeric, text, text) from public;
revoke all on function public.llenadora_anular_corrida(bigint, text) from public;
grant execute on function public.llenadora_iniciar_corrida(text, bigint, bigint, bigint, text, text, bigint) to authenticated;
grant execute on function public.llenadora_finalizar_corrida(bigint, numeric, numeric, numeric, numeric, numeric, text, text) to authenticated;
grant execute on function public.llenadora_anular_corrida(bigint, text) to authenticated;

-- Avance de los últimos 14 días, para Llenadora y para quien mira el
-- panorama general (Jefe de Producción, Gerente).
create or replace view public.llenadora_avance with (security_invoker = true) as
    select c.sabor_id, s.nombre as sabor, c.presentacion_id, p.nombre as presentacion,
           count(*) filter (where c.estado = 'finalizada') as corridas,
           coalesce(sum(c.botellas_llenadas - c.botellas_desechadas)
                    filter (where c.estado = 'finalizada'), 0) as botellas_buenas,
           max(c.hora_fin) filter (where c.estado = 'finalizada') as ultima_corrida
      from public.llenadora_corridas c
      join public.sabores s on s.id = c.sabor_id
      join public.presentaciones p on p.id = c.presentacion_id
     where c.fecha >= current_date - interval '14 days'
     group by c.sabor_id, s.nombre, c.presentacion_id, p.nombre;
grant select on public.llenadora_avance to authenticated;
