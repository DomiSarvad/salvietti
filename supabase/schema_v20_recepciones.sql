-- =====================================================================
-- SALVIETTI CONTROL — v20: recepciones de Almacén (Módulo 2).
-- Ejecutar DESPUÉS de schema_v18_inventario_almacenes.sql, en el SQL Editor
-- de Supabase. (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Las tablas (inv_recepciones, inv_proveedores, inv_item_proveedor) y los
-- triggers que suman el stock y recuerdan el SENASAG ya están en v18. Acá
-- se agregan:
--
--   * inv_recepciones_detalle : recepciones con el nombre del ítem y del
--                               proveedor, listas para mostrar.
--   * inv_diferencias_mes     : lo que faltó (o sobró) por proveedor e ítem
--                               en cada mes, para hacer el reclamo.
--   * bucket privado "recepciones" para la foto de la factura o etiqueta.
--
-- Las fotos son PRIVADAS: solo quien tenga permiso de ver Recepciones las
-- abre, y solo quien pueda crear recepciones las sube.

create or replace view public.inv_recepciones_detalle with (security_invoker = true) as
    select r.id, r.fecha, r.almacen_id, r.item_id, i.codigo, i.detalle, i.unidad,
           r.proveedor_id, p.nombre as proveedor, r.n_factura,
           r.cantidad_factura, r.cantidad_real, r.diferencia,
           r.n_lote, r.fecha_fabricacion, r.fecha_vencimiento, r.senasac,
           r.transportador, r.precio_transporte, r.foto_url, r.observaciones,
           r.usuario_id, r.creado_en
      from public.inv_recepciones r
      join public.inv_items i on i.id = r.item_id
      left join public.inv_proveedores p on p.id = r.proveedor_id;

-- Diferencia acumulada por mes, proveedor e ítem. Negativa = faltó producto.
create or replace view public.inv_diferencias_mes with (security_invoker = true) as
    select date_trunc('month', r.fecha)::date as mes,
           r.almacen_id, r.item_id, i.codigo, i.detalle, i.unidad,
           r.proveedor_id, p.nombre as proveedor,
           count(*) as recepciones,
           sum(r.cantidad_factura) as cantidad_factura,
           sum(r.cantidad_real) as cantidad_real,
           sum(r.diferencia) as diferencia,
           round(100 * sum(r.diferencia) / nullif(sum(r.cantidad_factura), 0), 2) as porcentaje
      from public.inv_recepciones r
      join public.inv_items i on i.id = r.item_id
      left join public.inv_proveedores p on p.id = r.proveedor_id
     group by 1, r.almacen_id, r.item_id, i.codigo, i.detalle, i.unidad, r.proveedor_id, p.nombre;

-- Lectura de recepciones: quien tiene el módulo (las tablas de v18 dejaban
-- leer a todos; acá se ajusta al permiso de Recepciones).
drop policy if exists "ver_inv_recepciones" on public.inv_recepciones;
create policy "ver_inv_recepciones" on public.inv_recepciones for select
    using (public.tiene_permiso('recepciones', 'ver'));

-- ---------------------------------------------------------------------
-- Fotos: bucket privado.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('recepciones', 'recepciones', false)
on conflict (id) do nothing;

drop policy if exists "recepciones_foto_subir" on storage.objects;
create policy "recepciones_foto_subir" on storage.objects for insert
    with check (bucket_id = 'recepciones' and public.tiene_permiso('recepciones', 'crear'));

drop policy if exists "recepciones_foto_ver" on storage.objects;
create policy "recepciones_foto_ver" on storage.objects for select
    using (bucket_id = 'recepciones' and public.tiene_permiso('recepciones', 'ver'));
