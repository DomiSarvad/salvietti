-- =====================================================================
-- SISTEMA SALVIETTI — Esquema v2 (roles, proveedores/transportadores,
-- producción con recetas, saldo de Jarabes tipo "caja chica")
-- Ejecutar DESPUÉS de schema.sql (o sobre la misma base, es idempotente)
-- Supabase Dashboard > SQL Editor > New query > pegar todo > Run
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. PERFILES Y ROLES
--    gerente   -> solo lectura + analítica + administra usuarios/roles
--    almacen   -> lectura/escritura de TODO
--    jarabes   -> lectura/escritura SOLO de su propia área (Jarabes)
--    ingeniero -> solo lectura + arma y marca la producción del día
-- ---------------------------------------------------------------------
do $$ begin
  create type public.rol_usuario as enum ('gerente','almacen','jarabes','ingeniero');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nombre      text not null,
  rol         public.rol_usuario not null default 'ingeniero',
  avatar_url  text,
  tema        text not null default 'claro',   -- 'claro' | 'oscuro' (personalización, no cambia permisos)
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- El propio usuario puede leer y actualizar SOLO avatar_url y tema (no nombre ni rol).
create or replace function public.fn_bloquear_cambio_nombre_rol()
returns trigger language plpgsql as $$
begin
  if auth.role() = 'authenticated' and not public.es_gerente(auth.uid()) then
    new.nombre := old.nombre;
    new.rol := old.rol;
    new.activo := old.activo;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Helpers de rol (para RLS y para el frontend vía RPC)
-- ---------------------------------------------------------------------
create or replace function public.rol_de(p_uid uuid)
returns public.rol_usuario language sql stable as $$
  select rol from public.profiles where id = p_uid;
$$;

create or replace function public.es_gerente(p_uid uuid) returns boolean language sql stable as $$
  select coalesce((select rol = 'gerente' from public.profiles where id = p_uid), false);
$$;
create or replace function public.es_almacen(p_uid uuid) returns boolean language sql stable as $$
  select coalesce((select rol = 'almacen' from public.profiles where id = p_uid), false);
$$;
create or replace function public.es_jarabes(p_uid uuid) returns boolean language sql stable as $$
  select coalesce((select rol = 'jarabes' from public.profiles where id = p_uid), false);
$$;
create or replace function public.es_ingeniero(p_uid uuid) returns boolean language sql stable as $$
  select coalesce((select rol = 'ingeniero' from public.profiles where id = p_uid), false);
$$;
-- Puede escribir en insumos/movimientos "generales" (todo excepto jarabes)
create or replace function public.puede_editar_almacen(p_uid uuid) returns boolean language sql stable as $$
  select public.es_almacen(p_uid);
$$;

drop trigger if exists trg_bloquear_cambio_nombre_rol on public.profiles;
create trigger trg_bloquear_cambio_nombre_rol
  before update on public.profiles
  for each row execute function public.fn_bloquear_cambio_nombre_rol();

-- Crea automáticamente un perfil (rol por defecto 'ingeniero') cuando se
-- registra un usuario nuevo en Supabase Auth. El Gerente lo asciende luego.
create or replace function public.fn_nuevo_usuario()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, nombre, rol)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)), 'ingeniero');
  return new;
end;
$$;
drop trigger if exists trg_nuevo_usuario on auth.users;
create trigger trg_nuevo_usuario
  after insert on auth.users
  for each row execute function public.fn_nuevo_usuario();

-- ---------------------------------------------------------------------
-- 3. PROVEEDORES Y TRANSPORTADORES (autocompletar-o-crear)
--    Si el usuario escribe uno nuevo, la app lo inserta aquí sin pedir
--    ningún dato adicional; queda disponible para el próximo autocomplete.
-- ---------------------------------------------------------------------
create table if not exists public.proveedores (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null unique,
  created_at  timestamptz not null default now()
);
create table if not exists public.transportadores (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null unique,
  created_at  timestamptz not null default now()
);

insert into public.proveedores (nombre) values
  ('Sapore'),('San Aurelio'),('Maprial'),('Alemcorp'),('IFF'),('Matriseven'),('SMI'),('Intercom'),('Naturex')
