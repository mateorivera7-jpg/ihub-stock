"""
Actualiza el catálogo de iHub.

1. Abre la lista de distribuidores (Streamlit) con un navegador automático.
2. Lee todas las listas (Openbox, Teléfonos nuevos, Gadgets, y las que se agreguen).
3. Suma el margen de iHub (tabla `margenes` de Supabase, o margenes.json local).
4. Guarda docs/data/catalogo.json y, si hay claves de Supabase, lo publica también allá
   (la app lee primero de Supabase y usa el JSON como respaldo).

El JSON publicado solo contiene el precio final de iHub (nunca el costo ni el margen).
El precio POR MAYOR (márgenes mayor_*) se publica solo en la tabla protegida productos_mayorista de Supabase.

Uso:  python actualizar.py

Supabase (opcional): variables de entorno SUPABASE_URL y SUPABASE_SECRET_KEY.
Con ellas, los márgenes se leen de la tabla `margenes` (si falla, de margenes.json, que es local y privado).
"""

import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

FUENTE = "https://mundocelularecdistribucion.streamlit.app/"
RAIZ = Path(__file__).resolve().parent
SALIDA = RAIZ / "docs" / "data" / "catalogo.json"
_ARCHIVO_MARGENES = RAIZ / "margenes.json"  # privado: no se sube a GitHub (ver .gitignore)
MARGENES = json.loads(_ARCHIVO_MARGENES.read_text(encoding="utf-8")) if _ARCHIVO_MARGENES.exists() else {}
CATEGORIAS = ("iphone", "macbook_ultima_generacion", "macbook_anterior", "ipad",
              "android", "cubos", "palancas", "otros")
CATEGORIAS_MAYOR = tuple(f"mayor_{c}" for c in ("iphone", "macbook", "ipad", "android", "cubos", "palancas", "otros"))

MARCAS_ANDROID = (
    "SAMSUNG", "GALAXY", "XIAOMI", "REDMI", "POCO", "ZTE", "NUVIA", "MOTOROLA",
    "MOTO ", "HONOR", "HUAWEI", "OPPO", "VIVO", "REALME", "TECNO", "INFINIX",
    "PIXEL", "ONEPLUS", "NOKIA", "TCL", "BLU ", "ITEL",
)
CUBOS = ("POWER ADAPTER", "ADAPTER", "ADAPTADOR", "CARGADOR", "CUBO", "CHARGER")
PALANCAS = (
    "DUALSENSE", "DUALSHOCK", "CONTROL", "JOYSTICK", "PALANCA", "MANDO",
    "JOY-CON", "JOYCON", "GAMEPAD",
)


# ---------------------------------------------------------------- reglas

def chip_macbook(modelo):
    m = re.search(r"\bM(\d+)\b", modelo)
    return int(m.group(1)) if m else None


def categoria(modelo):
    """Devuelve la categoría de margen para un nombre de producto."""
    m = modelo.upper()
    if any(k in m for k in CUBOS):
        return "cubos"
    if any(k in m for k in PALANCAS):
        return "palancas"
    if "IPHONE" in m:
        return "iphone"
    if "MACBOOK" in m:
        return "macbook"
    if "IPAD" in m:
        return "ipad"
    if any(m.startswith(k) or f" {k}" in m for k in MARCAS_ANDROID):
        return "android"
    return "otros"


def margen(modelo, ultimo_chip_mac):
    cat = categoria(modelo)
    if cat == "macbook":
        chip = chip_macbook(modelo.upper())
        if chip is not None and ultimo_chip_mac is not None and chip >= ultimo_chip_mac:
            return MARGENES["macbook_ultima_generacion"]
        return MARGENES["macbook_anterior"]
    return MARGENES[cat]


def margen_mayor(modelo):
    return MARGENES[f"mayor_{categoria(modelo)}"]


def precio_a_numero(texto):
    return float(re.sub(r"[^\d.]", "", texto) or 0)


