-- =====================================================================
-- SALVIETTI CONTROL — v13: importación de movimientos desde Excel.
-- Ejecutar DESPUÉS de schema.sql, en el SQL Editor de Supabase.
-- =====================================================================
--
-- Permite cargar el historial de movimientos que hoy llevan en Excel:
--  * origen            -> 'manual' (los de siempre) | 'importacion_excel'
--  * solo_historial    -> true = la fila queda en el historial/kardex pero
--                         NO modifica el stock (porque el stock actual ya
--                         se cargó aparte y volver a sumarlo lo duplicaría).
--  * importacion_id    -> agrupa todas las filas de una misma importación.
--
-- Las filas importadas NO escriben una entrada de bitácora por cada fila
-- (serían miles): la app registra una sola entrada resumen por importación.
-- Los duplicados los evita la app con `origen_offline_uuid` (índice único
-- que ya existe), así que volver a importar el mismo Excel no repite nada.

alter table public.movimientos add column if not exists origen text not null default 'manual';
alter table public.movimientos add column if not exists solo_historial boolean not null default false;
alter table public.movimientos add column if not exists importacion_id text;

create index if not exists ix_movimientos_importacion
    on public.movimientos(importacion_id) where importacion_id is not null;

create or replace function public.trg_aplicar_movimiento()
returns trigger language plpgsql as $$
declare
    signo numeric;
begin
    -- Solo historial: se guarda el movimiento pero el stock no cambia.
    if new.solo_historial then
        return new;
    end if;

    signo := case when new.tipo = 'ingreso' then 1
                  when new.tipo in ('salida','produccion') then -1
                  else 1 end; -- 'ajuste' se aplica tal cual (puede ser +/-)

    if new.tabla_origen = 'tapas' then
        update public.tapas set cantidad_real = cantidad_real + (signo * new.cantidad)
            where id = new.item_id;
    elsif new.tabla_origen = 'preformas' then
        update public.preformas set cantidad_real = cantidad_real + (signo * new.cantidad)
            where id = new.item_id;
    elsif new.tabla_origen = 'materia_prima' then
        update public.materia_prima set cantidad_real = cantidad_real + (signo * new.cantidad)
            where id = new.item_id;
    end if;

    if new.origen is distinct from 'importacion_excel' then
        insert into public.bitacora_acciones(usuario_id, accion, tabla_afectada, registro_id, detalle)
        values (new.usuario_id, 'movimiento_' || new.tipo, new.tabla_origen, new.item_id,
                jsonb_build_object('cantidad', new.cantidad, 'movimiento_id', new.id));
    end if;

    return new;
end; $$;
