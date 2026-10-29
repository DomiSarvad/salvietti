-- v45: recorridos guiados ya vistos, POR USUARIO (re-ejecutable).
--
-- Hasta acá se recordaba solo en la compu (Hive). En un navegador que borra
-- sus datos (o `flutter run -d chrome`, que abre un perfil nuevo cada vez) el
-- recorrido volvía a salir solo en cada ingreso. Ahora el servidor recuerda
-- qué recorrido vio cada persona: sale solo la primera vez que entra, en
-- cualquier compu; después, solo con el botón "?".
--
-- Es un dato personal (como datos_empleado), no un módulo: cada uno ve y
-- escribe solo lo suyo.

create table if not exists public.tours_vistos (
    usuario_id uuid not null default auth.uid() references public.usuarios(id) on delete cascade,
    id_tour text not null check (char_length(id_tour) between 1 and 60),
    visto_en timestamptz not null default now(),
    primary key (usuario_id, id_tour)
);

comment on table public.tours_vistos is
    'Recorridos guiados que cada usuario ya vio (para no mostrarlos solos de nuevo).';

alter table public.tours_vistos enable row level security;

drop policy if exists "tours_vistos_ver" on public.tours_vistos;
create policy "tours_vistos_ver" on public.tours_vistos for select
    using (usuario_id = auth.uid());

drop policy if exists "tours_vistos_crear" on public.tours_vistos;
create policy "tours_vistos_crear" on public.tours_vistos for insert
    with check (usuario_id = auth.uid());

-- "Volver a ver los recorridos" (Configuración) borra los propios.
drop policy if exists "tours_vistos_borrar" on public.tours_vistos;
create policy "tours_vistos_borrar" on public.tours_vistos for delete
    using (usuario_id = auth.uid());

grant select, insert, delete on public.tours_vistos to authenticated;
