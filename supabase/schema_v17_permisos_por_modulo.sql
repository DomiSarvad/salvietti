-- =====================================================================
-- SALVIETTI CONTROL — v17: permisos por módulo (modelo escalable).
-- Ejecutar DESPUÉS de schema_v16_organigrama_roles.sql y ANTES de
-- schema_v18_inventario_almacenes.sql, en el SQL Editor de Supabase.
-- (Se puede volver a ejecutar sin problema.)
-- =====================================================================
--
-- Hasta ahora los permisos estaban escritos a mano en cada política RLS
-- ("rol_actual() = 'almacen'"). Con esta tabla, dar o quitar un permiso es
-- una fila (rol, módulo, acción) y no un cambio de código:
--
--   app_modulos    : registro de módulos del sistema. Un módulo nuevo se
--                    agrega con un INSERT.
--   permisos_rol   : qué acciones tiene cada rol en cada módulo.
--   tiene_permiso(): la usan las políticas RLS. El servidor es quien manda;
--                    la app solo oculta lo que el rol no puede usar.
--
-- Modelo de seguridad (se mantiene):
--   * Denegar por defecto: sin fila en permisos_rol no hay permiso.
--   * Una cuenta desactivada no tiene rol (rol_actual() es null) y por
--     lo tanto tampoco permisos.
--   * Solo el Gerente modifica permisos, y no puede quitarse el acceso a
--     Usuarios ni a Permisos.

create table if not exists public.app_modulos (
    id text primary key,
    nombre text not null,
    estado text not null default 'planeado' check (estado in ('activo', 'planeado'))
);

create table if not exists public.permisos_rol (
    rol text not null check (public.rol_valido(rol)),
    modulo text not null references public.app_modulos(id) on delete cascade,
    accion text not null check (accion in ('ver', 'crear', 'editar', 'eliminar', 'aprobar')),
    primary key (rol, modulo, accion)
);

-- ---------------------------------------------------------------------
-- tiene_permiso: ¿el rol de quien consulta puede hacer esta acción?
-- ---------------------------------------------------------------------
create or replace function public.tiene_permiso(p_modulo text, p_accion text) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
    select exists (
        select 1 from public.permisos_rol
         where rol = public.rol_actual() and modulo = p_modulo and accion = p_accion
    );
