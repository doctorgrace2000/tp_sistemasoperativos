# Ejercicio 5 – Entrada/Salida

**Unidad 5:** Subsistema de entrada/salida (dispositivos, controladores, drivers, interrupciones,
DMA, capas del software de E/S)
**Código:** [`src/modulos/05_dispositivos.sh`](../../src/modulos/05_dispositivos.sh) (shell script)
**Herramientas Red Hat:** `ls -l /dev`, `stat`, `/proc/devices`, `lsblk`, `/proc/interrupts`, `dd`

---

## 1. Situación

> Un lunes a la mañana los usuarios de PagoSur se quejan de que el servidor anda lento. El
> administrador corre el monitor del ejercicio 2 y no encuentra ningún proceso que use mucha CPU.
> Sospecha del **disco**: alguien podría estar copiando archivos enormes.

Para investigarlo quiere ver dos cosas:

1. Cómo conoce el sistema operativo a sus dispositivos: cuál es de **bloque** y cuál de
   **carácter**, y qué **driver** atiende a cada uno.
2. Cuántas **interrupciones** por segundo genera el disco. Si el disco trabaja sin parar, avisa a la
   CPU todo el tiempo.

### En qué se diferencia del ejercicio 1

El inventario del ej. 1 responde **cuántos recursos** tiene el servidor (CPUs, RAM, espacio en
disco). Este ejercicio responde **cómo se comunica** el sistema operativo con sus dispositivos.

## 2. Solución

### Uso

```bash
sudo ./src/modulos/05_dispositivos.sh [segundos]     # default: 5
```

- **Solo lee:** no cambia nada del sistema. Por eso `revocar.sh` no tiene nada que deshacer.
- **Por qué `sudo`:** para leer los dispositivos no hace falta, pero el log `logs/asignador.log` lo
  creó root al correr los otros módulos, y un usuario común no puede escribir en él. Si se corre sin
  `sudo`, el script lo detecta y avisa.
- Cada resultado queda en el log con el prefijo `DISPOSITIVOS:`.

### Parte 1: cuatro dispositivos de ejemplo

En Linux **cada dispositivo es un archivo** en `/dev`. El script toma cuatro ejemplos conocidos y
de cada uno muestra:

- **Tipo:** bloque o carácter.
- **Número mayor:** qué **driver** lo atiende.
- **Número menor:** qué unidad de ese driver es (por ejemplo, qué partición).
- **Driver:** el nombre que figura para ese número mayor en `/proc/devices`, la tabla que usa el
  kernel para saber a qué driver llamar.

Salida en la VM del laboratorio:

```
== 1. Cómo conoce el sistema a sus dispositivos ==
ARCHIVO        TIPO      MAYOR MENOR  DRIVER
/dev/vda       bloque      252     0  virtblk
/dev/vda1      bloque      252     1  virtblk
/dev/pts/0     carácter    136     0  pts
/dev/null      carácter      1     3  mem
```

Cómo leerla:

- `vda` (el disco) y `vda1` (su primera partición) tienen el **mismo mayor**, 252: los atiende el
  mismo driver. Cambia el menor: 0 es el disco entero, 1 la partición 1.
- `pts/0` es la terminal desde la que se corre el script. Es de carácter: recibe y manda letras de
  a una, sin direcciones.
- `/dev/null` también es de carácter: todo lo que se le escribe se descarta.

### Parte 2: interrupciones del disco

Cuando el disco termina un trabajo, "toca el timbre": le manda a la CPU una **interrupción** para
avisarle. El kernel cuenta cuántas recibió de cada dispositivo en `/proc/interrupts`. El script lee
la cuenta del disco, espera los segundos indicados, la vuelve a leer y resta:

```
== 2. Interrupciones del disco vda en 5 s ==
El disco usa la(s) línea(s) de interrupción: 25 (en /proc/interrupts se llaman virtio1-...)
-> 11 interrupciones en 5 s = 2.2 por segundo
```

