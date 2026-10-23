#!/usr/bin/env bash
# Abre (descifra y descomprime) un respaldo de Salvietti Control.
#
# Uso, en Git Bash, dentro de la carpeta donde está el .enc descargado:
#   bash ruta/a/abrir_respaldo.sh                  (busca el .enc solo)
#   bash ruta/a/abrir_respaldo.sh archivo.tar.gz.enc
#
# Pide la contraseña (BACKUP_PASSWORD) sin mostrarla: no hay que escribir
# comillas ni comandos. Le quita espacios y saltos de línea de los bordes, igual
# que el respaldo al cifrar, así un espacio de más no la hace "incorrecta".
set -euo pipefail

archivo="${1:-}"
if [ -z "$archivo" ]; then
  shopt -s nullglob
  encontrados=(salvietti_respaldo_*.enc)
  if [ ${#encontrados[@]} -eq 0 ]; then
    echo "No hay ningún salvietti_respaldo_*.enc en esta carpeta ($(pwd))."
    exit 1
  fi
  if [ ${#encontrados[@]} -gt 1 ]; then
    echo "Hay más de un respaldo en esta carpeta; indicá cuál:"
    printf '  %s\n' "${encontrados[@]}"
    exit 1
  fi
  archivo="${encontrados[0]}"
fi

echo "Respaldo: $archivo"
read -rsp "Contraseña del respaldo (no se ve al escribir): " CLAVE
echo
CLAVE="${CLAVE#"${CLAVE%%[![:space:]]*}"}"
CLAVE="${CLAVE%"${CLAVE##*[![:space:]]}"}"
export CLAVE
echo "(escribiste ${#CLAVE} caracteres)"

destino="${archivo%%.tar.gz.enc}"
mkdir -p "$destino"

# Los respaldos hechos ANTES de que el respaldo limpiara la contraseña se
# cifraron con el secreto tal cual estaba en GitHub, que pudo tener un salto
# de línea o un espacio invisible al final: se prueba también con eso.
abrio=false
for variante in "$CLAVE" "$CLAVE"$'\n' "$CLAVE"$'\r\n' "$CLAVE "; do
  if CLAVE_PRUEBA="$variante" openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
       -pass env:CLAVE_PRUEBA -in "$archivo" 2>/dev/null | tar -tzf - > /dev/null 2>&1; then
    CLAVE_PRUEBA="$variante" openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
       -pass env:CLAVE_PRUEBA -in "$archivo" | tar -xzf - -C "$destino"
    abrio=true
    break
  fi
done

if [ "$abrio" != true ]; then
  rmdir "$destino" 2>/dev/null || true
  echo
  echo "No se pudo abrir: la contraseña no es la que tenía GitHub cuando se hizo ESTE respaldo."
  echo "Ojo: si cambiaste el secreto BACKUP_PASSWORD, los respaldos anteriores siguen con la vieja."
  echo "En el registro del respaldo (Actions → la ejecución → 'Comprimir y cifrar') dice cuántos"
  echo "caracteres tenía la contraseña usada: compará con los que escribiste."
  exit 1
fi

echo
echo "Listo, se abrió en la carpeta: $destino"
ls -R "$destino" | head -40
