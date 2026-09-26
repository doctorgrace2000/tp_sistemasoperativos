/*
 * 01_inventario.c — Ejercicio 1: Estructura del SO
 *
 * Objetivo: inventario del servidor. Reporta los recursos totales disponibles
 * para repartir entre departamentos (CPU, RAM, swap, discos).
 *
 * Herramientas: /proc/cpuinfo, /proc/meminfo, lscpu, strace (para mostrar
 *               las syscalls open/read que hace este programa).
 * Teoría:       syscalls, modo usuario vs modo kernel, sistema de archivos /proc.
 *
 * Compilar: make   (genera bin/01_inventario)
 * Demo:     strace -e trace=openat,read ./bin/01_inventario
 *
 * TODO:
 *   [ ] leer /proc/cpuinfo y contar núcleos (líneas "processor")
 *   [ ] leer /proc/meminfo: MemTotal, MemAvailable, SwapTotal
 *   [ ] leer /proc/loadavg
 *   [ ] imprimir un resumen legible y opcionalmente escribir en logs/asignador.log
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int contar_cpus(void) {
    FILE *f = fopen("/proc/cpuinfo", "r");
    if (!f) { perror("/proc/cpuinfo"); return -1; }
    char linea[256];
    int n = 0;
    while (fgets(linea, sizeof linea, f))
        if (strncmp(linea, "processor", 9) == 0) n++;
    fclose(f);
    return n;
}

int main(void) {
    printf("=== Inventario del servidor PagoSur ===\n");
    printf("CPUs: %d\n", contar_cpus());
    /* TODO: memoria, swap, loadavg, discos */
    return 0;
}
