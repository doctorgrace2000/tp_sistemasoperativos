#!/usr/bin/env bash
# =============================================================================
# revocar.sh — Baja de un departamento: deshace lo que hizo asignar.sh
#
# Uso:  ./revocar.sh --depto finanzas [--si]     (--si: no pide confirmación)
#
# Sirve para repetir la demo desde cero. Va en orden inverso al asignador:
# primero las reglas de limits.d, después el disco, y al final los usuarios.
# Cada paso se saltea si el recurso ya no existe, así se puede correr dos veces.
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/log.sh"

DEPTO="" SI=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --depto) DEPTO="$2"; shift 2 ;;
        --si)    SI=1; shift ;;
        *) echo "Uso: $0 --depto <nombre> [--si]"; exit 1 ;;
    esac
done
[[ -z "$DEPTO" ]] && { echo "Uso: $0 --depto <nombre> [--si]"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }

VG="vg_pagosur"
LV="lv_${DEPTO}"
PUNTO="/srv/${DEPTO}"

if [[ $SI -eq 0 ]]; then
    echo "Se borran los usuarios del grupo '$DEPTO', sus reglas de limits.d y el volumen /dev/$VG/$LV con sus datos."
    read -r -p "¿Continuar? [s/N] " resp
    [[ "$resp" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }
fi

log "INICIO revocación depto=$DEPTO"

# 1. CPU y memoria (Ej. 3 y 4): borrar las reglas de limits.d del grupo
for f in /etc/security/limits.d/depto-"$DEPTO"-*.conf; do
    [[ -f "$f" ]] || continue
    rm -f "$f"
    log "LIMITES: eliminado $f"
done

# 2. Almacenamiento (Ej. 5): desmontar, sacar de fstab, borrar el LV y la cuota de proyecto
if mountpoint -q "$PUNTO"; then
    umount "$PUNTO"
    log "ALMACENAMIENTO: desmontado $PUNTO"
fi
if grep -q "[[:space:]]$PUNTO[[:space:]]" /etc/fstab; then
    sed -i "\|[[:space:]]$PUNTO[[:space:]]|d" /etc/fstab
    log "ALMACENAMIENTO: quitado $PUNTO de /etc/fstab"
fi
if lvs "$VG/$LV" &>/dev/null; then
    lvremove -f "$VG/$LV"
    log "ALMACENAMIENTO: eliminado /dev/$VG/$LV"
fi
[[ -d "$PUNTO" ]] && rmdir "$PUNTO" && log "ALMACENAMIENTO: borrado $PUNTO"
sed -i "/^$DEPTO:/d" /etc/projid 2>/dev/null || true
sed -i "\|:$PUNTO\$|d" /etc/projects 2>/dev/null || true

# 3. Seguridad (Ej. 6): usuarios del grupo, grupo y sudoers
if getent group "$DEPTO" &>/dev/null; then
    for u in $(getent group "$DEPTO" | cut -d: -f4 | tr ',' ' '); do
        pkill -KILL -u "$u" || true        # no se puede borrar un usuario con procesos vivos
        userdel -r "$u"
        log "SEGURIDAD: eliminado usuario $u"
    done
    groupdel "$DEPTO"
    log "SEGURIDAD: eliminado grupo $DEPTO"
fi
rm -f "/etc/sudoers.d/$DEPTO"

log "FIN revocación depto=$DEPTO"
