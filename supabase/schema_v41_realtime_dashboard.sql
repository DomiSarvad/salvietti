-- =====================================================================
-- SALVIETTI CONTROL — v41: tiempo real para el Inicio (Dashboard).
-- Ejecutar en el SQL Editor de Supabase. Se puede volver a ejecutar sin
-- problema (no duplica nada).
-- =====================================================================
--
-- El Inicio necesita enterarse solo, sin que alguien apriete "actualizar",
-- cuando cambia el stock (cualquier movimiento) o una merma. Para eso la
-- app se suscribe con Supabase Realtime a estas tablas — pero Realtime
-- solo manda cambios de una tabla si esa tabla está agregada a la
-- publicación `supabase_realtime` (se crea sola cuando el proyecto tiene
-- Realtime habilitado). `alter publication ... add table` falla si la
-- tabla ya está agregada, así que se hace con un chequeo primero.

do $$
declare
    t text;
begin
    foreach t in array array[
        'inv_movimientos',
        'mermas_registros',
        'mermas_causas',
        'llenadora_corridas',
        'soplado_corridas',
        'codificacion_corridas'
    ]
    loop
        if not exists (
            select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
        ) then
            execute format('alter publication supabase_realtime add table public.%I', t);
        end if;
    end loop;
end $$;

-- Nada más que agregar acá: RLS + los grants de v29 ya alcanzan para que
-- Realtime solo mande a cada usuario lo que su rol puede leer.
