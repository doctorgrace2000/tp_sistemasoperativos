#!/usr/bin/env bash
# lib/log.sh — función de auditoría compartida por todos los módulos.
# Cada acción queda en logs/asignador.log con fecha, usuario y mensaje.

LOG_FILE="${LOG_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/logs/asignador.log}"

log() {
    local msg="$*"
    local linea
    linea="$(date '+%Y-%m-%d %H:%M:%S') [$(whoami)] $msg"
    echo "$linea" | tee -a "$LOG_FILE"
}