def tipo_lista(nombre):
    n = nombre.upper()
    if "OPEN" in n:
        return "openbox"
    if "NUEVO" in n:
        return "nuevos"
    if "GADGET" in n:
        return "gadgets"
    return re.sub(r"[^a-z0-9]+", "-", n.lower()).strip("-")


def nombre_bonito(modelo):
    t = modelo.upper()
    t = re.sub(r"\bOPEN ?BOX\b", "", t)
    t = re.sub(r"\bN\b", "", t)                 # "N" = nuevo en la lista origen
    t = re.sub(r"\bPROMAX\b", "PRO MAX", t)
    t = re.sub(r"\b(ESIM|CHIP)\b", "", t)
    return re.sub(r"\s+", " ", t).strip()


def armar_producto(lista, modelo, detalle, precio_txt, ultimo_chip_mac, por_mayor=False):
    partes = [p.strip() for p in detalle.split("·")]
    color = partes[0] if partes else ""
    capacidad = partes[1] if len(partes) > 1 else ""
    bateria = partes[2] if len(partes) > 2 else ""
    if capacidad in ("0GB", "") or color == "ACCESORIO":
        capacidad = ""
    if color == "ACCESORIO":
        color = ""
    bat = re.search(r"(\d+)\s*%", bateria)
    sim = "eSIM" if "ESIM" in modelo.upper() else ("Chip físico" if "CHIP" in modelo.upper() else "")

    base = precio_a_numero(precio_txt)
    final = round(base + (margen_mayor(modelo) if por_mayor else margen(modelo, ultimo_chip_mac)), 2)
    tipo = tipo_lista(lista)
    return {
        "lista": tipo,
        "modelo": nombre_bonito(modelo),
        "categoria": categoria(modelo),
        "color": color,
        "capacidad": capacidad,
        "bateria": int(bat.group(1)) if (bat and categoria(modelo) not in ("cubos", "palancas")) else None,
        "sim": sim,
        "precio": final,
    }


# ---------------------------------------------------------------- supabase

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY = os.environ.get("SUPABASE_SECRET_KEY", "")


def supabase(ruta, datos=None):
    cab = {"apikey": SUPABASE_KEY, "Content-Type": "application/json"}
    if SUPABASE_KEY.startswith("eyJ"):  # clave antigua (JWT service_role)
        cab["Authorization"] = f"Bearer {SUPABASE_KEY}"
    cuerpo = json.dumps(datos).encode() if datos is not None else None
    req = urllib.request.Request(f"{SUPABASE_URL}/rest/v1/{ruta}", data=cuerpo, headers=cab)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or "null")


def margenes_de_supabase():
    try:
        filas = supabase("margenes?select=categoria,monto")
        nuevos = {f["categoria"]: float(f["monto"]) for f in filas}
        if all(k in nuevos for k in CATEGORIAS):
            print("Márgenes leídos de Supabase.")
            for k in CATEGORIAS_MAYOR:  # si faltan en Supabase, se usan los de margenes.json
                if k not in nuevos and k in MARGENES:
                    nuevos[k] = MARGENES[k]
            return nuevos
        print("A la tabla margenes le faltan categorías; uso margenes.json.")
    except Exception as e:
        print("No se pudieron leer los márgenes de Supabase; uso margenes.json:", e)
    return MARGENES


# ---------------------------------------------------------------- lectura

