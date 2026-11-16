-- Acceso mayorista de iHub Stock (versión con aprobación y clave).
-- Pégalo completo en Supabase → SQL Editor → Run. Se puede correr varias veces sin romper nada.
--
-- Cómo funciona:
--   1. En la app, la persona llena "Solicitar acceso" → queda en la tabla `mayoristas` con estado 'pendiente'.
--   2. iHub la aprueba en SQL Editor:      select aprobar_mayorista('0991234567');
--      → devuelve una clave de 6 dígitos para enviarle por WhatsApp o correo
--        (o pon tu propia clave:         select aprobar_mayorista('0991234567', 'MiClave2026');)
--   3. En la app entra con su celular + clave y ve el stock con precio por mayor.
--   Bloquear a alguien:                  select bloquear_mayorista('0991234567');
--
-- Precio por mayor = precio público − descuento de su categoría (tabla `descuentos_mayorista`).
-- Los descuentos solo los recibe un mayorista aprobado con sesión válida. Nada de esto es visible para el público.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- tablas

create table if not exists public.mayoristas (
  id              bigint generated always as identity primary key,
  creado          timestamptz not null default now(),
  nombre          text not null,
  apellido        text not null,
  celular         text not null unique,          -- 593XXXXXXXXX
  correo          text not null default '',
  negocio         text not null default '',
  ciudad          text not null default '',
  estado          text not null default 'pendiente' check (estado in ('pendiente', 'aprobado', 'bloqueado')),
  clave_hash      text,
  intentos        int not null default 0,
  ultimo_ingreso  timestamptz
);

create table if not exists public.sesiones_mayorista (
  token_hash    text primary key,
  mayorista_id  bigint not null references public.mayoristas (id) on delete cascade,
  expira        timestamptz not null
);

create table if not exists public.descuentos_mayorista (
  categoria  text primary key,
  monto      numeric(10,2) not null default 0,
  nota       text not null default ''
);

-- Los montos reales se ponen en Table Editor → descuentos_mayorista (este archivo es público; aquí van en 0).
insert into public.descuentos_mayorista (categoria, monto, nota) values
  ('iphone',                    0, 'Se resta al precio público del iPhone'),
  ('macbook_ultima_generacion', 0, 'MacBook con el chip M más alto de la lista'),
  ('macbook_anterior',          0, 'Otras MacBook'),
  ('ipad',                      0, 'iPad'),
  ('android',                   0, 'Samsung, Xiaomi, ZTE…'),
  ('cubos',                     0, 'Cargadores'),
  ('palancas',                  0, 'Controles'),
  ('otros',                     0, 'AirPods, Apple Watch, audífonos…')
on conflict (categoria) do nothing;

-- Nadie de afuera lee ni escribe estas tablas directamente: todo pasa por las funciones de abajo.
alter table public.mayoristas           enable row level security;
alter table public.sesiones_mayorista   enable row level security;
alter table public.descuentos_mayorista enable row level security;
revoke all on public.mayoristas, public.sesiones_mayorista, public.descuentos_mayorista from anon, authenticated;

-- ---------------------------------------------------------------- utilidades

create or replace function public._celular(p text)
returns text language sql immutable as $$
  select case
    when length(d) = 12 and d like '593%' then d
    when length(d) = 10 and d like '0%'   then '593' || substr(d, 2)
    when length(d) = 9                    then '593' || d
  end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$$;

create or replace function public._nueva_sesion(p_id bigint)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  delete from sesiones_mayorista where expira < now();
  insert into sesiones_mayorista (token_hash, mayorista_id, expira)
  values (encode(extensions.digest(t, 'sha256'), 'hex'), p_id, now() + interval '30 days');
  update mayoristas set ultimo_ingreso = now(), intentos = 0 where id = p_id;
  return t;
end;
$$;

-- ---------------------------------------------------------------- desde la app (público)

-- 1. Solicitar acceso.
create or replace function public.solicitar_mayorista(p_nombre text, p_apellido text, p_celular text,
                                                       p_correo text default '', p_negocio text default '', p_ciudad text default '')
returns text language plpgsql security definer set search_path = public as $$
declare cel text := _celular(p_celular); actual text;
begin
  if cel is null then return 'celular_invalido'; end if;
  if length(trim(coalesce(p_nombre, ''))) < 2 or length(trim(coalesce(p_apellido, ''))) < 2 then return 'faltan_datos'; end if;
  select estado into actual from mayoristas where celular = cel;
  if actual = 'aprobado' then return 'ya_aprobado'; end if;
  if actual = 'bloqueado' then return 'bloqueado'; end if;
  insert into mayoristas (nombre, apellido, celular, correo, negocio, ciudad)
  values (left(trim(p_nombre), 60), left(trim(p_apellido), 60), cel, left(lower(trim(coalesce(p_correo, ''))), 120),
          left(trim(coalesce(p_negocio, '')), 80), left(trim(coalesce(p_ciudad, '')), 60))
  on conflict (celular) do update
     set nombre = excluded.nombre, apellido = excluded.apellido, correo = excluded.correo,
         negocio = excluded.negocio, ciudad = excluded.ciudad;
  return 'pendiente';
