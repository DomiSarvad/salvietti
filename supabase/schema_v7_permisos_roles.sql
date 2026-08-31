-- =====================================================================
-- SALVIETTI CONTROL — v7: permisos definitivos por rol.
-- Ejecutar DESPUÉS de schema.sql y schema_v6_productos_terminados.sql,
-- en el SQL Editor de Supabase.
-- =====================================================================
--
--  almacen          -> control total: única con permiso sobre tapas y
--                      preformas; sobre materia prima, control total.
--  jarabes          -> solo sobre la materia prima marcada como su área
--                      (columna nueva `area`). No edita tapas/preformas.
--  jefe_produccion  -> deja de editar el catálogo de inventario. Su
--                      única función de edición es la planificación de
--                      producción del día (es el ÚNICO que la edita).
--  gerente          -> solo observación (sin cambios aquí).

alter table public.materia_prima add column if not exists area text;
comment on column public.materia_prima.area is
    'null = general (Almacén). ''jarabes'' = insumo del área de Jarabes, que solo esa área puede editar.';

-- ---------------------------------------------------------------------
-- Tapas / Preformas: solo Almacén.
-- ---------------------------------------------------------------------
drop policy if exists "escritura_tapas" on public.tapas;
create policy "escritura_tapas" on public.tapas for insert
    with check (public.rol_actual() = 'almacen');
drop policy if exists "edicion_tapas" on public.tapas;
create policy "edicion_tapas" on public.tapas for update
    using (public.rol_actual() = 'almacen');

drop policy if exists "escritura_preformas" on public.preformas;
create policy "escritura_preformas" on public.preformas for insert
    with check (public.rol_actual() = 'almacen');
drop policy if exists "edicion_preformas" on public.preformas;
create policy "edicion_preformas" on public.preformas for update
    using (public.rol_actual() = 'almacen');

-- ---------------------------------------------------------------------
-- Materia prima: Almacén (cualquier fila) o Jarabes (solo su área).
-- ---------------------------------------------------------------------
drop policy if exists "escritura_mp" on public.materia_prima;
create policy "escritura_mp" on public.materia_prima for insert
    with check (
        public.rol_actual() = 'almacen'
        or (public.rol_actual() = 'jarabes' and area = 'jarabes')
    );
drop policy if exists "edicion_mp" on public.materia_prima;
create policy "edicion_mp" on public.materia_prima for update
    using (
        public.rol_actual() = 'almacen'
        or (public.rol_actual() = 'jarabes' and area = 'jarabes')
    )
    with check (
        public.rol_actual() = 'almacen'
        or (public.rol_actual() = 'jarabes' and area = 'jarabes')
    );

-- ---------------------------------------------------------------------
-- Movimientos manuales (entradas/salidas): Almacén (cualquier ítem) o
-- Jarabes (solo materia prima de su área). Jefe de Producción ya no
-- registra movimientos manuales — su impacto en stock es siempre a
-- través del trigger de producción al marcar un producto como hecho.
-- ---------------------------------------------------------------------
drop policy if exists "crear_movimientos" on public.movimientos;
create policy "crear_movimientos" on public.movimientos for insert
    with check (
        public.rol_actual() = 'almacen'
        or (
            public.rol_actual() = 'jarabes'
            and tabla_origen = 'materia_prima'
            and exists (
                select 1 from public.materia_prima mp
                where mp.id = item_id and mp.area = 'jarabes'
            )
        )
    );

-- ---------------------------------------------------------------------
-- Plan de producción: únicamente Jefe de Producción lo edita.
-- ---------------------------------------------------------------------
drop policy if exists "gestion_plan" on public.plan_produccion;
create policy "gestion_plan" on public.plan_produccion for all
    using (public.rol_actual() = 'jefe_produccion')
    with check (public.rol_actual() = 'jefe_produccion');

drop policy if exists "gestion_plan_detalle" on public.plan_produccion_detalle;
create policy "gestion_plan_detalle" on public.plan_produccion_detalle for all
    using (public.rol_actual() = 'jefe_produccion')
    with check (public.rol_actual() = 'jefe_produccion');

-- gestion_formulas / gestion_formula_detalle quedan sin cambios
-- (almacén + jefe_produccion siguen definiendo las recetas/fichas técnicas).
