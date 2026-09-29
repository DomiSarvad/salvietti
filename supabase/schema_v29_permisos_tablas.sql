-- =====================================================================
-- SALVIETTI CONTROL — v29: permisos de tabla para el rol `authenticated`.
-- Ejecutar en el SQL Editor de Supabase. (Se puede volver a ejecutar sin
-- problema; conviene correrlo de nuevo cada vez que se crea una tabla.)
-- =====================================================================
--
-- Síntoma: la app muestra el menú incompleto (sin Almacenes, Recepciones…) y
-- en consola aparece "permission denied for table permisos_rol (42501)".
--
-- Causa: en Supabase, una tabla creada por SQL puede quedar SIN el privilegio
-- de tabla para `authenticated`. Las políticas RLS deciden QUÉ FILAS ve o
-- toca cada usuario, pero antes de evaluarlas Postgres exige este privilegio
-- de tabla: sin él, nada llega a las políticas y todo da 42501.
--
-- Este script da el privilegio de tabla SOLO a las tablas que tienen RLS
-- activado (el servidor sigue mandando: lo que la política no permite, sigue
-- sin permitirse). Una tabla sin RLS se deja sin abrir y se avisa. Las
-- vistas reciben solo lectura (son security_invoker: aplican el RLS de las
-- tablas que leen). `anon` no recibe nada.

grant usage on schema public to authenticated;

do $$
declare r record;
begin
    for r in
        select c.relname, c.relkind, c.relrowsecurity
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind in ('r', 'p', 'v')
    loop
        if r.relkind = 'v' then
            execute format('grant select on public.%I to authenticated', r.relname);
        elsif r.relrowsecurity then
            execute format('grant select, insert, update, delete on public.%I to authenticated', r.relname);
        else
            raise notice 'Tabla SIN RLS, no se abre: %', r.relname;
        end if;
    end loop;
end $$;

-- Las columnas identity necesitan su secuencia para poder insertar.
grant usage, select on all sequences in schema public to authenticated;

-- Control: tablas que quedaron sin RLS (deberían ser ninguna, o solo las
-- que no se usan desde la app).
select c.relname as tabla_sin_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
 order by 1;
