#!/usr/bin/env bash
# =============================================================================
# asignar.sh — Orquestador del asignador de recursos (servidor "PagoSur")
#
# Uso:
#   ./asignar.sh --depto finanzas --usuarios ejemplos/finanzas.csv \
#                --disco 2G --cpu 30% --ram 512M
#
# Responsabilidad: validar parámetros y llamar a cada módulo en orden.
# NO contiene lógica de los ejercicios: eso vive en src/modulos/.
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/log.sh"

# ---- parámetros ----
DEPTO="" USUARIOS="" DISCO="" CPU="" RAM=""

uso() {
    cat <<USAGE
Uso: $0 --depto <nombre> --usuarios <archivo.csv> --disco <tamaño> --cpu <porcentaje> --ram <tamaño>
Ejemplo: $0 --depto finanzas --usuarios ejemplos/finanzas.csv --disco 2G --cpu 30% --ram 512M
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --depto)    DEPTO="$2";    shift 2 ;;
        --usuarios) USUARIOS="$2"; shift 2 ;;
        --disco)    DISCO="$2";    shift 2 ;;
        --cpu)      CPU="$2";      shift 2 ;;
        --ram)      RAM="$2";      shift 2 ;;
        -h|--help)  uso ;;
        *) echo "Parámetro desconocido: $1"; uso ;;
    esac
done

# ---- validaciones ----
[[ -z "$DEPTO" || -z "$USUARIOS" || -z "$DISCO" || -z "$CPU" || -z "$RAM" ]] && uso
[[ -f "$USUARIOS" ]] || { echo "No existe el CSV: $USUARIOS"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }

log "INICIO asignación depto=$DEPTO disco=$DISCO cpu=$CPU ram=$RAM usuarios=$USUARIOS"

# ---- módulos, en orden ----
# 1. Inventario: ¿qué recursos hay disponibles? (C)
"$DIR/../bin/01_inventario"

# 6. Seguridad primero: crea grupo y usuarios que el resto necesita
bash "$DIR/modulos/06_seguridad.sh"      "$DEPTO" "$USUARIOS"

# 5. Almacenamiento: LV + XFS + cuotas por usuario
bash "$DIR/modulos/05_almacenamiento.sh" "$DEPTO" "$DISCO"

# 3. CPU: slice de systemd con CPUQuota
bash "$DIR/modulos/03_cpu.sh"            "$DEPTO" "$CPU"

# 4. Memoria: MemoryMax sobre el mismo slice
bash "$DIR/modulos/04_memoria.sh"        "$DEPTO" "$RAM"

# 2. Monitor: vigila procesos del depto que se pasen de lo asignado (C)
# Se lanza en segundo plano; ver src/modulos/02_monitor.c
# "$DIR/../bin/02_monitor" "$DEPTO" &

log "FIN asignación depto=$DEPTO"
