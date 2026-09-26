/*
 * 03_carga_cpu.c — carga de prueba para el Ejercicio 3
 *
 * Bucle infinito que consume CPU al 100 % de un núcleo. Se lanza dentro
 * del slice del departamento para demostrar que CPUQuota lo limita.
 *
 * Uso: ./bin/03_carga_cpu [segundos]   (por defecto corre hasta Ctrl+C)
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    int segundos = (argc > 1) ? atoi(argv[1]) : 0;
    time_t inicio = time(NULL);
    volatile unsigned long x = 0;
    printf("Carga de CPU iniciada (PID %d)\n", (int)getpid());
    while (segundos == 0 || time(NULL) - inicio < segundos) x++;
    return 0;
}
