-- =====================================================================
-- SALVIETTI CONTROL — v34: Registro de salidas (Módulo 8, parte 3 de 3).
-- Ejecutar DESPUÉS de schema_v33_codificacion.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Formulario deducido (sección 14.3 del md): "Reporte diario de
-- producción". Un encabezado por día/turno (hora de inicio y final del
-- día), y una línea por cada sabor y formato que salió, con su propia
-- hora de inicio/final y, según el material:
--   PET    -> palets, paquetes libres, botellas libres.
--   Vidrio -> filas, cajas libres, botellas libres.
-- El total de botellas se calcula con la fórmula de la sección 6:
--   total = palets × empaques_por_palet × unidades_por_caja
--         + paquetes_libres × unidades_por_caja + botellas_libres      (PET)
-- Para vidrio, cuántas cajas arma cada "fila" de un palet todavía no está
-- definido (sección 13, "Datos que faltan"): el total se calcula con lo
-- que SÍ se conoce (cajas libres × unidades por caja + botellas libres);
-- "filas" queda registrado para el reporte pero no entra en el total
-- hasta que se confirme esa equivalencia.
-- La "Planilla de producción" es la vista `salidas_planilla`: se arma
-- sola agrupando estas líneas, sin que nadie la escriba a mano.

create table if not exists public.salidas_reportes (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    turno text not null check (turno in ('manana', 'tarde', 'noche')),
    hora_inicio_dia timestamptz not null default now(),
    hora_fin_dia timestamptz,
    estado text not null default 'abierto' check (estado in ('abierto', 'cerrado')),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    observaciones text check (observaciones is null or length(observaciones) <= 300),
    creado_en timestamptz not null default now(),
    unique (fecha, turno)
);

create table if not exists public.salidas_reporte_lineas (
    id bigint generated always as identity primary key,
    reporte_id bigint not null references public.salidas_reportes(id) on delete cascade,
    sabor_id bigint not null references public.sabores(id),
    presentacion_id bigint not null references public.presentaciones(id),
    hora_inicio timestamptz,
    hora_fin timestamptz,
    pet_palets numeric check (pet_palets is null or pet_palets >= 0),
    pet_paquetes_libres numeric check (pet_paquetes_libres is null or pet_paquetes_libres >= 0),
    pet_botellas_libres numeric check (pet_botellas_libres is null or pet_botellas_libres >= 0),
    vid_filas numeric check (vid_filas is null or vid_filas >= 0),
    vid_cajas_libres numeric check (vid_cajas_libres is null or vid_cajas_libres >= 0),
    vid_botellas_libres numeric check (vid_botellas_libres is null or vid_botellas_libres >= 0),
    creado_en timestamptz not null default now()
);
create index if not exists salidas_reporte_lineas_reporte on public.salidas_reporte_lineas (reporte_id);

alter table public.salidas_reportes enable row level security;
alter table public.salidas_reporte_lineas enable row level security;

drop policy if exists "ver_salidas_reportes" on public.salidas_reportes;
create policy "ver_salidas_reportes" on public.salidas_reportes for select
    using (public.tiene_permiso('salidas', 'ver'));
drop policy if exists "ver_salidas_reporte_lineas" on public.salidas_reporte_lineas;
create policy "ver_salidas_reporte_lineas" on public.salidas_reporte_lineas for select
    using (exists (select 1 from public.salidas_reportes r where r.id = reporte_id));
grant select on public.salidas_reportes to authenticated;
grant select on public.salidas_reporte_lineas to authenticated;

-- ---------------------------------------------------------------------
-- 1. Abrir el reporte del día/turno (uno solo por combinación).
-- ---------------------------------------------------------------------
create or replace function public.salidas_crear_reporte(p_turno text) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_id bigint; v_nombre text;
begin
    if not public.tiene_permiso('salidas', 'crear') then
        raise exception 'No tenés permiso para registrar el reporte de salidas.';
    end if;
    if p_turno not in ('manana', 'tarde', 'noche') then
        raise exception 'Elegí un turno válido.';
    end if;
    if exists (select 1 from public.salidas_reportes where fecha = current_date and turno = p_turno) then
        raise exception 'Ya existe un reporte de hoy para ese turno.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.salidas_reportes (turno, responsable_nombre)
    values (p_turno, v_nombre)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Agregar (o actualizar, si ya existe la misma línea) un sabor/formato
