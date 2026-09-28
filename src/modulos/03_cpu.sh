#!/usr/bin/env bash
# =============================================================================
# 03_cpu.sh — Ejercicio 3: Planificación de CPU
#
# Situación: un analista de finanzas deja corriendo un cálculo pesado y el
# resto de los usuarios nota el servidor lento. El admin decide que todos los
# procesos de los usuarios de un departamento arranquen con menor prioridad
# (nice 10), así el planificador les da CPU solo cuando nadie más la necesita.
#
# Cómo: una línea en /etc/security/limits.d/ por grupo. PAM la aplica en el
# login de cualquier usuario del grupo, sin que el usuario haga nada.
#
# Herramientas: limits.conf (pam_limits), nice, renice, top, chrt
# Teoría:       planificador, prioridades y nice, CFS, quantum, apropiación.
#
# Uso:  03_cpu.sh <depto> [nice]      ej: 03_cpu.sh finanzas 10
# Demo: su - ana -c 'nice'                     -> imprime 10
#       su - ana -c ./bin/03_carga_cpu &       (usuario de finanzas)
#       ./bin/03_carga_cpu &                   (root, nice 0)
#       top  -> columna NI y %CPU: con un solo núcleo, root se lleva casi todo.
#       Sin el límite, los dos se reparten 50/50: eso es lo que se compara.
#
# TODO:
#   [ ] escribir "@$DEPTO  -  priority  $NICE" en "$ARCHIVO"
#   [ ] verificar con: su - <usuario del depto> -c nice
#   [ ] loguear en logs/asignador.log
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
NICE="${2:-10}"
ARCHIVO="/etc/security/limits.d/depto-${DEPTO}-cpu.conf"

log "CPU: grupo=@$DEPTO priority=$NICE en $ARCHIVO (pendiente de implementar)"
