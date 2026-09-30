# Ejercicio 2 – Procesos

**Unidad:** Procesos (estados, PCB, creación, señales, zombies, prioridades)
**Código:** [`src/modulos/02_monitor.sh`](../../src/modulos/02_monitor.sh) (shell script)
**Herramientas Red Hat:** `ps`, `top`, `pstree`, `renice`, `kill`, `/proc/<PID>/`

---

## 1. Situación

> Un viernes a la tarde, Lucas Pérez (analista de Finanzas) deja corriendo un cálculo que quedó
> en un bucle infinito y se va a su casa. El proceso consume el 100 % de un núcleo del servidor de
> PagoSur durante todo el fin de semana y el resto de los departamentos nota el servidor lento.

El administrador necesita algo que vigile los procesos de los usuarios de un departamento y actúe
solo, sin castigar de entrada a un proceso que quizás estaba haciendo trabajo legítimo:

1. **Primer aviso:** si un proceso supera un umbral de CPU, se le **baja la prioridad** (`renice`).
   Sigue vivo, pero el planificador le da CPU solo cuando nadie más la necesita.
2. **Reincidencia:** si en la pasada siguiente sigue por encima del umbral, se lo **termina**:
   primero con `SIGTERM` (le pide que cierre ordenado) y, si no responde en 2 s, con `SIGKILL`.
3. **Zombies:** además reporta los procesos zombie del departamento y quién es su padre, que es el
   verdadero responsable.
4. **Resumen por departamento:** como el servidor lo comparten varios departamentos, en cada pasada
   muestra cuántos procesos tiene cada uno, en qué estado están y cuánta CPU suman, para ver quién
   está cargando la máquina.

Todo queda registrado en `logs/asignador.log`, el log de auditoría compartido por todo el TP.

## 2. Solución

### Uso

```bash
sudo ./src/modulos/02_monitor.sh <depto>[,<depto>...] [umbral_cpu%] [intervalo_seg]
sudo ./src/modulos/02_monitor.sh finanzas 50 5              # un departamento
sudo ./src/modulos/02_monitor.sh finanzas,marketing 50 5    # varios: un for recorre la lista
sudo ./src/modulos/02_monitor.sh finanzas,marketing 101 5   # solo observa (ver abajo)
```

Con umbral **101** el monitor no actúa nunca y solo muestra el resumen: un proceso de un solo hilo
no puede usar más del 100 % (un núcleo entero), así que ninguno lo supera.

Necesita root porque un usuario común solo puede hacer `renice` y `kill` sobre sus propios
procesos (y ni siquiera puede *subirse* la prioridad).

### Cómo funciona

El script tiene dos bucles: un `while true` que repite la pasada cada `intervalo` segundos, y
adentro un `for` que recorre la lista de departamentos. Para cada departamento ejecuta:

```bash
ps -o pid=,user=,%cpu=,stat=,comm= -G finanzas
```

- `-G finanzas` selecciona los procesos cuyo **grupo real** es `finanzas`. Por eso los usuarios del
  departamento se crean con `useradd -g finanzas` (grupo *primario*), tanto en el ej. 6 como en
  `demo/simular_depto.sh`.
- Los `=` después de cada columna eliminan el encabezado, así cada línea se lee directo con `read`.
- `ps` obtiene estos datos de `/proc/<PID>/stat` y `/proc/<PID>/status`, que es la vista que el
  kernel expone de cada PCB.

Para cada proceso:

```
         ┌──────────────────────┐
         │ estado empieza con Z?│── sí ──► log ZOMBIE (una sola vez por PID, con su PPID)
         └──────────┬───────────┘
                    no
         ┌──────────▼───────────┐
         │   %CPU >= umbral ?   │── no ──► nada
         └──────────┬───────────┘
                    sí
         ┌──────────▼───────────┐
         │ ya fue avisado antes?│── no ──► renice -n 19  → log AVISO (queda marcado)
         └──────────┬───────────┘
                    sí
         kill -TERM → espera 2 s → ¿sigue vivo? (kill -0) → kill -KILL
                                                     → log REINCIDE
```

