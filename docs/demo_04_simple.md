# Guion de presentación — Ejercicio 4: Almacenamiento

Presentación en vivo de `04_almacenamiento_simple.sh` (versión alternativa, simple: cuota de proyecto XFS sobre la
partición raíz). Dura entre 5 y 7 minutos. Dos terminales en la raíz del repo de la VM.
Lo que está en cursiva es lo que se dice. Los bloques de código son lo que se tipea.

Datos de la VM que condicionan el guion:

- La raíz (`/dev/vda4`) es XFS. `/srv` vive ahí. No hay disco extra ni espacio sin particionar.
- Las cuotas de proyecto se activan **una sola vez** con `rootflags=pquota` y un reinicio. Si la
  VM se reinició después, el parámetro queda en grub y sigue activo.
- El home de `student` tiene permisos 700; no afecta este ejercicio porque todo pasa en `/srv`.

---

## Paso 0 — Preparación (antes de la presentación)

Una sola vez, activar las cuotas de proyecto en la raíz:

```bash
sudo grubby --update-kernel=ALL --args="rootflags=pquota" && sudo reboot
```

Después del reinicio, confirmar:

```bash
findmnt -no OPTIONS /          # tiene que incluir: prjquota
```

Preparar el departamento y dejar limpio lo del ejercicio:

```bash
cd ~/tp_sistemasoperativos && git pull
sudo src/demo/simular_depto.sh finanzas
sudo src/revocar.sh --depto finanzas --si 2>/dev/null; sudo src/demo/simular_depto.sh finanzas
ls /srv                        # tiene que salir vacío (o sin finanzas)
```

Ensayar la secuencia completa una vez. Es la primera vez que el script corre en Linux.

---

## La demo

### 1. Situación (30 segundos, sin tipear)

*El servidor de PagoSur es el repositorio de archivos de la empresa. Cada departamento tiene su
carpeta. Si Finanzas guarda sin control, llena el disco y se queda sin espacio el sistema entero,
incluidos los otros departamentos. El objetivo: la carpeta de Finanzas no puede pasar de 256 MB,
y si lo intenta, falla esa escritura y nada más.*

### 2. Dónde vive la carpeta (1 minuto)

```bash
lsblk
findmnt -no SOURCE,FSTYPE,OPTIONS /
```

*Un solo disco, cuatro particiones. La raíz es vda4, XFS. Ahí va a vivir /srv/finanzas. Fíjense
en las opciones de montaje: prjquota. Eso le dice al sistema de archivos que lleve la contabilidad
de cuotas por proyecto. Sin esa opción no hay cuota posible, y como la raíz se monta al arrancar,
se activa con un parámetro del kernel. Es un ejemplo de que las opciones de montaje se fijan al
montar.*

### 3. El alta (1 minuto)

```bash
sudo src/modulos/04_almacenamiento_simple.sh finanzas 256M
```

*El script hace tres cosas. Chequea que estemos en XFS con cuotas activas. Crea la carpeta con
dueño root, grupo finanzas y permisos 2770. Y le aplica la cuota: la marca como proyecto
finanzas y le pone un tope duro de 256 MB. Al final muestra la tabla de cuotas.*

```bash
ls -ld /srv/finanzas
```

*drwxrws---: el departamento entra, el resto no. La "s" es el SGID: todo lo que se cree adentro
queda del grupo finanzas, sin importar quién lo creó.*

### 4. Cómo sabe el kernel a quién cobrarle (1 minuto)

```bash
cat /etc/projects /etc/projid
sudo xfs_quota -x -c "report -p -h" /
```

*Estos dos archivos son la agenda de la herramienta: el proyecto 1003 es /srv/finanzas y se llama
finanzas. El kernel no los lee. Lo que el kernel sabe está en el nodo-i: cuando marcamos la
carpeta, se le grabó el número de proyecto y una bandera de herencia. Cada archivo nuevo nace
con ese número en su propio nodo-i. Así, cuando un archivo pide un bloque, el kernel mira el
nodo-i, ve "proyecto 1003", suma el bloque a esa cuenta y la compara con el límite. El reporte
muestra la tabla: usado cero, límite duro 256M.*

### 5. La cuota en acción (1,5 minutos, el núcleo)

Terminal 1:

```bash
sudo su - lperez -c "dd if=/dev/zero of=/srv/finanzas/relleno bs=1M count=400"
```

*Un usuario de Finanzas intenta escribir 400 MB. Corta en 256 con "Disk quota exceeded". No es
"disco lleno": es cuota excedida.*

Terminal 2:

```bash
sudo xfs_quota -x -c "report -p -h" /
df -h /
```

*El reporte dice usado 256, igual al límite. Y df muestra que a la partición le sobran gigas. La
unidad lo describe así: cada vez que se agrega un bloque a un archivo se incrementa la cuenta del
propietario y se verifica con los límites; el duro no se puede exceder, y el intento produce un
error. Eso es exactamente lo que acabamos de ver.*

Opcional, la llamada al sistema que falla:

```bash
sudo strace -f -e trace=write -o /tmp/dd.log su - lperez -c "dd if=/dev/zero of=/srv/finanzas/r2 bs=1M count=5"; grep -m1 EDQUOT /tmp/dd.log
```

*El programa hace write, el kernel devuelve -1 con EDQUOT. dd no sabe que hay cuotas: hizo su
llamada normal y el kernel dijo que no. Igual que en el ejercicio 3 con la memoria.*

