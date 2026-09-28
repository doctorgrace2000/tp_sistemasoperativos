# TP Obligatorio – Sistemas Operativos

**Alta de departamentos en el servidor PagoSur**

Consignas oficiales: [`docs/Consignas_TPO.pdf`](docs/Consignas_TPO.pdf)
Propuesta vigente (v2): [`docs/TPO_Sistemas_Operativos_Propuesta_v2.pdf`](docs/TPO_Sistemas_Operativos_Propuesta_v2.pdf)
Propuesta original: [`docs/TPO_Sistemas_Operativos_Propuesta.pdf`](docs/TPO_Sistemas_Operativos_Propuesta.pdf)
(la v2 la simplifica; el porqué está en la sección "Qué cambió" del PDF y en "Criterio de diseño" abajo).

## La idea

Una máquina Red Hat es el servidor central de **PagoSur**, una fintech ficticia. Funciona como
repositorio de archivos de la empresa: cada departamento tiene su carpeta, sus usuarios y su
espacio. Cuando se incorpora un departamento nuevo, el administrador ejecuta un script de *alta*
que crea el grupo y los usuarios, la carpeta con cuota de disco, los permisos por rol, y las reglas
que evitan que un proceso de esos usuarios tumbe el servidor. Todo queda en un log de auditoría.

```bash
./asignar.sh --depto finanzas --usuarios finanzas.csv
```

Todo departamento recibe lo mismo, definido como constantes en `asignar.sh`: 256 MB de disco,
sus procesos con prioridad baja (nice 10) y hasta 1 GB de memoria virtual por proceso.
Cuando el departamento se disuelve, `revocar.sh` deshace todo en orden inverso.

El servidor es el escenario común, pero la consigna exige **6 ejercicios de unidades distintas**.
Por eso cada pieza del alta es un ejercicio independiente, con su propia situación, su solución
con capturas y su apartado teórico.

### Criterio de diseño

La consigna no exige ninguna herramienta concreta. Exige 6 ejercicios de unidades distintas,
consola de Red Hat, scripting en al menos 3, y que **cualquiera de los 4 integrantes pueda
defender cualquier ejercicio** con la teoría de su unidad (puntos 6 y 16). Por eso:

- Cada módulo se mantiene en la versión más simple que cumpla su objetivo; lo accesorio se
  muestra a mano en la demo.
- No se usan cgroups ni slices de systemd (no están en el programa de la materia). Los límites de
  CPU y memoria se aplican con `limits.conf`, que PAM activa en el login de cada usuario del grupo.
- El único recurso que se reparte de verdad *por departamento* es el disco, con una cuota de
  proyecto de XFS sobre la carpeta. CPU y memoria son reglas *por proceso* de los usuarios del
  grupo, pensadas para proteger al servidor, y así se explica en el informe.

## Los 6 ejercicios

| # | Ejercicio | Situación y qué hace | Herramientas Red Hat | Código | Teoría |
|---|-----------|----------------------|----------------------|--------|--------|
| 1 | Estructura del SO | Inventario del servidor: CPUs, carga, RAM, swap, discos y espacio libre, leyendo `/proc` y con la syscall `statvfs` | `/proc/cpuinfo`, `/proc/loadavg`, `/proc/meminfo`, `/proc/partitions`, `statvfs`, `strace`, `lscpu`, `free`, `df` | C | Syscalls, modo usuario/kernel, `/proc` |
| 2 | Procesos | Un usuario deja un proceso colgado consumiendo CPU. El monitor lo detecta, le baja la prioridad y si reincide lo termina; reporta zombies | `ps`, `top`, `pstree`, `renice`, `kill` | Script | Estados, PCB, señales, zombies |
| 3 | Planificación de CPU | Los procesos de los usuarios del departamento arrancan con nice 10, así el planificador prioriza al resto | `limits.conf`, `nice`, `renice`, `top`, `chrt` | Script + C (carga de prueba) | Planificador, prioridades, CFS, quantum |
| 4 | Memoria | Ningún proceso de un usuario del departamento puede pedir más de 1 GB; `malloc` falla solo en ese proceso y el servidor sigue | `limits.conf`, `ulimit -v`, `free`, `vmstat`, `pmap` | Script + C (malloc en loop) | Memoria virtual, paginación, swap, OOM killer |
| 5 | Almacenamiento | Carpeta del departamento sobre un volumen lógico XFS, montaje persistente y cuota de proyecto de 256 MB; extensión a demanda a mano | `losetup`, `pvcreate`, `vgcreate`, `lvcreate`, `mkfs.xfs`, `fstab`, `xfs_quota`, `lvextend` | Script | Sistemas de archivos, inodos, journaling, LVM |
| 6 | Seguridad | Alta de usuarios desde CSV, grupo por departamento, permisos por rol, auditor de solo lectura, sudo limitado; SELinux como ejemplo de MAC en la demo | `useradd`, `groupadd`, `chage`, `chmod`, SGID, `setfacl`, `sudoers`, `ls -Z`, `restorecon` | Script | DAC vs MAC, mínimo privilegio |

