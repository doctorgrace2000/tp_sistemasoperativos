#!/usr/bin/env bash
# =============================================================================
# 04_memoria.sh — Ejercicio 4: Memoria
#
# Objetivo: límite de RAM por departamento (MemoryMax en el slice) y
# demostración del OOM killer sin afectar al resto del servidor.
#
# Herramientas: systemctl set-property MemoryMax, free, vmstat, pmap,
#               journalctl -k (mensajes del OOM killer), swap
# Teoría:       memoria virtual, paginación, swapping, OOM killer.
#
# Uso: 04_memoria.sh <depto> <ram>      ej: 04_memoria.sh finanzas 512M
# Demo: lanzar bin/04_carga_ram dentro del slice; ver que muere por OOM y
#       que el resto de los procesos siguen vivos.
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
RAM="${2:?falta ram}"
SLICE="depto-${DEPTO}.slice"

# TODO:
#   [ ] systemctl set-property "$SLICE" MemoryMax="$RAM" MemorySwapMax=0
#   [ ] verificar: systemctl show "$SLICE" -p MemoryMax
#   [ ] demo: systemd-run --slice="$SLICE" ../bin/04_carga_ram
#   [ ] evidencia: journalctl -k | grep -i "out of memory"; free -h; vmstat 1

log "MEMORIA: slice=$SLICE MemoryMax=$RAM (pendiente de implementar)"
