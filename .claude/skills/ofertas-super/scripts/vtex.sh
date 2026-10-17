#!/usr/bin/env bash
# Precios online de cadenas VTEX.
#
# Uso:
#   vtex.sh ean EAN [CADENAS]        precio de ese EAN en cada cadena
#   vtex.sh buscar CADENA "TEXTO"    hasta 15 productos que matchean TEXTO (para resolver EANs)
#
# CADENAS: lista separada por coma de dia,jumbo,disco,vea,changomas,carrefour
#          (default: todas; carrefour a veces no responde)
#
# Salida (stdout, TSV):
#   cadena ean nombre marca precio precio_sin_desc stock destacados url
# "destacados" son los clusterHighlights de VTEX (ej. "Hasta 2do al 70% en Almacén"):
# pistas de promo, no promos confirmadas. ListPrice se ignora: en Cencosud trae valores basura.
# Cadenas que no responden salen como una línea "cadena<TAB>ERROR".
set -uo pipefail

host() {
  case $1 in
    dia) echo diaonline.supermercadosdia.com.ar ;;
    jumbo) echo www.jumbo.com.ar ;;
    disco) echo www.disco.com.ar ;;
    vea) echo www.vea.com.ar ;;
    changomas) echo www.masonline.com.ar ;;
    carrefour) echo www.carrefour.com.ar ;;
    *) return 1 ;;
  esac
}

# Parte la respuesta JSON por producto y saca los campos que importan (sin jq).
parse() {
  gawk -v cadena="$1" -v base="https://$2/" -v OFS='\t' '
    function campo(s, re,   m) { return match(s, re, m) ? m[1] : "" }
    BEGIN { RS = "\\{\"productId\":" }
    NR > 1 {
      ean = campo($0, "\"ean\":\"([0-9]*)\"")
      nombre = campo($0, "\"productName\":\"([^\"]*)\"")
      marca = campo($0, "\"brand\":\"([^\"]*)\"")
      precio = campo($0, "\"Price\":([0-9.]+)")
      sindesc = campo($0, "\"PriceWithoutDiscount\":([0-9.]+)")
      stock = campo($0, "\"AvailableQuantity\":([0-9]+)")
      link = campo($0, "\"linkText\":\"([^\"]*)\"")
      dest = ""
      if (match($0, /"clusterHighlights":\{([^}]*)\}/, m)) {
        n = split(m[1], parts, /"[0-9]+":/)
        for (i = 2; i <= n; i++) { v = parts[i]; gsub(/^"|",?$/, "", v); dest = dest (dest ? "; " : "") v }
      }
      print cadena, ean, nombre, marca, precio, sindesc, stock, dest, base link "/p"
    }'
}

pedir() {
  curl -sf -m 30 -A "Mozilla/5.0" "https://$1/api/catalog_system/pub/products/search?$2"
}

case ${1:-} in
  ean)
    ean=${2:?ean}
    for c in $(echo "${3:-dia,jumbo,disco,vea,changomas,carrefour}" | tr ',' ' '); do
      h=$(host "$c") || { printf '%s\tERROR\n' "$c"; continue; }
      r=$(pedir "$h" "fq=alternateIds_Ean:$ean") || { printf '%s\tERROR\n' "$c"; continue; }
      printf '%s' "$r" | parse "$c" "$h" | gawk -F'\t' -v e="$ean" '$2 == e'
    done ;;
  buscar)
    c=${2:?cadena}; txt=${3:?texto}
    h=$(host "$c") || { echo "cadena desconocida: $c" >&2; exit 1; }
    q=$(printf '%s' "$txt" | sed 's/ /%20/g')
    r=$(pedir "$h" "ft=$q&_from=0&_to=14") || { printf '%s\tERROR\n' "$c"; exit 0; }
    printf '%s' "$r" | parse "$c" "$h" ;;
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
