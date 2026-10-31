#!/usr/bin/env bash
# =============================================================================
# demo/guardar_recibos.sh — Simula a los empleados de PagoSur guardando
# recibos en el servidor, para la demo del ej. 5 (05_dispositivos.sh).
#
# Guarda <cantidad> archivos de texto chicos (recibo_1.txt dice "recibo 1"),
# uno por vuelta, y después de cada uno corre `sync`, que obliga al kernel a
# escribir YA en el disco lo que tiene en el búfer de la RAM. Así cada vuelta
# es una escritura real en el disco y termina con una interrupción.
# Al final (o con Ctrl+C) borra los recibos.
#
# Con --sin-sync hace lo mismo pero sin `sync`: los recibos quedan en el
# búfer de la RAM y el kernel los baja al disco más tarde, todos juntos. Sirve
# de contraste: las interrupciones del disco casi no se mueven.
#
# Uso:  guardar_recibos.sh [cantidad] [--sin-sync]     (default: 5000)
#       (en una terminal; en otra, sudo ./src/modulos/05_dispositivos.sh 5)
# =============================================================================
set -euo pipefail

CANTIDAD="${1:-5000}"
MODO="${2:-}"
[[ "$CANTIDAD" =~ ^[0-9]+$ && "$CANTIDAD" -gt 0 ]] || { echo "cantidad debe ser un entero positivo: '$CANTIDAD'"; exit 1; }
[[ -z "$MODO" || "$MODO" == "--sin-sync" ]] || { echo "Uso: $0 [cantidad] [--sin-sync]"; exit 1; }

# /var/tmp está en el disco (en RHEL /tmp también, pero en otras distros /tmp
# vive en la RAM y el disco no se enteraría).
DIR=/var/tmp/recibos
mkdir -p "$DIR"
# trap: pase lo que pase (fin normal o Ctrl+C), borrar los recibos al salir.
trap 'rm -rf "$DIR"; echo; echo "Recibos borrados."' EXIT

echo "Guardando $CANTIDAD recibos en $DIR ${MODO:+(sin sync)}. Ctrl+C para cortar."
for i in $(seq 1 "$CANTIDAD"); do
    echo "recibo $i" > "$DIR/recibo_$i.txt"
    [[ "$MODO" == "--sin-sync" ]] || sync
    echo "guardado recibo $i"
done
