-- =====================================================================
-- SALVIETTI CONTROL — v33: Codificación (Módulo 8, parte 2 de 3).
-- Ejecutar DESPUÉS de schema_v32_llenadora.sql, en el SQL Editor de
-- Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Formulario deducido (sección 14.2 del md): por corrida, sabor, formato,
-- N° de lote, hora de inicio y final, botellas codificadas, código o
-- fecha impresa; merma de botellas y tapas mal tapadas e impurezas;
-- consumo de solvente y tinta.
--
-- Igual que en Llenadora: el solvente y la tinta que se consumen acá ya
-- se descontaron del Almacén General cuando Almacén le entregó el pedido
-- a Codificación (Módulo 3). Esta pantalla solo REGISTRA cuánto se usó en
-- la corrida, para el informe de mermas (Módulo 9); no vuelve a descontar.

create table if not exists public.codificacion_corridas (
    id bigint generated always as identity primary key,
    fecha date not null default current_date,
    turno text not null check (turno in ('manana', 'tarde', 'noche')),
    sabor_id bigint not null references public.sabores(id),
    presentacion_id bigint not null references public.presentaciones(id),
    corrida_llenadora_id bigint references public.llenadora_corridas(id),
    n_lote text check (n_lote is null or length(n_lote) <= 40),
    estado text not null default 'en_curso' check (estado in ('en_curso', 'finalizada', 'anulada')),
    hora_inicio timestamptz not null default now(),
    hora_fin timestamptz,
    botellas_codificadas numeric check (botellas_codificadas is null or botellas_codificadas >= 0),
    codigo_impreso text check (codigo_impreso is null or length(codigo_impreso) <= 60),
    botellas_mal_tapadas numeric not null default 0 check (botellas_mal_tapadas >= 0),
    tapas_mal_tapadas numeric not null default 0 check (tapas_mal_tapadas >= 0),
    impurezas numeric not null default 0 check (impurezas >= 0),
    motivo_merma text check (motivo_merma is null or length(motivo_merma) <= 300),
    item_solvente_id bigint references public.inv_items(id),
    solvente_usado numeric not null default 0 check (solvente_usado >= 0),
    item_tinta_id bigint references public.inv_items(id),
    tinta_usada numeric not null default 0 check (tinta_usada >= 0),
    responsable uuid not null default auth.uid(),
    responsable_nombre text,
    observaciones text check (observaciones is null or length(observaciones) <= 300),
    creado_en timestamptz not null default now()
);
create index if not exists codificacion_corridas_estado on public.codificacion_corridas (estado, fecha desc);

alter table public.codificacion_corridas enable row level security;
drop policy if exists "ver_codificacion_corridas" on public.codificacion_corridas;
create policy "ver_codificacion_corridas" on public.codificacion_corridas for select
    using (public.tiene_permiso('codificacion', 'ver'));
grant select on public.codificacion_corridas to authenticated;

-- ---------------------------------------------------------------------
-- 1. Iniciar corrida.
-- ---------------------------------------------------------------------
create or replace function public.codificacion_iniciar_corrida(
    p_turno text,
    p_sabor_id bigint,
    p_presentacion_id bigint,
    p_corrida_llenadora_id bigint default null,
    p_n_lote text default null,
    p_item_solvente_id bigint default null,
    p_item_tinta_id bigint default null
) returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_id bigint; v_nombre text;
begin
    if not public.tiene_permiso('codificacion', 'crear') then
        raise exception 'No tenés permiso para registrar producción de Codificación.';
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
    if p_corrida_llenadora_id is not null and not exists (
        select 1 from public.llenadora_corridas
         where id = p_corrida_llenadora_id and sabor_id = p_sabor_id
    ) then
        raise exception 'Esa corrida de Llenadora no existe o es de otro sabor.';
    end if;
    if p_item_solvente_id is not null and not exists (select 1 from public.inv_items where id = p_item_solvente_id) then
        raise exception 'El solvente indicado no existe.';
    end if;
    if p_item_tinta_id is not null and not exists (select 1 from public.inv_items where id = p_item_tinta_id) then
        raise exception 'La tinta indicada no existe.';
    end if;
    if length(coalesce(p_n_lote, '')) > 40 then
        raise exception 'El número de lote es demasiado largo.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    insert into public.codificacion_corridas
        (turno, sabor_id, presentacion_id, corrida_llenadora_id, n_lote,
         item_solvente_id, item_tinta_id, responsable_nombre)
    values
        (p_turno, p_sabor_id, p_presentacion_id, p_corrida_llenadora_id,
         nullif(trim(coalesce(p_n_lote, '')), ''), p_item_solvente_id, p_item_tinta_id, v_nombre)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Finalizar corrida.