Al terminar cada departamento imprime una línea de resumen (solo en pantalla, no en el log, para
no llenarlo cada 5 s):

```
--- 18:05:10 ---
finanzas       3 procesos  R=2   S/D=1   Z=0   CPU total= 198%
marketing      2 procesos  R=1   S/D=1   Z=0   CPU total=  99%
```

`CPU total` suma el `%CPU` de todos los procesos del departamento. Con varios núcleos puede pasar
el 100 %: 100 % equivale a un núcleo entero (en el ejemplo, finanzas ocupa casi dos).

Los PIDs avisados se guardan en un arreglo asociativo de bash (`declare -A AVISADOS`); los zombies
ya reportados en otro (`ZOMBIES`) para no repetir la línea en cada pasada.

Detalles que vale la pena poder explicar en la defensa:

| Línea / decisión | Por qué |
|---|---|
| `renice -n 19` | 19 es la prioridad más baja posible (rango −20 a 19). No mata nada: es un aviso "suave". |
| `kill -TERM` primero | `SIGTERM` (15) se puede atrapar: el proceso puede guardar, cerrar archivos y salir limpio. |
| `kill -KILL` si no muere | `SIGKILL` (9) no se puede atrapar ni ignorar: lo ejecuta el kernel directamente. |
| `kill -0 $pid` | La señal 0 no se envía; solo verifica si el proceso existe y si tenemos permiso. |
| El zombie no se mata | Ya está muerto: solo queda su entrada en la tabla de procesos. Se reporta al padre. |
| `cpu_entero=${cpu%.*}` | `ps` devuelve `99.8`; bash solo compara enteros, así que se trunca. |
| `total=$((total + 1))` | Con `set -e`, `((total++))` corta el script cuando `total` vale 0 (devuelve "falso"). |
| `IFS=, read -ra LISTA` | Convierte `finanzas,marketing` en un arreglo para recorrerlo con `for`. |
| `renice ... \|\| continue` | Si el proceso terminó entre el `ps` y el `renice`, no se corta el monitor (`set -e`). |

## 3. Demostración en Red Hat

> Las capturas van en `docs/informe/capturas/` con el nombre indicado en cada paso.

### Preparación (una sola vez)

```bash
sudo ./src/demo/simular_depto.sh finanzas        # grupo finanzas + mgarcia, lperez, rsosa, auditor1 (clave: pagosur)
```

El proceso colgado se simula con `yes > /dev/null`: `yes` imprime "y" sin parar y, con la salida
descartada, consume el 100 % de un núcleo. No hace falta compilar nada.

### Paso 1 – Levantar el monitor (terminal 1)

```bash
sudo ./src/modulos/02_monitor.sh finanzas 50 5
```

Salida esperada:
```
2026-10-05 18:00:00 [root] MONITOR: deptos=finanzas umbral=50% cada 5s (Ctrl+C para salir)
```
📸 `02_01_monitor_inicio.png`

### Paso 2 – El proceso colgado (terminal 2)

```bash
su - lperez            # con guion: login completo (carga limits.conf si el ej. 3 está aplicado)
yes > /dev/null
```

### Paso 3 – Observar el proceso antes de que actúe el monitor (terminal 3)

```bash
ps -o pid,ppid,user,ni,pri,%cpu,stat,comm -G finanzas
pstree -p lperez
top -u lperez          # tecla q para salir
```

En `ps` se ve el proceso en estado **R** (running) con ~100 % de CPU, y la shell de `lperez` en
**S** (sleeping, esperando que termine su hijo). `pstree` muestra la jerarquía
`bash(4300)───yes(4321)`: la shell hizo `fork()` + `exec()` para lanzarlo.
📸 `02_02_ps_pstree_antes.png`

Para mostrar el PCB "por dentro":
```bash
cat /proc/4321/status | head -12     # Name, State, Pid, PPid, Uid, Gid, Threads...
grep ctxt /proc/4321/status          # cambios de contexto voluntarios / involuntarios
```
📸 `02_03_proc_status.png`

