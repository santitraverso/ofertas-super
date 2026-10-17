---
name: ofertas-super
description: Busca ofertas y precios de supermercado cerca de una zona de AMBA y dice dónde conviene comprar. Cruza precios por sucursal (SEPA), precios online de las cadenas (VTEX) y descuentos por banco/billetera del día, y escribe el resultado en un artifact con preferencias editables. Usar cuando diga "ofertas del súper", "dónde compro esto más barato", "qué promos hay hoy", "compará mi lista", "/ofertas-super", o cuando corra la rutina diaria.
---

# Ofertas Super

Compara la lista de productos de una persona entre las sucursales cercanas y escribe la corrida del día en su artifact "Ofertas del súper".

Reglas que no se negocian:
- No inventar precios ni promos. Si una fuente no responde, va en `fuentes` como `falló` y se sigue con las demás.
- Precios en formato `1500ars` (entero, sin separador de miles).
- Una promo con fecha de fin anterior a hoy no es una oferta. No se muestra.

## 0. Modo y artifact

- **Artifact**: la URL viene en los argumentos (`/ofertas-super https://claude.ai/artifact/...`) o en la línea `artifact:` de `config/preferencias.md`. Si no hay ninguna, ver "Setup para alguien nuevo" al final.
- **Modo**: si corrés desde una rutina programada (el prompt lo dice, o no hay nadie para responder), estás en **modo rutina**: nunca preguntes, decidí con lo que hay y dejá constancia en `avisos`. Si hay una persona, estás en **modo interactivo**: podés preguntar lo que falte.

## 1. Preferencias

Leer con `ArtifactData` → `get`, colección `config`, doc `preferencias`. Si no existe o el artifact no responde, usar `config/preferencias.md` como respaldo y decirlo en `avisos`.

Forma del documento (lo escribe el formulario del artifact):

```json
{
  "direccion": "Av. San Martín 5900, Villa Devoto",
  "lat": -34.60, "lon": -58.51,          // null hasta que la skill geocodifica
  "radio_km": 2,
  "cadenas": ["dia", "carrefour", "coto", "jumbo", "disco", "vea", "changomas"],  // vacío = todas
  "tarjetas": ["Visa Galicia"], "billeteras": ["MODO", "Mercado Pago"],
  "lista": [{ "id": "p…", "nombre": "Yerba Playadito 1kg", "marca_fija": true,
              "eans": ["7793704000928"], "resuelto_como": "Yerba Mate Playadito Suave 1 Kg" }],
  "notas": "texto libre con preferencias extra"
}
```

Si falta `direccion` o `lista` está vacía:
- interactivo: pedir solo eso, guardarlo en el doc y seguir;
- rutina: escribir una corrida con `resumen: "Faltan preferencias: completá <qué> en la pestaña Preferencias."`, sin precios, y terminar.

Toda escritura a `config/preferencias` va con `if_version` de la lectura y usando `update` solo con los campos que cambiaste: la persona puede estar editando el formulario. Si el `if_version` falla, releer y reintentar una vez.

### 1a. Coordenadas
Si `lat`/`lon` son null, geocodificar la dirección:
```bash
curl -s -A "ofertas-super-skill" "https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=ar&q=<direccion urlencoded>"
```
Usar `limit=3`: si hay varios resultados en localidades distintas (ej. "La Pampa 3993" existe en CABA, Mar del Plata y Olavarría), en modo interactivo preguntar cuál y en modo rutina no adivinar: avisar que falta la localidad. Guardar `lat`/`lon` y la dirección con barrio/localidad en el doc. Si no hay resultado, avisar y usar solo precios online (VTEX).

### 1a'. Lista
Si un item trae varios productos separados por comas ("Leche, Manteca, Huevos"), partirlo en un item por producto antes de resolver EANs y guardar la lista partida.