end;
$$;

-- 2. Ingresar con celular + clave → token de sesión (30 días).
create or replace function public.acceso_mayorista(p_celular text, p_clave text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare m mayoristas;
begin
  select * into m from mayoristas where celular = _celular(p_celular);
  if not found then return json_build_object('error', 'no_registrado'); end if;
  if m.estado = 'pendiente' then return json_build_object('error', 'pendiente'); end if;
  if m.estado <> 'aprobado' or m.clave_hash is null then return json_build_object('error', 'bloqueado'); end if;
  if m.intentos >= 10 then return json_build_object('error', 'demasiados_intentos'); end if;
  if extensions.crypt(coalesce(p_clave, ''), m.clave_hash) <> m.clave_hash then
    update mayoristas set intentos = intentos + 1 where id = m.id;
    return json_build_object('error', 'clave');
  end if;
  return json_build_object('token', _nueva_sesion(m.id));
end;
$$;

-- 2b. Ingresar con código al correo (Supabase Auth): si el correo es de un mayorista aprobado → token.
create or replace function public.acceso_mayorista_correo()
returns json language plpgsql security definer set search_path = public as $$
declare m mayoristas; v_correo text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if v_correo = '' then return json_build_object('error', 'sin_sesion'); end if;
  select * into m from mayoristas where lower(mayoristas.correo) = v_correo and mayoristas.estado = 'aprobado' limit 1;
  if not found then return json_build_object('error', 'correo_no_aprobado'); end if;
  return json_build_object('token', _nueva_sesion(m.id));
end;
$$;

-- 3. Con un token válido devuelve el perfil y los descuentos.
create or replace function public.datos_mayorista(p_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare m mayoristas;
begin
  select ma.* into m
    from sesiones_mayorista s join mayoristas ma on ma.id = s.mayorista_id
   where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
     and s.expira > now() and ma.estado = 'aprobado';
  if not found then return null; end if;
  return json_build_object(
    'nombre', m.nombre, 'apellido', m.apellido, 'celular', m.celular,
    'descuentos', (select json_object_agg(categoria, monto) from descuentos_mayorista));
end;
$$;

-- 4. Cerrar sesión.
create or replace function public.salir_mayorista(p_token text)
returns void language sql security definer set search_path = public, extensions as $$
  delete from sesiones_mayorista where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

-- ---------------------------------------------------------------- solo para iHub (SQL Editor)

create or replace function public.aprobar_mayorista(p_celular text, p_clave text default null)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare clave text := coalesce(nullif(trim(p_clave), ''),
          lpad(((('x00' || encode(extensions.gen_random_bytes(3), 'hex'))::bit(32)::int) % 1000000)::text, 6, '0'));
        m mayoristas;
begin
  update mayoristas set estado = 'aprobado', clave_hash = extensions.crypt(clave, extensions.gen_salt('bf')), intentos = 0
   where celular = _celular(p_celular) returning * into m;
  if not found then return 'No hay ninguna solicitud con ese celular.'; end if;
  return format('Aprobado: %s %s (%s). Su clave es: %s', m.nombre, m.apellido, m.celular, clave);
end;
$$;

create or replace function public.bloquear_mayorista(p_celular text)
returns text language plpgsql security definer set search_path = public as $$
declare m mayoristas;
begin
  update mayoristas set estado = 'bloqueado' where celular = _celular(p_celular) returning * into m;
  if not found then return 'No hay ningún mayorista con ese celular.'; end if;
  delete from sesiones_mayorista where mayorista_id = m.id;
  return format('Bloqueado: %s %s.', m.nombre, m.apellido);
end;
$$;

-- ---------------------------------------------------------------- permisos

revoke all on function public._celular(text), public._nueva_sesion(bigint),
                       public.aprobar_mayorista(text, text), public.bloquear_mayorista(text)
  from public, anon, authenticated;
revoke all on function public.solicitar_mayorista(text, text, text, text, text, text), public.acceso_mayorista(text, text),
                       public.acceso_mayorista_correo(), public.datos_mayorista(text), public.salir_mayorista(text)
  from public;
grant execute on function public.solicitar_mayorista(text, text, text, text, text, text), public.acceso_mayorista(text, text),
                          public.datos_mayorista(text), public.salir_mayorista(text) to anon, authenticated;
grant execute on function public.acceso_mayorista_correo() to authenticated;
