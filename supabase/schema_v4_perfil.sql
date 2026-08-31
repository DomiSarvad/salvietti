-- =====================================================================
-- SALVIETTI CONTROL — v4: perfil personal (foto + nombre) para TODOS
-- los usuarios, sin importar su rol.
-- Ejecutar DESPUÉS de schema.sql y schema_v3_alta_usuarios.sql,
-- en el SQL Editor de Supabase.
-- =====================================================================

alter table public.usuarios add column if not exists avatar_url text;

-- ---------------------------------------------------------------------
-- Cada usuario puede actualizar SU PROPIA fila (para cambiar su foto y
-- su nombre visible), además de que Gerente pueda seguir administrando
-- a cualquiera. El trigger de abajo evita que alguien se autoasigne un
-- rol distinto o se reactive/desactive a sí mismo por esta vía.
-- ---------------------------------------------------------------------
drop policy if exists "editar_usuarios" on public.usuarios;
create policy "editar_usuarios" on public.usuarios for update
    using (public.rol_actual() = 'gerente' or auth.uid() = id)
    with check (public.rol_actual() = 'gerente' or auth.uid() = id);

create or replace function public.fn_bloquear_cambios_perfil_propio()
returns trigger language plpgsql as $$
begin
    if public.rol_actual() <> 'gerente' then
        new.rol := old.rol;
        new.activo := old.activo;
        new.creado_por := old.creado_por;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_bloquear_cambios_perfil on public.usuarios;
create trigger trg_bloquear_cambios_perfil
    before update on public.usuarios
    for each row execute function public.fn_bloquear_cambios_perfil_propio();

-- ---------------------------------------------------------------------
-- Bucket de Storage para las fotos de perfil. Público para lectura (así
-- se puede mostrar el avatar con una URL directa, como cualquier app),
-- pero cada usuario solo puede subir/reemplazar/borrar dentro de su
-- propia carpeta (nombrada con su propio uuid).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatar_lectura_publica" on storage.objects;
create policy "avatar_lectura_publica" on storage.objects for select
    using (bucket_id = 'avatars');

drop policy if exists "avatar_subida_propia" on storage.objects;
create policy "avatar_subida_propia" on storage.objects for insert
    with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatar_actualizacion_propia" on storage.objects;
create policy "avatar_actualizacion_propia" on storage.objects for update
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatar_borrado_propio" on storage.objects;
create policy "avatar_borrado_propio" on storage.objects for delete
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
