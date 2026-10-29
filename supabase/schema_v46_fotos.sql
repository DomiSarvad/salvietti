-- =====================================================================
-- SALVIETTI CONTROL — v46: varias fotos por recepción, y foto de cada
-- producto del catálogo de Producción. (Re-ejecutable.)
-- =====================================================================
--
-- Recepciones: hasta v45 había una sola foto (`foto_url`). Ahora `fotos`
-- guarda todas las rutas (dentro del bucket privado "recepciones"). La
-- columna vieja se deja: las recepciones anteriores la siguen usando y la
-- app muestra las dos.
alter table public.inv_recepciones
    add column if not exists fotos text[] not null default '{}';

-- Misma vista de v20, con `fotos` AL FINAL (create or replace view solo
-- permite agregar columnas al final).
create or replace view public.inv_recepciones_detalle with (security_invoker = true) as
    select r.id, r.fecha, r.almacen_id, r.item_id, i.codigo, i.detalle, i.unidad,
           r.proveedor_id, p.nombre as proveedor, r.n_factura,
           r.cantidad_factura, r.cantidad_real, r.diferencia,
           r.n_lote, r.fecha_fabricacion, r.fecha_vencimiento, r.senasac,
           r.transportador, r.precio_transporte, r.foto_url, r.observaciones,
           r.usuario_id, r.creado_en, r.fotos
      from public.inv_recepciones r
      join public.inv_items i on i.id = r.item_id
      left join public.inv_proveedores p on p.id = r.proveedor_id;

-- Productos del catálogo de Producción (Producción del día): foto del
-- producto (bucket público "productos", como "avatars": no es dato sensible).
alter table public.productos_terminados
    add column if not exists foto_url text;

insert into storage.buckets (id, name, public)
values ('productos', 'productos', true)
on conflict (id) do nothing;

-- Ver: cualquiera con sesión. Subir/cambiar: quien puede editar Producción
-- (el mismo que da de alta productos).
drop policy if exists "productos_foto_ver" on storage.objects;
create policy "productos_foto_ver" on storage.objects for select
    using (bucket_id = 'productos' and auth.role() = 'authenticated');

drop policy if exists "productos_foto_subir" on storage.objects;
create policy "productos_foto_subir" on storage.objects for insert
    with check (bucket_id = 'productos' and public.tiene_permiso('plan_produccion', 'editar'));

drop policy if exists "productos_foto_cambiar" on storage.objects;
create policy "productos_foto_cambiar" on storage.objects for update
    using (bucket_id = 'productos' and public.tiene_permiso('plan_produccion', 'editar'));
