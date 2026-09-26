/*
 * 04_carga_ram.c — carga de prueba para el Ejercicio 4
 *
 * Reserva memoria en bloques de 10 MB en un loop y la toca (memset) para
 * que realmente se asignen páginas. Dentro de un slice con MemoryMax el
 * OOM killer lo termina al superar el límite.
 *
 * Uso: ./bin/04_carga_ram [mb_por_paso] [ms_entre_pasos]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    size_t mb_paso = (argc > 1) ? (size_t)atoi(argv[1]) : 10;
    int ms = (argc > 2) ? atoi(argv[2]) : 200;
    size_t total = 0;

    for (;;) {
        char *bloque = malloc(mb_paso * 1024 * 1024);
        if (!bloque) { perror("malloc"); return 1; }
        memset(bloque, 1, mb_paso * 1024 * 1024);   /* fuerza asignación real */
        total += mb_paso;
        printf("Reservados %zu MB\n", total);
        fflush(stdout);
        usleep(ms * 1000);
    }
}
