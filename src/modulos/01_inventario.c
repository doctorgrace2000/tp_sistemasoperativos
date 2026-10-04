

#include <stdio.h>
#include <string.h>
#include <sys/statvfs.h>

/* Tamaño del disco simulado que crea 04_almacenamiento.sh (archivo disperso
 * en /var/discos, o sea sobre /). Se usa para decir cuántos entran. */
#define DISCO_SIMULADO_GB 1.0


static int contar_cpus(void) {

    /*Devuelve un puntero a una estructura de tipo FILE, fopen reserva
    la estructura en memoria dinamica y devuelve la direccion*/
    FILE *f = fopen("/proc/cpuinfo", "r");
    if (!f) { perror("/proc/cpuinfo"); return -1; }

    /*Creamos un buffer de 256 elementos*/
    char linea[256];
    int n = 0;

    /*Intenta leer del archivo f y guardarla en linea buffer de caracteres*/
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
 * loop0 sí cuenta: es lo que usa 04_almacenamiento.sh como disco simulado. */
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

/* Espacio libre en GB del sistema de archivos que contiene 'ruta'.
 * statvfs es la syscall que usa df: el kernel devuelve bloques totales y
 * libres. f_bavail descuenta el 5 % reservado para root, igual que df. */
static double espacio_libre_gb(const char *ruta) {
    struct statvfs s;
    if (statvfs(ruta, &s) != 0) { perror(ruta); return -1; }
    return (double)s.f_bavail * s.f_frsize / (1024.0 * 1024.0 * 1024.0);
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

    /* Memoria: cuántos procesos de 1 GB (límite del ej. 3) entran hoy */
    unsigned long mem_total, mem_disp, swap;
    if (leer_meminfo(&mem_total, &mem_disp, &swap) == 0) {
        printf("RAM:     %lu MB total, %lu MB disponibles\n", mem_total, mem_disp);
        printf("         entran ~%lu procesos de 1 GB antes de swapear (swap: %lu MB)\n",
               mem_disp / 1024, swap);
    }

    /* Discos: qué hay, y cuánto queda libre en / para el disco simulado (ej. 4) */
    printf("Discos:\n");
    listar_discos();
    double libre = espacio_libre_gb("/");
    if (libre >= 0) {
        printf("  libre en /     %8.2f GB\n", libre);
        printf("         entran ~%d discos simulados de %.0f GB (ej. 4, /var/discos)\n",
               (int)(libre / DISCO_SIMULADO_GB), DISCO_SIMULADO_GB);
    }

    return 0;
}
