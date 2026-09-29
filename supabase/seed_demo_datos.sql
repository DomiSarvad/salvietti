-- =====================================================================
-- SALVIETTI CONTROL — datos de prueba (DEMO), NO reales.
-- Ejecutar DESPUÉS de todas las migraciones (hasta v40) y de
-- seed_usuarios_produccion.sql, en el SQL Editor de Supabase.
-- Se puede volver a ejecutar sin problema (no duplica nada).
-- =====================================================================
--
-- Objetivo: que se vea el sistema funcionando de punta a punta —
-- inventario con stock real, recepciones, pedidos en distintos estados,
-- una receta de jarabes activa y otra a medio aprobar, un preparado, un
-- análisis de calidad, corridas de soplado/llenadora/codificación, un
-- reporte de salidas, mermas y una entrega de soda cáustica.
--
-- TODO lo que crea este archivo tiene "(demo)" en el detalle/motivo, para
-- poder encontrarlo y borrarlo fácil el día que haya datos reales. No
-- toca nada que ya hayas cargado vos.
--
-- También completa acá DOS "datos que faltan" (sección 13 del md) con
-- valores DE EJEMPLO, para que los cálculos que dependen de ellos
-- (Registro de Salidas, Informe del Gerente) muestren números en vez de
-- "datos incompletos". Quedan marcados como SUPUESTO — hay que
-- reemplazarlos por los reales de la fábrica:
--   * botellas por paquete y paquetes por palet de cada presentación PET.
--   * paquetes (cajas) por palet de cada presentación de vidrio.
--
-- No usa las funciones de la app (inv_crear_pedido, jarabes_receta_crear,
-- etc.): esas funciones exigen `auth.uid()` de una sesión con la app, que
-- no existe corriendo esto desde el SQL Editor. En cambio, inserta
-- directo en las tablas con los mismos datos que esas funciones
-- calcularían, así el resultado se ve igual.

-- ---------------------------------------------------------------------
-- 0. Ayudante: responsable de cada fila (usuario del rol si existe, si no
-- cualquier usuario activo, para que esto funcione aunque no hayas
-- corrido seed_usuarios_produccion.sql).
-- ---------------------------------------------------------------------
create or replace function public._demo_usuario(p_rol text)
returns table (id uuid, nombre text)
language sql stable as $$
    (select u.id, u.nombre_completo from public.usuarios u where u.rol = p_rol and u.activo limit 1)
    union all
    (select u.id, u.nombre_completo from public.usuarios u where u.activo
      order by (case when u.rol = p_rol then 0 else 1 end) limit 1);
$$;

-- Ítem de catálogo "de prueba": lo crea si no existe (por categoría+detalle).
create or replace function public._demo_item(
    p_categoria bigint, p_detalle text, p_unidad text, p_stock_minimo numeric default null
) returns bigint
language plpgsql as $$
declare v bigint;
begin
    select id into v from public.inv_items where categoria_id = p_categoria and detalle = p_detalle;
    if v is null then
        insert into public.inv_items (categoria_id, detalle, unidad, stock_minimo)
        values (p_categoria, p_detalle, p_unidad, p_stock_minimo)
        returning id into v;
    end if;
    return v;
end;
$$;

-- Da de alta stock para un ítem en un almacén (como si viniera de un
-- saldo inicial), solo si ese ítem todavía no tiene movimientos ahí.
create or replace function public._demo_stock(p_item bigint, p_almacen text, p_cantidad numeric)
returns void language plpgsql as $$
begin
    if not exists (select 1 from public.inv_movimientos where item_id = p_item and almacen_id = p_almacen) then
        insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (p_item, p_almacen, 'entrada', p_cantidad, 'manual', 'Saldo inicial (demo)');
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 1. SUPUESTO — equivalencias de cajas/paletas (dato pendiente, sección 13).
--    Valores de ejemplo; reemplazar por los reales de la fábrica.
-- ---------------------------------------------------------------------
update public.presentaciones set unidades_por_caja = 4, empaques_por_palet = 48
 where material = 'pet' and nombre = '2.5 L' and unidades_por_caja is null;
update public.presentaciones set unidades_por_caja = 6, empaques_por_palet = 48
 where material = 'pet' and nombre = '2 L' and unidades_por_caja is null;
update public.presentaciones set unidades_por_caja = 12, empaques_por_palet = 48
 where material = 'pet' and nombre = '1 L' and unidades_por_caja is null;
