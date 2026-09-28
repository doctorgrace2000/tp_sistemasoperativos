#!/usr/bin/env bash
# =============================================================================
# 05_almacenamiento.sh — Ejercicio 5: Almacenamiento
#
# Situación: cada departamento necesita su carpeta en el servidor, con un
# tope de espacio (256 MB) que no pueda superar aunque sus usuarios llenen
# el disco, y que se pueda agrandar cuando lo pidan.
#
# Cómo: un volumen lógico (LVM) formateado en XFS, montado de forma
# persistente en /srv/<depto>, con una CUOTA DE PROYECTO de XFS sobre ese
# directorio. La cuota de proyecto limita la carpeta entera, no importa qué
# usuario escriba: es el único límite que de verdad es "por departamento".
#
# El "disco" es SIEMPRE un archivo montado como loop device, así no depende
# de que la VM tenga discos extra. Es un archivo disperso de 1 GB: ocupa
# solo lo que se escribe. La VM del lab tiene ~2 GB libres en /, por eso
# los tamaños son de escala demo (256 MB por depto = entran 3 departamentos,
# el cuarto falla por falta de espacio en el VG). En producción serían GB;
# el script recibe el tamaño por parámetro, así que es cambiar una constante.
#
# Herramientas: truncate, losetup, pvcreate, vgcreate, lvcreate, mkfs.xfs,
#               /etc/fstab, mount, xfs_quota   (lvextend + xfs_growfs: a mano)
# Teoría:       sistemas de archivos, inodos, journaling, LVM, montaje.
#
# Uso: 05_almacenamiento.sh <depto> <tamaño>   ej: 05_almacenamiento.sh finanzas 256M
#
# TODO:
#   [ ] si no existe el VG: truncate -s 1G /var/discos/pagosur.img
#                          losetup -f /var/discos/pagosur.img; pvcreate y vgcreate sobre el loop
#   [ ] si el VG ya existe, verificar que haya lugar: vgs --noheadings -o vg_free "$VG"
#   [ ] lvcreate -L "$TAM" -n "$LV" "$VG"
#   [ ] mkfs.xfs "/dev/$VG/$LV"
#   [ ] mkdir -p "$PUNTO"; agregar a /etc/fstab con "defaults,pquota"; mount -a
#   [ ] chown root:"$DEPTO" "$PUNTO"; chmod 2770 "$PUNTO"
#   [ ] cuota de proyecto: echo "$PUNTO" en /etc/projects y /etc/projid, luego
#       xfs_quota -x -c "project -s $DEPTO" -c "limit -p bhard=$TAM $DEPTO" "$PUNTO"
#   [ ] loguear en logs/asignador.log
#
# Demo de extensión a demanda (a mano, no en el script):
#   lvextend -L +64M /dev/$VG/$LV && xfs_growfs "$PUNTO" && df -h "$PUNTO"
# Demo de la cuota: su - ana -c "dd if=/dev/zero of=$PUNTO/relleno bs=1M" -> corta en 256M
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
TAM="${2:?falta tamaño}"
VG="vg_pagosur"
LV="lv_${DEPTO}"
PUNTO="/srv/${DEPTO}"

log "ALMACENAMIENTO: lv=/dev/$VG/$LV tam=$TAM montaje=$PUNTO (pendiente de implementar)"
