#!/usr/bin/env bash
# Precios por sucursal desde SEPA (datos.produccion.gob.ar), filtrados por radio y EAN.
#
# Uso: sepa.sh LAT LON RADIO_KM ARCHIVO_EANS [COMERCIOS]
#   ARCHIVO_EANS  un EAN por línea
#   COMERCIOS     ids SEPA separados por coma (default 9,10,11,12,15:
#                 9=Cencosud Vea/Disco/Jumbo, 10=Carrefour, 11=ChangoMás, 12=Coto, 15=Día)
#
# Salida (stdout, TSV con encabezado):
#   comercio bandera sucursal nombre direccion localidad dist_km ean descripcion marca
#   precio_lista promo1_precio promo1_leyenda promo2_precio promo2_leyenda
# En stderr: "SEPA_FECHA=AAAA-MM-DD" con la fecha de los datos usados.
#
# Descarga ~320MB por día a $SEPA_DIR (default ./data/sepa) y reusa la descarga si ya existe.
set -euo pipefail

LAT=${1:?lat}; LON=${2:?lon}; RADIO=${3:?radio_km}; EANS=${4:?archivo_eans}
COMERCIOS=${5:-9,10,11,12,15}
DIR=${SEPA_DIR:-data/sepa}
API="https://datos.produccion.gob.ar/api/3/action/package_show?id=sepa-precios"
mkdir -p "$DIR"

# 1. Elegir el zip más reciente: hay uno por día de la semana y se pisan semana a semana,
#    así que se compara el Last-Modified de cada uno.
meta=$(curl -sf -m 60 "$API") || { echo "ERROR: no responde la API de datos.produccion.gob.ar" >&2; exit 2; }
mejor_url=""; mejor_ts=0
for url in $(printf '%s' "$meta" | grep -o 'https://[^"]*/sepa_[a-z]*\.zip' | sort -u); do
  lm=$(curl -sfI -m 30 -L "$url" | tr -d '\r' | awk -F': ' 'tolower($1)=="last-modified"{print $2}' | tail -1)
  [ -z "$lm" ] && continue
  ts=$(date -d "$lm" +%s 2>/dev/null || echo 0)
  if [ "$ts" -gt "$mejor_ts" ]; then mejor_ts=$ts; mejor_url=$url; fi
done
[ -z "$mejor_url" ] && { echo "ERROR: no se pudo determinar el zip SEPA más reciente" >&2; exit 2; }
fecha=$(date -d "@$mejor_ts" +%F)
echo "SEPA_FECHA=$fecha" >&2

# 2. Descargar y extraer solo los comercios pedidos.
base="$DIR/$fecha"
if [ ! -f "$base/.ok" ]; then
  rm -rf "$base"; mkdir -p "$base/c"
  curl -sf -m 900 -L -o "$base/sepa.zip" "$mejor_url" || { echo "ERROR: falló la descarga de $mejor_url" >&2; exit 2; }
  unzip -oq "$base/sepa.zip" -d "$base/x"
  rm -f "$base/sepa.zip"
  for z in $(find "$base/x" -name '*.zip'); do
    id=$(basename "$z" | grep -o 'comercio-sepa-[0-9]*' | grep -o '[0-9]*$' || true)
    [ -z "$id" ] && continue
    mkdir -p "$base/c/$id"
    unzip -oq "$z" -d "$base/c/$id" 2>/dev/null || true
  done
  rm -rf "$base/x"
  touch "$base/.ok"
fi

suc=(); prod=()
for id in ${COMERCIOS//,/ }; do
  [ -d "$base/c/$id" ] || { echo "AVISO: comercio $id sin datos en SEPA $fecha" >&2; continue; }
  while IFS= read -r f; do suc+=("$f"); done < <(find "$base/c/$id" -name sucursales.csv)
  while IFS= read -r f; do prod+=("$f"); done < <(find "$base/c/$id" -name productos.csv)
done
[ ${#suc[@]} -eq 0 ] && { echo "ERROR: ningún comercio con datos" >&2; exit 2; }

# 3. Filtrar sucursales por distancia y productos por EAN.
#    En productos.csv el EAN está en id_producto ($4); productos_ean ($5) es solo un flag.
awk -F'|' -v OFS='\t' -v lat="$LAT" -v lon="$LON" -v radio="$RADIO" '
  function rad(x) { return x * 3.141592653589793 / 180 }
  function dist(a1, o1, a2, o2,   dl, dn, h) {
    dl = rad(a2 - a1); dn = rad(o2 - o1)
    h = sin(dl/2)^2 + cos(rad(a1)) * cos(rad(a2)) * sin(dn/2)^2
    return 2 * 6371 * atan2(sqrt(h), sqrt(1 - h))
  }
  { sub(/\r$/, "") }
  FILENAME == ARGV[1] { if ($1 != "") want[$1] = 1; next }
  FNR == 1 { tipo = ($0 ~ /sucursales_latitud/) ? "s" : "p"; next }
  $1 !~ /^[0-9]+$/ { next }
  tipo == "s" {
    if ($8 == "" || $9 == "") next
    d = dist(lat, lon, $8 + 0, $9 + 0)
    if (d <= radio) { k = $1 "|" $2 "|" $3; S[k] = $4 OFS $6 " " $7 OFS $13 OFS sprintf("%.2f", d) }
    next
  }
  tipo == "p" {
    k = $1 "|" $2 "|" $3
    if ((k in S) && ($4 in want))
      print $1, $2, $3, S[k], $4, $6, $9, $10, $14, $15, $16, $17
  }
  BEGIN { print "comercio","bandera","sucursal","nombre","direccion","localidad","dist_km","ean","descripcion","marca","precio_lista","promo1_precio","promo1_leyenda","promo2_precio","promo2_leyenda" }
' "$EANS" "${suc[@]}" "${prod[@]}"
