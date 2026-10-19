# iHub Stock en GoHighLevel: paso a paso

Tiempo total estimado: **60–90 minutos** (la mayor parte es esperar que el dominio se active).

## Cómo funciona (en una línea)

GitHub hace de **servidor y base de datos**: cada 20 minutos lee Mundo Celular, suma los márgenes de iHub
y guarda el stock en `docs/data/catalogo.json`. GoHighLevel **muestra** la app con un bloque de Código personalizado.

```
Mundo Celular ──(cada 20 min)──► GitHub (base de datos + app) ──► Página de GoHighLevel ──► Clientes / vendedores
```

> GoHighLevel **no permite subir un ZIP** ni alojar una app. Su base de datos (Custom Objects) tampoco se puede leer
> desde una página pública sin exponer tu clave. Por eso el stock vive en GitHub, que es gratis y no expone nada.

---

## ✅ Lista de tareas

### Parte A · GitHub (25 min) — la base de datos que se actualiza sola
- [ ] **A1.** Crear cuenta gratis en https://github.com (si no tienes).
- [ ] **A2.** Botón verde **New** → Repository name: **`ihub-stock`** (exactamente así) → **Public** → **Create repository**.
- [ ] **A3.** Clic en **uploading an existing file** → arrastra **todo el contenido** de la carpeta `ihub-catalogo`
      (incluida la carpeta oculta `.github`: en Mac `Cmd + Shift + .` para verla) → **Commit changes**.
- [ ] **A4.** **Settings → Actions → General** → *Workflow permissions* → **Read and write permissions** → **Save**.
- [ ] **A5.** **Settings → Pages** → *Source:* **Deploy from a branch** → Branch **main** / carpeta **/docs** → **Save**.
- [ ] **A6.** Pestaña **Actions** → **Actualizar stock** → **Run workflow** → espera el ✅ verde (3–5 min).
- [ ] **A7.** Abre `https://TU-USUARIO.github.io/ihub-stock/` y confirma que ves el stock con el logo de IHUB.

### Parte B · GoHighLevel (15 min) — la página
- [ ] **B1.** Entra a la sub-cuenta **IHUB** → **Sites → Funnels** → **+ New Funnel** → *From blank* → nombre: **Stock IHUB**.
- [ ] **B2.** **+ Add New Step** → nombre **Stock**, ruta `/stock` → **Edit**.
- [ ] **B3.** Borra todo lo que trae la plantilla. Agrega **una sección** → ajustes de la sección: **Full Width** activado;
      en *Sección, Fila y Columna* pon **Padding = 0** y **Margin = 0**.
- [ ] **B4.** **+ (Elementos) → Custom Code** (Código personalizado) → arrástralo a la columna → **Open Code Editor**.
- [ ] **B5.** Abre `codigo-para-ghl.html` (en esta carpeta), cambia **TU-USUARIO** por tu usuario de GitHub (2 veces), copia todo y pégalo → **Save**.
- [ ] **B6.** **Settings** del funnel → desactiva **Optimize JavaScript** si está activo.
- [ ] **B7.** **Save → Preview** (en el editor el código no se ve; en Preview sí) → **Publish**.
- [ ] **B8.** Prueba en tu celular: abre el link del funnel, toca un botón verde de WhatsApp y confirma que abre el chat.

### Parte C · Dominio propio (10 min de trabajo + espera) — opcional pero recomendado
- [ ] **C1.** GHL → **Settings → Domains & URL Redirects → + Connect a domain** → elige *Funnel/Website* → escribe **stock.ihub.com.ec**.
- [ ] **C2.** Elige **Add record manually** y copia el registro **CNAME** que GHL te muestra
      (host `stock`, valor el que indique GHL, normalmente `sites.ludicrous.cloud`).
- [ ] **C3.** En el panel donde administras **ihub.com.ec** (Cloudflare, Nic.ec, GoDaddy…) crea ese **CNAME**.
      Si es Cloudflare: nube **gris (DNS only)**.
- [ ] **C4.** Vuelve a GHL → **Verify**. El SSL (candado) se activa solo en minutos; el DNS puede tardar hasta 24 h.
- [ ] **C5.** Funnel **Stock IHUB → Settings → Domain** → elige **stock.ihub.com.ec** → **Save** → vuelve a **Publish**.

### Parte D · Cierre (5 min)
- [ ] **D1.** Comparte `https://stock.ihub.com.ec/stock` con vendedores y clientes (o el link del funnel mientras el dominio se activa).
- [ ] **D2.** Instálala en el celular: iPhone → Safari → Compartir → *Agregar a inicio*. Android → Chrome → ⋮ → *Instalar app*
      (para instalarla como app usa el link de GitHub `TU-USUARIO.github.io/ihub-stock`).
- [ ] **D3.** Desactiva la tarea programada de Claude "iHub · Actualizar stock" (ya no hace falta; GitHub la reemplaza).

---

## Día a día

| Quiero… | Hago… |
|---|---|
| Ver que se está actualizando | En la app, arriba a la derecha: "Stock actualizado hace X min" |
| Actualizar ya mismo | GitHub → Actions → Actualizar stock → **Run workflow** |
| Cambiar un margen | Supabase → Table Editor → `margenes` → cambia el monto. Se aplica en la próxima actualización (cada 20 min) |
| Poner foto real del producto estrella | GitHub → carpeta `docs` → Add file → Upload → archivo **`destacado.jpg`** |
| Cambiar el producto estrella | `docs/index.html` → línea `const DESTACADOS = [...]` |

## Si algo falla

- **La página de GHL sale en blanco:** revisa que cambiaste TU-USUARIO y que el link de GitHub (A7) abre solo.
- **Actions en rojo ❌:** abre la ejecución y mira el error. Lo normal es que Mundo Celular cambió su página; la app
  sigue mostrando el último stock bueno mientras tanto (nunca se vacía).
- **Precios viejos:** GitHub puede retrasar las tareas programadas unos minutos en horas pico; usa *Run workflow*.
