-- =====================================================================
-- SALVIETTI CONTROL — v6: catálogo de Productos Terminados y descuento
-- real de preformas/tapas al completar producción.
-- Ejecutar DESPUÉS de schema.sql, en el SQL Editor de Supabase.
-- =====================================================================
--
-- Hoy el plan de producción se arma por "sabor" y, al marcar completado,
-- solo se descuenta materia prima. En la realidad el Jefe de Producción
-- planifica por PRODUCTO TERMINADO (sabor + tamaño + envase, ej. "2,5 L
-- Papaya - Pett", tal como en el reporte que comparten por WhatsApp), y
-- al terminarlo también se consumen preformas y tapas — una por botella.

create table if not exists public.productos_terminados (
    id uuid primary key default uuid_generate_v4(),
    nombre text unique not null,                 -- '2,5 L Papaya - Pett'
    formula_id uuid not null references public.formulas(id),
    envase text not null check (envase in ('pett','vidrio')),
    litros_por_botella numeric(10,3) not null check (litros_por_botella > 0),
    botellas_por_paquete numeric(10,2),          -- opcional, solo informativo
    preforma_id uuid references public.preformas(id),  -- null si envase = 'vidrio'
    tapa_id uuid not null references public.tapas(id),
    activo boolean not null default true,
    created_at timestamptz not null default now()
);

comment on table public.productos_terminados is
    'Catálogo de productos embotellados (sabor + tamaño + envase). Cada uno define qué preforma y qué tapa consume por botella, y de qué fórmula sale el líquido.';

alter table public.productos_terminados enable row level security;

-- Las políticas de RLS solo filtran FILAS: el rol también necesita el
-- permiso de tabla en sí (GRANT), que las tablas creadas desde el SQL
-- Editor no heredan automáticamente como sí pasa con las creadas desde
-- el dashboard. Sin esto, cualquier insert/update/select da "permission
-- denied for table productos_terminados" aunque la política de RLS esté
-- bien.
grant select, insert, update, delete on public.productos_terminados to authenticated;

drop policy if exists "lectura_general_productos_terminados" on public.productos_terminados;
create policy "lectura_general_productos_terminados" on public.productos_terminados
    for select using (auth.uid() is not null);

drop policy if exists "gestion_productos_terminados" on public.productos_terminados;
create policy "gestion_productos_terminados" on public.productos_terminados for all
    using (public.rol_actual() in ('almacen','jefe_produccion'))
    with check (public.rol_actual() in ('almacen','jefe_produccion'));

-- ---------------------------------------------------------------------
-- El plan del día ahora referencia un producto terminado (no solo un
-- sabor suelto) y registra cuántas botellas se produjeron de verdad y
-- cuánta merma hubo, para poder descontar preformas/tapas con precisión.
-- ---------------------------------------------------------------------
alter table public.plan_produccion_detalle
    add column if not exists producto_terminado_id uuid references public.productos_terminados(id),
    add column if not exists botellas_producidas numeric(12,2),
    add column if not exists merma_litros numeric(12,2) not null default 0;

alter table public.plan_produccion_detalle alter column formula_id drop not null;

-- ---------------------------------------------------------------------
-- Reescritura del trigger de "marcar completado": además de la materia
-- prima (según fórmula, ahora escalada por litros producidos + merma,
-- porque la merma también se mezcló), descuenta preformas y tapas según
-- las botellas realmente producidas. Sigue insertando cada descuento
-- como un movimiento (tipo 'produccion') para que quede en el kardex.
-- ---------------------------------------------------------------------
create or replace function public.trg_completar_plan_detalle()
returns trigger language plpgsql as $$
declare
    r_formula record;
    r_producto record;
    r_detalle record;
    factor numeric;
    litros_totales numeric;
begin
    if new.completado = true and (old.completado is distinct from true) then
        if new.producto_terminado_id is not null then
            select * into r_producto from public.productos_terminados
                where id = new.producto_terminado_id;
            new.formula_id := coalesce(new.formula_id, r_producto.formula_id);
        end if;

        select * into r_formula from public.formulas where id = new.formula_id;

        new.litros_producidos := coalesce(new.litros_producidos, new.litros_planificados);
        litros_totales := new.litros_producidos + coalesce(new.merma_litros, 0);
        factor := litros_totales / r_formula.rendimiento_litros;

        for r_detalle in
            select * from public.formula_detalle where formula_id = new.formula_id
        loop
            insert into public.movimientos(
                tabla_origen, item_id, tipo, cantidad, unidad_medida,
                plan_produccion_detalle_id, usuario_id, observacion
            ) values (
                'materia_prima', r_detalle.materia_prima_id, 'produccion',
                r_detalle.cantidad_por_lote * factor,
                (select unidad_medida from public.materia_prima where id = r_detalle.materia_prima_id),
                new.id, new.completado_por,
                'Descuento automático por producción de ' || r_formula.sabor
            );
        end loop;

        if new.producto_terminado_id is not null
           and new.botellas_producidas is not null
           and new.botellas_producidas > 0 then
            if r_producto.preforma_id is not null then
                insert into public.movimientos(
                    tabla_origen, item_id, tipo, cantidad, unidad_medida,
                    plan_produccion_detalle_id, usuario_id, observacion
                ) values (
                    'preformas', r_producto.preforma_id, 'produccion', new.botellas_producidas,
                    (select unidad_medida from public.preformas where id = r_producto.preforma_id),
                    new.id, new.completado_por,
                    'Descuento automático por producción de ' || r_producto.nombre
                );
            end if;

            insert into public.movimientos(
                tabla_origen, item_id, tipo, cantidad, unidad_medida,
                plan_produccion_detalle_id, usuario_id, observacion
            ) values (
                'tapas', r_producto.tapa_id, 'produccion', new.botellas_producidas,
                (select unidad_medida from public.tapas where id = r_producto.tapa_id),
                new.id, new.completado_por,
                'Descuento automático por producción de ' || r_producto.nombre
            );
        end if;

        new.completado_en := now();
    end if;
    return new;
end; $$;
