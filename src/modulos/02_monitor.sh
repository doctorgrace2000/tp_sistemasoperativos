#!/usr/bin/env bash
# =============================================================================
# 02_monitor.sh — Ejercicio 2: Procesos
#
# Situación: un usuario deja un proceso colgado que consume CPU y se va a su
# casa. El monitor recorre los procesos de los usuarios de un departamento y,
# si alguno pasa el umbral de CPU, lo baja de prioridad (renice). Si reincide,
# lo termina (kill con SIGTERM, y SIGKILL si no responde). Además reporta
# procesos zombie.
#
# Herramientas: ps, top, pstree, renice, kill, /proc/<PID>/status
# Teoría:       estados de un proceso (R, S, D, Z), PCB, señales, zombies.
#
# Uso:  02_monitor.sh <depto> [umbral_cpu%] [intervalo_seg]
# Demo: lanzar bin/03_carga_cpu como un usuario del depto y ver en el log
#       cómo el monitor lo detecta, le hace renice y luego kill.
#       Para zombies: en otra terminal  (sleep 1 & exec sleep 60)  y  ps -o pid,stat,cmd
#
# TODO:
#   [ ] listar procesos del grupo:  ps -o pid,user,%cpu,stat,comm -G "$DEPTO" --no-headers
#   [ ] por cada PID que supere el umbral: renice +10 -p "$PID" y anotar el PID en una lista
#   [ ] si el PID ya estaba en la lista (reincide): kill -TERM "$PID"; sleep 2; kill -KILL si sigue
#   [ ] si stat empieza con Z: reportar "zombie" (no se puede matar, hay que avisar al padre)
#   [ ] repetir cada $INTERVALO segundos; loguear cada acción en logs/asignador.log
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
UMBRAL="${2:-50}"
INTERVALO="${3:-5}"

log "MONITOR: depto=$DEPTO umbral=${UMBRAL}% cada ${INTERVALO}s (pendiente de implementar)"
