#!/usr/bin/env bash
# =============================================================================
# 04_memoria.sh — Ejercicio 4: Memoria
#
# Situación: un proceso de un usuario pide memoria sin parar y el servidor
# empieza a swapear hasta que el OOM killer mata cualquier cosa. El admin
# limita la memoria virtual que puede pedir cada proceso de los usuarios de
# un departamento (1 GB). Al superarla, malloc falla solo en ese proceso y
# el resto del servidor no se entera.
#
# Cómo: una línea en /etc/security/limits.d/ por grupo (límite "as",
# address space, en KB). PAM la aplica en el login.
#
# Herramientas: limits.conf (pam_limits), ulimit -v, free, vmstat, pmap
# Teoría:       memoria virtual, espacio de direcciones, paginación, swap,
#               OOM killer.
#
# Uso:  04_memoria.sh <depto> [mb]     ej: 04_memoria.sh finanzas 1024
# Demo: su - ana -c 'ulimit -v'                -> 1048576
#       su - ana -c ./bin/04_carga_ram          -> "malloc: Cannot allocate memory"
#                                                   al llegar a ~1 GB
#       en otra terminal: free -h y vmstat 1 -> el servidor sigue normal
#       pmap <pid> mientras corre -> ver cómo crece el espacio de direcciones
#
# TODO:
#   [ ] escribir "@$DEPTO  hard  as  $((MB * 1024))" en "$ARCHIVO"
#   [ ] verificar con: su - <usuario del depto> -c 'ulimit -v'
#   [ ] loguear en logs/asignador.log
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
MB="${2:-1024}"
ARCHIVO="/etc/security/limits.d/depto-${DEPTO}-memoria.conf"

log "MEMORIA: grupo=@$DEPTO as=${MB}MB en $ARCHIVO (pendiente de implementar)"
