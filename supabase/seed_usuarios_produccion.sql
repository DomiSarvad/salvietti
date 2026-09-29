-- =====================================================================
-- SALVIETTI CONTROL — cuentas iniciales de cada rol de Producción.
-- Ejecutar en el SQL Editor de Supabase. Se puede volver a ejecutar:
-- si un correo ya existe NO se toca (ni su contraseña ni su rol).
-- =====================================================================
--
-- Mismo mecanismo que v8 (crea el usuario ya confirmado, sin pasar por
-- auth.signUp). Los correos @salvietti.local son MARCADORES: no existen de
-- verdad. Las contraseñas son TEMPORALES (6 a 10 caracteres, como exige la
-- app): cada persona debe cambiarla en su primer ingreso desde "Mi perfil".

do $$
declare
    v_uid uuid;
    v_cuentas jsonb := '[
        {"email":"gerente@salvietti.local",   "password":"Gerente26",   "nombre":"Gerente General",        "rol":"gerente"},
        {"email":"ingeniero@salvietti.local", "password":"Ingenio26",   "nombre":"Jefe de Producción",     "rol":"jefe_produccion"},
        {"email":"almacen@salvietti.local",   "password":"Almacen26",   "nombre":"Encargado de Almacén",   "rol":"almacen"},
        {"email":"jarabes@salvietti.local",   "password":"Jarabes26",   "nombre":"Jefe de Jarabes",        "rol":"jarabes"},
        {"email":"ayudante@salvietti.local",  "password":"Ayudante26",  "nombre":"Ayudante de Jarabes",    "rol":"ayudante_jarabes"},
        {"email":"soplado@salvietti.local",   "password":"Soplado26",   "nombre":"Operador de Soplado",    "rol":"soplado"},
        {"email":"llenadora@salvietti.local", "password":"Llenado26",   "nombre":"Operador de Llenadora",  "rol":"llenadora"},
        {"email":"codificacion@salvietti.local","password":"Codifi26",  "nombre":"Operador de Codificación","rol":"codificacion"},
        {"email":"salidas@salvietti.local",   "password":"Salidas26",   "nombre":"Registro de Salidas",    "rol":"registro_salidas"},
        {"email":"calidad@salvietti.local",   "password":"Calidad26",   "nombre":"Control de Calidad",     "rol":"control_calidad"},
        {"email":"soda@salvietti.local",      "password":"Soda2026",    "nombre":"Soda Cáustica",          "rol":"soda_caustica"}
    ]'::jsonb;
    v_cuenta jsonb;
begin
    for v_cuenta in select * from jsonb_array_elements(v_cuentas)
    loop
        if exists (select 1 from auth.users where email = v_cuenta->>'email') then
            continue;
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

-- Quién quedó en el sistema (solo lectura).
select u.email, us.nombre_completo, us.rol, us.activo,
       il.fallos, il.bloqueado_hasta
  from auth.users u
  join public.usuarios us on us.id = u.id
  left join public.intentos_login il on il.email = lower(u.email)
 order by us.rol, u.email;