--    al reporte. p_id_linea null = agrega una línea nueva.
-- ---------------------------------------------------------------------
create or replace function public.salidas_guardar_linea(
    p_reporte_id bigint,
    p_sabor_id bigint,
    p_presentacion_id bigint,
    p_hora_inicio timestamptz default null,
    p_hora_fin timestamptz default null,
    p_pet_palets numeric default null,
    p_pet_paquetes_libres numeric default null,
    p_pet_botellas_libres numeric default null,
    p_vid_filas numeric default null,
    p_vid_cajas_libres numeric default null,
    p_vid_botellas_libres numeric default null,
    p_id_linea bigint default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.salidas_reportes; v_id bigint;
begin
    if not public.tiene_permiso('salidas', 'editar') then
        raise exception 'No tenés permiso para editar el reporte de salidas.';
    end if;
    select * into v_r from public.salidas_reportes where id = p_reporte_id for update;
    if not found then raise exception 'El reporte no existe.'; end if;
    if v_r.estado <> 'abierto' then raise exception 'Este reporte ya está cerrado.'; end if;
    if not exists (
        select 1 from public.sabor_presentacion
         where sabor_id = p_sabor_id and presentacion_id = p_presentacion_id
    ) then
        raise exception 'Ese sabor no se fabrica en esa presentación.';
    end if;
    if least(coalesce(p_pet_palets, 0), coalesce(p_pet_paquetes_libres, 0), coalesce(p_pet_botellas_libres, 0),
             coalesce(p_vid_filas, 0), coalesce(p_vid_cajas_libres, 0), coalesce(p_vid_botellas_libres, 0)) < 0 then
        raise exception 'Ningún valor puede ser negativo.';
    end if;

    if p_id_linea is not null then
        if not exists (select 1 from public.salidas_reporte_lineas where id = p_id_linea and reporte_id = p_reporte_id) then
            raise exception 'Esa línea no existe en este reporte.';
        end if;
        update public.salidas_reporte_lineas
           set sabor_id = p_sabor_id, presentacion_id = p_presentacion_id,
               hora_inicio = p_hora_inicio, hora_fin = p_hora_fin,
               pet_palets = p_pet_palets, pet_paquetes_libres = p_pet_paquetes_libres,
               pet_botellas_libres = p_pet_botellas_libres, vid_filas = p_vid_filas,
               vid_cajas_libres = p_vid_cajas_libres, vid_botellas_libres = p_vid_botellas_libres
         where id = p_id_linea
        returning id into v_id;
    else
        insert into public.salidas_reporte_lineas
            (reporte_id, sabor_id, presentacion_id, hora_inicio, hora_fin,
             pet_palets, pet_paquetes_libres, pet_botellas_libres,
             vid_filas, vid_cajas_libres, vid_botellas_libres)
        values
            (p_reporte_id, p_sabor_id, p_presentacion_id, p_hora_inicio, p_hora_fin,
             p_pet_palets, p_pet_paquetes_libres, p_pet_botellas_libres,
             p_vid_filas, p_vid_cajas_libres, p_vid_botellas_libres)
        returning id into v_id;
    end if;
    return v_id;
end;
$$;

create or replace function public.salidas_eliminar_linea(p_id_linea bigint) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.salidas_reportes;
begin
    if not public.tiene_permiso('salidas', 'editar') then
        raise exception 'No tenés permiso para editar el reporte de salidas.';
    end if;
    select r.* into v_r from public.salidas_reportes r
      join public.salidas_reporte_lineas l on l.reporte_id = r.id
     where l.id = p_id_linea for update;
    if not found then raise exception 'La línea no existe.'; end if;
    if v_r.estado <> 'abierto' then raise exception 'Este reporte ya está cerrado.'; end if;
    delete from public.salidas_reporte_lineas where id = p_id_linea;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Cerrar el reporte del día/turno.
-- ---------------------------------------------------------------------
create or replace function public.salidas_cerrar_reporte(
    p_id bigint, p_observaciones text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.salidas_reportes;
begin
    if not public.tiene_permiso('salidas', 'editar') then
        raise exception 'No tenés permiso para cerrar el reporte de salidas.';
    end if;
    select * into v_r from public.salidas_reportes where id = p_id for update;
    if not found then raise exception 'El reporte no existe.'; end if;
    if v_r.estado <> 'abierto' then raise exception 'Este reporte ya está cerrado.'; end if;
    if not exists (select 1 from public.salidas_reporte_lineas where reporte_id = p_id) then
        raise exception 'Agregá al menos un sabor antes de cerrar el reporte.';
    end if;
    if length(coalesce(p_observaciones, '')) > 300 then
        raise exception 'Las observaciones son demasiado largas.';
    end if;
    update public.salidas_reportes
       set estado = 'cerrado', hora_fin_dia = now(),
           observaciones = nullif(trim(coalesce(p_observaciones, '')), '')
     where id = p_id;
end;
$$;

revoke all on function public.salidas_crear_reporte(text) from public;
revoke all on function public.salidas_guardar_linea(bigint, bigint, bigint, timestamptz, timestamptz, numeric, numeric, numeric, numeric, numeric, numeric, bigint) from public;
revoke all on function public.salidas_eliminar_linea(bigint) from public;
revoke all on function public.salidas_cerrar_reporte(bigint, text) from public;
grant execute on function public.salidas_crear_reporte(text) to authenticated;
grant execute on function public.salidas_guardar_linea(bigint, bigint, bigint, timestamptz, timestamptz, numeric, numeric, numeric, numeric, numeric, numeric, bigint) to authenticated;
grant execute on function public.salidas_eliminar_linea(bigint) to authenticated;
grant execute on function public.salidas_cerrar_reporte(bigint, text) to authenticated;

-- ---------------------------------------------------------------------
-- Vistas: detalle con el total calculado, y la Planilla (agrupada por
-- fecha, sabor y presentación) que se arma sola.
-- ---------------------------------------------------------------------
create or replace view public.salidas_reporte_detalle with (security_invoker = true) as
    select l.id, l.reporte_id, r.fecha, r.turno, r.estado as estado_reporte,
           l.sabor_id, s.nombre as sabor, l.presentacion_id, p.nombre as presentacion,
           p.material, l.hora_inicio, l.hora_fin,
           l.pet_palets, l.pet_paquetes_libres, l.pet_botellas_libres,
           l.vid_filas, l.vid_cajas_libres, l.vid_botellas_libres,
           case p.material
               when 'pet' then
                   case when p.empaques_por_palet is not null and p.unidades_por_caja is not null then
                       coalesce(l.pet_palets, 0) * p.empaques_por_palet * p.unidades_por_caja
                       + coalesce(l.pet_paquetes_libres, 0) * p.unidades_por_caja
                       + coalesce(l.pet_botellas_libres, 0)
                   end
               when 'vidrio' then
                   -- "Filas" no entra al total (falta la equivalencia por palet, sección 13
                   -- del md) pero eso no debe anular lo que sí se sabe: cajas y botellas
                   -- libres. Antes, cualquier vid_filas != 0 dejaba el total entero en null.
                   case when p.unidades_por_caja is not null then
                       coalesce(l.vid_cajas_libres, 0) * p.unidades_por_caja + coalesce(l.vid_botellas_libres, 0)
                   end
           end as total_botellas
      from public.salidas_reporte_lineas l
      join public.salidas_reportes r on r.id = l.reporte_id
      join public.sabores s on s.id = l.sabor_id
      join public.presentaciones p on p.id = l.presentacion_id;
grant select on public.salidas_reporte_detalle to authenticated;

create or replace view public.salidas_planilla with (security_invoker = true) as
    select fecha, sabor_id, sabor, presentacion_id, presentacion, material,
           count(*) as reportes,
           sum(total_botellas) as total_botellas
      from public.salidas_reporte_detalle
     group by fecha, sabor_id, sabor, presentacion_id, presentacion, material
     order by fecha desc, sabor, presentacion;
grant select on public.salidas_planilla to authenticated;