update public.presentaciones set unidades_por_caja = 12, empaques_por_palet = 60
 where material = 'pet' and nombre = '600 ml' and unidades_por_caja is null;
update public.presentaciones set unidades_por_caja = 24, empaques_por_palet = 60
 where material = 'pet' and nombre = '330 ml' and unidades_por_caja is null;
update public.presentaciones set empaques_por_palet = 60
 where material = 'vidrio' and empaques_por_palet is null;

-- Litros por preparado y Brix objetivo que faltaban (sección 13). Valores
-- de ejemplo, a confirmar con Jarabes/Calidad.
update public.sabores set litros_por_preparado = 1000
 where litros_por_preparado is null;
update public.sabores set brix_min = 10, brix_max = 12 where brix_min is null;

-- Matriz sabor × presentación: agrega Papaya en vidrio 1 L, para que el
-- ejemplo de Registro de Salidas en vidrio quede consistente si alguien
-- lo vuelve a guardar desde la app.
insert into public.sabor_presentacion (sabor_id, presentacion_id)
select s.id, p.id from public.sabores s, public.presentaciones p
 where s.nombre = 'Papaya' and p.nombre = '1 L' and p.material = 'vidrio'
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 2. Proveedores e ítems de catálogo de prueba.
-- ---------------------------------------------------------------------
insert into public.inv_proveedores (nombre) values ('Distribuidora Ejemplo S.R.L. (demo)')
on conflict (nombre) do nothing;
insert into public.inv_proveedores (nombre) values ('Plásticos del Valle (demo)')
on conflict (nombre) do nothing;

do $$
declare
    g text := 'general'; j text := 'jarabes'; sp text := 'soplado'; sc text := 'soda_caustica';
    cat_tapa_pet bigint; cat_preforma_25 bigint; cat_termo bigint; cat_azucar bigint;
    cat_acidos bigint; cat_concentrados bigint; cat_saneamiento bigint; cat_codif bigint;
    v_tapa bigint; v_preforma bigint; v_termo bigint; v_azucar bigint; v_acido bigint;
    v_concentrado bigint; v_soda bigint; v_solvente bigint; v_tinta bigint;
begin
    select id into cat_tapa_pet from public.inv_categorias
     where nombre = 'PET' and almacen_id = g
       and padre_id = (select id from public.inv_categorias where nombre = 'Tapas' and padre_id is null and almacen_id = g);
    select id into cat_preforma_25 from public.inv_categorias
     where nombre = '2.5 L' and almacen_id = g
       and padre_id = (select id from public.inv_categorias where nombre = 'Preformas' and padre_id is null and almacen_id = g);
    select id into cat_termo from public.inv_categorias where nombre = 'Termocontraíbles' and padre_id is null and almacen_id = g;
    select id into cat_saneamiento from public.inv_categorias where nombre = 'Saneamiento' and padre_id is null and almacen_id = g;
    select id into cat_codif from public.inv_categorias where nombre = 'Codificación (solvente y tinta)' and padre_id is null and almacen_id = g;
    select id into cat_azucar from public.inv_categorias where nombre = 'Azúcar' and padre_id is null and almacen_id = j;
    select id into cat_acidos from public.inv_categorias where nombre = 'Ácidos' and padre_id is null and almacen_id = j;
    select id into cat_concentrados from public.inv_categorias where nombre = 'Concentrados' and padre_id is null and almacen_id = j;

    v_tapa := public._demo_item(cat_tapa_pet, 'Tapa Short Negra 28mm (demo)', 'PZA', 5000);
    v_preforma := public._demo_item(cat_preforma_25, 'Preforma 2.5 L 54.7gr (demo)', 'PZA', 3000);
    v_termo := public._demo_item(cat_termo, 'Rollo termocontraíble 400mm (demo)', 'KG', 20);
    v_azucar := public._demo_item(cat_azucar, 'Azúcar blanca (demo)', 'KG', 500);
    v_acido := public._demo_item(cat_acidos, 'Ácido cítrico (demo)', 'KG', 50);
    v_concentrado := public._demo_item(cat_concentrados, 'Concentrado Papaya (demo)', 'L', 30);
    v_soda := public._demo_item(cat_saneamiento, 'Soda cáustica en escamas (demo)', 'KG', 40);
    v_solvente := public._demo_item(cat_codif, 'Solvente codificador (demo)', 'L', 5);
    v_tinta := public._demo_item(cat_codif, 'Tinta codificadora negra (demo)', 'L', 3);

    -- Stock inicial: la mayoría óptimo, uno bajo y uno crítico para ver
    -- el semáforo funcionando.
    perform public._demo_stock(v_tapa, g, 12000);       -- óptimo
    perform public._demo_stock(v_preforma, g, 3200);    -- óptimo
    perform public._demo_stock(v_termo, g, 22);         -- bajo, con el consumo de abajo
    perform public._demo_stock(v_azucar, j, 1200);      -- óptimo
    perform public._demo_stock(v_acido, j, 55);         -- óptimo
    perform public._demo_stock(v_concentrado, j, 8);    -- bajo (mínimo 30)
    perform public._demo_stock(v_soda, sc, 45);         -- óptimo
    perform public._demo_stock(v_solvente, g, 2);       -- crítico (mínimo 5)
    perform public._demo_stock(v_tinta, g, 3);          -- justo en el mínimo → marca "Pedido"

    -- Preforma también llega a Soplado (para elegirla al iniciar una corrida;
    -- alcanza para la corrida de demo de más abajo, que usa 3500).
    perform public._demo_stock(v_preforma, sp, 4000);

    -- Consumo diario de referencia, para que el semáforo de días de
    -- existencia del Inicio muestre crítico/bajo/óptimo (sin esto, un ítem
    -- recién creado y sin salidas queda "sin datos"). Valores de ejemplo.
    update public.inv_items set consumo_diario_manual = 300 where id = v_tapa;        -- óptimo
    update public.inv_items set consumo_diario_manual = 250 where id = v_preforma;    -- óptimo
    update public.inv_items set consumo_diario_manual = 4 where id = v_termo;         -- bajo
    update public.inv_items set consumo_diario_manual = 40 where id = v_azucar;       -- óptimo
    update public.inv_items set consumo_diario_manual = 5 where id = v_acido;         -- óptimo
    update public.inv_items set consumo_diario_manual = 4 where id = v_concentrado;   -- crítico
    update public.inv_items set consumo_diario_manual = 2 where id = v_soda;          -- óptimo
    update public.inv_items set consumo_diario_manual = 1.5 where id = v_solvente;    -- crítico
    update public.inv_items set consumo_diario_manual = 0.5 where id = v_tinta;       -- bajo
