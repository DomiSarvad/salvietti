-- =====================================================================
-- SALVIETTI CONTROL — v9: deshacer movimientos recientes con seguridad.
-- Ejecutar DESPUÉS de schema_v7_permisos_roles.sql, en el SQL Editor
-- de Supabase.
-- =====================================================================
--
-- Problema real: un movimiento con una cantidad enorme (típicamente un
-- error de tipeo) puede dejar en 0 el stock de un ítem sin que haya
-- forma de corregirlo salvo editando el stock a mano (lo que rompe el
-- kardex). La solución NO es borrar el movimiento original —eso dejaría
-- el historial incompleto, algo que este sistema evita en todos lados
-- (bitácora de eliminaciones, borrado siempre lógico)— sino insertar un
-- ajuste que revierte exactamente su efecto. Ese ajuste queda vinculado
-- al original mediante esta columna, para poder mostrar "ya deshecho"
-- en la UI y no permitir revertirlo dos veces.
--
-- La app (no esta migración) es la que limita "Deshacer" a movimientos
-- cuya cantidad sea chica en relación al stock actual del ítem —
-- precisamente para que un movimiento gigante como el del incidente NO
-- se pueda deshacer con un clic, evitando que alguien maquille un error
-- grande en vez de corregirlo con un ajuste manual revisado.

alter table public.movimientos
    add column if not exists revierte_movimiento_id uuid references public.movimientos(id);

comment on column public.movimientos.revierte_movimiento_id is
    'Si esta fila es un ajuste que "deshace" otro movimiento, apunta al movimiento original revertido.';