### Paso 4 – Primer aviso: renice

En la terminal 1 aparece:
```
... [root] AVISO   pid=4321 (yes) de lperez [finanzas] usa 99.6% > 50%: renice a 19
```
Y en la terminal 3, repitiendo el `ps`, la columna **NI** pasó de 0 a **19**, y el `STAT`
muestra la marca **N** (prioridad baja): `RN`.
📸 `02_04_renice.png`

### Paso 5 – Reincide: SIGTERM

Cinco segundos después sigue arriba del umbral:
```
... [root] REINCIDE pid=4321 (yes) de lperez [finanzas] sigue en 99.7%: kill -TERM
... [root]         pid=4321 terminó con SIGTERM
```
En la terminal 2 la shell de `lperez` muestra `Terminated` (Terminado).
📸 `02_05_sigterm.png`

### Paso 6 – Un proceso que ignora SIGTERM: SIGKILL

Como `lperez`, un bucle que atrapa y descarta `SIGTERM`:
```bash
bash -c 'trap "" TERM; while :; do :; done'
```
El monitor le hace `renice` y en la pasada siguiente:
```
... [root] REINCIDE pid=4400 (bash) de lperez [finanzas] sigue en 99.5%: kill -TERM
... [root]         pid=4400 ignoró SIGTERM: kill -KILL
```
En la terminal 2 aparece `Killed` (Terminado (killed)). Muestra la diferencia entre una señal que
el proceso puede manejar y una que ejecuta el kernel.
📸 `02_06_sigkill.png`

### Paso 7 – Zombie

Como `lperez`:
```bash
(sleep 1 & exec sleep 60) &
```
El subshell crea un hijo `sleep 1` y después se **reemplaza** a sí mismo (`exec`) por `sleep 60`,
que nunca llama a `wait()`. Cuando `sleep 1` termina, queda zombie durante 60 s.

```bash
ps -o pid,ppid,stat,comm -u lperez     # el hijo aparece como Z / <defunct>
pstree -p lperez                       # sleep(4501)───sleep(4502)
```
Monitor:
```
... [root] ZOMBIE  pid=4502 (sleep) de lperez [finanzas]: el padre pid=4501 no hizo wait()
```
📸 `02_07_zombie.png`

Para demostrar que un zombie no se puede matar:
```bash
sudo kill -9 4502; ps -o pid,stat,comm -p 4502    # sigue en Z
sudo kill 4501;    ps -o pid,stat,comm -p 4502    # desaparece
```
Al morir el padre, el zombie queda huérfano, lo adopta `systemd` (PID 1) y este hace `wait()`.
📸 `02_08_zombie_padre.png`

### Paso 8 – Dos departamentos: comparar la carga

```bash
sudo ./src/demo/simular_depto.sh marketing                     # jsuarez, mlopez, auditor2 (clave: pagosur)
sudo ./src/modulos/02_monitor.sh finanzas,marketing 101 5      # terminal 1: solo observa
```
Terminal 2, como `lperez` (finanzas), dos cargas en segundo plano con un `for`:
```bash
for i in 1 2; do yes > /dev/null & done
```
Terminal 3, como `jsuarez` (marketing), una sola carga:
```bash
yes > /dev/null &
```
Al terminar, en cada terminal: `pkill yes`.
El resumen muestra a finanzas con `R=2` y ~200 % de CPU y a marketing con `R=1` y ~100 %. Si la VM
tiene menos núcleos que cargas, los procesos se reparten la CPU y los porcentajes bajan: se ve
cómo el planificador comparte los núcleos entre los procesos listos (planificación de CPU).
📸 `02_09_dos_deptos.png`

Repitiendo con umbral 50 (`finanzas,marketing 50 5`) se ve que el monitor actúa en los dos
departamentos por igual y el log indica a cuál pertenece cada proceso (`[finanzas]`,
`[marketing]`).

### Paso 9 – Auditoría y limpieza

