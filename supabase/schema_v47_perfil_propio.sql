-- =====================================================================
-- SALVIETTI CONTROL — v47: cada usuario puede editar SU perfil (foto y
-- nombre). Re-ejecutable.
-- =====================================================================
--
-- v4 ya lo permitía, pero schema.sql y schema_v3_alta_usuarios.sql definen
-- la misma política "editar_usuarios" SOLO para el Gerente: si alguno se
-- vuelve a ejecutar después de v4, los demás roles dejan de poder guardar
-- su foto. Y Supabase no da error en ese caso (el update no cambia ninguna
-- fila), así que la app creía que se había guardado y la foto desaparecía
-- al volver a entrar. Después de correr schema.sql o v3, volver a correr esta.
--
-- El trigger de v4 (trg_bloquear_cambios_perfil) sigue impidiendo que alguien
-- que no es Gerente se cambie el rol o el estado activo por esta vía.

drop policy if exists "editar_usuarios" on public.usuarios;
create policy "editar_usuarios" on public.usuarios for update
    using (public.rol_actual() = 'gerente' or auth.uid() = id)
    with check (public.rol_actual() = 'gerente' or auth.uid() = id);

-- Por si falta el trigger (base creada sin v4).
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

-- Verificación: debe listar la política con "auth.uid() = id".
-- select policyname, qual from pg_policies where tablename = 'usuarios' and cmd = 'UPDATE';