-- ---------------------------------------------------------------------
create or replace function public.codificacion_finalizar_corrida(
    p_id bigint,
    p_botellas_codificadas numeric,
    p_codigo_impreso text default null,
    p_botellas_mal_tapadas numeric default 0,
    p_tapas_mal_tapadas numeric default 0,
    p_impurezas numeric default 0,
    p_motivo_merma text default null,
    p_solvente_usado numeric default 0,
    p_tinta_usada numeric default 0,
    p_observaciones text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_c public.codificacion_corridas;
begin
    if not public.tiene_permiso('codificacion', 'editar') then
        raise exception 'No tenés permiso para finalizar producción de Codificación.';
    end if;
    select * into v_c from public.codificacion_corridas where id = p_id for update;
    if not found then raise exception 'La corrida no existe.'; end if;
    if v_c.estado <> 'en_curso' then raise exception 'Esa corrida ya se cerró.'; end if;

    if p_botellas_codificadas is null or p_botellas_codificadas < 0 then
        raise exception 'La cantidad de botellas codificadas no puede ser negativa.';
    end if;
    if coalesce(p_botellas_mal_tapadas, 0) < 0 or coalesce(p_tapas_mal_tapadas, 0) < 0
       or coalesce(p_impurezas, 0) < 0 or coalesce(p_solvente_usado, 0) < 0
       or coalesce(p_tinta_usada, 0) < 0 then
        raise exception 'Ningún valor puede ser negativo.';
    end if;
    if coalesce(p_botellas_mal_tapadas, 0) > p_botellas_codificadas
       or coalesce(p_tapas_mal_tapadas, 0) > p_botellas_codificadas
       or coalesce(p_impurezas, 0) > p_botellas_codificadas then
        raise exception 'La merma no puede ser mayor a lo codificado.';
    end if;
    if (coalesce(p_botellas_mal_tapadas, 0) > 0 or coalesce(p_tapas_mal_tapadas, 0) > 0
        or coalesce(p_impurezas, 0) > 0)
       and length(trim(coalesce(p_motivo_merma, ''))) = 0 then
        raise exception 'Indicá el motivo de la merma.';
    end if;
    if length(coalesce(p_codigo_impreso, '')) > 60 then
        raise exception 'El código impreso es demasiado largo.';
    end if;
    if length(coalesce(p_motivo_merma, '')) > 300 or length(coalesce(p_observaciones, '')) > 300 then
        raise exception 'Alguno de los textos es demasiado largo.';
    end if;

    update public.codificacion_corridas
       set estado = 'finalizada', hora_fin = now(),
           botellas_codificadas = p_botellas_codificadas,
           codigo_impreso = nullif(trim(coalesce(p_codigo_impreso, '')), ''),
           botellas_mal_tapadas = coalesce(p_botellas_mal_tapadas, 0),
           tapas_mal_tapadas = coalesce(p_tapas_mal_tapadas, 0),
           impurezas = coalesce(p_impurezas, 0),
           motivo_merma = nullif(trim(coalesce(p_motivo_merma, '')), ''),
           solvente_usado = coalesce(p_solvente_usado, 0),
           tinta_usada = coalesce(p_tinta_usada, 0),
           observaciones = nullif(trim(coalesce(p_observaciones, '')), '')
     where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Anular una corrida en curso.
-- ---------------------------------------------------------------------
create or replace function public.codificacion_anular_corrida(p_id bigint, p_motivo text) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_c public.codificacion_corridas;
begin
    if not public.tiene_permiso('codificacion', 'editar') then
        raise exception 'No tenés permiso para anular una corrida de Codificación.';
    end if;
    select * into v_c from public.codificacion_corridas where id = p_id for update;
    if not found then raise exception 'La corrida no existe.'; end if;
    if v_c.estado <> 'en_curso' then raise exception 'Solo se anula una corrida en curso.'; end if;
    if length(trim(coalesce(p_motivo, ''))) < 3 then
        raise exception 'Escribí el motivo (mínimo 3 caracteres).';
    end if;
    update public.codificacion_corridas
       set estado = 'anulada', hora_fin = now(), observaciones = trim(p_motivo)
     where id = p_id;
end;
$$;

revoke all on function public.codificacion_iniciar_corrida(text, bigint, bigint, bigint, text, bigint, bigint) from public;
revoke all on function public.codificacion_finalizar_corrida(bigint, numeric, text, numeric, numeric, numeric, text, numeric, numeric, text) from public;
revoke all on function public.codificacion_anular_corrida(bigint, text) from public;
grant execute on function public.codificacion_iniciar_corrida(text, bigint, bigint, bigint, text, bigint, bigint) to authenticated;
grant execute on function public.codificacion_finalizar_corrida(bigint, numeric, text, numeric, numeric, numeric, text, numeric, numeric, text) to authenticated;
grant execute on function public.codificacion_anular_corrida(bigint, text) to authenticated;

create or replace view public.codificacion_avance with (security_invoker = true) as
    select c.sabor_id, s.nombre as sabor, c.presentacion_id, p.nombre as presentacion,
           count(*) filter (where c.estado = 'finalizada') as corridas,
           coalesce(sum(c.botellas_codificadas - c.botellas_mal_tapadas)
                    filter (where c.estado = 'finalizada'), 0) as botellas_buenas,
           max(c.hora_fin) filter (where c.estado = 'finalizada') as ultima_corrida
      from public.codificacion_corridas c
      join public.sabores s on s.id = c.sabor_id
      join public.presentaciones p on p.id = c.presentacion_id
     where c.fecha >= current_date - interval '14 days'
     group by c.sabor_id, s.nombre, c.presentacion_id, p.nombre;
grant select on public.codificacion_avance to authenticated;
