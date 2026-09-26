#!/usr/bin/env bash
# =============================================================================
# 05_almacenamiento.sh — Ejercicio 5: Almacenamiento
#
# Objetivo: un volumen lógico por departamento, formateado en XFS, montado
# de forma persistente en /srv/<depto> con cuotas por usuario, y extensible
# a demanda con lvextend.
#
# Herramientas: fdisk, losetup, pvcreate, vgcreate, lvcreate, lvextend,
#               mkfs.xfs, /etc/fstab, xfs_quota, xfs_growfs
# Teoría:       sistemas de archivos, inodos, journaling, LVM.
#
# Uso: 05_almacenamiento.sh <depto> <tamaño>   ej: 05_almacenamiento.sh finanzas 2G
#
# Notas:
#   - Si la VM no tiene discos extra: dd if=/dev/zero of=/var/discos/d1.img bs=1M count=4096
#     y losetup para simularlos; el VG se arma encima del loop device.
#   - Las cuotas solo funcionan si se monta con -o uquota (o pquota).
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
TAM="${2:?falta tamaño}"
VG="vg_pagosur"
LV="lv_${DEPTO}"
PUNTO="/srv/${DEPTO}"

# TODO:
#   [ ] asegurar que existe el VG (crear PV/VG sobre disco real o loop device)
#   [ ] lvcreate -L "$TAM" -n "$LV" "$VG"
#   [ ] mkfs.xfs "/dev/$VG/$LV"
#   [ ] mkdir -p "$PUNTO" y agregar a /etc/fstab con uquota; mount -a
#   [ ] chown root:"$DEPTO" "$PUNTO"; chmod 2770 "$PUNTO"
#   [ ] xfs_quota -x -c 'limit bsoft=... bhard=... <usuario>' "$PUNTO" por cada usuario
#   [ ] función extender(): lvextend -L +<tam> + xfs_growfs

log "ALMACENAMIENTO: lv=/dev/$VG/$LV tam=$TAM montaje=$PUNTO (pendiente de implementar)"
