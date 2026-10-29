-- =====================================================================
-- SALVIETTI CONTROL — v48: Almacén ve el almacén de Soda Cáustica, y foto
-- de cada ítem del inventario. (Re-ejecutable.)
-- =====================================================================

-- 1. Almacén recibe la soda cáustica y se la entrega al área (v36), pero
--    nunca tuvo permiso de VER ese almacén: en el Inicio y en Almacenes solo
--    veía General, Jarabes y Soplado. Mismo nivel que Jarabes/Soplado (ver).
insert into public.permisos_rol (rol, modulo, accion)
values ('almacen', 'inventario_soda_caustica', 'ver')
on conflict do nothing;

-- 2. Foto del ítem (bucket público "items": una foto de producto no es dato
--    sensible, como "avatars"/"productos").
alter table public.inv_items
    add column if not exists foto_url text;

insert into storage.buckets (id, name, public)
values ('items', 'items', true)
on conflict (id) do nothing;

drop policy if exists "items_foto_ver" on storage.objects;
create policy "items_foto_ver" on storage.objects for select
    using (bucket_id = 'items' and auth.role() = 'authenticated');

-- Subir/cambiar: quien puede crear o editar ítems en algún almacén.
drop policy if exists "items_foto_subir" on storage.objects;
create policy "items_foto_subir" on storage.objects for insert
    with check (bucket_id = 'items' and (
        public.tiene_permiso('inventario_general', 'editar') or
        public.tiene_permiso('inventario_general', 'crear') or
        public.tiene_permiso('inventario_jarabes', 'editar') or
        public.tiene_permiso('inventario_soplado', 'editar') or
        public.tiene_permiso('inventario_soda_caustica', 'editar')));

drop policy if exists "items_foto_cambiar" on storage.objects;
create policy "items_foto_cambiar" on storage.objects for update
    using (bucket_id = 'items' and (
        public.tiene_permiso('inventario_general', 'editar') or
        public.tiene_permiso('inventario_jarabes', 'editar') or
        public.tiene_permiso('inventario_soplado', 'editar') or
        public.tiene_permiso('inventario_soda_caustica', 'editar')));