En reposo son muy pocas. Con alguien copiando un archivo grande (la demo lo simula con `dd`), son
cientos por segundo.

### Decisiones que hay que poder explicar

| Decisión | Por qué |
|---|---|
| `stat -c '%F %t %T'` | Da el tipo de archivo y los números mayor y menor, sin recortar la salida de `ls -l`. |
| `$((16#...))` | `stat` da los números en hexadecimal (base 16); `16#` le dice a bash que los pase a decimal. |
| Buscar el driver en `/proc/devices` | Es la tabla del kernel que relaciona número mayor con driver. |
| Leer `/proc/interrupts` dos veces | Los contadores suman desde que se prendió la máquina. Lo que importa es cuánto crecen en un intervalo. |
| Cómo encuentra la línea del disco | En una VM el disco es "virtio" y sus interrupciones se llaman `virtioN-...`; el script averigua el `N` de su disco en `/sys/block/<disco>/device`. En discos NVMe o SATA usa otro nombre. |
| Avisar si no puede escribir el log | Si el log es de root, `tee` falla y `set -e` cortaría el script a mitad. Mejor un aviso claro al principio. |

## 3. Demostración en Red Hat

> Las capturas van en `docs/informe/capturas/` con el nombre indicado en cada paso.

### Paso 1 – Bloque o carácter, a mano

```bash
ls -l /dev/vda /dev/vda1 /dev/null /dev/tty
```

La primera letra dice el tipo: **`b`** de bloque, **`c`** de carácter. Donde en un archivo normal va
el tamaño, acá aparecen dos números, por ejemplo `252, 1`: el **mayor** y el **menor**.
📸 `05_01_ls_dev.png`

```bash
cat /proc/devices
```

La tabla del kernel: cada número mayor con su driver, separada en `Character devices:` y
`Block devices:`. Buscar el 252 (`virtblk`) y el 1 (`mem`).
📸 `05_02_proc_devices.png`

### Paso 2 – El módulo con el disco en reposo

```bash
sudo ./src/modulos/05_dispositivos.sh 5
```

Pocas interrupciones por segundo: el disco casi no trabaja.
📸 `05_03_reposo.png`

### Paso 3 – El disco trabajando

Hace falta que el disco trabaje **durante** los 5 segundos que mide el script. Por eso se usa una
lectura larga, que tarda varios minutos. En una **segunda terminal**:

```bash
sudo dd if=/dev/vda of=/dev/null bs=1M iflag=direct status=progress
```

- `if=/dev/vda`: lee el disco entero, de a bloques de 1 MB (`bs=1M`).
- `of=/dev/null`: lo leído se tira; no se escribe ni se ocupa nada.
- `iflag=direct`: cada bloque se pide de verdad al disco, sin aprovechar copias que ya estén en la RAM.
- `status=progress`: muestra cuánto lleva leído.

Mientras corre, en la **primera**:

```bash
sudo ./src/modulos/05_dispositivos.sh 5
```

Ahora son cientos de interrupciones por segundo: el disco avisa cada vez que termina de leer un
bloque. Ese es el "culpable" que buscaba el administrador.
📸 `05_04_carga.png`

Al terminar, en la segunda terminal cortar el `dd` con **Ctrl+C**.

### Paso 4 – Las interrupciones en vivo (opcional)

```bash
watch -d -n1 cat /proc/interrupts
```

`-d` resalta lo que cambia cada segundo. Repetir el `dd` del paso 3 y ver crecer la fila `virtio1-req.0` del
disco. Salir con Ctrl+C.
📸 `05_05_watch.png`

### Paso 5 – Auditoría

```bash
grep 'DISPOSITIVOS:' logs/asignador.log
```
📸 `05_06_log.png`

## 4. Apartado teórico

### El subsistema de E/S