## Estructura del proyecto

El orquestador es corto y solo llama a módulos, uno por ejercicio. Cada módulo vive en su propio
archivo dentro de `src/`, así cada integrante trabaja en el suyo sin pisar a los demás y cualquier
pieza se puede mostrar y defender por separado.

```
tp_sistemasoperativos/
├── README.md
├── Makefile                       # compila los .c de src/modulos/ en bin/
├── docs/
│   ├── Consignas_TPO.pdf          # consignas oficiales
│   ├── TPO_Sistemas_Operativos_Propuesta.pdf   # propuesta original
│   ├── TPO_Sistemas_Operativos_Propuesta_v2.pdf # propuesta vigente (+ .html fuente)
│   └── informe/                   # informe final: un .md por ejercicio + capturas/
├── ejemplos/
│   └── finanzas.csv               # CSV de usuarios de ejemplo (usuario,rol)
├── logs/
│   └── asignador.log              # auditoría de cada acción (ignorado por git)
└── src/
    ├── asignar.sh                 # alta: valida parámetros y llama a los módulos
    ├── revocar.sh                 # baja: deshace asignar.sh en orden inverso
    ├── demo/
    │   └── simular_depto.sh       # crea grupo + usuarios del CSV para presentar un módulo solo
    ├── lib/
    │   └── log.sh                 # función log() compartida (escribe en logs/asignador.log)
    └── modulos/
        ├── 01_inventario.c        # Ej. 1 – recursos del servidor (/proc, syscalls)
        ├── 02_monitor.sh          # Ej. 2 – control de procesos (ps / renice / kill)
        ├── 03_cpu.sh              # Ej. 3 – nice por grupo vía limits.d
        ├── 03_carga_cpu.c         # Ej. 3 – carga de prueba que satura un núcleo
        ├── 04_memoria.sh          # Ej. 4 – memoria máxima por proceso vía limits.d
        ├── 04_carga_ram.c         # Ej. 4 – malloc en loop hasta que falla
        ├── 05_almacenamiento.sh   # Ej. 5 – loop device + LVM + XFS + cuota de proyecto
        └── 06_seguridad.sh        # Ej. 6 – usuarios, permisos, ACL, sudo
```

### Reparto de tareas

Cada ejercicio es independiente: un archivo de código, un `.md` en `docs/informe/` y sus capturas.
Cada archivo tiene en el encabezado la situación, las herramientas, la demo y una lista de `TODO`.

| Ejercicio | Archivos a completar | Responsable |
|-----------|----------------------|-------------|
| 1. Estructura del SO | `src/modulos/01_inventario.c`, `docs/informe/01_estructura_so.md` | |
| 2. Procesos | `src/modulos/02_monitor.sh`, `docs/informe/02_procesos.md` | |
| 3. Planificación de CPU | `src/modulos/03_cpu.sh`, `03_carga_cpu.c`, `docs/informe/03_planificacion_cpu.md` | |
| 4. Memoria | `src/modulos/04_memoria.sh`, `04_carga_ram.c`, `docs/informe/04_memoria.md` | |
| 5. Almacenamiento | `src/modulos/05_almacenamiento.sh`, `docs/informe/05_almacenamiento.md` | |
| 6. Seguridad | `src/modulos/06_seguridad.sh`, `docs/informe/06_seguridad.md` | |
| Orquestador | `src/asignar.sh`, `src/revocar.sh`, `src/lib/log.sh` | |