end $$;

-- ---------------------------------------------------------------------
-- 3. Recepciones (Módulo 2): una con diferencia chica, otra exacta.
-- ---------------------------------------------------------------------
do $$
declare v_resp record; v_item bigint; v_prov bigint;
begin
    select * into v_resp from public._demo_usuario('almacen');
    select id into v_item from public.inv_items where detalle = 'Tapa Short Negra 28mm (demo)';
    select id into v_prov from public.inv_proveedores where nombre = 'Plásticos del Valle (demo)';

    if not exists (select 1 from public.inv_recepciones where item_id = v_item and n_factura = 'F-DEMO-001') then
        insert into public.inv_recepciones
            (fecha, almacen_id, item_id, proveedor_id, n_factura, cantidad_factura, cantidad_real,
             n_lote, fecha_fabricacion, fecha_vencimiento, senasac, transportador, observaciones, usuario_id)
        values
            (current_date - 3, 'general', v_item, v_prov, 'F-DEMO-001', 5000, 4950,
             'L-2026-DEMO1', current_date - 60, current_date + 300, 'SENASAG-DEMO-001',
             'Transportes Ejemplo', 'Faltaron 50 unidades del pedido (demo)', v_resp.id);
    end if;

    select id into v_item from public.inv_items where detalle = 'Azúcar blanca (demo)';
    if not exists (select 1 from public.inv_recepciones where item_id = v_item and n_factura = 'F-DEMO-002') then
        insert into public.inv_recepciones
            (fecha, almacen_id, item_id, proveedor_id, n_factura, cantidad_factura, cantidad_real,
             n_lote, fecha_fabricacion, fecha_vencimiento, senasac, observaciones, usuario_id)
        values
            (current_date - 1, 'jarabes', v_item, v_prov, 'F-DEMO-002', 800, 800,
             'L-2026-DEMO2', current_date - 20, current_date + 200, 'SENASAG-DEMO-002',
             'Recepción completa, sin diferencia (demo)', v_resp.id);
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Pedidos y entregas (Módulo 3): pendiente, entregado con observación
--    ya resuelta, y cerrado conforme (con una devolución parcial).
-- ---------------------------------------------------------------------
do $$
declare
    v_almacen record; v_jarabes record;
    v_item bigint; v_pedido bigint; v_linea bigint; v_mov bigint;