on conflict (nombre) do nothing;

-- ---------------------------------------------------------------------
-- 4. Ampliar tabla movimientos (transportador, precio de transporte,
--    usuario que registró, área del movimiento)
-- ---------------------------------------------------------------------
alter table public.movimientos add column if not exists transportador text;
alter table public.movimientos add column if not exists precio_transporte numeric(12,2);
alter table public.movimientos add column if not exists registrado_por uuid references public.profiles(id);
alter table public.movimientos add column if not exists area text not null default 'almacen'; -- 'almacen' | 'jarabes'

-- ---------------------------------------------------------------------
-- 5. RECETAS DE PRODUCCIÓN (para el descuento automático de insumos)
--    Cada sabor consume X unidades de cada insumo por litro producido.
-- ---------------------------------------------------------------------
create table if not exists public.recetas (
  id            uuid primary key default gen_random_uuid(),
  sabor         text not null,
  insumo_id     uuid not null references public.insumos(id) on delete cascade,
  cantidad_por_litro numeric(12,4) not null,
  unique (sabor, insumo_id)
);

-- ---------------------------------------------------------------------
-- 6. PRODUCCIÓN DEL DÍA (Ingeniero arma la lista; al marcar "Completado"
--    se descuentan automáticamente los insumos según la receta)
-- ---------------------------------------------------------------------
create table if not exists public.produccion_diaria (
  id                uuid primary key default gen_random_uuid(),
  fecha             date not null default current_date,
  sabor             text not null,
  litros_planificados numeric(12,2) not null,
  estado            text not null default 'pendiente' check (estado in ('pendiente','completado')),
  creado_por        uuid references public.profiles(id),
  completado_por    uuid references public.profiles(id),
  completado_en     timestamptz,
  created_at        timestamptz not null default now()
);

create or replace function public.fn_completar_produccion(p_id uuid)
returns void language plpgsql security definer as $$
declare
  v_prod record;
  v_receta record;
  v_mov_id text;
begin
  select * into v_prod from public.produccion_diaria where id = p_id and estado = 'pendiente';
  if not found then
    raise exception 'La producción ya fue marcada o no existe.';
  end if;

  for v_receta in select * from public.recetas where sabor = v_prod.sabor loop
    v_mov_id := public.fn_siguiente_movimiento_id('OUT');
    insert into public.movimientos (id, tipo, insumo_id, insumo_nombre, cantidad, unidad, fecha, hora, orden, area, registrado_por, notas)
    select v_mov_id, 'OUT', i.id, i.nombre, v_receta.cantidad_por_litro * v_prod.litros_planificados, i.unidad,
           current_date, current_time, 'Producción ' || v_prod.sabor, 'almacen', v_prod.creado_por,
           'Descuento automático por producción del día (' || v_prod.sabor || ')'
    from public.insumos i where i.id = v_receta.insumo_id;
  end loop;

  update public.produccion_diaria
     set estado = 'completado', completado_en = now()
   where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. JARABES — saldo tipo "caja chica"
--    a) Almacén asigna una cantidad de un insumo (concentrado, azúcar, etc.)
--       al área de Jarabes -> se descuenta del inventario general y se
--       acredita al saldo de Jarabes.
--    b) El personal de Jarabes registra su consumo contra ESE saldo,
--       igual que en el cuaderno de papel (columna "Saldo").
-- ---------------------------------------------------------------------
create table if not exists public.jarabes_saldos (
  insumo_id   uuid primary key references public.insumos(id) on delete cascade,
  saldo       numeric(14,3) not null default 0
);

create table if not exists public.jarabes_asignaciones (
  id            uuid primary key default gen_random_uuid(),
  insumo_id     uuid not null references public.insumos(id),
  cantidad      numeric(14,3) not null check (cantidad > 0),
  fecha         date not null default current_date,
  entregado_por uuid references public.profiles(id),
  notas         text,
  created_at    timestamptz not null default now()
);

