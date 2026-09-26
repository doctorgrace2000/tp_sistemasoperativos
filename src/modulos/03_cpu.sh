#!/usr/bin/env bash
# =============================================================================
# 03_cpu.sh — Ejercicio 3: Planificación de CPU
#
# Objetivo: asignar un porcentaje de CPU al departamento mediante un slice
# de systemd (cgroups v2) con CPUQuota.
#
# Herramientas: systemctl set-property, systemd-run, top, nice, chrt
# Teoría:       algoritmos de scheduling, CFS, prioridades y nice.
#
# Uso: 03_cpu.sh <depto> <cpu%>      ej: 03_cpu.sh finanzas 30%
# Demo: lanzar bin/03_carga_cpu dentro del slice y verificar en top que no
#       supera el porcentaje asignado.
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
CPU="${2:?falta cpu%}"
SLICE="depto-${DEPTO}.slice"

# TODO:
#   [ ] crear el slice: systemctl set-property "$SLICE" CPUQuota="$CPU"
#   [ ] verificar: systemctl show "$SLICE" -p CPUQuotaPerSecUSec
#   [ ] demo: systemd-run --slice="$SLICE" --uid=<usuario> ../bin/03_carga_cpu
#   [ ] comparar con nice/chrt sobre un proceso fuera del slice

log "CPU: slice=$SLICE CPUQuota=$CPU (pendiente de implementar)"