begin
    select * into v_almacen from public._demo_usuario('almacen');
    select * into v_jarabes from public._demo_usuario('jarabes');
    select id into v_item from public.inv_items where detalle = 'Ácido cítrico (demo)';

    -- 4.1 Pendiente: Jarabes pidió y todavía nadie entregó.
    if not exists (select 1 from public.inv_pedidos where motivo = 'Reposición para el lote de la semana (demo)') then
        insert into public.inv_pedidos
            (fecha, area_destino, almacen_origen, almacen_destino, motivo, estado, solicitante, solicitante_nombre)
        values (current_date, 'jarabes', 'general', 'jarabes', 'Reposición para el lote de la semana (demo)',
                'pendiente', v_jarabes.id, v_jarabes.nombre)
        returning id into v_pedido;
        insert into public.inv_pedido_lineas (pedido_id, item_id, cantidad_pedida)
        values (v_pedido, v_item, 15);
    end if;

    -- 4.2 Cerrado con observación ya resuelta: Almacén entregó de menos,
    -- Jarabes avisó, Almacén lo resolvió.
    select id into v_item from public.inv_items where detalle = 'Tapa Short Negra 28mm (demo)';
    if not exists (select 1 from public.inv_pedidos where motivo = 'Para la línea de llenado del jueves (demo)') then
        insert into public.inv_pedidos
            (fecha, area_destino, almacen_origen, motivo, estado, solicitante, solicitante_nombre,
             entregado_por, entregado_por_nombre, entregado_en, confirmado_por, confirmado_por_nombre,
             confirmado_en, nota_conformidad, resolucion)
        values (current_date - 2, 'llenadora', 'general', 'Para la línea de llenado del jueves (demo)',
                'cerrado', v_almacen.id, v_almacen.nombre, v_almacen.id, v_almacen.nombre,
                current_date - 2, v_almacen.id, v_almacen.nombre, current_date - 1,
                'Llegaron 50 menos, faltaba en el estante (demo)', 'Se completó con la siguiente entrega (demo)')
        returning id into v_pedido;
        insert into public.inv_pedido_lineas
            (pedido_id, item_id, cantidad_pedida, cantidad_entregada, cantidad_recibida, recibido_ok, observacion)
        values (v_pedido, v_item, 500, 450, 450, false, 'Faltaron 50 unidades (demo)')
        returning id into v_linea;
        insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
        values (v_item, 'general', 'salida', -450, 'entrega', v_pedido, 'Entrega a llenadora (demo)')
        returning id into v_mov;
        insert into public.inv_entrega_lotes (linea_id, cantidad) values (v_linea, 450);

        -- Devolución parcial: sobraron 50 al final del turno.
        if not exists (select 1 from public.inv_devoluciones where linea_id = v_linea) then
            insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, referencia_id, motivo)
            values (v_item, 'general', 'entrada', 50, 'devolucion', v_linea, 'Devolución de llenadora (demo)')
            returning id into v_mov;
            insert into public.inv_devoluciones (linea_id, cantidad, motivo, movimiento_id, responsable, responsable_nombre)
            values (v_linea, 50, 'Sobró al cerrar el turno (demo)', v_mov, v_almacen.id, v_almacen.nombre);
        end if;
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Salida directa (Módulo 1): rollo de termocontraíble a Llenadora.
-- ---------------------------------------------------------------------
do $$
declare v_almacen record; v_item bigint; v_mov bigint;
begin
    select * into v_almacen from public._demo_usuario('almacen');
    select id into v_item from public.inv_items where detalle = 'Rollo termocontraíble 400mm (demo)';
    if not exists (select 1 from public.inv_salidas_directas where item_id = v_item) then
        insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (v_item, 'general', 'salida', -3.5, 'salida_directa', 'Salida directa a llenadora (demo)')
        returning id into v_mov;
        insert into public.inv_salidas_directas
            (item_id, almacen_id, area_destino, cantidad_rollos, peso_real, motivo, movimiento_id, responsable, responsable_nombre)
        values (v_item, 'general', 'llenadora', 2, 3.5, 'Pedido verbal del turno tarde (demo)', v_mov, v_almacen.id, v_almacen.nombre);
        update public.inv_movimientos set referencia_id =
            (select id from public.inv_salidas_directas where movimiento_id = v_mov) where id = v_mov;
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 6. Jarabes (Módulo 6): receta activa de Papaya, un preparado finalizado,
--    y una receta nueva a medio aprobar (para ver el flujo del Módulo 11).
-- ---------------------------------------------------------------------
do $$
declare
    v_jarabes record; v_calidad record; v_produccion record;
    v_sabor bigint; v_azucar bigint; v_acido bigint; v_concentrado bigint;
    v_receta bigint; v_receta_nueva bigint; v_preparado bigint;