Además de procesos, memoria y archivos, el sistema operativo controla todos los dispositivos de
entrada/salida: les envía comandos, atiende sus interrupciones, maneja sus errores y ofrece al resto
del sistema una interfaz **igual para todos** (independencia del dispositivo).

### Dispositivos de bloque y de carácter

- **De bloque:** guardan la información en bloques de tamaño fijo, cada uno con su dirección, y se
  puede leer o escribir cualquier bloque sin pasar por los anteriores. Discos, pendrives, CD.
  En Linux: la `b` de `ls -l` (`/dev/vda`, `/dev/vda1`).
- **De carácter:** envían o reciben un flujo de caracteres, sin direcciones ni búsqueda. Terminal,
  mouse, impresora, placa de red. En Linux: la `c` de `ls -l` (`/dev/pts/0`, `/dev/null`).
- La clasificación no es perfecta (el reloj solo genera interrupciones), pero sirve para que, por
  ejemplo, el sistema de archivos trabaje sobre "un dispositivo de bloques" sin saber qué disco hay
  abajo.

### Controlador (hardware) y driver (software)

Un dispositivo tiene una parte física (el disco en sí) y una parte electrónica, el **controlador**:
un chip que maneja al dispositivo y que la CPU programa a través de sus **registros** (escribiendo
en ellos le da órdenes; leyéndolos conoce su estado). El **driver** es el programa del kernel que
sabe qué órdenes darle a ese controlador. En el ejercicio, `virtblk` es el driver del disco virtual
de la VM.

### Número mayor y menor

Un archivo de `/dev` no guarda datos: guarda el tipo (`b` o `c`) y dos números. Cuando un programa
lo abre, el kernel usa el **mayor** para elegir el driver y le pasa el **menor** para que sepa qué
unidad usar. Así un programa abre un disco igual que un archivo común: es la **denominación
uniforme**. Como los dispositivos son archivos, se protegen con los mismos permisos que cualquier
archivo (`ls -l /dev/vda`: solo root y el grupo `disk` pueden leerlo).

### Tres formas de hacer E/S

1. **E/S programada:** la CPU hace todo y pregunta en un bucle si el dispositivo está listo
   (*espera activa*). Desperdicia CPU.
2. **Por interrupciones:** la CPU da la orden y se va a hacer otra cosa; el dispositivo avisa con
   una interrupción cuando termina cada dato.
3. **Con DMA:** un controlador de **acceso directo a memoria** copia el bloque entero entre el
   disco y la RAM sin la CPU, y hay **una sola** interrupción al final. Es lo que usan los discos:
   por eso el `dd` genera cientos de interrupciones por segundo y no millones.

### Interrupciones

Una interrupción es una señal que un dispositivo manda para pedir atención. La CPU guarda lo que
estaba haciendo, ejecuta el **manejador de interrupciones** que corresponde a ese dispositivo y
después sigue. En Linux, `/proc/interrupts` muestra cuántas atendió cada CPU, por dispositivo.

En Linux el manejador se divide en dos partes, las dos dentro del kernel: la **parte alta**, que
corre apenas llega la interrupción y hace lo mínimo, y la **parte baja**, que hace el trabajo pesado
un instante después.

### Capas del software de E/S

```
   proceso de usuario          dd, el script (llaman a read / write)
          ▼
   software independiente      nombres en /dev, número mayor y menor, permisos,
   del dispositivo             búferes, errores
          ▼
   driver                      virtblk (el disco virtual)
          ▼
   manejador de interrupciones avisa que la operación terminó
          ▼
   hardware                    controlador + DMA + disco
```

Cuando `dd` escribe: el proceso pide escribir, el software independiente del dispositivo busca el
driver por el número mayor, el driver programa al controlador, el controlador copia los datos por
DMA, y al terminar genera una interrupción que el manejador atiende. Esa interrupción es la que
cuenta el script.

### Uso de búfer y spooling

- **Búfer:** memoria donde los datos esperan entre dos partes que van a distinta velocidad. Por eso
  el `dd` usa `iflag=direct`: sin eso, Linux podría darle bloques que ya tiene copiados en un búfer de
  la RAM, y el disco no trabajaría.
