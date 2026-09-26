# TP Obligatorio – Sistemas Operativos

**Servidor simulado con asignador de recursos**

Propuesta completa: [`docs/TPO_Sistemas_Operativos_Propuesta.pdf`](docs/TPO_Sistemas_Operativos_Propuesta.pdf)

## La idea

Una máquina Red Hat simula ser el servidor central de una empresa ficticia (**PagoSur**, una fintech).
Cada vez que se incorpora un departamento o proyecto nuevo, el administrador ejecuta un *asignador*
que crea usuarios, espacio en disco con cuota, límites de CPU y memoria, permisos y reglas de
seguridad, dejando todo registrado en un log de auditoría.

```bash
./asignar.sh --depto finanzas --usuarios finanzas.csv \
             --disco 2G --cpu 30% --ram 512M
```

El servidor es el escenario común, pero la consigna exige **6 ejercicios de unidades distintas**.
Por eso cada pieza del asignador es un ejercicio independiente, con su propio enunciado, solución
con capturas y apartado teórico.

## Los 6 ejercicios

| # | Ejercicio | Qué hace | Herramientas Red Hat | Código | Teoría |
|---|-----------|----------|----------------------|--------|--------|
| 1 | Estructura del SO | Inventario del servidor: reporta los recursos totales disponibles para repartir | `/proc/cpuinfo`, `/proc/meminfo`, `strace`, `lscpu` | C | Syscalls, modo usuario/kernel, `/proc` |
| 2 | Procesos | Monitor que detecta procesos que exceden lo asignado y los baja de prioridad o los termina | `ps`, `top`, `pstree`, `renice`, `kill`, `/proc/<PID>/stat` | C o script | Estados, PCB, señales, zombies |
| 3 | Planificación de CPU | Asigna % de CPU por departamento con slices de systemd (cgroups) | `systemctl set-property ... CPUQuota=30%`, `top`, `nice`, `chrt` | C (carga de prueba) | Algoritmos de scheduling, CFS |
| 4 | Memoria | Límite de RAM por departamento; se demuestra el OOM killer sin afectar al resto | `MemoryMax`, `free`, `vmstat`, `pmap`, `journalctl`, swap | C (malloc en loop) | Memoria virtual, paginación, swapping |
| 5 | Almacenamiento | Un volumen lógico por departamento, montaje persistente y cuotas por usuario; extensión a demanda | `fdisk`, `pvcreate`, `vgcreate`, `lvcreate`, `lvextend`, `mkfs.xfs`, `fstab`, `xfs_quota` | Script | Sistemas de archivos, inodos, journaling |
| 6 | Seguridad | Alta de usuarios desde CSV, permisos por rol, auditor de solo lectura, sudo limitado, SELinux | `useradd`, `groupadd`, `chage`, `chmod`, SGID, `setfacl`, `sudoers`, `semanage`, `restorecon` | Script | DAC vs MAC, mínimo privilegio |

## Estructura del proyecto

El orquestador es corto y solo llama a módulos, uno por ejercicio. Cada módulo vive en su propio
archivo dentro de `src/`, así cada integrante trabaja en el suyo sin pisar a los demás y cualquier
pieza se puede mostrar y defender por separado.

```
tp_sistemasoperativos/
├── README.md
├── Makefile                       # compila los .c de src/modulos/ en bin/
├── docs/
│   ├── TPO_Sistemas_Operativos_Propuesta.pdf   # propuesta original
│   └── informe/                   # informe final: un .md por ejercicio + capturas/
├── ejemplos/
│   └── finanzas.csv               # CSV de usuarios de ejemplo (usuario,rol)
├── logs/
│   └── asignador.log              # auditoría de cada acción (ignorado por git)
└── src/
    ├── asignar.sh                 # orquestador: valida parámetros y llama a los módulos
    ├── lib/
    │   └── log.sh                 # función log() compartida (escribe en logs/asignador.log)
    └── modulos/
        ├── 01_inventario.c        # Ej. 1 – recursos disponibles (/proc, syscalls)
        ├── 02_monitor.c           # Ej. 2 – control de procesos (renice / kill)
        ├── 03_cpu.sh              # Ej. 3 – slice de systemd + CPUQuota
        ├── 03_carga_cpu.c         # Ej. 3 – carga de prueba que satura un núcleo
        ├── 04_memoria.sh          # Ej. 4 – MemoryMax por departamento
        ├── 04_carga_ram.c         # Ej. 4 – malloc en loop para disparar el OOM killer
        ├── 05_almacenamiento.sh   # Ej. 5 – LVM + XFS + cuotas
        └── 06_seguridad.sh        # Ej. 6 – usuarios, permisos, ACL, sudo, SELinux
```

