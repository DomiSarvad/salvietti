-- =====================================================================
-- SALVIETTI CONTROL — v15: datos personales del empleado.
-- Ejecutar DESPUÉS de schema_v14 (o v4), en el SQL Editor de Supabase.
-- (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- El Gerente crea el usuario con lo mínimo (nombre, correo, contraseña
-- temporal y rol). En su primer ingreso, cada empleado completa SUS datos
-- (celular, carnet, dirección y fecha de nacimiento): la app no lo deja
-- pasar al sistema hasta completarlos.
--
-- Son datos personales, por eso viven en una tabla APARTE de `usuarios`
-- (que Almacén puede leer completa): solo los ven el propio empleado y el
-- Gerente.

create table if not exists public.datos_empleado (
    usuario_id uuid primary key references public.usuarios(id) on delete cascade,
    celular text check (celular is null or char_length(celular) <= 30),
    carnet text check (carnet is null or char_length(carnet) <= 30),
    direccion text check (direccion is null or char_length(direccion) <= 200),
    fecha_nacimiento date,
    fecha_ingreso date, -- la define el Gerente
    actualizado_en timestamptz not null default now(),
    actualizado_por uuid references public.usuarios(id)
);

comment on table public.datos_empleado is
    'Datos personales de cada empleado. Solo los ve el propio empleado y el Gerente.';

alter table public.datos_empleado enable row level security;

drop policy if exists "datos_empleado_ver" on public.datos_empleado;
create policy "datos_empleado_ver" on public.datos_empleado for select
    using (usuario_id = auth.uid() or public.rol_actual() = 'gerente');

drop policy if exists "datos_empleado_crear" on public.datos_empleado;
create policy "datos_empleado_crear" on public.datos_empleado for insert
    with check (usuario_id = auth.uid() or public.rol_actual() = 'gerente');

drop policy if exists "datos_empleado_editar" on public.datos_empleado;
create policy "datos_empleado_editar" on public.datos_empleado for update
    using (usuario_id = auth.uid() or public.rol_actual() = 'gerente')
    with check (usuario_id = auth.uid() or public.rol_actual() = 'gerente');

-- Quién y cuándo lo modificó; y la fecha de ingreso solo la define el Gerente.
create or replace function public.fn_datos_empleado_sellar()
returns trigger language plpgsql as $$
begin
    if public.rol_actual() is distinct from 'gerente' then
        if tg_op = 'UPDATE' then
            new.fecha_ingreso := old.fecha_ingreso;
        else
            new.fecha_ingreso := null;
        end if;
    end if;
    new.actualizado_en := now();
    new.actualizado_por := auth.uid();
    return new;
end;
$$;

drop trigger if exists trg_datos_empleado_sellar on public.datos_empleado;
create trigger trg_datos_empleado_sellar
    before insert or update on public.datos_empleado
    for each row execute function public.fn_datos_empleado_sellar();
