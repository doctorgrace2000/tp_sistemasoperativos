#!/usr/bin/env bash
# =============================================================================
# 04_almacenamiento.sh — Ejercicio 4: Almacenamiento
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
# El volumen se crea un 25 % más grande que la cuota (256 MB -> LV de 320 MB).
# Si fueran del mismo tamaño, XFS usa parte del volumen para su journal y sus
# estructuras, el disco se llenaría ANTES de llegar a la cuota y el error sería
# "No space left on device" en vez de "Disk quota exceeded": la cuota no
# estaría haciendo nada. Con margen, lo que corta es la cuota.
#
# El "disco" es SIEMPRE un archivo montado como loop device, así no depende
# de que la VM tenga discos extra. Es un archivo disperso de 1 GB: ocupa
# solo lo que se escribe. La VM del lab tiene ~2 GB libres en /, por eso
# los tamaños son de escala demo (3 departamentos de 320 MB entran en el VG,
# el cuarto falla por falta de espacio). En producción serían GB; el script
# recibe el tamaño por parámetro, así que es cambiar una constante.
#
# Un loop device NO sobrevive a un reinicio. La línea de fstab lleva "nofail"
# para que la VM arranque igual; después de reiniciar, volver a correr este
# script: reconecta el archivo, activa el VG y monta (cada paso se saltea si
# ya está hecho).
#
# Herramientas: truncate, losetup, pvcreate, vgcreate, lvcreate, mkfs.xfs,
#               /etc/fstab, mount, xfs_quota   (lvextend -r: a mano en la demo)
# Teoría:       sistemas de archivos, inodos, journaling, LVM, montaje, cuotas.
#
# Uso: sudo 04_almacenamiento.sh <depto> <tamaño>   ej: 04_almacenamiento.sh finanzas 256M
#      El grupo <depto> tiene que existir (06_seguridad.sh o demo/simular_depto.sh).
#      ¡Sacar snapshot de la VM antes de la primera vez! (toca LVM y /etc/fstab)
#
# Demo (desde la raíz del repo):
#   sudo ./src/demo/simular_depto.sh finanzas
#   sudo ./src/modulos/04_almacenamiento.sh finanzas 256M
#   lsblk; sudo pvs; sudo vgs; sudo lvs; df -h /srv/finanzas; grep srv /etc/fstab
#   sudo xfs_quota -x -c "report -p -h" /srv/finanzas
#   sudo su - lperez -c "dd if=/dev/zero of=/srv/finanzas/relleno bs=1M count=400"
#       -> corta en 256 MB con "Disk quota exceeded"
#   Agrandar a demanda (a mano):
#   sudo lvextend -r -L +64M /dev/vg_pagosur/lv_finanzas      # -r agranda también el XFS
#   sudo xfs_quota -x -c "limit -p bhard=320M finanzas" /srv/finanzas
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?Uso: $0 <depto> <tamaño>   ej: $0 finanzas 256M}"
TAM="${2:?Uso: $0 <depto> <tamaño>   ej: $0 finanzas 256M}"
VG="vg_pagosur"
LV="lv_${DEPTO}"
PUNTO="/srv/${DEPTO}"
IMG="/var/discos/pagosur.img"   # el "disco" simulado
IMG_TAM="1G"

# ---- validaciones ----
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }
[[ "$TAM" =~ ^[0-9]+[MG]$ ]] || { echo "Tamaño inválido '$TAM': usar por ej. 256M o 1G"; exit 1; }
getent group "$DEPTO" >/dev/null || { echo "El grupo '$DEPTO' no existe: crear el depto primero (06_seguridad.sh)"; exit 1; }
for cmd in losetup pvcreate mkfs.xfs xfs_quota; do
    command -v "$cmd" >/dev/null || { echo "Falta '$cmd': sudo dnf install -y lvm2 xfsprogs"; exit 1; }
done

# Tamaños en MB. numfmt pasa "256M" a bytes (268435456).
CUOTA_MB=$(( $(numfmt --from=iec "$TAM") / 1024 / 1024 ))
LV_MB=$(( CUOTA_MB * 5 / 4 ))    # +25 %: ver encabezado

# ---- 1. Disco simulado y grupo de volúmenes (una sola vez para todos) ----
# truncate crea un archivo DISPERSO: declara 1 GB pero no ocupa nada hasta
# que se escribe. losetup lo presenta como un disco de bloques (/dev/loopN).
if [[ ! -f "$IMG" ]]; then
    mkdir -p "$(dirname "$IMG")"
    truncate -s "$IMG_TAM" "$IMG"
    log "ALMACENAMIENTO: creado disco simulado $IMG ($IMG_TAM, disperso)"