def leer_fuente():
    from playwright.sync_api import sync_playwright

    crudo = []  # (lista, modelo, detalle, precio)
    with sync_playwright() as p:
        nav = p.chromium.launch()
        pag = nav.new_page(viewport={"width": 1200, "height": 900})
        pag.goto(FUENTE, wait_until="domcontentloaded", timeout=90_000)

        # Si la app de Streamlit está dormida, la despertamos.
        try:
            boton = pag.get_by_role("button", name=re.compile("get this app back up", re.I))
            boton.wait_for(timeout=8_000)
            boton.click()
            print("La fuente estaba dormida; despertando…")
        except Exception:
            pass

        app = pag.frame_locator("iframe[title='streamlitApp'], iframe").first
        combo = app.get_by_role("combobox").first
        combo.wait_for(timeout=180_000)

        combo.click()
        opciones = [o.strip() for o in app.get_by_role("option").all_inner_texts()]
        pag.keyboard.press("Escape")
        listas = [o for o in opciones if o and not o.upper().startswith("SELECCIONA")]
        print("Listas encontradas:", listas)

        for lista in listas:
            combo.click()
            app.get_by_role("option", name=lista, exact=True).click()
            app.get_by_text(re.compile(rf"^{re.escape(lista)} · \d+ modelos")).wait_for(timeout=60_000)
            pag.wait_for_timeout(800)
            tarjetas = app.locator(".item-card")
            filas = tarjetas.evaluate_all(
                """els => els.map(e => [
                    e.querySelector('.item-modelo')?.innerText || '',
                    e.querySelector('.item-detalle')?.innerText || '',
                    e.querySelector('.item-precio')?.innerText || ''])"""
            )
            print(f"  {lista}: {len(filas)} productos")
            crudo += [(lista, *f) for f in filas if f[0] and f[2]]
        nav.close()
    return crudo


def main():
    global MARGENES
    if SUPABASE_URL and SUPABASE_KEY:
        MARGENES = margenes_de_supabase()
    if not all(k in MARGENES for k in CATEGORIAS):
        if not (SUPABASE_URL or SUPABASE_KEY):
            print("Supabase aún no está configurado (faltan SUPABASE_URL y SUPABASE_SECRET_KEY); no se actualiza nada.")
            return
        sys.exit("No hay márgenes: configura Supabase (SUPABASE_URL y SUPABASE_SECRET_KEY) o crea margenes.json.")

    crudo = leer_fuente()
    if len(crudo) < 5:
        sys.exit(f"Solo se leyeron {len(crudo)} productos; no se reemplaza el catálogo actual.")

    chips = [chip_macbook(m.upper()) for _, m, _, _ in crudo if categoria(m) == "macbook"]
    chips = [c for c in chips if c is not None]
    ultimo_chip = max(chips) if chips else None

    productos = [armar_producto(l, m, d, pr, ultimo_chip) for l, m, d, pr in crudo]
    nuevo = {"productos": productos}

    anterior = {}
    if SALIDA.exists():
        anterior = json.loads(SALIDA.read_text(encoding="utf-8"))
    ahora = datetime.now(timezone.utc).isoformat(timespec="seconds")
    cambio = anterior.get("productos") != productos
    nuevo["actualizado"] = ahora if cambio else anterior.get("actualizado", ahora)
    nuevo["revisado"] = ahora  # última vez que se comparó con la lista origen
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    SALIDA.write_text(json.dumps(nuevo, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"Catálogo actualizado: {len(productos)} productos." if cambio else "Sin cambios en el stock (revisado).")

    if SUPABASE_URL and SUPABASE_KEY:
        r = supabase("rpc/publicar_catalogo", {"productos": productos, "revisado": ahora})
        print("Supabase:", r)
        if all(MARGENES.get(k) for k in CATEGORIAS_MAYOR):
            mayor = [armar_producto(l, m, d, pr, ultimo_chip, por_mayor=True) for l, m, d, pr in crudo]
            for pm, pp in zip(mayor, productos):  # el precio por mayor nunca supera al público
                pm["precio"] = min(pm["precio"], pp["precio"])
            try:
                print("Supabase:", supabase("rpc/publicar_mayorista", {"productos": mayor}))
            except Exception as e:
                print("No se pudo publicar el stock mayorista (¿falta correr supabase/mayoristas.sql?):", e)
        else:
            print("Faltan los márgenes mayor_* en la tabla margenes; no se publica el stock mayorista.")


if __name__ == "__main__":
    main()
