-- Base de datos de iHub Stock en Supabase.
-- Pégalo completo en Supabase → SQL Editor → Run. Se puede correr varias veces sin romper nada.
--
-- productos  · el stock con el precio final de iHub (lo que ve la app; público, solo lectura)
-- estado     · cuándo cambió el stock y cuándo se revisó por última vez (público, solo lectura)
-- margenes   · lo que se suma a cada categoría (privado; se edita en Table Editor)
--
-- La app solo puede LEER productos y estado. Escribir solo lo hace actualizar.py con la clave secreta.

create table if not exists public.productos (
  id         bigint generated always as identity primary key,
  orden      int not null,
  lista      text not null,
  modelo     text not null,
  categoria  text not null,
  color      text not null default '',
  capacidad  text not null default '',
  bateria    int,
  sim        text not null default '',
  precio     numeric(10,2) not null
);
create index if not exists productos_orden on public.productos (orden);

create table if not exists public.estado (
  id          int primary key default 1 check (id = 1),
  actualizado timestamptz not null default now(),
  revisado    timestamptz not null default now(),
  total       int not null default 0
);
insert into public.estado (id) values (1) on conflict do nothing;

create table if not exists public.margenes (
  categoria text primary key,
  monto     numeric(10,2) not null default 0,
  nota      text not null default ''
);
-- Los montos reales se ponen en Table Editor (este archivo es público; aquí van en 0).
insert into public.margenes (categoria, monto, nota) values
  ('iphone',                    0, 'iPhone sellado u open box'),
  ('macbook_ultima_generacion', 0, 'MacBook con el chip M más alto de la lista'),
  ('macbook_anterior',          0, 'MacBook con chips anteriores'),
  ('ipad',                      0, 'iPad'),
  ('android',                    0, 'Samsung, Xiaomi, ZTE, Motorola, Honor…'),
  ('cubos',                      0, 'Cargadores / power adapter'),
  ('palancas',                   0, 'DualSense, controles, joysticks'),
  ('otros',                       0, 'AirPods, Apple Watch, audífonos…')
on conflict (categoria) do nothing;

-- ---------------------------------------------------------------- seguridad

alter table public.productos enable row level security;
alter table public.estado    enable row level security;
alter table public.margenes  enable row level security;   -- sin políticas: nadie de afuera la ve

grant usage on schema public to anon, authenticated, service_role;
grant select on public.productos, public.estado to anon, authenticated;
grant all on public.productos, public.estado, public.margenes to service_role;
revoke insert, update, delete, truncate on public.productos, public.estado from anon, authenticated;
revoke all on public.margenes from anon, authenticated;

drop policy if exists "cualquiera ve el stock" on public.productos;
create policy "cualquiera ve el stock" on public.productos for select to anon, authenticated using (true);

drop policy if exists "cualquiera ve el estado" on public.estado;
create policy "cualquiera ve el estado" on public.estado for select to anon, authenticated using (true);

-- ---------------------------------------------------------------- publicar

-- Reemplaza todo el stock de una sola vez (si algo falla, queda el stock anterior).
-- Solo lo puede llamar la clave secreta (service_role).
create or replace function public.publicar_catalogo(productos jsonb, revisado timestamptz default now())
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  previo jsonb;
  nuevo  jsonb;
begin
  if jsonb_array_length(productos) < 5 then
    raise exception 'Muy pocos productos (%); no se reemplaza el stock.', jsonb_array_length(productos);
  end if;

  select coalesce(jsonb_agg(jsonb_build_array(lista, modelo, categoria, color, capacidad, bateria, sim, precio) order by orden), '[]')
    into previo from public.productos;
  select coalesce(jsonb_agg(jsonb_build_array(p->>'lista', p->>'modelo', p->>'categoria', coalesce(p->>'color', ''),
                                              coalesce(p->>'capacidad', ''), (p->>'bateria')::int, coalesce(p->>'sim', ''),
                                              (p->>'precio')::numeric(10,2)) order by n), '[]')
    into nuevo from jsonb_array_elements(productos) with ordinality as t(p, n);

  if previo = nuevo then
    update public.estado set revisado = publicar_catalogo.revisado where id = 1;
    return 'sin cambios';
  end if;

  delete from public.productos where true;
  insert into public.productos (orden, lista, modelo, categoria, color, capacidad, bateria, sim, precio)
  select n, p->>'lista', p->>'modelo', p->>'categoria', coalesce(p->>'color', ''), coalesce(p->>'capacidad', ''),
         (p->>'bateria')::int, coalesce(p->>'sim', ''), (p->>'precio')::numeric(10,2)
    from jsonb_array_elements(productos) with ordinality as t(p, n);
  update public.estado
     set actualizado = publicar_catalogo.revisado, revisado = publicar_catalogo.revisado, total = jsonb_array_length(productos)
   where id = 1;
  return 'actualizado';
end;
$$;

revoke all on function public.publicar_catalogo(jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.publicar_catalogo(jsonb, timestamptz) to service_role;
