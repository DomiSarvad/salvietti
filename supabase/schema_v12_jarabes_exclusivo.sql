-- =====================================================================
-- SALVIETTI CONTROL — v12: Jarabes es exclusiva del área de Jarabes.
-- Ejecutar DESPUÉS de schema_v7_permisos_roles.sql, en el SQL Editor de
-- Supabase.
-- =====================================================================
--
--  jarabes  -> único rol que edita los ítems de materia prima marcados
--              área = 'jarabes' y registra sus movimientos.
--  almacen  -> sigue controlando Tapas, Preformas y la materia prima
--              general (área nula), pero YA NO puede modificar Jarabes.
--  El resto de los roles (gerente, jefe_produccion) queda igual.

-- Materia prima: alta y edición.
drop policy if exists "escritura_mp" on public.materia_prima;
create policy "escritura_mp" on public.materia_prima for insert
    with check (
        (public.rol_actual() = 'almacen' and area is distinct from 'jarabes')
        or (public.rol_actual() = 'jarabes' and area = 'jarabes')
    );

drop policy if exists "edicion_mp" on public.materia_prima;
create policy "edicion_mp" on public.materia_prima for update
    using (
        (public.rol_actual() = 'almacen' and area is distinct from 'jarabes')
        or (public.rol_actual() = 'jarabes' and area = 'jarabes')
    )
    with check (
        (public.rol_actual() = 'almacen' and area is distinct from 'jarabes')
        or (public.rol_actual() = 'jarabes' and area = 'jarabes')
    );

-- Movimientos manuales (entradas/salidas/ajustes): Almacén en todo menos
-- Jarabes; Jarabes solo sobre su propia materia prima.
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
            public.rol_actual() = 'jarabes'
            and tabla_origen = 'materia_prima'
            and exists (
                select 1 from public.materia_prima mp
                where mp.id = item_id and mp.area = 'jarabes'
            )
        )
    );