begin
    select * into v_jarabes from public._demo_usuario('jarabes');
    select * into v_calidad from public._demo_usuario('control_calidad');
    select * into v_produccion from public._demo_usuario('jefe_produccion');
    select id into v_sabor from public.sabores where nombre = 'Papaya';
    select id into v_azucar from public.inv_items where detalle = 'Azúcar blanca (demo)';
    select id into v_acido from public.inv_items where detalle = 'Ácido cítrico (demo)';
    select id into v_concentrado from public.inv_items where detalle = 'Concentrado Papaya (demo)';

    if not exists (select 1 from public.jarabes_recetas where sabor_id = v_sabor and estado = 'activa') then
        insert into public.jarabes_recetas
            (sabor_id, estado, creada_por, creada_por_nombre, aprobada_por, aprobada_por_nombre, aprobada_en)
        values (v_sabor, 'activa', v_jarabes.id, v_jarabes.nombre, v_produccion.id, v_produccion.nombre, now() - interval '30 days')
        returning id into v_receta;
        insert into public.jarabes_receta_items (receta_id, item_id, cantidad_por_preparado) values
            (v_receta, v_azucar, 180), (v_receta, v_acido, 3.5), (v_receta, v_concentrado, 1.2);
    else
        select id into v_receta from public.jarabes_recetas where sabor_id = v_sabor and estado = 'activa';
    end if;

    -- Preparado finalizado (para que Calidad tenga algo pendiente de analizar).
    if not exists (select 1 from public.jarabes_preparados where sabor_id = v_sabor and n_lote = 1) then
        insert into public.jarabes_preparados
            (fecha, sabor_id, receta_id, n_lote, tanque, cantidad_preparados, litros, estado,
             hora_inicio, hora_fin, brix, responsable, responsable_nombre)
        values
            (current_date - 1, v_sabor, v_receta, 1, 2, 1.5, 1500, 'finalizada',
             now() - interval '1 day' - interval '2 hours', now() - interval '1 day', 11.2,
             v_jarabes.id, v_jarabes.nombre)
        returning id into v_preparado;
        insert into public.jarabes_preparado_insumos (preparado_id, item_id, cantidad_necesaria) values
            (v_preparado, v_azucar, 270), (v_preparado, v_acido, 5.25), (v_preparado, v_concentrado, 1.8);
    end if;

    -- Receta nueva "propuesta", con el visto bueno de Calidad ya dado —
    -- para mostrar el Módulo 11 a mitad de camino (falta Producción y la
    -- clave del Gerente).
    if not exists (select 1 from public.jarabes_recetas where sabor_id = v_sabor and estado = 'propuesta') then
        insert into public.jarabes_recetas
            (sabor_id, estado, creada_por, creada_por_nombre, aprobada_calidad_por, aprobada_calidad_nombre, aprobada_calidad_en)
        values (v_sabor, 'propuesta', v_jarabes.id, v_jarabes.nombre, v_calidad.id, v_calidad.nombre, now() - interval '2 hours')
        returning id into v_receta_nueva;
        insert into public.jarabes_receta_items (receta_id, item_id, cantidad_por_preparado) values
            (v_receta_nueva, v_azucar, 175), (v_receta_nueva, v_acido, 3.2), (v_receta_nueva, v_concentrado, 1.3);
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 7. Control de Calidad (Módulo 7): análisis del preparado de arriba.
-- ---------------------------------------------------------------------
do $$
declare v_calidad record; v_preparado bigint;
begin
    select * into v_calidad from public._demo_usuario('control_calidad');
    select p.id into v_preparado from public.jarabes_preparados p
     join public.sabores s on s.id = p.sabor_id where s.nombre = 'Papaya' and p.n_lote = 1;
    if v_preparado is not null and not exists (select 1 from public.calidad_analisis where preparado_id = v_preparado) then
        insert into public.calidad_analisis
            (preparado_id, brix_diluido, ph, aspecto, resultado, responsable, responsable_nombre)
        values (v_preparado, 11.0, 3.2, 'Color y olor normales (demo)', 'conforme', v_calidad.id, v_calidad.nombre);
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 8. Soplado (Módulo 5): corrida finalizada de Papaya 2.5 L, con merma.
-- ---------------------------------------------------------------------
do $$
declare v_soplado record; v_sabor bigint; v_pres bigint; v_preforma bigint; v_prov bigint;
begin
    select * into v_soplado from public._demo_usuario('soplado');
    select id into v_sabor from public.sabores where nombre = 'Papaya';
    select id into v_pres from public.presentaciones where nombre = '2.5 L' and material = 'pet';
    select id into v_preforma from public.inv_items where detalle = 'Preforma 2.5 L 54.7gr (demo)';
    select id into v_prov from public.inv_proveedores where nombre = 'Plásticos del Valle (demo)';

    if not exists (select 1 from public.soplado_corridas where sabor_id = v_sabor and presentacion_id = v_pres and estado = 'finalizada') then
        insert into public.soplado_corridas
            (fecha, sabor_id, presentacion_id, item_preforma_id, proveedor_id, lote_preforma, estado,
             hora_inicio, hora_fin, preformas_usadas, botellas_sopladas, botellas_etiquetadas,
             merma_soplado, merma_preforma, merma_etiquetado, motivo_merma, responsable, responsable_nombre)
        values
            (current_date, v_sabor, v_pres, v_preforma, v_prov, 'L-PREF-DEMO', 'finalizada',
             now() - interval '4 hours', now() - interval '1 hour', 3500, 3480, 3460,
             15, 20, 5, 'Ajuste de temperatura al inicio del turno (demo)', v_soplado.id, v_soplado.nombre);
        insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (v_preforma, 'soplado', 'salida', -3500, 'soplado_corrida', 'Consumo de soplado (demo)');
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 9. Llenadora y Codificación (Módulo 8): corridas finalizadas, la de
--    Codificación vinculada a la de Llenadora.
-- ---------------------------------------------------------------------
do $$
declare
    v_llenadora record; v_codificacion record;
    v_sabor bigint; v_pres bigint; v_preparado bigint; v_tapa bigint; v_solvente bigint; v_tinta bigint;
    v_corrida_llenadora bigint;
