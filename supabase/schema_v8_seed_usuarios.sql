-- =====================================================================
-- SALVIETTI CONTROL — v8: cuentas iniciales de Gerente, Jarabes y Jefe
-- de Producción (marcador de posición).
-- Ejecutar UNA VEZ, DESPUÉS de schema_v7_permisos_roles.sql, en el SQL
-- Editor de Supabase.
-- =====================================================================
--
-- Mismo mecanismo que `crear_usuario_admin` (crea el usuario ya
-- confirmado, sin pasar por auth.signUp), pero sin exigir que quien lo
-- ejecuta sea Gerente, porque todavía no existe ninguno — este script
-- ES la forma de crear al primer Gerente.
--
-- Los 3 correos son MARCADORES DE POSICIÓN (@salvietti.local, no
-- existen de verdad). Reemplácenlos por los reales apenas los tengan:
-- el Gerente puede editar su propio correo desde "Mi perfil", y puede
-- dar de alta a Jarabes/Ingeniero de nuevo con el correo correcto desde
-- "Usuarios" (y luego desactivar/borrar lógicamente estas cuentas de
-- prueba). Cambien la contraseña desde "Mi perfil" en el primer ingreso.

do $$
declare
    v_uid uuid;
    v_cuentas jsonb := '[
        {"email":"gerente@salvietti.local","password":"Gerente26","nombre":"Gerente General","rol":"gerente"},
        {"email":"jarabes@salvietti.local","password":"Jarabes26","nombre":"Encargado de Jarabes","rol":"jarabes"},
        {"email":"ingeniero@salvietti.local","password":"Ingenio26","nombre":"Jefe de Producción","rol":"jefe_produccion"}
    ]'::jsonb;
    v_cuenta jsonb;
begin
    for v_cuenta in select * from jsonb_array_elements(v_cuentas)
    loop
        if exists (select 1 from auth.users where email = v_cuenta->>'email') then
            continue; -- ya existe, no lo recrea (script idempotente)
        end if;

        v_uid := gen_random_uuid();

        insert into auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at,
            confirmation_token, recovery_token, email_change_token_new, email_change
        ) values (
            '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
            v_cuenta->>'email', crypt(v_cuenta->>'password', gen_salt('bf')),
            now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
            now(), now(),
            '', '', '', ''
        );

        insert into auth.identities (
            id, user_id, provider_id, identity_data, provider,
            last_sign_in_at, created_at, updated_at
        ) values (
            gen_random_uuid(), v_uid, v_uid::text,
            jsonb_build_object('sub', v_uid::text, 'email', v_cuenta->>'email'),
            'email', now(), now(), now()
        );

        insert into public.usuarios (id, nombre_completo, rol, activo)
        values (v_uid, v_cuenta->>'nombre', v_cuenta->>'rol', true);
    end loop;
end $$;

-- Credenciales para el primer ingreso (recuerden cambiarlas):
select email, 'Gerente26 / Jarabes26 / Ingenio26 según el correo' as contraseña_temporal
from auth.users
where email in ('gerente@salvietti.local','jarabes@salvietti.local','ingeniero@salvietti.local');