fi

LOOP=$(losetup -j "$IMG" | cut -d: -f1 | head -n1)    # ¿ya está conectado?
if [[ -z "$LOOP" ]]; then
    LOOP=$(losetup -f --show "$IMG")                   # -f: primer loop libre
    log "ALMACENAMIENTO: $IMG conectado como $LOOP"
fi

if vgs "$VG" &>/dev/null; then
    vgchange -ay "$VG" >/dev/null       # por si se reinició: activa los LV
else
    # PV = el disco marcado para LVM; VG = el "pozo" de espacio que se reparte
    pvcreate -q "$LOOP"
    vgcreate -q "$VG" "$LOOP"
    log "ALMACENAMIENTO: creado PV $LOOP y VG $VG"
fi

# ---- 2. Volumen lógico del departamento + sistema de archivos XFS ----
if lvs "$VG/$LV" &>/dev/null; then
    log "ALMACENAMIENTO: /dev/$VG/$LV ya existe, no se toca"
else
    LIBRE_MB=$(( $(vgs --noheadings --units b --nosuffix -o vg_free "$VG" | tr -d ' ') / 1024 / 1024 ))
    if (( LIBRE_MB < LV_MB )); then
        log "ALMACENAMIENTO: ERROR no hay lugar para $DEPTO: hacen falta ${LV_MB} MB y el VG $VG tiene ${LIBRE_MB} MB libres"
        exit 1
    fi
    lvcreate -q -y -L "${LV_MB}M" -n "$LV" "$VG"
    mkfs.xfs -q "/dev/$VG/$LV"
    log "ALMACENAMIENTO: creado /dev/$VG/$LV de ${LV_MB} MB con XFS"
fi

# ---- 3. Montaje persistente en /srv/<depto> ----
# fstab: <dispositivo> <punto> <tipo> <opciones> <dump> <fsck>
#   pquota: activa las cuotas de proyecto (sin esto xfs_quota no limita nada,
#           y en XFS no se puede activar después con un remount)
#   nofail: si el loop no está (después de un reinicio) la VM arranca igual
mkdir -p "$PUNTO"
if ! grep -q "[[:space:]]$PUNTO[[:space:]]" /etc/fstab; then
    echo "/dev/$VG/$LV  $PUNTO  xfs  defaults,pquota,nofail  0 0" >> /etc/fstab
    systemctl daemon-reload            # systemd genera los montajes a partir de fstab
    log "ALMACENAMIENTO: agregado $PUNTO a /etc/fstab"
fi
if ! mountpoint -q "$PUNTO"; then
    mount "$PUNTO"                     # usa la línea de fstab: prueba que esté bien
    log "ALMACENAMIENTO: montado /dev/$VG/$LV en $PUNTO"
fi

# Permisos DESPUÉS de montar (antes se aplicarían a la carpeta vacía de abajo).
# 2770: dueño y grupo leen/escriben, el resto nada; el 2 (SGID) hace que todo
# lo que se cree adentro quede del grupo del departamento.
chown root:"$DEPTO" "$PUNTO"
chmod 2770 "$PUNTO"
# Un XFS recién creado no tiene etiquetas de SELinux: restorecon le pone la
# que corresponde a /srv (el detalle de SELinux es del ej. 6).
command -v restorecon >/dev/null && restorecon -R "$PUNTO"

# ---- 4. Cuota de proyecto ----
# Un "proyecto" de XFS es un árbol de directorios con un número (ID). Se usa
# el GID del grupo: ya es único y fácil de explicar.
#   /etc/projects: <ID>:<carpeta>      /etc/projid: <nombre>:<ID>
ID=$(getent group "$DEPTO" | cut -d: -f3)
grep -q "^$ID:" /etc/projects 2>/dev/null || echo "$ID:$PUNTO" >> /etc/projects
grep -q "^$DEPTO:" /etc/projid 2>/dev/null || echo "$DEPTO:$ID" >> /etc/projid

# project -s: marca la carpeta (y lo que se cree adentro) con el ID del proyecto
# limit bhard: tope duro de bloques; al llegar, write() falla con EDQUOT
xfs_quota -x -c "project -s $DEPTO" "$PUNTO" >/dev/null
xfs_quota -x -c "limit -p bhard=$TAM $DEPTO" "$PUNTO"
log "ALMACENAMIENTO: cuota de proyecto $DEPTO (id $ID) = $TAM sobre $PUNTO"

df -h "$PUNTO"