begin
    select * into v_llenadora from public._demo_usuario('llenadora');
    select * into v_codificacion from public._demo_usuario('codificacion');
    select id into v_sabor from public.sabores where nombre = 'Papaya';
    select id into v_pres from public.presentaciones where nombre = '2.5 L' and material = 'pet';
    select p.id into v_preparado from public.jarabes_preparados p
     join public.sabores s on s.id = p.sabor_id where s.nombre = 'Papaya' and p.n_lote = 1;
    select id into v_tapa from public.inv_items where detalle = 'Tapa Short Negra 28mm (demo)';
    select id into v_solvente from public.inv_items where detalle = 'Solvente codificador (demo)';
    select id into v_tinta from public.inv_items where detalle = 'Tinta codificadora negra (demo)';

    if not exists (select 1 from public.llenadora_corridas where sabor_id = v_sabor and presentacion_id = v_pres) then
        insert into public.llenadora_corridas
            (fecha, turno, sabor_id, presentacion_id, preparado_id, tanque, estado,
             hora_inicio, hora_fin, botellas_llenadas, botellas_desechadas,
             item_tapa_id, tapas_usadas, tapas_desechadas, rebalse, motivo_merma, responsable, responsable_nombre)
        values
            (current_date, 'manana', v_sabor, v_pres, v_preparado, 2, 'finalizada',
             now() - interval '3 hours', now() - interval '1 hour', 3400, 12,
             v_tapa, 3400, 8, 4, 'Rebalse normal de arranque (demo)', v_llenadora.id, v_llenadora.nombre)
        returning id into v_corrida_llenadora;
    else
        select id into v_corrida_llenadora from public.llenadora_corridas
         where sabor_id = v_sabor and presentacion_id = v_pres limit 1;
    end if;

    if not exists (select 1 from public.codificacion_corridas where corrida_llenadora_id = v_corrida_llenadora) then
        insert into public.codificacion_corridas
            (fecha, turno, sabor_id, presentacion_id, corrida_llenadora_id, n_lote, estado,
             hora_inicio, hora_fin, botellas_codificadas, codigo_impreso,
             botellas_mal_tapadas, tapas_mal_tapadas, impurezas, motivo_merma,
             item_solvente_id, solvente_usado, item_tinta_id, tinta_usada, responsable, responsable_nombre)
        values
            (current_date, 'manana', v_sabor, v_pres, v_corrida_llenadora, 'L-2026-0001', 'finalizada',
             now() - interval '1 hour', now() - interval '20 minutes', 3390, 'VTO 12/2026 L1',
             6, 4, 2, 'Boquilla desalineada, ya corregida (demo)', v_solvente, 0.3, v_tinta, 0.15,
             v_codificacion.id, v_codificacion.nombre);
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 10. Registro de salidas (Módulo 8): reporte cerrado de hoy, con una
--     línea PET y una de vidrio (esta última usa la equivalencia
--     SUPUESTA de la sección 1).
-- ---------------------------------------------------------------------
do $$
declare
    v_salidas record; v_reporte bigint; v_sabor bigint; v_pres_pet bigint; v_pres_vid bigint;
