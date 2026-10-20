#!/usr/bin/env bash
# =============================================================================
# 05_dispositivos.sh — Ejercicio 5: Entrada/Salida
#
# Situación: un lunes el servidor de PagoSur anda lento, pero ningún proceso
# usa mucha CPU (el monitor del ej. 2 no encuentra nada). El admin sospecha
# del disco: quiere ver cómo el sistema operativo conoce a sus dispositivos
# y cuántas veces por segundo el disco le está "tocando el timbre" a la CPU.
#
# Cómo: solo lee lo que publica el kernel, en dos partes.
#   1. Cuatro dispositivos de ejemplo: el disco, una partición, la terminal
#      desde la que se corre y /dev/null. En Linux cada dispositivo es un
#      archivo en /dev; de cada uno se muestra si es de bloque o de carácter,
#      su número MAYOR (qué driver lo atiende) y su número MENOR (qué unidad
#      de ese driver), y el nombre del driver según /proc/devices.
#   2. Interrupciones del disco: cuando el disco termina un trabajo, avisa a
#      la CPU con una interrupción. El kernel las cuenta en /proc/interrupts.
#      Se lee esa cuenta dos veces, con <segundos> de diferencia, y la resta
#      dice cuántas hubo por segundo.
#
# Solo lee: no cambia nada del sistema, así que revocar.sh no tiene nada que
# deshacer. Para leer no hace falta root, pero el log compartido suele ser de
# root (los otros módulos corren con sudo): por eso se corre con sudo.
#
# Herramientas: ls -l /dev, stat, /proc/devices, lsblk, /proc/interrupts,
#               dd (en la demo)
# Teoría:       dispositivos de bloque y de carácter, controlador y driver,
#               número mayor/menor, interrupciones, DMA, capas de E/S.
#
# Uso:  sudo 05_dispositivos.sh [segundos]     (default 5)
#
# Demo (desde la raíz del repo):
#   sudo ./src/modulos/05_dispositivos.sh 5            # disco en reposo: pocas
#   En otra terminal, poner al disco a trabajar (lee el disco entero, tarda
#   minutos y no escribe nada):
#     sudo dd if=/dev/vda of=/dev/null bs=1M iflag=direct status=progress
#   y mientras corre, en la primera:
#     sudo ./src/modulos/05_dispositivos.sh 5          # muchas más por segundo
#   Al terminar, Ctrl+C en la otra terminal para cortar el dd.
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

SEG="${1:-5}"
[[ "$SEG" =~ ^[0-9]+$ && "$SEG" -gt 0 ]] || { echo "segundos debe ser un entero positivo: '$SEG'"; exit 1; }

# logs/asignador.log lo crea el primer módulo que se corre, y casi siempre es
# uno con sudo: el archivo queda de root. Un usuario común no puede agregarle
# líneas, tee falla y set -e cortaría el script a mitad. Mejor avisar antes.
if [[ -e "$LOG_FILE" && ! -w "$LOG_FILE" ]]; then
    echo "No se puede escribir en $LOG_FILE: es de $(stat -c %U "$LOG_FILE")."
    echo "Correr con sudo:  sudo $0 $SEG"
    exit 1
fi