### 1b. Códigos de barras (EAN)
SEPA describe los productos con textos truncados ("LECHE ZERO LACTOSA" / marca "SEREN"), así que **todo se cruza por EAN**. Para cada item de `lista` con `eans` vacío:
1. `bash .claude/skills/ofertas-super/scripts/vtex.sh buscar dia "<nombre>"` y lo mismo con `jumbo` (nombres completos, devuelven EAN).
2. `marca_fija: true` → quedarse con el EAN del producto exacto (marca, variedad, tamaño). Si hay presentaciones distintas, la que coincide con el nombre.
3. `marca_fija: false` → el EAN pedido más hasta 4 equivalentes de otras marcas (mismo tipo y tamaño), para poder sugerir reemplazos.
4. Guardar `eans` y `resuelto_como` (nombre legible de lo elegido). Si nada matchea, dejar `eans: []` y avisar con el nombre del producto.

## 2. Precios por sucursal (SEPA)

Dataset oficial de precios por sucursal. Se publica un zip por día de la semana (~320MB) y llega con 1–2 días de atraso. El script elige el más reciente, lo cachea en `data/sepa/` y filtra:

```bash
printf '%s\n' <todos los EAN> > /tmp/eans.txt
bash .claude/skills/ofertas-super/scripts/sepa.sh <lat> <lon> <radio_km> /tmp/eans.txt [comercios] > /tmp/sepa.tsv
# stderr: SEPA_FECHA=AAAA-MM-DD → va a sepa_fecha de la corrida
```

Comercios SEPA según `cadenas` (default todos):

| cadena | comercio | bandera |
|---|---|---|
| dia | 15 | 1 |
| carrefour | 10 | 1 Hiper, 2 Market, 3 Express, 4 Maxi |
| coto | 12 | 1 |
| vea / disco / jumbo | 9 | 1 Vea, 2 Disco, 3 Jumbo |
| changomas | 11 | todas |

Columnas: `comercio bandera sucursal nombre direccion localidad dist_km ean descripcion marca precio_lista promo1_precio promo1_leyenda promo2_precio promo2_leyenda`.

- Precio efectivo de una fila = el menor entre `precio_lista`, `promo1_precio` y `promo2_precio`, contando solo promos vigentes. Mirar las dos promos: Día pone en `promo2` sus promos con fecha ("2DO AL 70% PH DH 30M - Vigencia: Desde el 14/10/2026 hasta el 19/10/2026").
- Vigencia: la fecha de fin aparece como "hasta dd/mm/aaaa", "hasta el dd/mm/aaaa" (Carrefour, Día) o "AL dd/mm/aaaa" (Coto). Si es anterior a hoy, ignorar la promo. Si la leyenda no tiene fecha (Día: "Hasta Agotar Stock o Finalice Vigencia"), contarla pero con "vigencia sin confirmar".
- Las promos tipo "2do al X%" vienen como precio unitario promedio llevando 2: aclararlo en `promo`.
- Con radio grande hay cientos de sucursales: `donde_comprar` tiene que priorizar las cercanas (si una sucursal a menos de 1,5km cuesta hasta 2% más que la más barata, va primero).
- Las promos de Día, Carrefour y Coto vienen en SEPA. Cencosud (Jumbo/Disco/Vea) y ChangoMás casi no informan promos ahí: para esas usar VTEX.
- Si el script falla (exit 2), registrar `SEPA: falló` con el mensaje y seguir con VTEX.

## 3. Precios online (VTEX)

```bash
bash .claude/skills/ofertas-super/scripts/vtex.sh ean <EAN> [dia,jumbo,disco,vea,changomas,carrefour]
# cadena ean nombre marca precio precio_sin_desc stock destacados url
```

- Descuento real y activo: `precio < precio_sin_desc`.
- `destacados` (ej. "Hasta 2do al 70% en Almacén") son pistas: muchas están viejas. Mostrar solo como "posible promo, verificar" y nunca contarlas en el precio.
- `stock` 0 → sin stock online, no recomendar.
- Es precio de la tienda online; puede no coincidir con la góndola. Marcar `fuente: "online"`.
- Carrefour responde a veces sí y a veces no. Una línea `cadena<TAB>ERROR` es fuente caída para esa cadena, no "no lo vende".
- Coto no es VTEX: solo SEPA.

## 4. Descuentos bancarios y billeteras de hoy