### Cómo correr

```bash
make                                   # compila los .c en bin/
sudo ./src/asignar.sh --depto finanzas --usuarios ejemplos/finanzas.csv
tail -f logs/asignador.log             # auditoría
sudo ./src/revocar.sh --depto finanzas # para repetir la demo desde cero
```

Cada módulo también se ejecuta solo. Para presentarlo sin correr el alta completa, primero se
simula el departamento (grupo y usuarios del CSV, clave `pagosur`):

```bash
sudo ./src/demo/simular_depto.sh finanzas            # crea grupo + usuarios de ejemplos/finanzas.csv
sudo ./src/demo/simular_depto.sh finanzas --borrar   # los elimina al terminar
```

y después el módulo que se quiera mostrar:

```bash
sudo ./src/modulos/05_almacenamiento.sh finanzas 256M
sudo ./src/modulos/02_monitor.sh finanzas 50
./bin/01_inventario
```

### Flujo del alta

1. `asignar.sh` valida `--depto` y `--usuarios`. Los valores son fijos: `DISCO=256M`, `NICE=10`,
   `RAM_MB=1024`.
2. Llama a los módulos en orden: inventario → seguridad (grupo y usuarios) → almacenamiento →
   CPU → memoria. El monitor (ej. 2) no se lanza desde acá: se demuestra solo en su terminal.
3. Cada módulo escribe en `logs/asignador.log` con fecha, usuario, acción y resultado.
4. Un error en un módulo no debe romper la demo de los demás.

## Cumplimiento de la consigna

| Requisito | Cómo se cumple |
|-----------|----------------|
| 6 ejercicios, uno por unidad | Cada módulo es un ejercicio con su unidad |
| Consola de Red Hat en todos | Todos se resuelven y demuestran por terminal |
| Shell scripting en al menos 3 | Ejercicios 2, 3, 4, 5, 6 y el orquestador |
| C/C++ (valorado) | Ejercicio 1 (inventario) y las cargas de prueba de 3 y 4 |
| Enunciado hipotético creativo | Escenario de empresa único; cada ejercicio arranca con una situación de una oración |
| Apartado teórico por ejercicio | Columna "Teoría" de la tabla como punto de partida |
| Cualquiera defiende cualquier ejercicio | Módulos mínimos; cada `.md` del informe cierra con preguntas de la unidad y sus respuestas |

## Consideraciones técnicas

- **Discos:** siempre un archivo disperso montado como loop device (`truncate` + `losetup`), nunca
  discos reales. Declara 1 GB pero ocupa solo lo escrito. Sacar snapshot de la VM antes de tocar LVM.
- **Tamaños a escala de demo:** la VM del lab tiene ~2 GB libres en `/`, así que el disco simulado es
  de 1 GB y cada departamento recibe 256 MB. La demo es la misma que con cientos de GB (la cuota
  corta, el VG se agota en el cuarto departamento) y el `dd` termina en segundos. En producción se
  cambia la constante `DISCO` de `asignar.sh`.
- **Cuota de proyecto en XFS:** el volumen debe montarse con `pquota`; si no, `xfs_quota` no tiene efecto.
- **limits.conf:** los límites se aplican en el login (PAM). Para probarlos hay que entrar como el
  usuario con `su - usuario` o `ssh`; un `su usuario` sin guion no los carga.
- **Entorno del lab:** verificar si se resetea entre sesiones. Todo vive en este repo para reconstruir rápido.
- **Independencia:** cada ejercicio debe poder demostrarse solo.
- **Defensa:** el que explica cada ejercicio se elige al azar (consigna, punto 6), y la teoría de la
  unidad pesa tanto como el ejercicio (punto 16). Usar los cuestionarios de cada unidad para preparar preguntas.
