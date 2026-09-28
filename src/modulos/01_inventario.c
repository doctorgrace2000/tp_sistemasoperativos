/*
 * 01_inventario.c — Ejercicio 1: Estructura del SO
 *
 * Situación: antes de dar de alta un departamento, el admin quiere saber en
 * qué estado está el servidor: si la CPU ya está saturada, cuánta memoria
 * queda para los procesos de los nuevos usuarios y qué discos hay. Es el
 * primer paso de asignar.sh.
 *
 * Cada dato responde a una pregunta de otro ejercicio:
 *   CPUs y carga  -> ¿hay contención? El nice del ej. 3 solo importa cuando
 *                    la carga supera la cantidad de núcleos.
 *   RAM disponible-> ¿cuántos procesos de 1 GB (límite del ej. 4) entran?
 *   Discos        -> ¿dónde vive el volumen de los departamentos (ej. 5)?
 *
 * Todo sale de /proc: archivos virtuales que el kernel genera al leerlos.
 * El programa solo usa fopen/fgets/fclose, que por debajo son las syscalls
 * openat, read y close. Eso es lo que se muestra con strace en la demo.
 *
 * Herramientas: /proc/cpuinfo, /proc/loadavg, /proc/meminfo, /proc/partitions,
 *               lscpu, uptime y free (para comparar), strace (para ver las syscalls).
 * Teoría:       syscalls, modo usuario vs modo kernel, sistema de archivos /proc.
 *
 * Compilar: make   (genera bin/01_inventario)
 * Demo:     strace -e trace=openat,read,close ./bin/01_inventario
 *           strace -c ./bin/01_inventario        (resumen: cuántas syscalls de cada tipo)
 *           strace -e trace=openat uptime        (uptime lee el mismo /proc/loadavg)
 */
#include <stdio.h>
#include <string.h>

/* Cuenta las líneas "processor" de /proc/cpuinfo: hay una por núcleo. */
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

/* Lee los tres promedios de carga (1, 5 y 15 minutos) de /proc/loadavg.
 * Es una sola línea: "0.52 0.58 0.59 1/612 4213". */
static int leer_loadavg(double *l1, double *l5, double *l15) {
    FILE *f = fopen("/proc/loadavg", "r");
    if (!f) { perror("/proc/loadavg"); return -1; }
    int ok = fscanf(f, "%lf %lf %lf", l1, l5, l15) == 3;
    fclose(f);
    return ok ? 0 : -1;
}

/* Lee MemTotal, MemAvailable y SwapTotal de /proc/meminfo, en MB.
 * Cada línea es "Nombre:   valor kB". sscanf ignora los espacios, así que
 * "MemTotal: %lu kB" matchea sin importar la alineación. */
static int leer_meminfo(unsigned long *total, unsigned long *disp, unsigned long *swap) {
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) { perror("/proc/meminfo"); return -1; }
    char linea[256];
    unsigned long kb;
    *total = *disp = *swap = 0;
    while (fgets(linea, sizeof linea, f)) {
        if (sscanf(linea, "MemTotal: %lu kB", &kb) == 1)     *total = kb / 1024;
        else if (sscanf(linea, "MemAvailable: %lu kB", &kb) == 1) *disp = kb / 1024;
        else if (sscanf(linea, "SwapTotal: %lu kB", &kb) == 1)    *swap = kb / 1024;
    }
    fclose(f);
    return 0;
}

/* Imprime los discos de /proc/partitions con su tamaño en GB y devuelve el total.
 * Formato del archivo:  major minor  #blocks  name   (bloques de 1 KB).
 * Las particiones vienen justo después de su disco y llevan su nombre como
 * prefijo (vda -> vda1, vda2), así que se saltan para no contar dos veces.
 * loop0 sí cuenta: es lo que usa 05_almacenamiento.sh como disco simulado. */
static double listar_discos(void) {
    FILE *f = fopen("/proc/partitions", "r");
    if (!f) { perror("/proc/partitions"); return -1; }
    char linea[256], nombre[64], disco[64] = "";
    unsigned major, minor;
    unsigned long long bloques;
    double total_gb = 0;
    while (fgets(linea, sizeof linea, f)) {
        if (sscanf(linea, "%u %u %llu %63s", &major, &minor, &bloques, nombre) != 4)
            continue;                                   /* encabezado o línea vacía */
        if (disco[0] && strncmp(nombre, disco, strlen(disco)) == 0)
            continue;                                   /* partición del disco anterior */
        if (strncmp(nombre, "sr", 2) == 0 || strncmp(nombre, "ram", 3) == 0)
            continue;                                   /* CD-ROM y ramdisks no cuentan */
        strcpy(disco, nombre);
        double gb = bloques / (1024.0 * 1024.0);
        printf("  disco %-8s %8.2f GB\n", nombre, gb);
        total_gb += gb;
    }
    fclose(f);
    return total_gb;
}

int main(void) {
    printf("=== Estado del servidor PagoSur antes del alta ===\n");

    /* CPU: cantidad de núcleos contra carga promedio de los últimos 15 min */
    int cpus = contar_cpus();
    double l1, l5, l15;
    if (cpus > 0 && leer_loadavg(&l1, &l5, &l15) == 0) {
        printf("CPU:     %d nucleos, carga %.2f (1 min) %.2f (15 min)\n", cpus, l1, l15);
        if (l15 < cpus)
            printf("         sin contencion: sobran ~%.1f nucleos\n", cpus - l15);
        else
            printf("         SATURADO: hay %.1f procesos por nucleo esperando CPU\n", l15 / cpus);
    }

    /* Memoria: cuántos procesos de 1 GB (límite del ej. 4) entran hoy */
    unsigned long mem_total, mem_disp, swap;
    if (leer_meminfo(&mem_total, &mem_disp, &swap) == 0) {
        printf("RAM:     %lu MB total, %lu MB disponibles\n", mem_total, mem_disp);
        printf("         entran ~%lu procesos de 1 GB antes de swapear (swap: %lu MB)\n",
               mem_disp / 1024, swap);
    }

    /* Discos: dónde vive el volumen de los departamentos (ej. 5) */
    printf("Discos:\n");
    double total_discos = listar_discos();
    if (total_discos >= 0)
        printf("  total          %8.2f GB   (el VG de los departamentos va sobre el loop)\n",
               total_discos);

    return 0;
}