No hay fuente estructurada. Para cada medio de pago de las preferencias:
1. Buscar en la web `"<banco o billetera>" descuentos supermercados <mes> <año>` y mirar el día de la semana de hoy.
2. Preferir la página oficial del banco/billetera; si no, una nota de medio fechada este mes. Descartar notas de otro mes o con fechas incoherentes.
3. Quedarse solo con lo que aplica **hoy** y en cadenas de la lista (o cercanas).
4. `estado`: `"confirmado"` solo si salió de la página oficial leída hoy; si no, `"a confirmar"`.

Los clusters VTEX tipo "25% + 3 CSI con Cencopay" también son promos de medio de pago: mencionarlas si el medio está en las preferencias.

## 5. Armar la corrida

- Por item: mejor precio efectivo cercano (SEPA) contra online (VTEX). `rango` con min/max entre todas las cadenas; `ahorro` = precio de lista más caro − mejor efectivo.
- Si `marca_fija: false` y un equivalente sale más barato, ponerlo en `otras` aclarando la marca.
- `donde_comprar`: para cada sucursal, sumar el mejor precio efectivo de los items que tiene. Ordenar primero por cantidad de items y después por total. Máximo 5 filas. Agregar `nota` si conviene partir la compra en dos lugares.
- `destacadas`: hasta 8 ofertas vigentes fuertes (≥25%) en las sucursales cercanas sobre productos que no están en la lista, solo si salieron de los mismos datos (no buscar aparte).
- `resumen`: 1–3 oraciones en rioplatense, directo: dónde ir hoy, cuánto se ahorra y qué descuento bancario usar.

## 6. Escribir

`ArtifactData` → `set`, colección `corridas`, doc_id `AAAA-MM-DD` (fecha de hoy en Argentina). Si ya existe (corrida repetida), leerlo y pisar con `if_version`.

```json
{
  "fecha": "2026-10-17", "generado": "2026-10-17T07:02:00-03:00", "sepa_fecha": "2026-10-15",
  "resumen": "…",
  "donde_comprar": [{ "cadena": "Día", "sucursal": "Villa del Parque", "dist_km": 0.9, "items": 7, "total": 18450, "nota": "" }],
  "lista": [{
    "producto": "Leche Zero Lactosa La Serenísima 1L", "ean": "7790742333605",
    "mejor": { "cadena": "Coto", "sucursal": "…", "dist_km": 1.2, "precio": 2079, "precio_lista": 3119,
               "promo": "2do al 70%", "vigencia": "hasta 20/10", "fuente": "sepa" },
    "rango": { "min": 2079, "max": 3400, "cadenas": 6 }, "ahorro": 1321,
    "otras": [{ "cadena": "Vea", "sucursal": "online", "precio": 3118, "promo": "" }],
    "nota": ""                                    // si no hay "mejor": por qué
  }],
  "bancos": [{ "medio": "MODO", "cadena": "Coto", "descuento": "20%", "tope": "10000ars",
               "condiciones": "Sábados, débito", "fuente": "modo.com.ar", "url": "https://…", "estado": "a confirmar" }],
  "destacadas": [{ "producto": "…", "cadena": "Día", "precio": 2470, "antes": 3800, "promo": "35%" }],
  "fuentes": [{ "nombre": "SEPA", "estado": "ok", "detalle": "datos del 15/10" },
              { "nombre": "VTEX Carrefour", "estado": "falló", "detalle": "timeout" }],
  "avisos": ["…"]
}
```

`estado` de fuentes: `ok`, `parcial` o `falló`. El documento tiene que pesar menos de 256KB: recortar `otras` a 5 por item.

Después, si hay más de 90 corridas, borrar las más viejas.

En modo interactivo, cerrar con 3–5 líneas: dónde ir, el ahorro y el link al artifact.

## Setup para alguien nuevo

1. Publicar `artifact/ofertas.html` como artifact propio con
   `capabilities: {"db": {"rules": [{"path": "", "read": "view", "write": "admin"}]}, "user": {}}`.
2. Completar la pestaña Preferencias (o pasarle los datos a Claude para que escriba `config/preferencias`).
3. Correr `/ofertas-super <url del artifact>` una vez a mano para resolver EANs y coordenadas.
4. Programar la rutina diaria con el prompt: `/ofertas-super <url del artifact> — modo rutina`.
