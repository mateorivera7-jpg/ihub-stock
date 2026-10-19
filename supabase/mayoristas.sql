-- Acceso mayorista de iHub Stock.
-- Pégalo completo en Supabase → SQL Editor → Run (después de esquema.sql). Se puede correr varias veces.
--
-- mayoristas          · quién se registró (nombre, apellido, celular). Se llena solo al registrarse.
-- productos_mayorista · el stock con precio POR MAYOR. Solo lo ven mayoristas con sesión iniciada y activos.
-- margenes            · se agregan las filas mayor_* (lo que se suma al costo en el precio por mayor).
--
-- Para bloquear a alguien: Table Editor → mayoristas → activo = false.

-- ---------------------------------------------------------------- mayoristas

create table if not exists public.mayoristas (
  id        uuid primary key references auth.users (id) on delete cascade,
  nombre    text not null default '',
  apellido  text not null default '',
  celular   text not null unique,
  activo    boolean not null default true,
  creado    timestamptz not null default now()
);

alter table public.mayoristas enable row level security;
grant select on public.mayoristas to authenticated;
revoke insert, update, delete, truncate on public.mayoristas from anon, authenticated;
revoke all on public.mayoristas from anon;
grant all on public.mayoristas to service_role;

drop policy if exists "cada mayorista ve su ficha" on public.mayoristas;
create policy "cada mayorista ve su ficha" on public.mayoristas for select to authenticated using (id = auth.uid());

-- Al registrarse desde la app, se crea su ficha con los datos del formulario.
create or replace function public.crear_mayorista()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.raw_user_meta_data ? 'celular' then
    insert into public.mayoristas (id, nombre, apellido, celular)
    values (new.id,
            left(coalesce(new.raw_user_meta_data->>'nombre', ''), 80),
            left(coalesce(new.raw_user_meta_data->>'apellido', ''), 80),
            left(new.raw_user_meta_data->>'celular', 20))
    on conflict (id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists al_registrar_mayorista on auth.users;
create trigger al_registrar_mayorista after insert on auth.users
  for each row execute function public.crear_mayorista();

-- Quien se registró antes de correr este archivo también queda dado de alta.
insert into public.mayoristas (id, nombre, apellido, celular)
select id, left(coalesce(raw_user_meta_data->>'nombre', ''), 80), left(coalesce(raw_user_meta_data->>'apellido', ''), 80),
       left(raw_user_meta_data->>'celular', 20)
  from auth.users
 where raw_user_meta_data ? 'celular'
on conflict do nothing;

-- ---------------------------------------------------------------- precios por mayor

create table if not exists public.productos_mayorista (
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
create index if not exists productos_mayorista_orden on public.productos_mayorista (orden);

alter table public.productos_mayorista enable row level security;
revoke all on public.productos_mayorista from anon;
grant select on public.productos_mayorista to authenticated;
revoke insert, update, delete, truncate on public.productos_mayorista from authenticated;
grant all on public.productos_mayorista to service_role;

drop policy if exists "solo mayoristas activos" on public.productos_mayorista;
create policy "solo mayoristas activos" on public.productos_mayorista for select to authenticated
  using (exists (select 1 from public.mayoristas m where m.id = auth.uid() and m.activo));

-- Reemplaza todo el stock mayorista de una sola vez. Solo la clave secreta (service_role).
create or replace function public.publicar_mayorista(productos jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if jsonb_array_length(productos) < 5 then
    raise exception 'Muy pocos productos (%); no se reemplaza el stock mayorista.', jsonb_array_length(productos);
  end if;
  delete from public.productos_mayorista where true;
  insert into public.productos_mayorista (orden, lista, modelo, categoria, color, capacidad, bateria, sim, precio)
  select n, p->>'lista', p->>'modelo', p->>'categoria', coalesce(p->>'color', ''), coalesce(p->>'capacidad', ''),
         (p->>'bateria')::int, coalesce(p->>'sim', ''), (p->>'precio')::numeric(10,2)
    from jsonb_array_elements(productos) with ordinality as t(p, n);
  return 'mayorista actualizado';
end;
$$;

revoke all on function public.publicar_mayorista(jsonb) from public, anon, authenticated;
grant execute on function public.publicar_mayorista(jsonb) to service_role;

-- ---------------------------------------------------------------- márgenes por mayor

-- Los montos reales se ponen en Table Editor → margenes (este archivo es público; aquí van en 0).
insert into public.margenes (categoria, monto, nota) values
  ('mayor_iphone',   0, 'Por mayor · iPhone'),
  ('mayor_macbook',  0, 'Por mayor · MacBook (todas)'),
  ('mayor_ipad',     0, 'Por mayor · iPad'),
  ('mayor_android',  0, 'Por mayor · Android'),
  ('mayor_cubos',    0, 'Por mayor · cargadores'),
  ('mayor_palancas', 0, 'Por mayor · controles'),
  ('mayor_otros',    0, 'Por mayor · AirPods, Watch, audífonos…')
on conflict (categoria) do nothing;
