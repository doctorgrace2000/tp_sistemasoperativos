# Contexto para Claude Code — TP Sistemas Operativos (PagoSur)

Este archivo existe para que cualquier sesión de Claude Code (en el Mac del autor o en la VM
Red Hat del laboratorio) arranque con el mismo contexto. El `README.md` tiene la descripción
completa del TP; acá va lo que un agente necesita para trabajar sin que se lo expliquen.

## Qué es esto

TP obligatorio de la materia Sistemas Operativos. Una VM Red Hat es el servidor de archivos de
una fintech ficticia ("PagoSur"). Un script de alta (`src/asignar.sh`) incorpora un departamento:
grupo y usuarios, carpeta con cuota de disco, permisos por rol y una regla que impide que un
proceso de esos usuarios tumbe el servidor. `src/revocar.sh` lo deshace. Cada pieza del alta es
uno de los 6 ejercicios que exige la consigna (uno por unidad de la materia).

Reglas de diseño que NO hay que romper (están justificadas en el README y en la propuesta v2):

- Cada módulo se mantiene en la versión más simple que cumpla su objetivo. Lo accesorio se
  muestra a mano en la demo, no se agrega al script.
- No se usan cgroups ni slices de systemd. El límite de memoria es `limits.conf` + PAM.
- Cada ejercicio tiene que poder demostrarse solo, sin correr el alta completa
  (`src/demo/simular_depto.sh` crea el grupo y los usuarios para eso; clave `pagosur`).
- Un error en un módulo no debe romper la demo de los demás.
- Todo lo que hace un módulo se registra con `log` (de `src/lib/log.sh`) en `logs/asignador.log`.
- El trabajo lo defienden 4 integrantes elegidos al azar, así que los comentarios y el informe
  tienen que explicar el porqué, no solo el qué. Todo en castellano rioplatense.

## Convenciones de código

- Bash: `set -euo pipefail`, `source` de `lib/log.sh`, encabezado con Situación / Cómo /
  Herramientas / Teoría / Uso / Demo. Validar root con `[[ $EUID -eq 0 ]]`. Mirar
  `src/modulos/02_monitor.sh` y `src/modulos/03_memoria.sh` como referencia de estilo.
- C: compilar con `make` (gcc `-Wall -Wextra -O2`, salida en `bin/`). Sin warnings.
- Los usuarios de un departamento se crean con `useradd -g <depto>` (grupo PRIMARIO), porque
  el monitor del ej. 2 los busca con `ps -G <depto>` y `03_memoria.sh` los busca por GID
  primario para verificar.
- Nombres de archivos generados en el sistema: `/etc/security/limits.d/depto-<depto>-memoria.conf`,
  `/srv/<depto>`, `vg_pagosur` / `lv_<depto>`, `/etc/sudoers.d/<depto>`. `revocar.sh` ya sabe
  borrar todos estos; si se agrega algo nuevo, agregar también su baja ahí.
- Informe: un `.md` por ejercicio en `docs/informe/`, con capturas en `docs/informe/capturas/`.
  Seguir la estructura de `docs/informe/02_procesos.md` (situación, solución paso a paso con
  capturas, teoría de la unidad, preguntas y respuestas para la defensa).
- Commits en castellano, en imperativo o descriptivos cortos (ver `git log`).

## Estado al 2026-10-05

| Pieza | Estado |
|---|---|
| Orquestador (`asignar.sh`, `revocar.sh`, `lib/log.sh`, `demo/simular_depto.sh`) | Hecho |
| Ej. 1 `01_inventario.c` | Implementado. Falta compilarlo y correrlo en la VM y escribir `docs/informe/01_estructura_so.md` |
| Ej. 2 `02_monitor.sh` + `docs/informe/02_procesos.md` | Hecho y probado |
| Ej. 3 `03_memoria.sh` | **Implementado en macOS, NUNCA ejecutado en Linux.** Hay que probarlo en la VM |
| Ej. 3 `03_carga_ram.c` | Hecho. Falta compilarlo en la VM |
| Ej. 3 `docs/informe/03_memoria.md` | No existe |
| Ej. 4 `04_almacenamiento.sh` | Solo esqueleto, los pasos están en su TODO |
| Ej. 5 | Sin definir todavía |
| Ej. 6 `06_seguridad.sh` | Solo esqueleto, los pasos están en su TODO |

## Qué hacer en la VM, en este orden

