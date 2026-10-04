#!/usr/bin/env bash
# =============================================================================
# asignar.sh — Alta de un departamento en el servidor "PagoSur"
#
# Uso:
#   ./asignar.sh --depto finanzas --usuarios ejemplos/finanzas.csv
#
# Crea el grupo y los usuarios del departamento, su carpeta en /srv/<depto>
# con cuota de disco fija (256 MB), y la regla de memoria que protege al
# servidor de los procesos de sus usuarios.
#
# Responsabilidad: validar parámetros y llamar a cada módulo en orden.
# NO contiene lógica de los ejercicios: eso vive en src/modulos/.
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/log.sh"

# ---- valores fijos para todo departamento ----
DISCO="256M"   # cuota de proyecto de la carpeta   -> 04_almacenamiento.sh
RAM_MB=1024    # memoria virtual máxima por proceso -> 03_memoria.sh

# ---- parámetros ----
DEPTO="" USUARIOS=""

uso() {
    cat <<USAGE
Uso: $0 --depto <nombre> --usuarios <archivo.csv>
Ejemplo: $0 --depto finanzas --usuarios ejemplos/finanzas.csv
Cada departamento recibe $DISCO de disco; sus procesos pueden usar hasta ${RAM_MB} MB cada uno.
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --depto)    DEPTO="$2";    shift 2 ;;
        --usuarios) USUARIOS="$2"; shift 2 ;;
        -h|--help)  uso ;;
        *) echo "Parámetro desconocido: $1"; uso ;;
    esac
done

# ---- validaciones ----
[[ -z "$DEPTO" || -z "$USUARIOS" ]] && uso
[[ -f "$USUARIOS" ]] || { echo "No existe el CSV: $USUARIOS"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }

log "INICIO alta depto=$DEPTO usuarios=$USUARIOS disco=$DISCO ram=${RAM_MB}MB"

# ---- módulos, en orden ----
# 1. Inventario: ¿qué recursos tiene el servidor? (C)
"$DIR/../bin/01_inventario"

# 6. Seguridad primero: crea el grupo y los usuarios que el resto necesita
bash "$DIR/modulos/06_seguridad.sh"      "$DEPTO" "$USUARIOS"

# 4. Almacenamiento: LV + XFS + cuota de proyecto en /srv/<depto>
bash "$DIR/modulos/04_almacenamiento.sh" "$DEPTO" "$DISCO"

# 3. Memoria: memoria virtual máxima por proceso del grupo, vía limits.d
bash "$DIR/modulos/03_memoria.sh"        "$DEPTO" "$RAM_MB"

# 2. Monitor: no se lanza desde acá. Se demuestra solo, en su propia terminal:
#    sudo src/modulos/02_monitor.sh finanzas 50

log "FIN alta depto=$DEPTO"
