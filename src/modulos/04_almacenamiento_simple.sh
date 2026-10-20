#!/usr/bin/env bash
# =============================================================================
# 04_almacenamiento_simple.sh — Ejercicio 4: Almacenamiento (versión ALTERNATIVA)
#
# La versión que se presenta es 04_almacenamiento.sh (LVM + disco simulado).
# Esta queda como alternativa: cuota de proyecto sobre la partición raíz.
#
# Situación: cada departamento necesita su carpeta en el servidor con un tope
# de espacio (256 MB) que no pueda superar aunque sus usuarios llenen el disco.
#
# Cómo: la carpeta /srv/<depto> vive en el sistema de archivos XFS del
# servidor, y sobre esa carpeta se aplica una CUOTA DE PROYECTO de XFS. La
# cuota de proyecto limita la carpeta entera, no importa qué usuario escriba:
# es el único límite que de verdad es "por departamento". No hace falta disco
# aparte, ni LVM, ni formatear ni montar nada: se usa el espacio libre que ya
# tiene la partición.
#
# Llamadas al sistema que hay detrás de cada paso (se ven con strace):
#   mkdir(2), chown(2), chmod(2)        -> la carpeta y sus permisos
#   setxattr(2)                         -> etiqueta SELinux (restorecon)
#   ioctl(FS_IOC_FSSETXATTR)            -> marca la carpeta con el ID de proyecto
#                                          y el flag de herencia (xfs_quota project -s)
#   quotactl(2) Q_XSETQLIM              -> fija el tope duro de bloques (xfs_quota limit)
#   write(2) -> -1, errno = EDQUOT      -> lo que recibe el usuario al pasarse:
#                                          "Disk quota exceeded"
#
# Requisito (una sola vez, antes de la primera alta): el XFS tiene que estar
# montado con cuotas de proyecto. Para la raíz eso se activa con un parámetro
# del kernel y un reinicio; el script lo detecta y dice qué hacer:
#   sudo grubby --update-kernel=ALL --args="rootflags=pquota" && sudo reboot
#   findmnt -no OPTIONS /     -> tiene que incluir "prjquota"
#
# Herramientas: xfs_quota, findmnt, /etc/projects, /etc/projid, df, du, strace
# Teoría:       sistemas de archivos, inodos, journaling, cuotas, montaje
#               y opciones de montaje, llamadas al sistema de E/S de archivos.
#
# Uso: sudo 04_almacenamiento_simple.sh <depto> <tamaño>   ej: 04_almacenamiento_simple.sh finanzas 256M
#      El grupo <depto> tiene que existir (06_seguridad.sh o demo/simular_depto.sh).
#
# Demo (desde la raíz del repo):
#   sudo ./src/demo/simular_depto.sh finanzas
#   sudo ./src/modulos/04_almacenamiento_simple.sh finanzas 256M
#   ls -ld /srv/finanzas                               -> drwxrws--- root finanzas
#   sudo xfs_quota -x -c "report -p -h" /              -> finanzas: usado 0, límite 256M
#   sudo su - lperez -c "dd if=/dev/zero of=/srv/finanzas/relleno bs=1M count=400"
#       -> corta en 256 MB con "Disk quota exceeded"; df -h / casi no se mueve
#   Ver la syscall que falla:
#   sudo strace -f -e trace=write -o /tmp/dd.log su - lperez -c "dd if=/dev/zero of=/srv/finanzas/r2 bs=1M count=5"
#   grep EDQUOT /tmp/dd.log
#   Agrandar a demanda (a mano): sudo xfs_quota -x -c "limit -p bhard=512M finanzas" /
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?Uso: $0 <depto> <tamaño>   ej: $0 finanzas 256M}"
TAM="${2:?Uso: $0 <depto> <tamaño>   ej: $0 finanzas 256M}"
PUNTO="/srv/${DEPTO}"

