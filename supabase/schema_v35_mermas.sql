-- =====================================================================
-- SALVIETTI CONTROL — v35: Mermas (Módulo 9).
-- Ejecutar DESPUÉS de schema_v34_registro_salidas.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Soplado, Llenadora y Codificación YA registran su propia merma dentro de
-- sus corridas (con su propio "producido": botellas sopladas/llenadas/
-- codificadas), así que no se repite acá. Este módulo agrega:
--
--   1. Un registro de merma para las áreas que todavía no tienen una
--      corrida propia donde anotarla: Jarabes, Calidad y Vidrio (sección
--      14.4 del md — "Vidrio" ahí no es un rol nuevo, es la línea de
--      envasado en vidrio; ESTO ES LO MENOS VALIDADO DE TODO EL MÓDULO,
--      revisar con Producción antes de usarlo en serio).
--   2. `mermas_consolidado`: junta este registro nuevo con la merma que ya
--      sale de soplado/llenadora/codificacion, en un solo lugar, con el
--      porcentaje sobre lo producido y la alerta cuando supera el 3 %
--      (el "estándar" que menciona el md es ese 3 %, igual para todos los
--      sabores: no hay una tolerancia distinta guardada por sabor).

-- ---------------------------------------------------------------------
-- Permisos: v17 ya sembró 'mermas' para casi todos los roles, pero
-- Control de Calidad solo tenía "ver" (necesita "crear" para registrar
-- "exceso de agua"). El área "Vidrio" no tiene un rol propio en el
-- organigrama: hasta que se confirme quién la carga, se la habilita a
-- Jefe de Producción (supervisa toda la línea) además de Gerente.
-- ---------------------------------------------------------------------
insert into public.permisos_rol (rol, modulo, accion)
select v.rol, 'mermas', v.accion
  from (values ('control_calidad', 'crear'), ('jefe_produccion', 'crear')) as v(rol, accion)
on conflict do nothing;

create table if not exists public.mermas_registros (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    area text not null check (area in ('jarabes', 'calidad', 'vidrio')),
    sabor_id bigint references public.sabores(id),
    presentacion_id bigint references public.presentaciones(id),
    cantidad_producida numeric check (cantidad_producida is null or cantidad_producida >= 0),
    motivo text check (motivo is null or length(motivo) <= 300),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    creado_en timestamptz not null default now()
);
create index if not exists mermas_registros_area on public.mermas_registros (area, fecha desc);

create table if not exists public.mermas_causas (
    id bigint generated always as identity primary key,
    registro_id bigint not null references public.mermas_registros(id) on delete cascade,
    causa text not null,
    cantidad numeric not null check (cantidad > 0)
);

alter table public.mermas_registros enable row level security;
alter table public.mermas_causas enable row level security;

drop policy if exists "ver_mermas_registros" on public.mermas_registros;
create policy "ver_mermas_registros" on public.mermas_registros for select
    using (public.tiene_permiso('mermas', 'ver'));
drop policy if exists "ver_mermas_causas" on public.mermas_causas;
create policy "ver_mermas_causas" on public.mermas_causas for select
    using (exists (select 1 from public.mermas_registros r where r.id = registro_id));
grant select on public.mermas_registros to authenticated;
grant select on public.mermas_causas to authenticated;

-- ---------------------------------------------------------------------
-- Causas válidas por área (las de la sección 14.4 del md).
-- ---------------------------------------------------------------------
create or replace function public._mermas_causas_validas(p_area text) returns text[]
language sql immutable as $$
    select case p_area
        when 'jarabes' then array['menor_volumen', 'diferencia_peso_insumos']
        when 'calidad' then array['exceso_agua']
        when 'vidrio' then array['botellas_quebradas', 'de_racion', 'descarte_suciedad', 'tapas_usadas']
        else array[]::text[]
    end;
$$;

