-- =====================================================================
-- SALVIETTI CONTROL — v16: roles según el organigrama de Producción.
-- Ejecutar DESPUÉS de schema_v14_roles_y_edicion_usuarios.sql, en el SQL
-- Editor de Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Roles nuevos (se suman a almacen, gerente, jefe_produccion, jarabes):
--   ayudante_jarabes  -> mismo alcance que 'jarabes' sobre su inventario.
--   control_calidad, soplado, codificacion, llenadora, registro_salidas,
--   soda_caustica     -> por ahora solo lectura; sus permisos propios se
--                        agregan con el módulo de cada área.
--
-- 'jarabes' pasa a ser "Jefe de Jarabes" (mismo id, no se migra ningún dato).

-- Lista única de roles válidos: la usan el constraint y las funciones.
create or replace function public.rol_valido(p_rol text) returns boolean
language sql immutable as $$
    select p_rol in (
        'almacen', 'gerente', 'jefe_produccion', 'jarabes', 'ayudante_jarabes',
        'control_calidad', 'soplado', 'codificacion', 'llenadora',
        'registro_salidas', 'soda_caustica'
    );
$$;

-- Jefe y Ayudante de Jarabes comparten permisos sobre el área Jarabes.
create or replace function public.es_rol_jarabes() returns boolean
language sql stable as $$
    select public.rol_actual() in ('jarabes', 'ayudante_jarabes');
$$;

-- ---------------------------------------------------------------------
-- Constraint de la tabla usuarios (se busca por definición, no por nombre).
-- ---------------------------------------------------------------------
do $$
declare c text;
begin
    for c in
        select conname from pg_constraint
         where conrelid = 'public.usuarios'::regclass
           and contype = 'c'
           and pg_get_constraintdef(oid) ilike '%rol = any%'
    loop
        execute format('alter table public.usuarios drop constraint %I', c);
    end loop;
end $$;

alter table public.usuarios drop constraint if exists usuarios_rol_check;
alter table public.usuarios
    add constraint usuarios_rol_check check (public.rol_valido(rol));

-- ---------------------------------------------------------------------
-- Alta de usuarios (misma función de v3, con la lista nueva de roles).
-- ---------------------------------------------------------------------
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

    if not public.rol_valido(p_rol) then
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
-- Edición de usuarios (misma función de v14, con la lista nueva de roles).
-- ---------------------------------------------------------------------
create or replace function public.editar_usuario_admin(
    p_id uuid,
    p_email text,
    p_nombre_completo text,
    p_rol text,
    p_area text default null,
    p_activo boolean default true
) returns void
language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_email text := lower(trim(p_email));
begin
    if public.rol_actual() is distinct from 'gerente' then
        raise exception 'Solo el Gerente puede editar usuarios.';
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
    if not public.rol_valido(p_rol) then
        raise exception 'Rol inválido.';
    end if;
    if not exists (select 1 from public.usuarios where id = p_id) then
        raise exception 'El usuario no existe.';
    end if;
    if exists (select 1 from auth.users where email = v_email and id <> p_id) then
        raise exception 'Ya existe otra cuenta con ese correo.';
    end if;

    -- El Gerente no se puede quitar a sí mismo el rol ni desactivarse
    -- (quedaría sin nadie que administre los usuarios).
    if p_id = auth.uid() and (p_rol <> 'gerente' or not coalesce(p_activo, true)) then
        raise exception 'No podés quitarte el rol de Gerente ni desactivar tu propia cuenta.';
    end if;

    update auth.users
       set email = v_email, updated_at = now()
     where id = p_id and email is distinct from v_email;

    update auth.identities
       set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(v_email)),
           updated_at = now()
     where user_id = p_id and provider = 'email';

    update public.usuarios
       set nombre_completo = trim(p_nombre_completo),
           rol = p_rol,
           area = case when p_rol in ('jarabes', 'ayudante_jarabes')
                       then nullif(trim(coalesce(p_area, '')), '') else null end,
           activo = coalesce(p_activo, true)
     where id = p_id;

    insert into public.bitacora_acciones(usuario_id, accion, tabla_afectada, registro_id, detalle)
    values (auth.uid(), 'editar_usuario', 'usuarios', p_id,
            jsonb_build_object('correo', v_email, 'rol', p_rol, 'activo', coalesce(p_activo, true)));
end;
$$;
grant execute on function public.editar_usuario_admin(uuid, text, text, text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- Área Jarabes: el Ayudante tiene los mismos permisos que el Jefe
-- (políticas de v12 con es_rol_jarabes() en lugar de rol = 'jarabes').
-- ---------------------------------------------------------------------
drop policy if exists "escritura_mp" on public.materia_prima;
create policy "escritura_mp" on public.materia_prima for insert
    with check (
        (public.rol_actual() = 'almacen' and area is distinct from 'jarabes')
        or (public.es_rol_jarabes() and area = 'jarabes')
    );

drop policy if exists "edicion_mp" on public.materia_prima;
create policy "edicion_mp" on public.materia_prima for update
    using (
        (public.rol_actual() = 'almacen' and area is distinct from 'jarabes')
        or (public.es_rol_jarabes() and area = 'jarabes')
    )
    with check (
        (public.rol_actual() = 'almacen' and area is distinct from 'jarabes')
        or (public.es_rol_jarabes() and area = 'jarabes')
    );

drop policy if exists "crear_movimientos" on public.movimientos;
create policy "crear_movimientos" on public.movimientos for insert
    with check (
        (
            public.rol_actual() = 'almacen'
            and (
                tabla_origen <> 'materia_prima'
                or not exists (
                    select 1 from public.materia_prima mp
                    where mp.id = item_id and mp.area = 'jarabes'
                )
            )
        )
        or (
            public.es_rol_jarabes()
            and tabla_origen = 'materia_prima'
            and exists (
                select 1 from public.materia_prima mp
                where mp.id = item_id and mp.area = 'jarabes'
            )
        )
    );