create table if not exists public.jarabes_movimientos (
  id              uuid primary key default gen_random_uuid(),
  insumo_id       uuid not null references public.insumos(id),
  cantidad_usada  numeric(14,3) not null check (cantidad_usada > 0),
  sabor_producido text,
  litros_producidos numeric(12,2),
  fecha           date not null default current_date,
  hora            time not null default current_time,
  observaciones   text,
  registrado_por  uuid references public.profiles(id),
  created_at      timestamptz not null default now()
);

create or replace function public.fn_asignar_a_jarabes()
returns trigger language plpgsql as $$
begin
  update public.insumos
     set stock_real = greatest(0, stock_real - new.cantidad),
         stock_sistema = greatest(0, stock_sistema - new.cantidad)
   where id = new.insumo_id;

  insert into public.jarabes_saldos (insumo_id, saldo)
  values (new.insumo_id, new.cantidad)
  on conflict (insumo_id) do update set saldo = public.jarabes_saldos.saldo + excluded.saldo;

  return new;
end;
$$;
drop trigger if exists trg_asignar_a_jarabes on public.jarabes_asignaciones;
create trigger trg_asignar_a_jarabes
  after insert on public.jarabes_asignaciones
  for each row execute function public.fn_asignar_a_jarabes();

create or replace function public.fn_consumir_saldo_jarabes()
returns trigger language plpgsql as $$
begin
  update public.jarabes_saldos
     set saldo = greatest(0, saldo - new.cantidad_usada)
   where insumo_id = new.insumo_id;

  if not found then
    insert into public.jarabes_saldos (insumo_id, saldo) values (new.insumo_id, 0);
  end if;

  return new;
end;
$$;
drop trigger if exists trg_consumir_saldo_jarabes on public.jarabes_movimientos;
create trigger trg_consumir_saldo_jarabes
  after insert on public.jarabes_movimientos
  for each row execute function public.fn_consumir_saldo_jarabes();

-- ---------------------------------------------------------------------
-- 8. RLS por rol (reemplaza las políticas "anon_all" abiertas de schema.sql)
-- ---------------------------------------------------------------------
alter table public.profiles              enable row level security;
alter table public.proveedores           enable row level security;
alter table public.transportadores       enable row level security;
alter table public.recetas               enable row level security;
alter table public.produccion_diaria     enable row level security;
alter table public.jarabes_saldos        enable row level security;
alter table public.jarabes_asignaciones  enable row level security;
alter table public.jarabes_movimientos   enable row level security;

-- profiles: todos autenticados pueden leer todos los perfiles (para
-- mostrar nombres); solo el propio usuario o el gerente pueden actualizar.
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select using (auth.uid() is not null);
drop policy if exists "profiles_update_self_or_gerente" on public.profiles;
create policy "profiles_update_self_or_gerente" on public.profiles
  for update using (auth.uid() = id or public.es_gerente(auth.uid()));
drop policy if exists "profiles_insert_gerente" on public.profiles;
create policy "profiles_insert_gerente" on public.profiles
  for insert with check (auth.uid() = id or public.es_gerente(auth.uid()));

-- proveedores / transportadores: cualquier autenticado puede leer y crear
-- (autocompletar-o-crear), nadie borra desde la app.
drop policy if exists "proveedores_rw" on public.proveedores;
create policy "proveedores_rw" on public.proveedores for all
  using (auth.uid() is not null) with check (auth.uid() is not null);
drop policy if exists "transportadores_rw" on public.transportadores;
create policy "transportadores_rw" on public.transportadores for all
  using (auth.uid() is not null) with check (auth.uid() is not null);

-- insumos / movimientos: reemplaza políticas abiertas por reglas de rol.
drop policy if exists "anon_all_insumos" on public.insumos;
drop policy if exists "insumos_select" on public.insumos;
create policy "insumos_select" on public.insumos for select using (auth.uid() is not null);
drop policy if exists "insumos_write_almacen" on public.insumos;
create policy "insumos_write_almacen" on public.insumos for all
  using (public.es_almacen(auth.uid())) with check (public.es_almacen(auth.uid()));