$$;
revoke all on function public.tiene_permiso(text, text) from public;
grant execute on function public.tiene_permiso(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- RLS: cualquiera autenticado lee (la app necesita los suyos); solo el
-- Gerente escribe.
-- ---------------------------------------------------------------------
alter table public.app_modulos enable row level security;
alter table public.permisos_rol enable row level security;

drop policy if exists "ver_app_modulos" on public.app_modulos;
create policy "ver_app_modulos" on public.app_modulos for select using (auth.uid() is not null);
drop policy if exists "editar_app_modulos" on public.app_modulos;
create policy "editar_app_modulos" on public.app_modulos for all
    using (public.tiene_permiso('permisos', 'editar'))
    with check (public.tiene_permiso('permisos', 'editar'));

drop policy if exists "ver_permisos_rol" on public.permisos_rol;
create policy "ver_permisos_rol" on public.permisos_rol for select using (auth.uid() is not null);
drop policy if exists "editar_permisos_rol" on public.permisos_rol;
create policy "editar_permisos_rol" on public.permisos_rol for all
    using (public.rol_actual() = 'gerente' and public.tiene_permiso('permisos', 'editar'))
    with check (public.rol_actual() = 'gerente' and public.tiene_permiso('permisos', 'editar'));

-- El Gerente no puede dejarse sin acceso a Usuarios ni a Permisos.
create or replace function public.permisos_proteger_gerente() returns trigger
language plpgsql as $$
begin
    if old.rol = 'gerente' and old.modulo in ('usuarios', 'permisos') then
        raise exception 'No se pueden quitar al Gerente los permisos de Usuarios y Permisos.';
    end if;
    return old;
end;
$$;
drop trigger if exists trg_permisos_proteger_gerente on public.permisos_rol;
create trigger trg_permisos_proteger_gerente before delete on public.permisos_rol
    for each row execute function public.permisos_proteger_gerente();

-- ---------------------------------------------------------------------
-- Registro de módulos. 'activo' = ya existe en la app; 'planeado' = se
-- construye en los módulos siguientes (los permisos ya quedan definidos).
-- ---------------------------------------------------------------------
insert into public.app_modulos (id, nombre, estado) values
    ('dashboard',          'Inicio',                          'activo'),
    ('inventario_general', 'Inventario · Almacén General',    'activo'),
    ('inventario_jarabes', 'Inventario · Almacén de Jarabes', 'activo'),
    ('inventario_soplado', 'Inventario · Almacén de Soplado', 'planeado'),
    ('recepciones',        'Recepciones de materiales',       'planeado'),
    ('entregas',           'Entregas y conformidad',          'planeado'),
    ('solicitudes',        'Solicitudes',                     'planeado'),
    ('aprobaciones',       'Aprobaciones de Gerencia',        'planeado'),
    ('plan_produccion',    'Plan de producción',              'activo'),
    ('soplado',            'Soplado',                         'planeado'),
    ('jarabes_produccion', 'Producción de Jarabes',           'planeado'),
    ('recetas',            'Recetas de concentrados',         'planeado'),
    ('calidad',            'Control de Calidad',              'planeado'),
    ('llenado',            'Llenadora',                       'planeado'),
    ('codificacion',       'Codificación',                    'planeado'),
    ('salidas',            'Registro de salidas',             'planeado'),
    ('mermas',             'Mermas',                          'planeado'),
    ('soda_caustica',      'Soda cáustica',                   'planeado'),
    ('informe_produccion', 'Informe general de producción',   'planeado'),
    ('historial',          'Historial / Bitácora',            'activo'),
    ('usuarios',           'Usuarios',                        'activo'),
    ('permisos',           'Permisos por rol',                'planeado')
on conflict (id) do update set nombre = excluded.nombre;

-- ---------------------------------------------------------------------
-- Matriz inicial de permisos. Ajustarla es un UPDATE/INSERT/DELETE sobre
-- permisos_rol, sin desplegar la app.
-- ---------------------------------------------------------------------
insert into public.permisos_rol (rol, modulo, accion)
select v.rol, v.modulo, a
  from (values
    -- Gerente General: observa todo, aprueba y administra usuarios/permisos.
    ('gerente', 'dashboard',          array['ver']),
    ('gerente', 'usuarios',           array['ver', 'crear', 'editar']),
    ('gerente', 'permisos',           array['ver', 'editar']),
    ('gerente', 'historial',          array['ver']),
    ('gerente', 'plan_produccion',    array['ver']),
    ('gerente', 'inventario_general', array['ver']),
    ('gerente', 'inventario_jarabes', array['ver']),
    ('gerente', 'inventario_soplado', array['ver']),
    ('gerente', 'recepciones',        array['ver']),
    ('gerente', 'entregas',           array['ver']),
    ('gerente', 'solicitudes',        array['ver']),
    ('gerente', 'aprobaciones',       array['ver', 'aprobar']),
    ('gerente', 'recetas',            array['ver', 'aprobar']),
    ('gerente', 'soplado',            array['ver']),
    ('gerente', 'jarabes_produccion', array['ver']),
    ('gerente', 'calidad',            array['ver']),
    ('gerente', 'llenado',            array['ver']),
    ('gerente', 'codificacion',       array['ver']),
    ('gerente', 'salidas',            array['ver']),
    ('gerente', 'mermas',             array['ver']),
    ('gerente', 'soda_caustica',      array['ver']),
    ('gerente', 'informe_produccion', array['ver']),

    -- Jefe de Producción: arma el plan del día; pide a Gerencia; aprueba recetas.
    ('jefe_produccion', 'dashboard',          array['ver']),
    ('jefe_produccion', 'plan_produccion',    array['ver', 'crear', 'editar']),
    ('jefe_produccion', 'inventario_general', array['ver']),
    ('jefe_produccion', 'inventario_jarabes', array['ver']),
    ('jefe_produccion', 'inventario_soplado', array['ver']),
    ('jefe_produccion', 'recepciones',        array['ver']),
    ('jefe_produccion', 'entregas',           array['ver']),
    ('jefe_produccion', 'solicitudes',        array['ver', 'crear']),
    ('jefe_produccion', 'recetas',            array['ver', 'aprobar']),
    ('jefe_produccion', 'soplado',            array['ver']),
    ('jefe_produccion', 'jarabes_produccion', array['ver']),
    ('jefe_produccion', 'calidad',            array['ver']),
    ('jefe_produccion', 'llenado',            array['ver']),
    ('jefe_produccion', 'codificacion',       array['ver']),
    ('jefe_produccion', 'salidas',            array['ver']),
    ('jefe_produccion', 'mermas',             array['ver']),
    ('jefe_produccion', 'informe_produccion', array['ver']),

    -- Almacén: control total de su almacén; recibe, entrega y solicita.
    ('almacen', 'dashboard',          array['ver']),
    ('almacen', 'inventario_general', array['ver', 'crear', 'editar', 'eliminar']),
    ('almacen', 'inventario_jarabes', array['ver']),
    ('almacen', 'inventario_soplado', array['ver']),
    ('almacen', 'recepciones',        array['ver', 'crear', 'editar']),
    ('almacen', 'entregas',           array['ver', 'crear', 'editar']),
    ('almacen', 'solicitudes',        array['ver', 'crear']),
    ('almacen', 'plan_produccion',    array['ver']),
    ('almacen', 'historial',          array['ver']),
    ('almacen', 'usuarios',           array['ver']),

    -- Jefe y Ayudante de Jarabes: su almacén, su producción, proponen recetas.
    ('jarabes', 'dashboard',          array['ver']),
    ('jarabes', 'inventario_jarabes', array['ver', 'crear', 'editar', 'eliminar']),
    ('jarabes', 'recepciones',        array['ver', 'crear']),
    ('jarabes', 'entregas',           array['ver', 'editar']),
    ('jarabes', 'solicitudes',        array['ver', 'crear']),
    ('jarabes', 'jarabes_produccion', array['ver', 'crear', 'editar']),
    ('jarabes', 'recetas',            array['ver', 'crear']),
    ('jarabes', 'soplado',            array['ver']),
    ('jarabes', 'plan_produccion',    array['ver']),
    ('jarabes', 'mermas',             array['ver', 'crear']),
    ('jarabes', 'calidad',            array['ver']),
    ('ayudante_jarabes', 'dashboard',          array['ver']),
    ('ayudante_jarabes', 'inventario_jarabes', array['ver', 'crear', 'editar', 'eliminar']),
    ('ayudante_jarabes', 'recepciones',        array['ver', 'crear']),
    ('ayudante_jarabes', 'entregas',           array['ver', 'editar']),
    ('ayudante_jarabes', 'solicitudes',        array['ver', 'crear']),
    ('ayudante_jarabes', 'jarabes_produccion', array['ver', 'crear', 'editar']),
    ('ayudante_jarabes', 'recetas',            array['ver', 'crear']),
    ('ayudante_jarabes', 'soplado',            array['ver']),
    ('ayudante_jarabes', 'plan_produccion',    array['ver']),
    ('ayudante_jarabes', 'mermas',             array['ver', 'crear']),
    ('ayudante_jarabes', 'calidad',            array['ver']),

    -- Soplado: su almacén y su producción; segunda recepción tras Almacén.
    ('soplado', 'dashboard',          array['ver']),
    ('soplado', 'inventario_general', array['ver']),
    ('soplado', 'inventario_jarabes', array['ver']),
    ('soplado', 'inventario_soplado', array['ver', 'crear', 'editar', 'eliminar']),
    ('soplado', 'recepciones',        array['ver', 'crear']),
    ('soplado', 'entregas',           array['ver', 'editar']),
    ('soplado', 'solicitudes',        array['ver', 'crear']),
    ('soplado', 'soplado',            array['ver', 'crear', 'editar']),
    ('soplado', 'plan_produccion',    array['ver']),
    ('soplado', 'mermas',             array['ver', 'crear']),

    -- Llenadora y Codificación: su registro, merma y solicitudes.
    ('llenadora', 'dashboard',          array['ver']),
    ('llenadora', 'inventario_general', array['ver']),
    ('llenadora', 'inventario_jarabes', array['ver']),
    ('llenadora', 'llenado',            array['ver', 'crear', 'editar']),
    ('llenadora', 'entregas',           array['ver', 'editar']),
    ('llenadora', 'solicitudes',        array['ver', 'crear']),
    ('llenadora', 'mermas',             array['ver', 'crear']),
    ('llenadora', 'plan_produccion',    array['ver']),
    ('codificacion', 'dashboard',          array['ver']),
    ('codificacion', 'inventario_general', array['ver']),
    ('codificacion', 'inventario_jarabes', array['ver']),
    ('codificacion', 'codificacion',       array['ver', 'crear', 'editar']),
    ('codificacion', 'entregas',           array['ver', 'editar']),
    ('codificacion', 'solicitudes',        array['ver', 'crear']),
    ('codificacion', 'mermas',             array['ver', 'crear']),
    ('codificacion', 'plan_produccion',    array['ver']),

    -- Registro de salidas: producto terminado del día.
    ('registro_salidas', 'dashboard',          array['ver']),
    ('registro_salidas', 'inventario_general', array['ver']),
    ('registro_salidas', 'inventario_jarabes', array['ver']),
    ('registro_salidas', 'salidas',            array['ver', 'crear', 'editar']),
    ('registro_salidas', 'plan_produccion',    array['ver']),

    -- Control de Calidad: análisis, aprueba cambios de receta.
    ('control_calidad', 'dashboard',          array['ver']),
    ('control_calidad', 'inventario_general', array['ver']),
    ('control_calidad', 'inventario_jarabes', array['ver']),
    ('control_calidad', 'calidad',            array['ver', 'crear', 'editar']),
    ('control_calidad', 'recetas',            array['ver', 'aprobar']),
    ('control_calidad', 'jarabes_produccion', array['ver']),
    ('control_calidad', 'entregas',           array['ver', 'editar']),
    ('control_calidad', 'solicitudes',        array['ver', 'crear']),
    ('control_calidad', 'mermas',             array['ver']),
    ('control_calidad', 'plan_produccion',    array['ver']),

    -- Encargado de Soda Cáustica: registra entregas, pide insumo, merma.
    ('soda_caustica', 'dashboard',          array['ver']),
    ('soda_caustica', 'inventario_general', array['ver']),
    ('soda_caustica', 'inventario_jarabes', array['ver']),
    ('soda_caustica', 'soda_caustica',      array['ver', 'crear', 'editar']),
    ('soda_caustica', 'entregas',           array['ver', 'editar']),
    ('soda_caustica', 'solicitudes',        array['ver', 'crear']),
    ('soda_caustica', 'mermas',             array['ver', 'crear']),
    ('soda_caustica', 'plan_produccion',    array['ver'])
  ) as v(rol, modulo, acciones)
  cross join lateral unnest(v.acciones) as a
on conflict do nothing;
