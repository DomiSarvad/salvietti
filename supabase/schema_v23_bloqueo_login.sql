-- =====================================================================
-- SALVIETTI CONTROL — v23: bloqueo escalonado de inicio de sesión.
-- Ejecutar DESPUÉS de schema_v22_fix_recursion_login.sql, en el SQL Editor
-- de Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Antes, el conteo de intentos fallidos vivía en la memoria de la app: se
-- reiniciaba solo con cerrar y volver a abrir, y no protegía si probaban
-- desde otro dispositivo. Ahora vive en el servidor, por correo:
--
--   5 fallos  -> bloqueo de 30 segundos
--   10 fallos -> bloqueo de 2 minutos
--   15 fallos -> bloqueo de 10 minutos
--   20 fallos -> bloqueo de 30 minutos
--   25 fallos -> bloqueo PERMANENTE: solo el Gerente lo levanta.
--
-- Como el login pasa por Supabase Auth (no por nuestras tablas), este
-- control se hace con funciones que la app llama ANTES y DESPUÉS de cada
-- intento — necesitan poder ejecutarse sin sesión (rol anon), por eso la
-- tabla no tiene ninguna política: nadie la toca directo, todo pasa por
-- estas funciones.

create table if not exists public.intentos_login (
    email text primary key,
    fallos int not null default 0,
    ciclos_bloqueo int not null default 0,
    bloqueado_hasta timestamptz,
    actualizado_en timestamptz not null default now()
);
alter table public.intentos_login enable row level security;

-- ---------------------------------------------------------------------
-- Estado actual para ese correo (no cambia nada). La llama la app antes
-- de intentar entrar, para no gastar el intento si ya está bloqueado.
-- ---------------------------------------------------------------------
create or replace function public.intentos_login_estado(p_email text) returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v public.intentos_login;
    v_encontrado boolean;
begin
    select * into v from public.intentos_login where email = lower(trim(p_email));
    v_encontrado := found;

    if not v_encontrado or v.bloqueado_hasta is null or v.bloqueado_hasta <= now() then
        return jsonb_build_object(
            'permitido', true, 'permanente', false, 'espera_segundos', 0,
            'intentos_restantes', case when v_encontrado then greatest(1, 5 - (v.fallos % 5)) else 5 end
        );
    end if;

    if v.bloqueado_hasta = 'infinity'::timestamptz then
        return jsonb_build_object(
            'permitido', false, 'permanente', true, 'espera_segundos', 0, 'intentos_restantes', 0
        );
    end if;

    return jsonb_build_object(
        'permitido', false, 'permanente', false,
        'espera_segundos', ceil(extract(epoch from (v.bloqueado_hasta - now()))),
        'intentos_restantes', 0
    );
end;
$$;

-- ---------------------------------------------------------------------
-- Registra un intento fallido y devuelve el mismo estado de arriba, ya
-- actualizado. Si ya estaba bloqueado no extiende el reloj (evita que
-- reintentar durante el bloqueo lo alargue sin fin).
-- ---------------------------------------------------------------------
create or replace function public.intentos_login_registrar_fallo(p_email text) returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
    v_email text := lower(trim(p_email));
    v public.intentos_login;
    v_duraciones int[] := array[30, 120, 600, 1800]; -- 30s, 2min, 10min, 30min
begin
    if coalesce(v_email, '') = '' then
        raise exception 'Correo inválido.';
    end if;

    insert into public.intentos_login (email) values (v_email)
        on conflict (email) do nothing;
    select * into v from public.intentos_login where email = v_email for update;

    if v.bloqueado_hasta is not null and v.bloqueado_hasta > now() then
        return public.intentos_login_estado(v_email);
    end if;

    update public.intentos_login set fallos = fallos + 1, actualizado_en = now()
     where email = v_email returning * into v;

    if v.fallos % 5 = 0 then
        update public.intentos_login set ciclos_bloqueo = ciclos_bloqueo + 1
         where email = v_email returning * into v;
        update public.intentos_login
           set bloqueado_hasta = case
               when v.ciclos_bloqueo <= array_length(v_duraciones, 1)
                   then now() + make_interval(secs => v_duraciones[v.ciclos_bloqueo])
               else 'infinity'::timestamptz
           end
         where email = v_email;
    end if;

    return public.intentos_login_estado(v_email);
end;
$$;

-- Un ingreso correcto limpia el historial de intentos de ese correo.
create or replace function public.intentos_login_registrar_exito(p_email text) returns void
language sql security definer
set search_path = public, pg_temp
as $$
    delete from public.intentos_login where email = lower(trim(p_email));
$$;

-- ---------------------------------------------------------------------
-- Solo el Gerente: desbloquear una cuenta, y ver cuáles están bloqueadas
-- ahora mismo (para mostrarlo en "Usuarios").
-- ---------------------------------------------------------------------
create or replace function public.intentos_login_desbloquear(p_email text) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_email text := lower(trim(p_email));
begin
    if public.rol_actual() is distinct from 'gerente' then
        raise exception 'Solo el Gerente puede desbloquear un acceso.';
    end if;
    delete from public.intentos_login where email = v_email;
    insert into public.bitacora_acciones (usuario_id, accion, tabla_afectada, detalle)
    values (auth.uid(), 'desbloquear_login', 'intentos_login', jsonb_build_object('correo', v_email));
end;
$$;

create or replace function public.intentos_login_bloqueadas()
returns table (correo text, nombre_completo text, permanente boolean, bloqueado_hasta timestamptz)
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
    if public.rol_actual() is distinct from 'gerente' then
        raise exception 'Solo el Gerente puede ver esto.';
    end if;
    return query
        select il.email, u.nombre_completo,
               il.bloqueado_hasta = 'infinity'::timestamptz, il.bloqueado_hasta
          from public.intentos_login il
          left join auth.users au on au.email = il.email
          left join public.usuarios u on u.id = au.id
         where il.bloqueado_hasta is not null and il.bloqueado_hasta > now()
         order by il.bloqueado_hasta desc;
end;
$$;

revoke all on function public.intentos_login_estado(text) from public;
revoke all on function public.intentos_login_registrar_fallo(text) from public;
revoke all on function public.intentos_login_registrar_exito(text) from public;
revoke all on function public.intentos_login_desbloquear(text) from public;
revoke all on function public.intentos_login_bloqueadas() from public;

-- estado/registrar_* deben poder llamarse SIN sesión (todavía no se
-- inició sesión cuando se usan): por eso incluyen 'anon'.
grant execute on function public.intentos_login_estado(text) to anon, authenticated;
grant execute on function public.intentos_login_registrar_fallo(text) to anon, authenticated;
grant execute on function public.intentos_login_registrar_exito(text) to anon, authenticated;
grant execute on function public.intentos_login_desbloquear(text) to authenticated;
grant execute on function public.intentos_login_bloqueadas() to authenticated;
