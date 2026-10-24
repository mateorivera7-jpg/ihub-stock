# iHub Stock

App web + app de celular (se instala desde el navegador) con el stock de iHub.
Se actualiza sola leyendo la lista de distribuidores y sumando el margen de iHub.

## Cómo funciona

1. `actualizar.py` abre https://mcdistribucion.streamlit.app/, lee todas sus listas
   (Openbox, Teléfonos nuevos, Gadgets y cualquier lista nueva que aparezca).
2. Suma el margen de iHub a cada producto (los montos son privados: están en la tabla `margenes` de Supabase).
3. Guarda `docs/data/catalogo.json` (solo precios finales; nunca el costo).
4. La app (`docs/`) lee ese archivo y se refresca cada 5 minutos.

## Publicarla gratis (GitHub, una sola vez, ~10 min)

1. Crea una cuenta en https://github.com y un repositorio nuevo, por ejemplo `ihub-stock`.
2. Sube todo el contenido de esta carpeta (botón **Add file → Upload files**; incluye la carpeta `.github`).
3. En el repositorio: **Settings → Pages → Build and deployment → Deploy from a branch**,
   rama `main`, carpeta `/docs`. Guarda.
4. En **Settings → Actions → General → Workflow permissions** marca **Read and write permissions**.
5. Ve a **Actions → Actualizar stock → Run workflow** para la primera actualización.

Tu app queda en `https://TU-USUARIO.github.io/ihub-stock/`. Desde ahí:
- **iPhone:** ábrela en Safari → Compartir → *Agregar a pantalla de inicio*.
- **Android:** ábrela en Chrome → menú ⋮ → *Instalar app*.

Se actualiza cada 20 minutos de 6:00 a 22:00 (hora de Ecuador). Para actualizar al instante: Actions → Run workflow.
Si quieres usar tu dominio (por ejemplo `stock.ihub.com.ec`), se configura en Settings → Pages → Custom domain.

## Foto del producto estrella

El banner muestra el iPhone 18 Pro / 18 Pro Max. Para poner tu foto real, sube una imagen llamada
`destacado.jpg` dentro de la carpeta `docs/` (en GitHub: entra a `docs` → Add file → Upload files).
Debe ser formato JPG, mejor con fondo oscuro, de unos 1000 px de ancho. Si no hay foto, se ve la ilustración.
Para cambiar el producto estrella, edita `DESTACADOS` al inicio del script en `docs/index.html`.

## Base de datos (Supabase)

La app lee el stock de Supabase (proyecto **iHub Stock**, https://rtifsifehgsejfgeetdq.supabase.co).
Si Supabase no responde, usa sola `docs/data/catalogo.json` como respaldo.

- **Tablas:** `productos` (el stock con precio final), `estado` (cuándo se actualizó) y `margenes`
  (lo que se suma por categoría). El esquema completo está en `supabase/esquema.sql`.
- **Seguridad:** la clave publishable que va en `docs/index.html` solo permite LEER productos y estado.
  Nadie de afuera puede borrar, cambiar precios ni ver los márgenes.
- **Cambiar márgenes:** Supabase → Table Editor → `margenes` → edita el monto. Se aplica en la próxima actualización.

### Para que la actualización automática escriba en Supabase (una sola vez)

1. Supabase → Project Settings → API Keys → **Secret keys** → copia la clave `sb_secret_…`.
2. En GitHub, tu repositorio → Settings → Secrets and variables → Actions → **New repository secret**:
   - `SUPABASE_URL` = `https://rtifsifehgsejfgeetdq.supabase.co`
   - `SUPABASE_SECRET_KEY` = la clave `sb_secret_…`
3. Actions → Actualizar stock → Run workflow. En el registro debe salir `Supabase: actualizado` o `Supabase: sin cambios`.

Nunca pongas la clave secreta dentro de `docs/` ni la compartas: con ella se puede cambiar todo.

## Noticias y recién llegados

- **Noticias:** la app copia el recuadro NOTICIAS de la lista origen (por ejemplo "Disponibles entrega inmediata…").
- **Recién llegados:** cada producto que aparece y no estaba en la revisión anterior lleva la etiqueta **Nuevo**
  durante 7 días (`DIAS_NUEVO` en `actualizar.py`). La campanita de arriba muestra cuántos no ha visto cada persona
  y la pestaña "Recién llegados" los filtra.

## Actualización automática en GitHub (una sola vez)

GitHub → Settings → Secrets and variables → Actions → **New repository secret**:
- `MARGENES_JSON` = el contenido de tu `margenes.json` (en una sola línea). Con esto se actualiza cada 20 min.
- Opcional, para Supabase y mayoristas: `SUPABASE_URL` y `SUPABASE_SECRET_KEY`.

## Mayoristas (precio por mayor)

En la app, el botón **Mayoristas** permite registrarse con nombre, apellido, celular y clave.
Con la sesión iniciada, la lista muestra el precio por mayor (tabla `productos_mayorista`, que solo ven
mayoristas registrados y activos; nunca está en el archivo público `catalogo.json`).

- **Márgenes por mayor:** filas `mayor_*` de la tabla `margenes` (iPhone, MacBook, iPad, Android, cubos, palancas, otros).
  El precio por mayor nunca supera al precio público.
- **Ver quién se registró / bloquear a alguien:** Supabase → Table Editor → `mayoristas` → `activo = false`.
- **Instalar (una sola vez):** pega `supabase/mayoristas.sql` en SQL Editor → Run, y en
  Authentication → Sign In / Providers → Email desactiva **Confirm email** (el usuario es el celular, no un correo real).

## Cambiar márgenes

Cámbialos en Supabase → Table Editor → `margenes`. Se aplican en la próxima actualización (cada 20 minutos).

## Probar en tu computadora

```bash
pip install -r requirements.txt
python -m playwright install chromium
python actualizar.py
python -m http.server 8765 --directory docs
```