```bash
grep -E 'MONITOR|AVISO|REINCIDE|ZOMBIE|pid=' logs/asignador.log
kill -l                                           # lista de señales (para la teoría)
sudo ./src/demo/simular_depto.sh finanzas --borrar
sudo ./src/demo/simular_depto.sh marketing --borrar
```
📸 `02_10_log.png`

## 4. Apartado teórico

### Proceso y PCB

Un **proceso** es un programa en ejecución: el código más su estado (registros, pila, memoria,
archivos abiertos). El sistema operativo lo representa con un **PCB** (*Process Control Block*),
que en Linux es la estructura `task_struct` del kernel. Contiene, entre otros:

- identificación: PID, PPID (padre), UID/GID dueños;
- estado y contexto de CPU: registros, contador de programa, puntero de pila (se guardan en cada
  cambio de contexto);
- planificación: prioridad, valor *nice*, tiempo de CPU consumido;
- memoria: tablas de páginas / regiones (`mm_struct`);
- archivos abiertos, directorio actual, manejadores de señales y señales pendientes.

`/proc/<PID>/` es una vista de solo lectura de ese PCB. `ps` y `top` no hacen más que leerla.

### Estados de un proceso

| Estado (modelo teórico) | `STAT` en `ps` | Significado |
|---|---|---|
| Ejecución / Listo | `R` | Usando la CPU o en la cola esperando turno. Linux no los distingue en `ps`. |
| Bloqueado (interrumpible) | `S` | Espera un evento (teclado, red, `sleep`, `wait`). Una señal lo despierta. |
| Bloqueado (no interrumpible) | `D` | Espera E/S de disco; no atiende señales hasta que termina la operación. |
| Detenido | `T` | Pausado con `SIGSTOP` o Ctrl+Z; se reanuda con `SIGCONT`. |
| Terminado (zombie) | `Z` | Ya terminó, pero el padre no leyó su código de salida. |

Transiciones: *Nuevo → Listo* (al crearse), *Listo → Ejecución* (el planificador lo elige),
*Ejecución → Listo* (se le acaba el quantum o llega uno de mayor prioridad), *Ejecución →
Bloqueado* (pide E/S), *Bloqueado → Listo* (llega el evento), *Ejecución → Terminado* (`exit`).

Modificadores que aparecen en el demo: `N` prioridad baja (nice > 0), `<` prioridad alta,
`s` líder de sesión, `+` en primer plano de la terminal, `l` multihilo.

### Creación y terminación: `fork`, `exec`, `wait`, `exit`

- `fork()` crea un hijo que es una copia del padre (con *copy-on-write*: las páginas se copian
  recién cuando alguno escribe). Devuelve 0 en el hijo y el PID del hijo en el padre.
- `exec()` reemplaza la imagen del proceso por otro programa, manteniendo el PID.
- `exit()` termina el proceso; el kernel libera su memoria y archivos pero **conserva** la entrada
  en la tabla con el código de salida, y manda `SIGCHLD` al padre.
- `wait()` / `waitpid()` es cómo el padre lee ese código; recién ahí la entrada se libera.

Así lanza la shell cada comando: `fork()` → el hijo hace `exec("yes")` → el padre
(`bash`) hace `wait()`. Por eso en el paso 3 la shell aparece en estado `S`.

### Zombies y huérfanos

- **Zombie:** hijo que terminó y cuyo padre todavía no hizo `wait()`. No consume CPU ni memoria,
  solo una entrada en la tabla de procesos (y su PID). No se puede matar porque ya está muerto;
  la solución es que el padre haga `wait()` o terminar al padre. Muchos zombies acumulados pueden
  agotar los PIDs disponibles (`/proc/sys/kernel/pid_max`).
- **Huérfano:** hijo cuyo padre terminó primero. Lo adopta `systemd` (PID 1), que sí hace `wait()`
  cuando termina, así que un huérfano nunca queda zombie para siempre.

### Señales

