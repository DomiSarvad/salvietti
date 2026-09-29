-- =====================================================================
-- SALVIETTI CONTROL — v37: doble aprobación de recetas + clave del Gerente
-- (Módulo 11, primera parte). Ejecutar DESPUÉS de schema_v36_soda_caustica.sql,
-- en el SQL Editor de Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- El Módulo 6 aprobaba una receta con el visto bueno de CUALQUIERA de
-- Producción, Calidad o Gerencia (sección 12 bis, nota del Módulo 6). El
-- proceso real (sección 7) es más estricto: Calidad Y Producción deben dar
-- su visto bueno por separado, y recién entonces el Gerente la activa
-- reingresando su contraseña (no alcanza con estar logueado como Gerente:
-- se vuelve a pedir la clave en el momento, como una re-confirmación).
--
-- Las recetas que ya están 'activa' NO se tocan (quedan como estaban,
-- aprobadas con la regla vieja). Las que sigan 'propuesta' desde ahora
-- necesitan el proceso nuevo — incluidas las que ya estén pendientes.
--
-- Se borra `jarabes_receta_aprobar` (el aprobado de un solo paso): si algo
-- todavía la llama, es una versión vieja de la app que hay que actualizar,
-- no un camino alternativo para saltarse la doble aprobación.

alter table public.jarabes_recetas
    add column if not exists aprobada_calidad_por uuid,
    add column if not exists aprobada_calidad_nombre text,
    add column if not exists aprobada_calidad_en timestamptz,
    add column if not exists aprobada_produccion_por uuid,
    add column if not exists aprobada_produccion_nombre text,
    add column if not exists aprobada_produccion_en timestamptz;

drop function if exists public.jarabes_receta_aprobar(bigint);

-- ---------------------------------------------------------------------
-- Re-confirma la contraseña de quien está llamando (no alcanza con la
-- sesión abierta). `auth.users.encrypted_password` es un hash bcrypt
-- (pgcrypto, ya en uso desde v3/v8/v14 para crear cuentas): `crypt(clave,
-- hash)` vuelve a aplicar el mismo salt y compara.
-- ---------------------------------------------------------------------
create or replace function public._verificar_clave_actual(p_clave text) returns boolean
language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
declare v_hash text;
begin
    if p_clave is null or length(p_clave) = 0 then return false; end if;
    select encrypted_password into v_hash from auth.users where id = auth.uid();
    if v_hash is null then return false; end if;
    return v_hash = crypt(p_clave, v_hash);
end;
$$;
revoke all on function public._verificar_clave_actual(text) from public;
grant execute on function public._verificar_clave_actual(text) to authenticated;

-- ---------------------------------------------------------------------
-- 1. Visto bueno de Calidad.
-- ---------------------------------------------------------------------
create or replace function public.jarabes_receta_aprobar_calidad(p_id bigint) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.jarabes_recetas; v_nombre text;
begin
    if not public.tiene_permiso('recetas', 'aprobar') then
        raise exception 'No tenés permiso para aprobar recetas.';
    end if;
    if public.rol_actual() <> 'control_calidad' then
        raise exception 'Este visto bueno lo da Control de Calidad.';
    end if;
    select * into v_r from public.jarabes_recetas where id = p_id for update;
    if not found then raise exception 'La receta no existe.'; end if;
    if v_r.estado <> 'propuesta' then raise exception 'Esta receta ya fue resuelta.'; end if;
    if v_r.aprobada_calidad_por is not null then
        raise exception 'Calidad ya dio su visto bueno a esta receta.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.jarabes_recetas
       set aprobada_calidad_por = auth.uid(), aprobada_calidad_nombre = v_nombre,
           aprobada_calidad_en = now()
     where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Visto bueno de Producción.
-- ---------------------------------------------------------------------
create or replace function public.jarabes_receta_aprobar_produccion(p_id bigint) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.jarabes_recetas; v_nombre text;
begin
    if not public.tiene_permiso('recetas', 'aprobar') then
        raise exception 'No tenés permiso para aprobar recetas.';
    end if;
    if public.rol_actual() <> 'jefe_produccion' then
        raise exception 'Este visto bueno lo da Jefe de Producción.';
    end if;
    select * into v_r from public.jarabes_recetas where id = p_id for update;
    if not found then raise exception 'La receta no existe.'; end if;
    if v_r.estado <> 'propuesta' then raise exception 'Esta receta ya fue resuelta.'; end if;
    if v_r.aprobada_produccion_por is not null then
        raise exception 'Producción ya dio su visto bueno a esta receta.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.jarabes_recetas
       set aprobada_produccion_por = auth.uid(), aprobada_produccion_nombre = v_nombre,
           aprobada_produccion_en = now()
     where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. El Gerente confirma con su clave: recién acá la receta queda activa
--    (y la anterior activa de ese sabor pasa a inactiva), igual que antes.
-- ---------------------------------------------------------------------
create or replace function public.jarabes_receta_confirmar_gerente(p_id bigint, p_clave text) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_r public.jarabes_recetas; v_nombre text;
begin
    if not public.tiene_permiso('recetas', 'aprobar') then
        raise exception 'No tenés permiso para aprobar recetas.';
    end if;
    if public.rol_actual() <> 'gerente' then
        raise exception 'Solo el Gerente confirma el cambio de receta.';
    end if;
    if not public._verificar_clave_actual(p_clave) then
        raise exception 'Clave incorrecta.';
    end if;

    select * into v_r from public.jarabes_recetas where id = p_id for update;
    if not found then raise exception 'La receta no existe.'; end if;
    if v_r.estado <> 'propuesta' then raise exception 'Esta receta ya fue resuelta.'; end if;
    if v_r.aprobada_calidad_por is null then
        raise exception 'Todavía falta el visto bueno de Control de Calidad.';
    end if;
    if v_r.aprobada_produccion_por is null then
        raise exception 'Todavía falta el visto bueno de Jefe de Producción.';
    end if;

    select nombre_completo into v_nombre from public.usuarios where id = auth.uid();
    update public.jarabes_recetas set estado = 'inactiva'
     where sabor_id = v_r.sabor_id and estado = 'activa';
    update public.jarabes_recetas
       set estado = 'activa', aprobada_por = auth.uid(), aprobada_por_nombre = v_nombre, aprobada_en = now()
     where id = p_id;
end;
$$;

revoke all on function public.jarabes_receta_aprobar_calidad(bigint) from public;
revoke all on function public.jarabes_receta_aprobar_produccion(bigint) from public;
revoke all on function public.jarabes_receta_confirmar_gerente(bigint, text) from public;
grant execute on function public.jarabes_receta_aprobar_calidad(bigint) to authenticated;
grant execute on function public.jarabes_receta_aprobar_produccion(bigint) to authenticated;
grant execute on function public.jarabes_receta_confirmar_gerente(bigint, text) to authenticated;

-- `jarabes_receta_rechazar` (v26) no cambia: cualquiera de los tres roles
-- con 'recetas':'aprobar' puede rechazar en cualquier momento de este
-- proceso, con motivo obligatorio — eso ya funcionaba y sigue igual.
