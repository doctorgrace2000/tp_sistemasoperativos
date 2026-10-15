# Propuesta — Ejercicio 5: Entrada/Salida (`05_es.sh`)

Estado: **propuesta, pendiente de decisión del grupo**. El módulo `src/modulos/05_es.sh` existe
pero está vacío. Material de referencia: `Unidad 5.pdf` y su cuestionario (19 preguntas).

## Qué cubre la unidad 5

Dispositivos de bloque y de carácter; controladores de dispositivo y sus registros; E/S por
asignación de puertos y por asignación de memoria; DMA; interrupciones; E/S programada, por
interrupciones y por DMA; las cuatro capas del software de E/S (manejadores de interrupciones,
drivers, software independiente del dispositivo, espacio de usuario); nombres uniformes y
protección en `/dev`; búferes; dispositivos dedicados vs compartidos; spooling.

## Opción recomendada: dispositivo dedicado por departamento

**Situación.** PagoSur tiene una impresora fiscal (o un lector de tarjetas) conectada al puerto
serie del servidor. Es un dispositivo **dedicado**: solo lo puede usar Finanzas, y si otro
departamento le escribe en el medio de un ticket lo arruina. El alta del departamento le asigna
el dispositivo al grupo.

**Cómo.** Una regla de `udev`, que es la pieza en espacio de usuario que nombra y protege los
dispositivos cuando el kernel los detecta:

```
# /etc/udev/rules.d/90-depto-finanzas-es.rules
KERNEL=="ttyS0", GROUP="finanzas", MODE="0660", SYMLINK+="impresora_fiscal"
```

`05_es.sh <depto> [dispositivo]` (default `ttyS0`): valida root y que el grupo exista, escribe la
regla, la recarga con `udevadm control --reload && udevadm trigger --name-match=<dispositivo>`,
verifica con `stat -c '%G' /dev/<dispositivo>` y loguea. `revocar.sh` borra la regla y vuelve a
disparar `udev` para que el dispositivo recupere su grupo original (`dialout`). `asignar.sh` lo
llama después de seguridad, como a los demás.

**Demo** (todo existe en cualquier VM, sin hardware extra):

| Qué se muestra | Comando | Teoría / pregunta del cuestionario |
|---|---|---|
| Dispositivo de carácter (`c`) vs de bloque (`b`), números mayor y menor | `ls -l /dev/ttyS0 /dev/vda /dev/null` | P1, nombres uniformes, major/minor |
| El controlador se direcciona por puertos de E/S | `grep -i serial /proc/ioports` muestra `03f8-03ff` | P3, P5 (`/proc/iomem` para el contraste con memoria) |
| E/S controlada por interrupciones | `grep ttyS /proc/interrupts` muestra la IRQ 4 | P12, P15 |
| Qué driver lo maneja y que vive en el kernel | `udevadm info -a -n /dev/ttyS0 \| grep -i driver`, `lsmod` | P16, P17 |
| Dispositivo dedicado y protección por permisos | `lperez` escribe y funciona; un usuario de otro depto recibe `Permission denied` | P10, naming y protección |
| Capas del software de E/S | `strace -e trace=openat,write echo hola > /dev/ttyS0` (libc → syscall → driver) | P14, P19 |

Si en VirtualBox se habilita el puerto COM1 en modo "archivo" (Raw File), lo que `lperez` escribe
en `/dev/ttyS0` aparece en un archivo del host: la impresora fiscal "imprime" de verdad. Sin eso, la
escritura puede devolver `No such device or address` (el permiso pasó, el driver no encontró UART);
la demo de protección funciona igual.

**Por qué esta.** Mapea a más de la mitad del cuestionario con comandos concretos, no requiere
instalar nada, es una regla de una línea (regla de diseño del TP) y es el único ejercicio donde se
ve literalmente la E/S por puertos y las interrupciones en `/proc`.

**Limitación a decir en el informe.** Un puerto serie es uno solo: el segundo departamento que lo
pida se lo "roba" al primero. Eso es exactamente lo que la unidad llama dispositivo dedicado.

## Opción 2: cola de impresión por departamento (spooling)

**Situación.** Varios departamentos comparten una impresora. Sin cola, uno la abre y la bloquea.
El alta crea una cola CUPS propia del departamento, restringida a su grupo y con cuota de páginas:
`lpadmin -p imp_finanzas -u allow:@finanzas -o job-page-limit=100`. Demo con `lp`, `lpstat`,
`/var/spool/cups` y el demonio `cupsd`.

**Teoría.** Spooling, demonios, software de E/S en espacio de usuario, dispositivo dedicado vuelto
compartible (P10, P19). El resto de la unidad queda solo en el apartado teórico.

**Contra.** Hay que instalar CUPS y una impresora virtual (`cups-pdf` viene de EPEL en RHEL). Más
configuración, más cosas que pueden fallar en vivo.

## Opción 3 (descartada): monitor de E/S de disco con `ionice`

Hermano del ejercicio 2 para disco. `ionice` solo tiene efecto con el planificador BFQ; los discos
virtuales de RHEL 9 usan `none` o `mq-deadline`, así que la demo no mostraría nada sin cambiar el
planificador a mano. Además se superpone con el ejercicio 2.

## Decisión

Pendiente. Recomendación: opción 1, con la 2 como plan B si alguien se anima a configurar CUPS.
Cuando el grupo decida, se implementa el script siguiendo el estilo de `03_memoria.sh` y se agrega
la baja a `revocar.sh`.