### 1. Preparar el entorno

```bash
sudo dnf install -y gcc git
make
```

Los binarios que pueda haber en `bin/` vienen compilados en macOS: `make clean && make` los
regenera para Linux. Si `make` tira warnings, corregirlos.

### 2. Probar el ejercicio 3 de punta a punta (prioridad)

Antes de nada, confirmar que PAM tiene `pam_limits` en la pila de sesión; en RHEL suele estar
en `/etc/pam.d/system-auth` y `/etc/pam.d/password-auth`:

```bash
grep -r pam_limits /etc/pam.d/
```

Después la secuencia completa:

```bash
sudo src/demo/simular_depto.sh finanzas          # grupo + usuarios de ejemplos/finanzas.csv
sudo src/modulos/03_memoria.sh finanzas 1024     # escribe la regla y la verifica con su -
su - lperez -c 'ulimit -v'                       # esperado: 1048576
su - lperez -c "$PWD/bin/03_carga_ram"           # esperado: corta cerca de 1000 MB con
                                                 # "malloc: Cannot allocate memory"
```

Mientras corre la carga, en otra terminal: `free -h`, `vmstat 1`, `pmap <pid>`. El servidor no
tiene que inmutarse. Contraste: el mismo binario como root no para (cortarlo con Ctrl+C antes
de que swapee de más). Guardar capturas de cada paso en `docs/informe/capturas/03_*.png`.

Cosas que pueden fallar y cómo encararlas:

- `ulimit -v` devuelve `unlimited`: o `pam_limits` no está en `system-auth`, o se usó `su` sin
  guion. Nunca "arreglarlo" poniendo el límite en `.bashrc`: la gracia es que lo aplique PAM.
- El script de verificación compara `ulimit -v` con el valor en KB; si el usuario tiene un
  `.bash_profile` que imprime cosas, la comparación falla. Preferir `su - usuario -c` con un
  shell limpio o filtrar la última línea.
- Si `03_memoria.sh` necesita cambios, mantener el formato `@grupo - as <KB>` y el log.

Al terminar, deshacer con `sudo src/demo/simular_depto.sh finanzas --borrar` y borrar el
archivo de `limits.d` (o `sudo src/revocar.sh --depto finanzas`).

### 3. Escribir `docs/informe/03_memoria.md`

Misma estructura que `02_procesos.md`. Puntos que tiene que cubrir la teoría: memoria virtual y
espacio de direcciones, por qué `malloc` no asigna RAM física hasta que se toca la página
(demand paging, page fault), diferencia entre memoria virtual y RSS, `RLIMIT_AS` vs un límite
de RSS/cgroup, swap y OOM killer, por qué el límite se hereda (fork copia los rlimits) y por
qué solo se aplica en el login (PAM). Incluir el porqué del `memset` con valor 1 (gcc convierte
`malloc`+`memset(0)` en `calloc`, que no toca las páginas).

### 4. Ejercicio 1 en la VM

`./bin/01_inventario` tiene que correr sin errores y mostrar CPUs, carga, RAM, swap, discos y
espacio libre. Sacar capturas, incluyendo `strace -e trace=openat,statfs ./bin/01_inventario`
para mostrar las syscalls. Escribir `docs/informe/01_estructura_so.md`.

### 5. Ejercicios 4 y 6

Seguir los TODO del encabezado de cada script. Para el 4: **sacar snapshot de la VM antes de
tocar LVM**; el disco es siempre un archivo disperso con `losetup`, nunca un disco real; el
volumen se monta con `pquota` o la cuota no funciona. Para el 6: `simular_depto.sh` ya hace la
parte de grupo y usuarios, el módulo real agrega `chage`, sudoers del jefe, ACL del auditor,
SGID en `/srv/<depto>` y `restorecon`.

### 6. Ejercicio 5

Sigue sin definirse. No inventar uno sin consultar: es una decisión del grupo.

## Cómo trabaja el autor con Claude

- Benjamín está aprendiendo C y Bash; cuando pide una explicación, quiere que sea pieza por
  pieza e intuitiva, sin asumir conocimientos previos. No alcanza con describir qué hace el
  código: hay que explicar el mecanismo de abajo (kernel, syscalls, PAM).
- Antes de cambiar algo que ya funciona, preguntar. Antes de tocar LVM, fstab o PAM en la VM,
  avisar qué se va a modificar.
- No hacer commits ni push salvo que se pida.