-- Qué área puede cargar cada rol (además del permiso genérico 'mermas').
-- Evita que, por ejemplo, Jarabes registre una merma de "calidad".
create or replace function public._mermas_area_de_rol(p_rol text) returns text[]
language sql immutable as $$
    select case p_rol
        when 'jarabes' then array['jarabes']
        when 'ayudante_jarabes' then array['jarabes']
        when 'control_calidad' then array['calidad']
        when 'jefe_produccion' then array['jarabes', 'calidad', 'vidrio']
        when 'gerente' then array['jarabes', 'calidad', 'vidrio']
        else array[]::text[]
    end;
$$;

-- ---------------------------------------------------------------------
-- 1. Registrar una merma. p_causas: [{"causa": "menor_volumen", "cantidad": 12}, ...]
-- ---------------------------------------------------------------------
create or replace function public.mermas_registrar(
    p_area text,
    p_sabor_id bigint,
    p_causas jsonb,
    p_presentacion_id bigint default null,
    p_cantidad_producida numeric default null,
    p_motivo text default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_id bigint;
    v_nombre text;
    v_causa jsonb;
    v_nombre_causa text;
    v_cantidad numeric;
    v_validas text[];
begin
    if not public.tiene_permiso('mermas', 'crear') then
        raise exception 'No tenés permiso para registrar mermas.';
    end if;
    v_validas := public._mermas_causas_validas(p_area);
    if array_length(v_validas, 1) is null then
        raise exception 'Área inválida.';
    end if;
    if not (p_area = any (public._mermas_area_de_rol(public.rol_actual()))) then
        raise exception 'Tu rol no registra mermas de esa área.';
    end if;
    if not exists (select 1 from public.sabores where id = p_sabor_id) then
        raise exception 'El sabor indicado no existe.';
    end if;
    if p_cantidad_producida is not null and p_cantidad_producida < 0 then
        raise exception 'Lo producido no puede ser negativo.';
    end if;
    if jsonb_typeof(p_causas) is distinct from 'array' or jsonb_array_length(p_causas) = 0 then
        raise exception 'Indicá al menos una causa de merma.';
    end if;
    if length(coalesce(p_motivo, '')) > 300 then
        raise exception 'El motivo es demasiado largo.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.mermas_registros
        (area, sabor_id, presentacion_id, cantidad_producida, motivo, responsable_nombre)
    values
        (p_area, p_sabor_id, p_presentacion_id, p_cantidad_producida,
         nullif(trim(coalesce(p_motivo, '')), ''), v_nombre)
    returning id into v_id;

    for v_causa in select * from jsonb_array_elements(p_causas) loop
        v_nombre_causa := v_causa ->> 'causa';
        v_cantidad := (v_causa ->> 'cantidad')::numeric;
        if v_nombre_causa is null or not (v_nombre_causa = any (v_validas)) then
            raise exception 'Causa inválida para el área %: %.', p_area, v_nombre_causa;
        end if;
        if v_cantidad is null or v_cantidad <= 0 then
            raise exception 'La cantidad de "%" debe ser mayor a cero.', v_nombre_causa;
        end if;
        insert into public.mermas_causas (registro_id, causa, cantidad) values (v_id, v_nombre_causa, v_cantidad);
    end loop;

    return v_id;
end;
$$;

revoke all on function public.mermas_registrar(text, bigint, jsonb, bigint, numeric, text) from public;
grant execute on function public.mermas_registrar(text, bigint, jsonb, bigint, numeric, text) to authenticated;

-- ---------------------------------------------------------------------
-- Detalle de un registro (para listarlo con sus causas ya sumadas).
-- ---------------------------------------------------------------------
create or replace view public.mermas_registros_detalle with (security_invoker = true) as
    select r.id, r.fecha, r.area, r.sabor_id, s.nombre as sabor,
           r.presentacion_id, p.nombre as presentacion,
           r.cantidad_producida, r.motivo, r.responsable_nombre, r.creado_en,
           coalesce(sum(c.cantidad), 0) as total_merma,
           case when r.cantidad_producida > 0
                then round(100 * coalesce(sum(c.cantidad), 0) / r.cantidad_producida, 2)
           end as porcentaje,
           jsonb_agg(jsonb_build_object('causa', c.causa, 'cantidad', c.cantidad)) as causas
      from public.mermas_registros r
      join public.sabores s on s.id = r.sabor_id
      left join public.presentaciones p on p.id = r.presentacion_id
      left join public.mermas_causas c on c.registro_id = r.id
     group by r.id, s.nombre, p.nombre;
grant select on public.mermas_registros_detalle to authenticated;

-- ---------------------------------------------------------------------
-- Consolidado: junta este registro con la merma que ya sale de las
-- corridas de Soplado, Llenadora y Codificación. Una fila por evento, con
-- el porcentaje sobre lo producido y la alerta al 3 %.
-- ---------------------------------------------------------------------
-- `sabor_id` va al final: el Módulo 11 (informe del Gerente) lo necesita
-- para juntar esto con `informe_produccion_resumen` sin depender del
-- nombre del sabor. Agregar una columna al final con `create or replace
-- view` no rompe nada de lo que ya la usaba.
create or replace view public.mermas_consolidado with (security_invoker = true) as
    select 'jarabes_calidad_vidrio' as origen, r.id, r.fecha, r.area, s.nombre as sabor,
           p.nombre as presentacion, r.total_merma, r.cantidad_producida as producido,
           r.porcentaje, coalesce(r.porcentaje > 3, false) as alerta, r.motivo, r.sabor_id
      from public.mermas_registros_detalle r
      join public.sabores s on s.id = r.sabor_id
      left join public.presentaciones p on p.id = r.presentacion_id
    union all
    select 'soplado', c.id, c.fecha, 'soplado', s.nombre, p.nombre,
           c.merma_soplado + c.merma_preforma + c.merma_etiquetado, c.botellas_sopladas,
           case when c.botellas_sopladas > 0
                then round(100 * (c.merma_soplado + c.merma_preforma + c.merma_etiquetado) / c.botellas_sopladas, 2)
           end,
           coalesce(c.botellas_sopladas > 0
               and (c.merma_soplado + c.merma_preforma + c.merma_etiquetado) / c.botellas_sopladas > 0.03, false),
           c.motivo_merma, c.sabor_id
      from public.soplado_corridas c
      join public.sabores s on s.id = c.sabor_id
      join public.presentaciones p on p.id = c.presentacion_id
     where c.estado = 'finalizada'
    union all
    select 'llenadora', c.id, c.fecha, 'llenadora', s.nombre, p.nombre,
           c.botellas_desechadas + c.tapas_desechadas + c.rebalse, c.botellas_llenadas,
           case when c.botellas_llenadas > 0
                then round(100 * (c.botellas_desechadas + c.tapas_desechadas + c.rebalse) / c.botellas_llenadas, 2)
           end,
           coalesce(c.botellas_llenadas > 0
               and (c.botellas_desechadas + c.tapas_desechadas + c.rebalse) / c.botellas_llenadas > 0.03, false),
           c.motivo_merma, c.sabor_id
      from public.llenadora_corridas c
      join public.sabores s on s.id = c.sabor_id
      join public.presentaciones p on p.id = c.presentacion_id
     where c.estado = 'finalizada'
    union all
    select 'codificacion', c.id, c.fecha, 'codificacion', s.nombre, p.nombre,
           c.botellas_mal_tapadas + c.tapas_mal_tapadas + c.impurezas, c.botellas_codificadas,
           case when c.botellas_codificadas > 0
                then round(100 * (c.botellas_mal_tapadas + c.tapas_mal_tapadas + c.impurezas) / c.botellas_codificadas, 2)
           end,
           coalesce(c.botellas_codificadas > 0
               and (c.botellas_mal_tapadas + c.tapas_mal_tapadas + c.impurezas) / c.botellas_codificadas > 0.03, false),
           c.motivo_merma, c.sabor_id
      from public.codificacion_corridas c
      join public.sabores s on s.id = c.sabor_id
      join public.presentaciones p on p.id = c.presentacion_id
     where c.estado = 'finalizada';
grant select on public.mermas_consolidado to authenticated;