begin
    select * into v_salidas from public._demo_usuario('registro_salidas');
    select id into v_sabor from public.sabores where nombre = 'Papaya';
    select id into v_pres_pet from public.presentaciones where nombre = '2.5 L' and material = 'pet';
    select id into v_pres_vid from public.presentaciones where nombre = '1 L' and material = 'vidrio';

    if not exists (select 1 from public.salidas_reportes where fecha = current_date and turno = 'manana') then
        insert into public.salidas_reportes
            (fecha, turno, hora_inicio_dia, hora_fin_dia, estado, responsable, responsable_nombre, observaciones)
        values (current_date, 'manana', now() - interval '5 hours', now() - interval '30 minutes',
                'cerrado', v_salidas.id, v_salidas.nombre, 'Turno sin novedades (demo)')
        returning id into v_reporte;
        insert into public.salidas_reporte_lineas
            (reporte_id, sabor_id, presentacion_id, hora_inicio, hora_fin,
             pet_palets, pet_paquetes_libres, pet_botellas_libres)
        values (v_reporte, v_sabor, v_pres_pet, now() - interval '4 hours', now() - interval '1 hour',
                14, 6, 2);
        insert into public.salidas_reporte_lineas
            (reporte_id, sabor_id, presentacion_id, hora_inicio, hora_fin,
             vid_filas, vid_cajas_libres, vid_botellas_libres)
        values (v_reporte, v_sabor, v_pres_vid, now() - interval '2 hours', now() - interval '1 hour',
                0, 8, 3);
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 11. Mermas (Módulo 9): Jarabes y Calidad, con sus causas.
-- ---------------------------------------------------------------------
do $$
declare v_jarabes record; v_calidad record; v_sabor bigint; v_registro bigint;
begin
    select * into v_jarabes from public._demo_usuario('jarabes');
    select * into v_calidad from public._demo_usuario('control_calidad');
    select id into v_sabor from public.sabores where nombre = 'Papaya';

    if not exists (select 1 from public.mermas_registros where area = 'jarabes' and motivo = 'Preparado del lote 1 (demo)') then
        insert into public.mermas_registros (area, sabor_id, cantidad_producida, motivo, responsable, responsable_nombre)
        values ('jarabes', v_sabor, 1500, 'Preparado del lote 1 (demo)', v_jarabes.id, v_jarabes.nombre)
        returning id into v_registro;
        -- A propósito por encima del 3 %, para que se vea la alerta en rojo (demo).
        insert into public.mermas_causas (registro_id, causa, cantidad) values (v_registro, 'menor_volumen', 55);
    end if;

    if not exists (select 1 from public.mermas_registros where area = 'calidad' and motivo = 'Control del lote 1 (demo)') then
        insert into public.mermas_registros (area, sabor_id, cantidad_producida, motivo, responsable, responsable_nombre)
        values ('calidad', v_sabor, 1500, 'Control del lote 1 (demo)', v_calidad.id, v_calidad.nombre)
        returning id into v_registro;
        insert into public.mermas_causas (registro_id, causa, cantidad) values (v_registro, 'exceso_agua', 10);
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 12. Soda cáustica (Módulo 10): una entrega.
-- ---------------------------------------------------------------------
do $$
declare v_soda record; v_item bigint; v_mov bigint; v_saldo numeric;
begin
    select * into v_soda from public._demo_usuario('soda_caustica');
    select id into v_item from public.inv_items where detalle = 'Soda cáustica en escamas (demo)';
    if not exists (select 1 from public.soda_entregas where item_id = v_item) then
        insert into public.inv_movimientos (item_id, almacen_id, tipo, cantidad, referencia_tipo, motivo)
        values (v_item, 'soda_caustica', 'salida', -5, 'soda_entrega', 'Entrega a Mantenimiento (demo)')
        returning id into v_mov;
        select coalesce(sum(cantidad), 0) into v_saldo from public.inv_movimientos
         where item_id = v_item and almacen_id = 'soda_caustica';
        insert into public.soda_entregas
            (item_id, cantidad, entregado_a, area_recibe, motivo, saldo_restante, movimiento_id, responsable, responsable_nombre)
        values (v_item, 5, 'Carlos Mamani (demo)', 'Mantenimiento', 'Limpieza de tanques (demo)',
                v_saldo, v_mov, v_soda.id, v_soda.nombre);
    end if;