### Reparto de tareas

Cada ejercicio es independiente: un archivo de código, un `.md` en `docs/informe/` y sus capturas.
Cada archivo tiene en el encabezado el objetivo, las herramientas y una lista de `TODO` con los pasos.

| Ejercicio | Archivos a completar | Responsable |
|-----------|----------------------|-------------|
| 1. Estructura del SO | `src/modulos/01_inventario.c`, `docs/informe/01_estructura_so.md` | |
| 2. Procesos | `src/modulos/02_monitor.c`, `docs/informe/02_procesos.md` | |
| 3. Planificación de CPU | `src/modulos/03_cpu.sh`, `03_carga_cpu.c`, `docs/informe/03_planificacion_cpu.md` | |
| 4. Memoria | `src/modulos/04_memoria.sh`, `04_carga_ram.c`, `docs/informe/04_memoria.md` | |
| 5. Almacenamiento | `src/modulos/05_almacenamiento.sh`, `docs/informe/05_almacenamiento.md` | |
| 6. Seguridad | `src/modulos/06_seguridad.sh`, `docs/informe/06_seguridad.md` | |
| Orquestador | `src/asignar.sh`, `src/lib/log.sh` | |

### Cómo correr

```bash
make                                   # compila los .c en bin/
sudo ./src/asignar.sh --depto finanzas --usuarios ejemplos/finanzas.csv \
                      --disco 2G --cpu 30% --ram 512M
tail -f logs/asignador.log             # auditoría
```

Cada módulo también se ejecuta solo, por ejemplo:

```bash
sudo ./src/modulos/05_almacenamiento.sh finanzas 2G
./bin/01_inventario
```

### Flujo del asignador

1. `asignar.sh` valida los parámetros (`--depto`, `--usuarios`, `--disco`, `--cpu`, `--ram`).
2. Llama a los módulos en orden: inventario → seguridad (grupo y usuarios) → almacenamiento →
   CPU → memoria → monitor.
3. Cada módulo escribe en `logs/asignador.log` con fecha, usuario, acción y resultado.
4. Un error en un módulo no debe romper la demo de los demás.

## Cumplimiento de la consigna

| Requisito | Cómo se cumple |
|-----------|----------------|
| 6 ejercicios, uno por unidad | Cada módulo es un ejercicio con su unidad |
| Consola de Red Hat en todos | Todos se resuelven y demuestran por terminal |
| Shell scripting en al menos 3 | Ejercicios 5, 6 y el orquestador (3 y 4 también) |
| C/C++ (valorado) | Ejercicios 1, 2, 3 y 4 |
| Enunciado hipotético creativo | Escenario de empresa único que da coherencia al TP |
| Apartado teórico por ejercicio | Columna "Teoría" de la tabla como punto de partida |

## Consideraciones técnicas

- **Discos:** si la VM no tiene discos extra, se simulan con archivos y loop devices (`dd` + `losetup`)
  y se arma el volume group encima.
- **Cuotas en XFS:** el volumen debe montarse con `uquota` o `pquota`; si no, `xfs_quota` no tiene efecto.
- **Entorno del lab:** verificar si se resetea entre sesiones. Todo vive en este repo para reconstruir rápido.
- **Independencia:** cada ejercicio debe poder demostrarse solo.
- **Defensa:** todos deben entender los 6 módulos; conviene rotar quién prepara cada uno.