Una señal es una notificación asíncrona que el kernel entrega a un proceso. El proceso puede
tomar la acción por defecto, ignorarla o atraparla con un manejador (`trap` en bash, `signal()` /
`sigaction()` en C), salvo `SIGKILL` y `SIGSTOP`.

| Señal | N° | Uso | ¿Se puede atrapar? |
|---|---|---|---|
| `SIGHUP` | 1 | Se cerró la terminal; muchos demonios la usan para recargar configuración | Sí |
| `SIGINT` | 2 | Ctrl+C | Sí |
| `SIGKILL` | 9 | Terminación inmediata por el kernel | **No** |
| `SIGTERM` | 15 | Pedido de terminación ordenada (default de `kill`) | Sí |
| `SIGCHLD` | 17 | Un hijo terminó o se detuvo (se envía al padre) | Sí |
| `SIGCONT` | 18 | Reanudar un proceso detenido | Sí |
| `SIGSTOP` | 19 | Detener (pausar) | **No** |
| `SIGTSTP` | 20 | Ctrl+Z | Sí |

Se envían con `kill -SEÑAL PID`, `pkill` / `killall` (por nombre o usuario) o desde el teclado.
Un usuario solo puede enviar señales a sus propios procesos; root, a cualquiera.

### Prioridad y `nice`

El valor **nice** va de **−20** (máxima prioridad) a **19** (mínima); el default es 0. En `top`,
la columna `PR` = 20 + nice para procesos normales. Un usuario común solo puede *subir* su nice
(ser más "amable"); bajarlo requiere root. El planificador de Linux (CFS) reparte la CPU en
proporción a un peso que depende del nice (cada nivel ≈ 10 % más o menos de CPU): un proceso con
nice 19 frente a uno con nice 0 recibe apenas ~1,5 % de la CPU **cuando compiten**. Si la CPU está
libre, igual la usa entera: por eso `renice` no baja el `%CPU` del proceso colgado en una máquina
ociosa, pero sí evita que perjudique a los demás en un servidor cargado.

## 5. Limitaciones y posibles mejoras

- `%CPU` de `ps` es el **promedio desde que arrancó** el proceso (tiempo de CPU / tiempo de
  vida), no el uso instantáneo. Un proceso que estuvo horas quieto y recién empieza a girar tarda
  en superar el umbral. Para una medición instantánea se podría usar `top -b -n 2 -d <intervalo>`
  o comparar `utime+stime` de `/proc/<PID>/stat` entre dos pasadas.
- Entre el aviso y el `kill` pasa un solo intervalo; en producción convendría un intervalo largo
  (por ej. 60 s) o exigir varias pasadas seguidas por encima del umbral.
- Solo ve procesos cuyo **grupo real** es el del departamento (`ps -G`). Un usuario con otro grupo
  primario o un proceso lanzado con `newgrp` quedaría afuera; `ps -u` por lista de usuarios sería
  la alternativa.
- El monitor corre en primer plano. Para dejarlo fijo se lo podría convertir en un servicio de
  `systemd` (`Restart=always`) o lanzar con `nohup ... &`.
- En vez de terminar al padre de un zombie, se podría enviarle `SIGCHLD` para "recordarle" hacer
  `wait()`; si el programa está mal escrito no sirve, por eso solo se reporta.

## 6. Preguntas para la defensa

**¿Qué es un proceso y en qué se diferencia de un programa?**
Un programa es un archivo pasivo en disco; un proceso es ese programa en ejecución, con su PCB,
memoria, registros y recursos. Un mismo programa puede tener muchos procesos a la vez.

**¿Qué es el PCB y dónde lo vemos en Linux?**
La estructura del kernel que guarda todo lo necesario para administrar y reanudar un proceso
(PID, estado, registros, prioridad, memoria, archivos). En Linux es `task_struct`; se consulta
desde `/proc/<PID>/status` y `/proc/<PID>/stat`, que es lo que lee `ps`.