end $$;

-- ---------------------------------------------------------------------
-- 13. Solicitudes a Gerencia (Módulo 4): una pendiente, una aprobada.
-- ---------------------------------------------------------------------
do $$
declare v_produccion record; v_gerente record; v_item bigint;
begin
    select * into v_produccion from public._demo_usuario('jefe_produccion');
    select * into v_gerente from public._demo_usuario('gerente');
    select id into v_item from public.inv_items where detalle = 'Concentrado Papaya (demo)';

    if not exists (select 1 from public.solicitudes_gerencia where asunto = 'Faltante de concentrado Papaya (demo)') then
        insert into public.solicitudes_gerencia
            (tipo, asunto, detalle, item_id, cantidad_sugerida, estado, solicitante, solicitante_nombre, solicitante_rol)
        values ('suministro', 'Faltante de concentrado Papaya (demo)',
                'El stock quedó bajo el mínimo esta semana (demo)', v_item, 25, 'pendiente',
                v_produccion.id, v_produccion.nombre, 'jefe_produccion');
    end if;

    if not exists (select 1 from public.solicitudes_gerencia where asunto = 'Autorización de horas extra (demo)') then
        insert into public.solicitudes_gerencia
            (tipo, asunto, detalle, estado, solicitante, solicitante_nombre, solicitante_rol,
             resuelta_por, resuelta_por_nombre, resuelta_en, respuesta)
        values ('autorizacion', 'Autorización de horas extra (demo)',
                'Para terminar el lote del viernes (demo)', 'aprobada',
                v_produccion.id, v_produccion.nombre, 'jefe_produccion',
                v_gerente.id, v_gerente.nombre, now() - interval '1 day', 'Autorizado (demo)');
    end if;
end $$;

-- ---------------------------------------------------------------------
-- Resumen: qué se cargó.
-- ---------------------------------------------------------------------
select 'inv_items (demo)' as tabla, count(*) as filas from public.inv_items where detalle like '%(demo)%'
union all select 'inv_recepciones', count(*) from public.inv_recepciones where observaciones like '%(demo)%'
union all select 'inv_pedidos', count(*) from public.inv_pedidos where motivo like '%(demo)%'
union all select 'inv_devoluciones', count(*) from public.inv_devoluciones where motivo like '%(demo)%'
union all select 'inv_salidas_directas', count(*) from public.inv_salidas_directas where motivo like '%(demo)%'
union all select 'jarabes_recetas', count(*) from public.jarabes_recetas where creada_por_nombre is not null and id in (
    select receta_id from public.jarabes_receta_items ri join public.inv_items i on i.id = ri.item_id where i.detalle like '%(demo)%')
union all select 'jarabes_preparados', count(*) from public.jarabes_preparados where observaciones is null and n_lote = 1
union all select 'calidad_analisis (demo)', count(*) from public.calidad_analisis where aspecto like '%(demo)%'
union all select 'soplado_corridas (demo)', count(*) from public.soplado_corridas where motivo_merma like '%(demo)%'
union all select 'llenadora_corridas (demo)', count(*) from public.llenadora_corridas where motivo_merma like '%(demo)%'
union all select 'codificacion_corridas (demo)', count(*) from public.codificacion_corridas where motivo_merma like '%(demo)%'
union all select 'salidas_reportes (demo)', count(*) from public.salidas_reportes where observaciones like '%(demo)%'
union all select 'mermas_registros (demo)', count(*) from public.mermas_registros where motivo like '%(demo)%'
union all select 'soda_entregas (demo)', count(*) from public.soda_entregas where entregado_a like '%(demo)%'
union all select 'solicitudes_gerencia (demo)', count(*) from public.solicitudes_gerencia where asunto like '%(demo)%';

-- Las funciones _demo_* quedan instaladas para poder volver a correr este
-- archivo más adelante (ej. para agregar otro sabor de ejemplo); no
-- afectan nada del resto del sistema.