drop policy if exists "anon_all_movimientos" on public.movimientos;
drop policy if exists "movimientos_select" on public.movimientos;
create policy "movimientos_select" on public.movimientos for select using (auth.uid() is not null);
drop policy if exists "movimientos_insert" on public.movimientos;
create policy "movimientos_insert" on public.movimientos for insert
  with check (
    public.es_almacen(auth.uid())
    or (area = 'jarabes' and public.es_jarabes(auth.uid()))
  );

-- recetas: solo almacén/gerente las mantienen; todos pueden leerlas.
drop policy if exists "recetas_select" on public.recetas;
create policy "recetas_select" on public.recetas for select using (auth.uid() is not null);
drop policy if exists "recetas_write" on public.recetas;
create policy "recetas_write" on public.recetas for all
  using (public.es_almacen(auth.uid()) or public.es_gerente(auth.uid()))
  with check (public.es_almacen(auth.uid()) or public.es_gerente(auth.uid()));

-- produccion_diaria: ingeniero crea y marca completado; los demás solo leen.
drop policy if exists "produccion_select" on public.produccion_diaria;
create policy "produccion_select" on public.produccion_diaria for select using (auth.uid() is not null);
drop policy if exists "produccion_insert" on public.produccion_diaria;
create policy "produccion_insert" on public.produccion_diaria for insert
  with check (public.es_ingeniero(auth.uid()) or public.es_almacen(auth.uid()));
drop policy if exists "produccion_update" on public.produccion_diaria;
create policy "produccion_update" on public.produccion_diaria for update
  using (public.es_ingeniero(auth.uid()) or public.es_almacen(auth.uid()));

-- jarabes_*: almacén ve y asigna todo; jarabes ve y registra solo su consumo.
drop policy if exists "jarabes_saldos_select" on public.jarabes_saldos;
create policy "jarabes_saldos_select" on public.jarabes_saldos for select using (auth.uid() is not null);

drop policy if exists "jarabes_asignaciones_select" on public.jarabes_asignaciones;
create policy "jarabes_asignaciones_select" on public.jarabes_asignaciones for select using (auth.uid() is not null);
drop policy if exists "jarabes_asignaciones_insert" on public.jarabes_asignaciones;
create policy "jarabes_asignaciones_insert" on public.jarabes_asignaciones for insert
  with check (public.es_almacen(auth.uid()));

drop policy if exists "jarabes_movimientos_select" on public.jarabes_movimientos;
create policy "jarabes_movimientos_select" on public.jarabes_movimientos for select using (auth.uid() is not null);
drop policy if exists "jarabes_movimientos_insert" on public.jarabes_movimientos;
create policy "jarabes_movimientos_insert" on public.jarabes_movimientos for insert
  with check (public.es_jarabes(auth.uid()) or public.es_almacen(auth.uid()));

-- config: gerente y almacén pueden guardar umbrales; todos leen.
drop policy if exists "anon_all_config" on public.config;
drop policy if exists "config_select" on public.config;
create policy "config_select" on public.config for select using (auth.uid() is not null);
drop policy if exists "config_write" on public.config;
create policy "config_write" on public.config for all
  using (public.es_almacen(auth.uid()) or public.es_gerente(auth.uid()))
  with check (public.es_almacen(auth.uid()) or public.es_gerente(auth.uid()));

-- ---------------------------------------------------------------------
-- 9. Primer Gerente
--    Después de crear tu primer usuario desde la pantalla de login,
--    ejecuta esto UNA vez reemplazando el correo para volverlo Gerente:
--
--    update public.profiles set rol = 'gerente'
--      where id = (select id from auth.users where email = 'tu-correo@ejemplo.com');
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 10. Recetas de ejemplo (ajusta cantidades reales por litro).
--     Sin al menos una fila por sabor, "Marcar completado" en Producción
--     no tendrá qué descontar para ese sabor (no da error, simplemente
--     no resta nada) — complétalas con tus fórmulas reales.
-- ---------------------------------------------------------------------
insert into public.recetas (sabor, insumo_id, cantidad_por_litro)
select 'Lima Limón', id, 0.05 from public.insumos where codigo = 'AZ-001'
union all
select 'Lima Limón', id, 0.006 from public.insumos where codigo = 'CN-002'
on conflict (sabor, insumo_id) do nothing;