**¿Qué es un cambio de contexto?**
Guardar el estado de CPU del proceso que sale en su PCB y cargar el del que entra. Es trabajo
"improductivo" del SO. En `/proc/<PID>/status` están `voluntary_ctxt_switches` (el proceso se
bloqueó) y `nonvoluntary_ctxt_switches` (el planificador lo desalojó); un bucle infinito tiene
casi todos involuntarios.

**¿Cuáles son los estados de un proceso y cómo se ven en `ps`?**
Nuevo, listo, ejecución, bloqueado, terminado. En `ps`: `R` (listo o ejecutando), `S` / `D`
(bloqueado interrumpible / no interrumpible), `T` (detenido), `Z` (zombie).

**¿Qué es un zombie? ¿Por qué `kill -9` no lo elimina? ¿Cómo se soluciona?**
Un proceso que terminó pero cuyo padre no hizo `wait()`. `kill -9` no tiene efecto porque ya no
hay nada ejecutándose que terminar. Se soluciona haciendo que el padre llame a `wait()` o
terminando al padre: el zombie pasa a ser hijo de `systemd`, que lo recoge.

**¿Qué es un proceso huérfano?**
Uno cuyo padre terminó antes. Lo adopta `systemd` (PID 1). No es un problema en sí mismo.

**Diferencia entre `SIGTERM` y `SIGKILL`. ¿Por qué el monitor manda primero `SIGTERM`?**
`SIGTERM` se puede atrapar e ignorar: le da al proceso la oportunidad de cerrar archivos y
guardar. `SIGKILL` la ejecuta el kernel sin intervención del proceso, que puede dejar datos a
medio escribir. Por eso primero se pide y solo si no responde se fuerza.

**¿Qué señales no se pueden atrapar ni ignorar?**
`SIGKILL` (9) y `SIGSTOP` (19). Así el administrador siempre puede terminar o detener un proceso.

**¿Para qué sirve `kill -0`?**
No envía ninguna señal; solo verifica que el PID exista y que tengamos permiso de señalizarlo.

**¿Qué hacen `fork()` y `exec()`? ¿Cómo lanza la shell un comando?**
`fork()` duplica el proceso (padre e hijo siguen desde el mismo punto); `exec()` reemplaza el
programa del proceso actual sin cambiar el PID. La shell hace `fork()`, el hijo hace `exec()` del
comando y el padre hace `wait()`. `pstree` muestra esa jerarquía.

**¿Qué es el valor nice? ¿Quién puede cambiarlo?**
Un ajuste de prioridad de −20 (más prioridad) a 19 (menos). Cualquier usuario puede aumentar el
nice de sus procesos; solo root puede bajarlo o tocar procesos ajenos. Se fija al lanzar con
`nice -n` y se cambia en ejecución con `renice`.

**¿Por qué el monitor primero hace `renice` y no mata directamente?**
Porque el proceso podría estar haciendo trabajo legítimo. Bajarle la prioridad protege al resto
del servidor sin perder ese trabajo; solo si persiste se lo termina.

**¿Por qué el monitor tiene que correr como root?**
Porque actúa sobre procesos de otros usuarios: enviar señales o cambiar el nice de un proceso
ajeno requiere privilegios de root.

**¿Qué diferencia hay entre `ps` y `top`?**
`ps` es una foto en un instante (ideal para scripts); `top` se actualiza continuamente y su `%CPU`
es el uso en el último intervalo, mientras que el de `ps` es el promedio de toda la vida del
proceso.

**¿Por qué el `CPU total` de un departamento puede superar el 100 %?**
Porque `ps` mide el `%CPU` de cada proceso respecto de **un** núcleo. Con dos procesos en bucle en
una máquina de dos núcleos, cada uno usa ~100 % y el departamento suma ~200 %. Un proceso de un solo
hilo nunca pasa el 100 %, porque solo puede ejecutarse en un núcleo a la vez.

**¿Qué muestra `pstree` que no muestra `ps`?**
La jerarquía padre/hijo en forma de árbol. Sirve para encontrar al padre responsable de un zombie
o ver qué lanzó cada proceso.