# Nombre del driver para un tipo ("b" o "c") y un número mayor.
# /proc/devices tiene dos listas, "Character devices:" y "Block devices:",
# con líneas "<mayor> <nombre>". Es la tabla que usa el kernel para saber qué
# driver llamar cuando alguien abre un archivo de /dev.
driver_de() {
    local tipo="$1" mayor="$2" seccion
    [[ "$tipo" == b ]] && seccion="Block devices:" || seccion="Character devices:"
    awk -v s="$seccion" -v m="$mayor" '
        /devices:$/ { en = ($0 == s); next }
        en && $1 == m { if (!r || (r ~ /^\// && $2 !~ /^\//)) r = $2 }
        END { print r }' /proc/devices
}

# ---- elegir los 4 ejemplos ----
# El disco: el primero que lsblk marca como "disk" (zram es un disco en RAM,
# no cuenta). La partición: la primera de ese disco.
DISCO=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" && $1 !~ /^zram/ {print $1; exit}')
[[ -n "$DISCO" ]] || { echo "No se encontró ningún disco con lsblk"; exit 1; }
PARTICION=$(lsblk -lno NAME,TYPE "/dev/$DISCO" | awk '$2 == "part" {print $1; exit}')
# La terminal: tty dice desde cuál se está corriendo (por ej. /dev/pts/0).
TERMINAL=$(tty 2>/dev/null || true)
[[ "$TERMINAL" == /dev/* ]] || TERMINAL=/dev/console

EJEMPLOS=("/dev/$DISCO")
[[ -n "$PARTICION" ]] && EJEMPLOS+=("/dev/$PARTICION")
EJEMPLOS+=("$TERMINAL" /dev/null)

# ---- 1. Cuatro dispositivos de ejemplo ----
echo "== 1. Cómo conoce el sistema a sus dispositivos =="
printf "%-14s %-9s %5s %5s  %s\n" ARCHIVO TIPO MAYOR MENOR DRIVER
resumen=""
for f in "${EJEMPLOS[@]}"; do
    # stat: %F tipo de archivo, %t y %T números mayor y menor en hexadecimal.
    # $((16#ff)) pasa de hexadecimal a decimal.
    read -r tipo_hex mayor_hex menor_hex <<< "$(stat -c '%F %t %T' "$f" | sed 's/ special file//; s/^block/b/; s/^character/c/')"
    mayor=$((16#$mayor_hex)); menor=$((16#$menor_hex))
    [[ "$tipo_hex" == b ]] && tipo="bloque" || tipo="carácter"
    drv=$(driver_de "$tipo_hex" "$mayor")
    printf "%-14s %-9s %5s %5s  %s\n" "$f" "$tipo" "$mayor" "$menor" "${drv:-?}"
    resumen="$resumen $f=$tipo_hex:$mayor:$menor:${drv:-?}"
done
log "DISPOSITIVOS: ejemplos (archivo=tipo:mayor:menor:driver):$resumen"

# ---- 2. Interrupciones del disco ----
# Hay que encontrar qué líneas de /proc/interrupts son del disco. El nombre
# depende del tipo de disco de la máquina:
#   - disco virtual (virtio, el de las VM): /sys/block/<disco>/device apunta
#     a una carpeta "virtioN", y sus interrupciones se llaman "virtioN-...".
#   - disco NVMe (nvme0n1): las interrupciones se llaman "nvme0q...".
#   - disco SATA: las del controlador "ahci".
ruta=$(readlink -f "/sys/block/$DISCO/device" 2>/dev/null || true)
virtio=$(grep -oE 'virtio[0-9]+' <<< "$ruta" | head -1 || true)
if   [[ -n "$virtio" ]];        then PATRON="${virtio}-"
elif [[ "$DISCO" == nvme* ]];   then PATRON="${DISCO%%n[0-9]*}q"
else                                 PATRON="ahci"
fi

# Suma, en todas las CPU, las interrupciones de las líneas del disco.
# Cada línea es "IRQ: <una cuenta por CPU> <tipo> <nombre>"; la primera
# línea del archivo dice cuántas CPU hay (CPU0 CPU1 ...).
contar() {
    awk -v p="$PATRON" '
        NR == 1 { ncpu = NF; next }
        index($NF, p) == 1 { for (i = 2; i <= ncpu + 1; i++) s += $i; irqs = irqs " " substr($1, 1, length($1) - 1) }
        END { printf "%d%s\n", s, irqs }' /proc/interrupts
}

echo
echo "== 2. Interrupciones del disco $DISCO en $SEG s =="
read -r antes IRQS_TXT <<< "$(contar)"
if [[ -z "$IRQS_TXT" ]]; then
    echo "No se encontró la línea del disco en /proc/interrupts (se buscó '$PATRON')."
    echo "Mirarla a mano con:  cat /proc/interrupts"
    exit 0
fi
sleep "$SEG"
read -r despues _ <<< "$(contar)"
total=$(( despues - antes ))
por_seg=$(awk -v t="$total" -v s="$SEG" 'BEGIN {printf "%.1f", t / s}')
echo "El disco usa la(s) línea(s) de interrupción: $IRQS_TXT (en /proc/interrupts se llaman ${PATRON}...)"
echo "-> $total interrupciones en $SEG s = $por_seg por segundo"
log "DISPOSITIVOS: el disco $DISCO generó $total interrupciones en ${SEG}s ($por_seg por segundo)"
