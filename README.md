# ofertas-super

Skill de Claude Code que compara tu lista del súper entre las sucursales cercanas y te dice dónde conviene comprar hoy. Escribe cada corrida en un artifact donde también editás tus preferencias.

## Fuentes

- **SEPA** (datos.produccion.gob.ar): precios y promos por sucursal, con ubicación. Llega con 1–2 días de atraso.
- **VTEX**: precios online de Día, Jumbo, Disco, Vea, ChangoMás y Carrefour.
- **Descuentos bancarios**: búsqueda web del día según tus tarjetas y billeteras.

## Uso

1. Publicá `artifact/ofertas.html` como artifact (los pasos están al final de `.claude/skills/ofertas-super/SKILL.md`).
2. Completá la pestaña Preferencias.
3. Corré `/ofertas-super <url del artifact>` una vez a mano.
4. Programá una rutina diaria con `/ofertas-super <url del artifact> — modo rutina`.

Requiere `bash`, `curl`, `unzip` y `awk`.
