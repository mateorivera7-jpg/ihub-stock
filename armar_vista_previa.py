"""Arma la carpeta vista-previa/ (página + datos + logo) que se publica en el link de Claude."""
import re
import shutil
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
DOCS, SALIDA = RAIZ / "docs", RAIZ / "vista-previa"
(SALIDA / "data").mkdir(parents=True, exist_ok=True)

html = (DOCS / "index.html").read_text(encoding="utf-8")
pagina = html.split("<!--ARTIFACT-START-->")[1].split("<!--ARTIFACT-END-->")[0]
pagina = re.sub(r"<!--HEAD-END-->\s*</head>\s*<body>", "", pagina)
(SALIDA / "ihub-stock.html").write_text(pagina, encoding="utf-8")
shutil.copy(DOCS / "data" / "catalogo.json", SALIDA / "data" / "catalogo.json")
shutil.copy(DOCS / "logo-blanco.png", SALIDA / "logo-blanco.png")
print("Vista previa lista en", SALIDA)
