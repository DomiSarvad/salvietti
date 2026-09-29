-- =====================================================================
-- SALVIETTI CONTROL — v19: catálogo inicial del Almacén de Jarabes.
-- Ejecutar DESPUÉS de schema_v18_inventario_almacenes.sql, en el SQL Editor
-- de Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Carga solo NOMBRES, categoría y unidad. Sale de las fotos del inventario
-- de materia prima y del Balance de insumos, así que hay que REVISARLO:
--
--   * No carga stock. El stock inicial se registra con un conteo físico
--     (el Balance de insumos del cierre) o con la primera recepción.
--   * No carga tipo de envase ni kilos por envase (bidón, bolsa, cartón),
--     salvo el azúcar (quintal de 46 kg). Se completan editando cada ítem.
--   * Las cantidades que se pesan en gramos (colores, natamicina) se cuentan
--     en KG; la app convierte de gramos a kilos.
--   * El alcohol llega en litros pero se controla en kilos.
--
-- Si un nombre no coincide con el que usan en el almacén, se corrige desde
-- la pantalla Almacenes (Editar) sin tocar este archivo.

insert into public.inv_items (categoria_id, detalle, unidad, unidad_compra, factor_compra)
select c.id, v.detalle, v.unidad, v.unidad_compra, v.factor_compra
  from (values
    -- Azúcar
    ('Azúcar', 'Azúcar', 'KG', 'quintal', 46),

    -- Concentrados (uno por sabor y proveedor)
    ('Concentrados', 'Concentrado Naranja', 'KG', null, null),
    ('Concentrados', 'Concentrado Lima limón', 'KG', null, null),
    ('Concentrados', 'Concentrado Piña', 'KG', null, null),
    ('Concentrados', 'Concentrado Granadina', 'KG', null, null),
    ('Concentrados', 'Concentrado Pomelo', 'KG', null, null),
    ('Concentrados', 'Concentrado Ginger Ale', 'KG', null, null),
    ('Concentrados', 'Concentrado Ross', 'KG', null, null),
    ('Concentrados', 'Concentrado Kinotto Chepe', 'KG', null, null),
    ('Concentrados', 'Concentrado Kinotto Cola', 'KG', null, null),
    ('Concentrados', 'Concentrado Papaya IFF', 'KG', null, null),
    ('Concentrados', 'Concentrado Papaya Sapore', 'KG', null, null),
    ('Concentrados', 'Concentrado Arándano', 'KG', null, null),
    ('Concentrados', 'Concentrado Frambuesa', 'KG', null, null),
    ('Concentrados', 'Concentrado Kiwi', 'KG', null, null),
    ('Concentrados', 'Concentrado Tumbo', 'KG', null, null),
    ('Concentrados', 'Concentrado Frutilla', 'KG', null, null),
    ('Concentrados', 'Concentrado Chocolate', 'KG', null, null),
    ('Concentrados', 'Concentrado Menta', 'KG', null, null),

    -- Conservantes
    ('Conservantes', 'Benzoato de sodio (americano)', 'KG', null, null),
    ('Conservantes', 'Benzoato de sodio (chino)', 'KG', null, null),
    ('Conservantes', 'Sorbato de potasio', 'KG', null, null),
    ('Conservantes', 'Natamicina', 'KG', null, null),

    -- Edulcorantes
    ('Edulcorantes', 'Edulcorante', 'KG', null, null),

    -- Ácidos
    ('Ácidos', 'Ácido cítrico', 'KG', null, null),
    ('Ácidos', 'Ácido fosfórico', 'KG', null, null),
    ('Ácidos', 'Citrato de sodio', 'KG', null, null),

    -- Colorantes
    ('Colorantes', 'Color amaranto', 'KG', null, null),
    ('Colorantes', 'Color caramelo', 'KG', null, null),
    ('Colorantes', 'Color tartrazina', 'KG', null, null),
    ('Colorantes', 'Color sunset (amarillo)', 'KG', null, null),
    ('Colorantes', 'Color azul', 'KG', null, null),
    ('Colorantes', 'Color verde', 'KG', null, null),

    -- Alcohol (llega en litros, se controla en kilos)
    ('Alcohol', 'Alcohol', 'KG', null, null),

    -- Aditivos
    ('Aditivos', 'Cafeína anhidra', 'KG', null, null),
    ('Aditivos', 'Vimix', 'KG', null, null),
    ('Aditivos', 'Enturbiante', 'KG', null, null),

    -- Filtros
    ('Filtros', 'Tela filtro', 'M', null, null),
    ('Filtros', 'Filtro cartucho grande', 'UNI', null, null),
    ('Filtros', 'Filtro cartucho pequeño', 'UNI', null, null)
  ) as v(categoria, detalle, unidad, unidad_compra, factor_compra)
  join public.inv_categorias c
    on c.nombre = v.categoria and c.padre_id is null and c.almacen_id = 'jarabes'
on conflict (categoria_id, detalle) do nothing;
