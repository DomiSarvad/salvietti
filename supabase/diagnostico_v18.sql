-- =====================================================================
-- DIAGNÓSTICO — no modifica nada, solo muestra cómo quedó tu base.
-- Ejecutalo y pasame el resultado (una captura de pantalla alcanza).
-- =====================================================================

-- 1. ¿Existen las tablas del Módulo 1?
select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('inv_almacenes','inv_categorias','inv_items','inv_movimientos',
                       'inv_conteos','sabores','presentaciones','sabor_presentacion',
                       'inv_proveedores','inv_recepciones','inv_stock','inv_existencia')
 order by table_name;

-- 2. Columnas actuales de inv_items
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'inv_items'
 order by ordinal_position;

-- 3. Columnas actuales de sabores
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'sabores'
 order by ordinal_position;

-- 4. Columnas actuales de presentaciones
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'presentaciones'
 order by ordinal_position;

-- 5. Si hay una vista inv_existencia, con qué definición quedó
select pg_get_viewdef('public.inv_existencia'::regclass, true)
 where to_regclass('public.inv_existencia') is not null;
