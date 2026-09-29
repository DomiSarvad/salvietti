-- =====================================================================
-- SALVIETTI CONTROL — v22: arregla "stack depth limit exceeded" al iniciar
-- sesión (con CUALQUIER usuario). Ejecutar YA en el SQL Editor de Supabase,
-- sin esperar a nada más. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Causa: rol_actual() consulta la tabla `usuarios`, y esa tabla tiene una
-- política ("ver_propio_usuario") que para decidir si mostrar una fila
-- vuelve a llamar a rol_actual() -> vuelve a consultar `usuarios` -> ida y
-- vuelta sin fin. Con pocas políticas dependiendo de rol_actual() (como al
-- principio del proyecto) nunca llegaba a notarse; con las decenas que se
-- sumaron en v16-v21 el círculo se volvió lo bastante profundo como para
-- agotar la pila de Postgres.
--
-- Arreglo: rol_actual() pasa a ser `security definer`, así que al leer la
-- fila de usuarios NO vuelve a aplicar la política de la tabla (deja de
-- necesitar preguntarse el rol para poder... preguntarse el rol). Sigue
-- devolviendo únicamente el rol de quien llama (auth.uid()): no expone
-- datos de otros usuarios.

create or replace function public.rol_actual() returns text
language sql stable security definer
set search_path = public, pg_temp
as $$
    select rol from public.usuarios where id = auth.uid() and activo;
$$;
