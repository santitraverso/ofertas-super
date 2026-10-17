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
# awk POSIX (sin extensiones de gawk): la nube trae mawk.
parse() {
  sed 's/{"productId":/\n&/g' | awk -v cadena="$1" -v base="https://$2/" -v OFS='\t' '
    # Valor de "clave": texto (t="s") o número (t="n"), primera aparición.
    function campo(s, clave, t,   re, v) {
      re = (t == "s") ? "\"" clave "\":\"[^\"]*\"" : "\"" clave "\":[0-9.]+"
      if (!match(s, re)) return ""
      v = substr(s, RSTART + length(clave) + 3, RLENGTH - length(clave) - 3)
      return (t == "s") ? substr(v, 2, length(v) - 2) : v
    }
    NR > 1 {
      ean = campo($0, "ean", "s")
      nombre = campo($0, "productName", "s")
      marca = campo($0, "brand", "s")
      precio = campo($0, "Price", "n")
      sindesc = campo($0, "PriceWithoutDiscount", "n")
      stock = campo($0, "AvailableQuantity", "n")
      link = campo($0, "linkText", "s")
      dest = ""
      if (match($0, /"clusterHighlights":\{[^}]*\}/)) {
        m = substr($0, RSTART + 21, RLENGTH - 22)
        n = split(m, parts, /"[0-9]+":/)
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
      printf '%s' "$r" | parse "$c" "$h" | awk -F'\t' -v e="$ean" '$2 == e'
    done ;;
  buscar)
    c=${2:?cadena}; txt=${3:?texto}
    h=$(host "$c") || { echo "cadena desconocida: $c" >&2; exit 1; }
    q=$(printf '%s' "$txt" | sed 's/ /%20/g')
    r=$(pedir "$h" "ft=$q&_from=0&_to=14") || { printf '%s\tERROR\n' "$c"; exit 0; }
    printf '%s' "$r" | parse "$c" "$h" ;;
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
