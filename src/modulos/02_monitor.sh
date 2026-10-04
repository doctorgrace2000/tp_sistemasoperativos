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
# Herramientas: ps, renice, kill, /proc/<PID>/stat (lo lee ps por debajo)
# Teoría:       estados de un proceso (R, S, D, Z), PCB, señales, zombies,
#               prioridades (nice).
#
# Uso:  sudo 02_monitor.sh <depto> [umbral_cpu%] [intervalo_seg]
#       Ctrl+C para terminar. Necesita root para tocar procesos de otros.
#
# Cómo encuentra los procesos: `ps -G <depto>` selecciona por grupo REAL, o sea
# el grupo primario del usuario. Por eso los usuarios del departamento se crean
# con `useradd -g <depto>` (ej. 6 o demo/simular_depto.sh).
#
# Demo (sin los otros módulos):
#   sudo ./src/demo/simular_depto.sh finanzas        # crea grupo y usuarios
#   sudo ./src/modulos/02_monitor.sh finanzas 50 5   # terminal 1
#   su - lperez  ->  yes > /dev/null                # terminal 2 (clave: pagosur): satura un núcleo
#   El monitor lo detecta (renice), a la pasada siguiente reincide (SIGTERM)
#   y si no muere en 2 s, SIGKILL. Todo queda en logs/asignador.log.
#   Zombies: como lperez  (sleep 1 & exec sleep 60)  -> el monitor lo reporta.
#   Ver estados a mano:  ps -o pid,user,ni,%cpu,stat,comm -G finanzas
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?Uso: $0 <depto> [umbral_cpu%] [intervalo_seg]}"
UMBRAL="${2:-50}"        # % de CPU a partir del cual un proceso es sospechoso
INTERVALO="${3:-5}"      # segundos entre pasadas
NICE_CASTIGO=19          # la prioridad más baja que existe

[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo): renice y kill sobre procesos ajenos"; exit 1; }
getent group "$DEPTO" >/dev/null || { echo "El grupo '$DEPTO' no existe (ver demo/simular_depto.sh)"; exit 1; }

# PIDs que ya recibieron el primer aviso (renice). Si aparecen de nuevo
# sobre el umbral, reinciden y se terminan.
declare -A AVISADOS
# Zombies ya reportados, para no repetir la misma línea en cada pasada.
declare -A ZOMBIES

log "MONITOR: depto=$DEPTO umbral=${UMBRAL}% cada ${INTERVALO}s (Ctrl+C para salir)"

while true; do
    # Una línea por proceso del grupo: pid usuario %cpu estado comando.
    # Los "=" vacían los encabezados. comm va último porque puede tener espacios.
    while read -r pid user cpu stat comm; do
        [[ -z "$pid" ]] && continue

        # --- Zombie: ya terminó pero el padre no hizo wait(). No se puede matar
        #     (ya está muerto); solo se puede avisar o terminar al padre. ---
        if [[ "$stat" == Z* ]]; then
            if [[ -z "${ZOMBIES[$pid]:-}" ]]; then
                # || true: si el padre lo recogió recién, ps ya no lo encuentra
                ppid=$(ps -o ppid= -p "$pid" | tr -d ' ' || true)
                log "ZOMBIE  pid=$pid ($comm) de $user: el padre pid=${ppid:-?} no hizo wait()"
                ZOMBIES[$pid]=1
            fi
            continue
        fi

        # %cpu viene con decimales (99.8); bash compara enteros -> se trunca.
        cpu_entero=${cpu%.*}
        (( cpu_entero >= UMBRAL )) || continue

        if [[ -z "${AVISADOS[$pid]:-}" ]]; then
            # --- Primera vez: bajar prioridad. El planificador le da menos CPU
            #     pero el proceso sigue vivo, por si era trabajo legítimo. ---
            # Si terminó entre el ps y acá, renice falla: se saltea.
            renice -n "$NICE_CASTIGO" -p "$pid" >/dev/null 2>&1 || continue
            AVISADOS[$pid]=1
            log "AVISO   pid=$pid ($comm) de $user usa ${cpu}% > ${UMBRAL}%: renice a $NICE_CASTIGO"
        else
            # --- Reincide: terminar. SIGTERM es una petición que el proceso
            #     puede atrapar para cerrar ordenado; SIGKILL la ejecuta el
            #     kernel sin que el proceso pueda hacer nada. ---
            log "REINCIDE pid=$pid ($comm) de $user sigue en ${cpu}%: kill -TERM"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then       # kill -0 solo pregunta si existe
                kill -KILL "$pid" 2>/dev/null || true
                log "        pid=$pid ignoró SIGTERM: kill -KILL"
            else
                log "        pid=$pid terminó con SIGTERM"
            fi
            unset "AVISADOS[$pid]"
        fi
    done < <(ps -o pid=,user=,%cpu=,stat=,comm= -G "$DEPTO")

    sleep "$INTERVALO"
done
