-- =====================================================================
-- v44 · Arregla "function gen_salt(unknown) does not exist" al crear usuarios
--
-- En Supabase la extensión pgcrypto (crypt, gen_salt) está instalada en el
-- esquema `extensions`, no en `public`. Las funciones `security definer` que
-- la usan fijan su propio search_path (`public, auth, pg_temp`, por seguridad)
-- y por eso no la encontraban:
--   * crear_usuario_admin (v16): "Nuevo usuario" fallaba con ese error.
--   * _verificar_clave_actual (v37): la confirmación de recetas del Gerente
--     (vuelve a pedir su contraseña) fallaba con el mismo error.
--
-- No hace falta reescribirlas: se les agrega `extensions` al search_path.
-- Sigue siendo una lista fija y explícita (no se hereda la del usuario), así
-- que no se pierde la protección que da fijarlo. Re-ejecutable.
-- (v16 y v37 también quedaron corregidos, por si se vuelven a ejecutar.)
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

alter function public.crear_usuario_admin(text, text, text, text, text)
    set search_path = public, auth, extensions, pg_temp;

alter function public._verificar_clave_actual(text)
    set search_path = public, auth, extensions, pg_temp;