- **Spooling:** para dispositivos que no se pueden compartir, como una impresora, los trabajos se
  dejan en una cola (`/var/spool/cups/` en Red Hat) y un **demonio** los imprime de a uno.

## 5. Limitaciones

- El número de interrupciones es un **promedio** en el intervalo: un pico muy corto se diluye.
- El script reconoce discos virtuales (virtio), NVMe y SATA. Si el disco es de otro tipo, avisa y hay
  que mirar `/proc/interrupts` a mano.
- Muestra cuántas interrupciones hay, no cuánto tarda cada escritura. Para eso están `vmstat` e
  `iostat`.

## 6. Preguntas para la defensa

**¿Qué es un dispositivo de bloque y uno de carácter? Dé ejemplos.**
Bloque: bloques de tamaño fijo con dirección, se puede ir a cualquiera (`/dev/vda`, un pendrive).
Carácter: un flujo de caracteres sin direcciones (`/dev/pts/0`, el mouse, la impresora). Se
distinguen por la `b` o la `c` al principio de `ls -l`.

**¿Qué son los números mayor y menor?**
Los dos números que guarda un archivo de `/dev`. El mayor indica qué driver lo atiende; el menor, qué
unidad de ese driver. `vda` y `vda1` tienen el mismo mayor (252) y distinto menor (0 y 1).

**¿Cómo sabe el kernel qué driver usar cuando un programa abre `/dev/vda`?**
Lee el número mayor del archivo y lo busca en su tabla de drivers (la que muestra `/proc/devices`).

**¿Qué diferencia hay entre controlador y driver?**
El controlador es hardware: un chip con registros que maneja al dispositivo. El driver es software
del kernel que sabe programar ese controlador.

**Compare E/S programada, por interrupciones y con DMA.**
Programada: la CPU hace todo y espera en un bucle. Por interrupciones: la CPU da la orden y hace otra
cosa, y el dispositivo avisa cuando termina cada dato. DMA: un controlador aparte copia el bloque
entero a la RAM y hay una sola interrupción al final.

**¿Qué es una interrupción y qué pasa cuando llega?**
Una señal que manda un dispositivo para pedir atención. La CPU guarda lo que estaba haciendo,
ejecuta el manejador de ese dispositivo y después sigue.

**¿Por qué en el paso 3 aumentan las interrupciones del disco?**
Porque `dd` lo hace leer sin parar, y cada vez que el controlador termina una transferencia le
avisa a la CPU con una interrupción.

**¿Qué son la parte alta y la parte baja de un manejador?**
La alta corre apenas llega la interrupción y hace lo mínimo; la baja hace el trabajo pesado un
instante después. Las dos dentro del kernel.

**¿Cuáles son las capas del software de E/S?**
Manejadores de interrupciones, drivers, software independiente del dispositivo y software en el
espacio del usuario. Arriba, el proceso; abajo, el hardware.

**¿Qué es la independencia del dispositivo?**
Que un programa pueda usar cualquier dispositivo sin cambiar su código: `dd` escribe igual en un
disco, en un pendrive o en `/dev/null`.

**¿Cómo se protegen los dispositivos de los usuarios?**
Como son archivos, con permisos: `/dev/vda` solo lo pueden leer root y el grupo `disk`.

**¿Para qué sirve un búfer?**
Para que dos partes que van a distinta velocidad no tengan que esperarse: los datos quedan guardados
un momento en memoria.

**¿Qué es el spooling?**
Una forma de compartir un dispositivo que solo puede usar uno a la vez, como una impresora: los
trabajos se ponen en una cola y un demonio los procesa de a uno.

**¿El script necesita root?**
Para leer los dispositivos, no. Se corre con `sudo` porque el log de auditoría es de root (lo
crearon los otros módulos). Es un ejemplo de permisos de archivo.
