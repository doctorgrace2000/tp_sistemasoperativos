#!/usr/bin/env bash
# =============================================================================
# demo/leer_disco.sh — Pone al disco a trabajar leyéndolo entero, para la
# demo del ej. 5 (05_dispositivos.sh).
#
# Simula a "alguien copiando un archivo enorme": lee el disco de punta a punta
# de a 1 MB y tira lo leído. No escribe nada en el disco. Tarda varios
# minutos; se corta con Ctrl+C.
#
# Va aparte del módulo a propósito: 05_dispositivos.sh es la herramienta del
# administrador que MIDE; esto es la carga que tiene que detectar.
#
# Uso:  sudo leer_disco.sh            (en una terminal; en otra, el módulo)
# =============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo): leer el disco entero es solo para root"; exit 1; }

# El mismo disco que mide el módulo: el primero que lsblk marca como "disk".
DISCO=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" && $1 !~ /^zram/ {print $1; exit}')
[[ -n "$DISCO" ]] || { echo "No se encontró ningún disco con lsblk"; exit 1; }

echo "Leyendo /dev/$DISCO entero (solo lectura). Ctrl+C para cortar."
echo "Mientras corre, en otra terminal:  sudo ./src/modulos/05_dispositivos.sh 5"
echo

# iflag=direct: cada bloque se pide de verdad al disco, sin usar las copias que
# Linux guarda en la RAM (el búfer). Sin esto el disco casi no trabajaría.
dd if="/dev/$DISCO" of=/dev/null bs=1M iflag=direct status=progress
