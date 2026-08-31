-- =====================================================================
-- SALVIETTI CONTROL — v3: alta de usuarios segura + permisos de Gerente
-- Ejecutar DESPUÉS de schema.sql, en el SQL Editor de Supabase.
-- =====================================================================
--
-- Problema que resuelve:
-- La app creaba usuarios nuevos con `auth.signUp()` desde el cliente.
-- Eso tiene dos fallas:
--   1) Si el proyecto exige confirmar el correo, la cuenta queda sin
--      confirmar y esa persona nunca puede iniciar sesión.
--   2) `signUp()` reemplaza la sesión activa del dispositivo por la del
--      usuario recién creado, así que el Gerente termina "deslogueado"
--      de su propia cuenta.
--
-- Esta función crea el usuario directamente en el servidor, ya
-- confirmado, sin tocar la sesión de quien la ejecuta. Solo la puede
-- ejecutar quien tenga rol 'gerente' (se valida en el propio servidor,
-- no solo en la app).

create or replace function public.crear_usuario_admin(
    p_email text,
    p_password text,
    p_nombre_completo text,
    p_rol text,
    p_area text default null
) returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_uid uuid;
    v_email text := lower(trim(p_email));
begin
    if public.rol_actual() is distinct from 'gerente' then
        raise exception 'Solo el Gerente puede crear usuarios.';
    end if;

    if p_nombre_completo is null or length(trim(p_nombre_completo)) = 0 then
        raise exception 'El nombre completo es obligatorio.';
    end if;
    if length(p_nombre_completo) > 120 then
        raise exception 'El nombre completo es demasiado largo.';
    end if;

    if v_email !~ '^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$' then
        raise exception 'El correo no tiene un formato válido.';
    end if;

    if p_password is null or length(p_password) < 6 then
        raise exception 'La contraseña debe tener al menos 6 caracteres.';
    end if;
    if length(p_password) > 10 then
        raise exception 'La contraseña es demasiado larga (máx. 10 caracteres).';
    end if;

    if p_rol not in ('almacen','gerente','jefe_produccion','jarabes') then
        raise exception 'Rol inválido.';
    end if;

    if exists (select 1 from auth.users where email = v_email) then
        raise exception 'Ya existe una cuenta con ese correo.';
    end if;

    v_uid := gen_random_uuid();

    insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
        '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
        v_email, crypt(p_password, gen_salt('bf')),
        now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
        now(), now(),
        '', '', '', ''
    );

    insert into auth.identities (
        id, user_id, provider_id, identity_data, provider,
        last_sign_in_at, created_at, updated_at
    ) values (
        gen_random_uuid(), v_uid, v_uid::text,
        jsonb_build_object('sub', v_uid::text, 'email', v_email),
        'email', now(), now(), now()
    );

    insert into public.usuarios (id, nombre_completo, rol, area, activo, creado_por)
    values (v_uid, trim(p_nombre_completo), p_rol, p_area, true, auth.uid());

    return v_uid;
end;
$$;

grant execute on function public.crear_usuario_admin(text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Ahora que la creación pasa por la función de arriba (que ya valida el
-- rol), solo Gerente administra la tabla usuarios; Almacén y el resto
-- únicamente pueden verla (política "ver_propio_usuario" sin cambios).
-- ---------------------------------------------------------------------
drop policy if exists "crear_usuarios" on public.usuarios;
create policy "crear_usuarios" on public.usuarios for insert with check (public.rol_actual() = 'gerente');

drop policy if exists "editar_usuarios" on public.usuarios;
create policy "editar_usuarios" on public.usuarios for update using (public.rol_actual() = 'gerente');
