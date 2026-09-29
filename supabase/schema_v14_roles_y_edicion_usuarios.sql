-- =====================================================================
-- SALVIETTI CONTROL — v14: edición de usuarios por el Gerente.
-- Ejecutar DESPUÉS de schema_v4_perfil.sql, en el SQL Editor de Supabase.
-- (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- * editar_usuario_admin : el Gerente cambia nombre, correo, rol, área y
--                          si la cuenta está activa. El correo vive en la
--                          cuenta de acceso (auth.users), que la app no
--                          puede tocar directamente: por eso va por una
--                          función del servidor que valida que quien la
--                          llama es Gerente.
-- * usuarios_con_correo  : devuelve el correo de cada usuario (solo Gerente).
-- * rol_actual()         : una cuenta desactivada pierde sus permisos
--                          también en el servidor.
--
-- Los roles siguen siendo los 4 de siempre (almacen, gerente,
-- jefe_produccion, jarabes). Crear roles nuevos con permisos propios queda
-- como mejora futura (ver el informe).

-- Un usuario desactivado deja de tener rol para las políticas RLS.
create or replace function public.rol_actual() returns text language sql stable as $$
    select rol from public.usuarios where id = auth.uid() and activo;
$$;

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
    if p_rol not in ('almacen','gerente','jefe_produccion','jarabes') then
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
           area = case when p_rol = 'jarabes' then nullif(trim(coalesce(p_area, '')), '') else null end,
           activo = coalesce(p_activo, true)
     where id = p_id;

    insert into public.bitacora_acciones(usuario_id, accion, tabla_afectada, registro_id, detalle)
    values (auth.uid(), 'editar_usuario', 'usuarios', p_id,
            jsonb_build_object('correo', v_email, 'rol', p_rol, 'activo', coalesce(p_activo, true)));
end;
$$;
grant execute on function public.editar_usuario_admin(uuid, text, text, text, text, boolean) to authenticated;

create or replace function public.usuarios_con_correo()
returns table (id uuid, email text)
language sql stable security definer
set search_path = public, auth, pg_temp
as $$
    select u.id, au.email::text
      from public.usuarios u
      join auth.users au on au.id = u.id
     where public.rol_actual() = 'gerente';
$$;
grant execute on function public.usuarios_con_correo() to authenticated;
