#!/usr/bin/env bash
# =============================================================================
# demo/simular_depto.sh — Crea un departamento "de mentira" para presentar un
# módulo solo, sin correr asignar.sh ni los otros ejercicios.
#
# Hace lo mínimo que después hará el ej. 6: el grupo del departamento y sus
# usuarios (del CSV), con clave conocida. Nada de disco, límites ni permisos.
#
# Uso:  sudo simular_depto.sh <depto> [archivo.csv]     (default: ejemplos/<depto>.csv)
#       sudo simular_depto.sh <depto> --borrar           (elimina usuarios y grupo)
#
# Los usuarios se crean con -g (grupo PRIMARIO = departamento) para que
# `ps -G <depto>` los encuentre; es lo que usa 02_monitor.sh.
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPTO="${1:?Uso: $0 <depto> [archivo.csv | --borrar]}"
ARG2="${2:-$RAIZ/ejemplos/$DEPTO.csv}"
CLAVE="pagosur"

[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }

# ---- borrar ----
if [[ "$ARG2" == "--borrar" ]]; then
    if ! getent group "$DEPTO" >/dev/null; then
        echo "El grupo '$DEPTO' no existe, nada que borrar."; exit 0
    fi
    gid=$(getent group "$DEPTO" | cut -d: -f3)
    # usuarios con ese grupo primario (columna 4 de /etc/passwd)
    for u in $(getent passwd | awk -F: -v g="$gid" '$4 == g {print $1}'); do
        pkill -KILL -u "$u" 2>/dev/null || true       # por si dejaron algo corriendo
        userdel -r "$u" 2>/dev/null && echo "usuario $u eliminado"
    done
    groupdel "$DEPTO" && echo "grupo $DEPTO eliminado"
    exit 0
fi

# ---- crear ----
CSV="$ARG2"
[[ -f "$CSV" ]] || { echo "No existe el CSV: $CSV"; exit 1; }

if getent group "$DEPTO" >/dev/null; then
    echo "grupo $DEPTO ya existe"
else
    groupadd "$DEPTO" && echo "grupo $DEPTO creado"
fi

# CSV: usuario,rol  (la primera línea es el encabezado)
tail -n +2 "$CSV" | while IFS=, read -r usuario rol; do
    usuario="${usuario//[[:space:]]/}"
    [[ -z "$usuario" ]] && continue
    if id -u "$usuario" >/dev/null 2>&1; then
        echo "usuario $usuario ya existe ($rol)"
    else
        useradd -m -g "$DEPTO" -s /bin/bash -c "$DEPTO/$rol" "$usuario"
        echo "usuario $usuario creado ($rol)"
    fi
    echo "$usuario:$CLAVE" | chpasswd
done

echo
echo "Listo. Clave de todos: $CLAVE"
echo "Probar:  su - $(tail -n +2 "$CSV" | head -1 | cut -d, -f1)"
echo "Borrar:  sudo $0 $DEPTO --borrar"