### 6. Agrandar a demanda (30 segundos)

*Finanzas pide más espacio. Es cambiar un número en la tabla de cuotas, sin tocar nada más:*

```bash
sudo xfs_quota -x -c "limit -p bhard=512M finanzas" /
sudo xfs_quota -x -c "report -p -h" /
```

### 7. Cierre (30 segundos)

```bash
tail -5 logs/asignador.log
```

*Todo auditado. En el flujo normal este módulo lo llama asignar.sh al dar de alta el
departamento, y revocar.sh lo deshace: quita la cuota y borra la carpeta.*

*Resumen: la carpeta vive en la partición raíz, XFS montada con cuotas de proyecto. El número de
proyecto está en el nodo-i de cada archivo. En cada bloque que se pide, el kernel suma y compara
con el límite duro. Al pasarlo, el write falla. El usuario se entera, el resto del servidor no.*

---

## Preguntas probables y respuestas

**¿Por qué cuota de proyecto y no de usuario, que es la que describe la unidad?**
Porque el requisito es por carpeta: "Finanzas no pasa de 256 MB" sin importar cuál de los cuatro
usuarios escribe. Una cuota por usuario daría 256 a cada uno, 1 GB al departamento. El mecanismo
del kernel es el mismo que describe la unidad (tabla de cuotas, verificación en cada bloque, error
al pasar el límite duro); solo cambia a quién se le cobra: al proyecto en vez de al propietario.

**¿Qué diferencia hay entre límite duro y suave?**
El suave se puede exceder un tiempo de gracia, con aviso. El duro no: la escritura falla. Usamos
solo el duro porque queremos un tope, no una advertencia.

**¿Dónde guarda el kernel a qué proyecto pertenece un archivo?**
En el nodo-i, como un atributo más junto al dueño, los permisos y las direcciones de los bloques.
La carpeta tiene además una bandera de herencia para que los archivos nuevos nazcan con el mismo
número.

**¿Por qué hubo que reiniciar?**
Porque en XFS la contabilidad de cuotas se activa con una opción de montaje y no se puede prender
en caliente. La raíz se monta al arrancar, así que la opción se pasa por el kernel con
`rootflags=pquota`. Es un caso concreto de "las opciones se fijan en el montaje".

**¿Qué es un nodo-i y guarda el nombre del archivo?**
La estructura con los metadatos del archivo: permisos, dueño, tamaño, fechas, direcciones de los
bloques y, acá, el proyecto. El nombre no: está en el directorio, que asocia nombres con números de
nodo-i. `ls -i` muestra el número.

**¿Se puede quedar un disco sin lugar teniendo espacio libre?**
Sí, si se acaban los nodos-i. Se ve con `df -i`. La cuota de XFS también puede limitar la cantidad
de nodos-i (`ihard`), no solo los bloques.

**¿Qué pasa si se llena la partición raíz entera?**
Las cuotas evitan que un departamento lo haga solo, pero si todos juntos llenan el disco, el
sistema se queda sin espacio. Por eso una versión más robusta pondría los departamentos en un
volumen separado. Lo dejamos fuera a propósito: la unidad no pide LVM ni crear particiones, y la VM
del laboratorio no permite agregar discos.

**¿Qué es el journaling y qué tiene que ver acá?**
XFS anota en una bitácora lo que va a hacer antes de hacerlo; tras un corte, al arrancar completa o
descarta lo pendiente. La contabilidad de cuotas pasa por ese mismo journal, así que después de un
apagón los contadores quedan consistentes. Se ve la sección `log` con `xfs_info /`.

**¿Por qué el límite se aplica al escribir y no al abrir el archivo?**
Porque lo que se limita son bloques, y los bloques se asignan cuando se escribe. Abrir no consume
espacio. La unidad lo dice: la verificación ocurre "cada vez que se agrega un bloque a un archivo".

**¿Qué significa el 2 en `chmod 2770`?**
El bit SGID en un directorio: lo que se cree adentro hereda el grupo del directorio en vez del
grupo de quien lo creó. Así los archivos quedan compartidos por el departamento sin intervención.

---

## Si algo falla en vivo

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El script dice que `/` no está montado con cuotas | Falta `rootflags=pquota` o no se reinició | Mostrar `findmnt -no OPTIONS /`; no se puede arreglar sin reiniciar: explicar y pasar al paso 4 con capturas del ensayo |
| `dd` escribe los 400 MB sin cortar | Lo mismo: cuota no activa, o la carpeta no quedó marcada | `sudo xfs_quota -x -c "report -p -h" /`; si no aparece finanzas, repetir el script |
| El script dice que el grupo no existe | No corrió `simular_depto.sh` | `sudo src/demo/simular_depto.sh finanzas` |
| `xfs_quota: cannot set limits: Function not implemented` | Montado sin `prjquota` | Igual que la primera fila |
| `Permission denied` al escribir como `lperez` | La carpeta quedó con otro grupo | `ls -ld /srv/finanzas`; `sudo chown root:finanzas /srv/finanzas` |

---

## Después de la presentación: dejar la VM como estaba

```bash
sudo src/revocar.sh --depto finanzas --si
```

Quita la cuota, borra `/srv/finanzas` con sus datos, y elimina usuarios y grupo. El parámetro
`rootflags=pquota` queda en grub; no molesta y evita el reinicio la próxima vez. Para sacarlo:

```bash
sudo grubby --update-kernel=ALL --remove-args="rootflags=pquota"
```