# ---- validaciones ----
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }
[[ "$TAM" =~ ^[0-9]+[MG]$ ]] || { echo "Tamaño inválido '$TAM': usar por ej. 256M o 1G"; exit 1; }
getent group "$DEPTO" >/dev/null || { echo "El grupo '$DEPTO' no existe: crear el depto primero (06_seguridad.sh)"; exit 1; }
command -v xfs_quota >/dev/null || { echo "Falta xfs_quota: sudo dnf install -y xfsprogs"; exit 1; }

# ¿En qué sistema de archivos cae /srv? Tiene que ser XFS montado con cuotas de proyecto.
mkdir -p /srv
MONTAJE=$(findmnt -no TARGET  --target /srv)
TIPO=$(findmnt -no FSTYPE  --target /srv)
OPCIONES=$(findmnt -no OPTIONS --target /srv)

[[ "$TIPO" == "xfs" ]] || { echo "/srv está en un sistema de archivos $TIPO; las cuotas de proyecto de este módulo son de XFS"; exit 1; }
if ! grep -qE '(^|,)(prjquota|pquota)(,|$)' <<<"$OPCIONES"; then
    cat >&2 <<EOF
El sistema de archivos $MONTAJE ($TIPO) no está montado con cuotas de proyecto.
En XFS no se puede activar en caliente: hay que montarlo con "pquota" desde el arranque.
Para la raíz, una sola vez:
    sudo grubby --update-kernel=ALL --args="rootflags=pquota" && sudo reboot
Después verificar con:  findmnt -no OPTIONS $MONTAJE   (tiene que incluir prjquota)
EOF
    log "ALMACENAMIENTO: ERROR $MONTAJE sin pquota, no se puede aplicar la cuota de $DEPTO"
    exit 1
fi

# ---- 1. La carpeta del departamento ----
# 2770: dueño y grupo leen/escriben, el resto nada. El "2" (SGID) hace que todo
# lo que se cree adentro quede del grupo del departamento, no del que lo creó.
mkdir -p "$PUNTO"                                   # mkdir(2)
chown root:"$DEPTO" "$PUNTO"                        # chown(2)
chmod 2770 "$PUNTO"                                 # chmod(2)
command -v restorecon >/dev/null && restorecon -R "$PUNTO"   # setxattr(2) security.selinux
log "ALMACENAMIENTO: carpeta $PUNTO root:$DEPTO 2770"

# ---- 2. Cuota de proyecto ----
# Un "proyecto" de XFS es un árbol de directorios con un número. Se usa el GID
# del grupo como ID: ya es único y fácil de explicar.
#   /etc/projects: <ID>:<carpeta>      /etc/projid: <nombre>:<ID>
# Son tablas de nombres para xfs_quota; el kernel solo conoce el número.
ID=$(getent group "$DEPTO" | cut -d: -f3)
grep -q "^$ID:" /etc/projects 2>/dev/null || echo "$ID:$PUNTO" >> /etc/projects
grep -q "^$DEPTO:" /etc/projid 2>/dev/null || echo "$DEPTO:$ID" >> /etc/projid

# project -s: ioctl(FS_IOC_FSSETXATTR) sobre la carpeta: fsx_projid = ID y el
#   flag PROJINHERIT, así cada archivo nuevo nace "cobrado" a este proyecto.
# limit -p bhard: quotactl(Q_XSETQLIM): tope duro de bloques. Al llegar, el
#   write(2) del usuario falla con EDQUOT.
xfs_quota -x -c "project -s $DEPTO" "$MONTAJE" >/dev/null
xfs_quota -x -c "limit -p bhard=$TAM $DEPTO" "$MONTAJE"
log "ALMACENAMIENTO: cuota de proyecto $DEPTO (id $ID) = $TAM sobre $PUNTO (fs $MONTAJE)"

xfs_quota -x -c "report -p -h" "$MONTAJE" | grep -E "Project|^$DEPTO|^-" || true
