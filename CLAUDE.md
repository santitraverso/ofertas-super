# ofertas-super

Skill para encontrar ofertas de supermercado cerca de una zona de AMBA y saber dónde conviene comprar.

- La lógica vive en la skill `ofertas-super` (`.claude/skills/ofertas-super/`), con scripts bash para SEPA y VTEX.
- Las preferencias y los resultados viven en el artifact "Ofertas del súper" (fuente: `artifact/ofertas.html`): `config/preferencias` y `corridas/AAAA-MM-DD`.
- `config/preferencias.md` es respaldo para correr sin artifact y guarda la URL del artifact.
- Precios en formato `1500ars`. Español rioplatense, directo, sin relleno.
- No inventes precios ni promos: si una fuente no responde, decilo.
