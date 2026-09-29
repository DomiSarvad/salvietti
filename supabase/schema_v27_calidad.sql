-- =====================================================================
-- SALVIETTI CONTROL — v27: Control de Calidad (Módulo 7).
-- Ejecutar DESPUÉS de schema_v26_jarabes.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- La aprobación de recetas por Calidad YA funciona desde el Módulo 6
-- (permiso 'recetas':'aprobar'); no se repite acá.
--
-- Cuando Jarabes finaliza un preparado, éste queda "pendiente de análisis"
-- para Calidad automáticamente: no hace falta un aviso aparte, alcanza con
-- listar los preparados finalizados que todavía no tienen un análisis
-- (vista `calidad_pendientes`). La "notificación" a Jarabes y al Jefe de
-- Producción cuando algo no cumple es que el análisis queda visible para
-- ambos (ya tienen permiso de ver el módulo 'calidad').

create table if not exists public.calidad_analisis (
    id bigint generated always as identity primary key,
    preparado_id bigint not null unique references public.jarabes_preparados(id),
    fecha timestamptz not null default now(),
    brix_diluido numeric check (brix_diluido is null or (brix_diluido >= 0 and brix_diluido <= 100)),
    ph numeric check (ph is null or (ph >= 0 and ph <= 14)),
    aspecto text check (aspecto is null or length(aspecto) <= 200),
    resultado text not null check (resultado in ('conforme', 'no_conforme')),
    accion_tomada text check (accion_tomada is null or length(accion_tomada) <= 300),
    observaciones text check (observaciones is null or length(observaciones) <= 300),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    creado_en timestamptz not null default now(),
    actualizado_en timestamptz
);

alter table public.calidad_analisis enable row level security;
drop policy if exists "ver_calidad_analisis" on public.calidad_analisis;
create policy "ver_calidad_analisis" on public.calidad_analisis for select
    using (public.tiene_permiso('calidad', 'ver'));

-- Preparados finalizados que todavía no tienen análisis: la bandeja de Calidad.
create or replace view public.calidad_pendientes with (security_invoker = true) as
    select p.id as preparado_id, p.fecha, p.sabor_id, s.nombre as sabor, p.n_lote, p.tanque,
           p.cantidad_preparados, p.litros, p.brix, p.hora_fin,
           s.brix_min, s.brix_max
      from public.jarabes_preparados p
      join public.sabores s on s.id = p.sabor_id
     where p.estado = 'finalizada'
       and not exists (select 1 from public.calidad_analisis a where a.preparado_id = p.id)
     order by p.hora_fin;

-- ---------------------------------------------------------------------
-- 1. Registrar el análisis de un preparado.
-- ---------------------------------------------------------------------
create or replace function public.calidad_registrar_analisis(
    p_preparado_id bigint,
    p_brix_diluido numeric,
    p_ph numeric,
    p_resultado text,
    p_aspecto text default null,
    p_accion_tomada text default null,
    p_observaciones text default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_id bigint; v_nombre text;
begin
    if not public.tiene_permiso('calidad', 'crear') then
        raise exception 'No tenés permiso para registrar análisis de Calidad.';
    end if;
    if not exists (
        select 1 from public.jarabes_preparados where id = p_preparado_id and estado = 'finalizada'
    ) then
        raise exception 'Ese preparado no existe o todavía no fue finalizado por Jarabes.';
    end if;
    if exists (select 1 from public.calidad_analisis where preparado_id = p_preparado_id) then
        raise exception 'Ese preparado ya tiene un análisis registrado.';
    end if;
    if p_resultado not in ('conforme', 'no_conforme') then
        raise exception 'Resultado inválido.';
    end if;
    if p_brix_diluido is null or p_brix_diluido < 0 or p_brix_diluido > 100 then
        raise exception 'Ingresá un Brix válido (0 a 100).';
    end if;
    if p_ph is null or p_ph < 0 or p_ph > 14 then
        raise exception 'Ingresá un pH válido (0 a 14).';
    end if;
    if p_resultado = 'no_conforme' and length(trim(coalesce(p_accion_tomada, ''))) = 0 then
        raise exception 'Indicá qué acción se tomó, ya que no cumple.';
    end if;
    if length(coalesce(p_aspecto, '')) > 200 or length(coalesce(p_accion_tomada, '')) > 300
       or length(coalesce(p_observaciones, '')) > 300 then
        raise exception 'Alguno de los textos es demasiado largo.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.calidad_analisis
        (preparado_id, brix_diluido, ph, aspecto, resultado, accion_tomada, observaciones, responsable_nombre)
    values
        (p_preparado_id, p_brix_diluido, p_ph, nullif(trim(coalesce(p_aspecto, '')), ''),
         p_resultado, nullif(trim(coalesce(p_accion_tomada, '')), ''),
         nullif(trim(coalesce(p_observaciones, '')), ''), v_nombre)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Completar la acción tomada u observaciones más tarde (ej. una vez
--    decidida la corrección), sin tocar la medición original.
-- ---------------------------------------------------------------------
create or replace function public.calidad_actualizar_analisis(
    p_id bigint, p_accion_tomada text, p_observaciones text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
    if not public.tiene_permiso('calidad', 'editar') then
        raise exception 'No tenés permiso para editar análisis de Calidad.';
    end if;
    if not exists (select 1 from public.calidad_analisis where id = p_id) then
        raise exception 'El análisis no existe.';
    end if;
    if length(coalesce(p_accion_tomada, '')) > 300 or length(coalesce(p_observaciones, '')) > 300 then
        raise exception 'Alguno de los textos es demasiado largo.';
    end if;
    update public.calidad_analisis
       set accion_tomada = nullif(trim(coalesce(p_accion_tomada, '')), ''),
           observaciones = nullif(trim(coalesce(p_observaciones, '')), ''),
           actualizado_en = now()
     where id = p_id;
end;
$$;

revoke all on function public.calidad_registrar_analisis(bigint, numeric, numeric, text, text, text, text) from public;
revoke all on function public.calidad_actualizar_analisis(bigint, text, text) from public;
grant execute on function public.calidad_registrar_analisis(bigint, numeric, numeric, text, text, text, text) to authenticated;
grant execute on function public.calidad_actualizar_analisis(bigint, text, text) to authenticated;
