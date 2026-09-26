/*
 * 02_monitor.c — Ejercicio 2: Procesos
 *
 * Objetivo: monitor que recorre los procesos de un departamento (por grupo
 * o por slice) y, si alguno excede lo asignado, lo baja de prioridad
 * (renice) o lo termina (SIGTERM / SIGKILL).
 *
 * Herramientas: ps, top, pstree, renice, kill, /proc/<PID>/stat, /proc/<PID>/status
 * Teoría:       estados de un proceso, PCB, señales, procesos zombie.
 *
 * Uso:  ./bin/02_monitor <depto> [umbral_cpu%]
 *
 * TODO:
 *   [ ] recorrer /proc y quedarse con los PIDs cuyo UID pertenece al grupo del depto
 *   [ ] leer utime/stime de /proc/<PID>/stat y calcular % de CPU entre dos muestras
 *   [ ] si supera el umbral: setpriority() para bajar prioridad; si reincide: kill()
 *   [ ] detectar estado 'Z' (zombie) y reportarlo
 *   [ ] loguear cada acción en logs/asignador.log
 */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/resource.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <depto> [umbral_cpu%%]\n", argv[0]);
        return 1;
    }
    const char *depto = argv[1];
    int umbral = (argc > 2) ? atoi(argv[2]) : 50;

    printf("Monitor del depto '%s' (umbral %d%%)\n", depto, umbral);
    /* TODO: loop principal de monitoreo */
    return 0;
}
