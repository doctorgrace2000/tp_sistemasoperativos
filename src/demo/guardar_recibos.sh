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
# Sin `sync` el kernel juntaría los recibos en la RAM y los bajaría al disco
# de golpe cuando él decide: la medición daría ráfagas impredecibles (lo
# probamos: 1065/s en un momento, 1,2/s medio minuto después).
#
# Uso:  guardar_recibos.sh [cantidad]     (default: 5000)
#       (en una terminal; en otra, sudo ./src/modulos/05_dispositivos.sh 5)
# =============================================================================
set -euo pipefail

CANTIDAD="${1:-5000}"
[[ "$CANTIDAD" =~ ^[0-9]+$ && "$CANTIDAD" -gt 0 ]] || { echo "Uso: $0 [cantidad]   (cantidad: entero positivo)"; exit 1; }

# /var/tmp está en el disco (en RHEL /tmp también, pero en otras distros /tmp
# vive en la RAM y el disco no se enteraría).
DIR=/var/tmp/recibos
mkdir -p "$DIR"
# trap: pase lo que pase (fin normal o Ctrl+C), borrar los recibos al salir.
trap 'rm -rf "$DIR"; echo; echo "Recibos borrados."' EXIT

echo "Guardando $CANTIDAD recibos en $DIR. Ctrl+C para cortar."
for i in $(seq 1 "$CANTIDAD"); do
    echo "recibo $i" > "$DIR/recibo_$i.txt"
    sync
    echo "guardado recibo $i"
done
