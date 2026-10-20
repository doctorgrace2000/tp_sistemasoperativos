#!/usr/bin/env bash
# =============================================================================
# revocar.sh — Baja de un departamento: deshace lo que hizo asignar.sh
#
# Uso:  ./revocar.sh --depto finanzas [--si]     (--si: no pide confirmación)
#
# Sirve para repetir la demo desde cero. Va en orden inverso al asignador:
# primero la regla de limits.d, después el disco, y al final los usuarios.
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
    echo "Se borran los usuarios del grupo '$DEPTO', su regla de limits.d, su regla de red, su cuota y la carpeta $PUNTO con sus datos."
    read -r -p "¿Continuar? [s/N] " resp
    [[ "$resp" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }
fi

log "INICIO revocación depto=$DEPTO"

# 1. Memoria (Ej. 3): borrar la regla de limits.d del grupo
for f in /etc/security/limits.d/depto-"$DEPTO"-*.conf; do
    [[ -f "$f" ]] || continue
    rm -f "$f"
    log "LIMITES: eliminado $f"
done

# 2. Almacenamiento (Ej. 4): sacar la cuota de proyecto y borrar la carpeta.
#    Desmonta el volumen del depto, lo saca de fstab y borra su LV (los crea
#    04_almacenamiento.sh). Cada paso se saltea si ya no existe.
if grep -q "^$DEPTO:" /etc/projid 2>/dev/null; then
    FS=$(findmnt -no TARGET --target /srv)
    xfs_quota -x -c "limit -p bhard=0 bsoft=0 $DEPTO" "$FS" 2>/dev/null || true
    log "ALMACENAMIENTO: quitada la cuota de proyecto $DEPTO en $FS"
fi
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
[[ -d "$PUNTO" ]] && rm -rf "$PUNTO" && log "ALMACENAMIENTO: borrado $PUNTO con sus datos"
sed -i "/^$DEPTO:/d" /etc/projid 2>/dev/null || true
sed -i "\|:$PUNTO\$|d" /etc/projects 2>/dev/null || true

# 3. Seguridad (Ej. 6): regla de red, usuarios del grupo y grupo
TABLA="depto_${DEPTO//-/_}"
if nft list table inet "$TABLA" &>/dev/null; then
    nft delete table inet "$TABLA"
    log "SEGURIDAD: eliminada la tabla nft $TABLA (bloqueo de puertos)"
fi
rm -f "/etc/nftables/depto-$DEPTO-red.nft"

if getent group "$DEPTO" &>/dev/null; then
    gid=$(getent group "$DEPTO" | cut -d: -f3)
    # Los usuarios del depto tienen el grupo como PRIMARIO (useradd -g), y esos
    # no aparecen en la lista de miembros de getent group: hay que buscarlos
    # por GID en passwd. Se suman también los miembros secundarios por si acaso.
    usuarios=$( { getent passwd | awk -F: -v g="$gid" '$4 == g {print $1}';
                  getent group "$DEPTO" | cut -d: -f4 | tr ',' '\n'; } | sort -u )
    for u in $usuarios; do
        [[ -z "$u" ]] && continue
        pkill -KILL -u "$u" || true        # no se puede borrar un usuario con procesos vivos
        userdel -r "$u"
        log "SEGURIDAD: eliminado usuario $u"
    done
    groupdel "$DEPTO"
    log "SEGURIDAD: eliminado grupo $DEPTO"
fi
rm -f "/etc/sudoers.d/$DEPTO"

log "FIN revocación depto=$DEPTO"
