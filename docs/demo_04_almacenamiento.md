# Guion de presentación — Ejercicio 4: Almacenamiento

Cómo poner en marcha `04_almacenamiento.sh` en la VM Red Hat y cómo presentarlo al profesor.
Dura entre 7 y 9 minutos. El detalle técnico, la teoría y las preguntas completas están en
`docs/informe/04_almacenamiento.md`; esto es la hoja para tener al lado en la presentación.
Lo que está en cursiva es lo que se dice. Los bloques de código son lo que se tipea.

Datos de la VM que condicionan el guion:

- El script toca LVM y `/etc/fstab`. **Snapshot de la VM antes de la primera corrida.**
- El "disco" es un archivo disperso de 1,5 GB en `/var/discos/`. Hace falta que `/` tenga al menos
  1 GB libre de verdad, porque el `dd` de la demo lo va a llenar en parte.
- Un loop device no sobrevive a un reinicio. Si la VM se reinició entre el ensayo y la demo, volver
  a correr el script para cada departamento: reconecta el archivo, activa el VG y monta.
- El script nunca se ejecutó en Linux antes del ensayo. **Ensayar completo al menos una vez.**

---

## Parte A — Implementarlo en la VM (una sola vez)

### A1. Paquetes y espacio

```bash
cd ~/tp_sistemasoperativos && git pull
sudo dnf install -y lvm2 xfsprogs util-linux coreutils
df -h /
```

`df -h /` tiene que mostrar más de 1 GB en `Avail`. Si no, liberar espacio antes de seguir.

### A2. Snapshot

En VirtualBox: Máquina → Tomar instantánea. Nombre: `antes-ej4`. Si algo sale mal con LVM o
fstab, se vuelve acá en segundos.

### A3. Estado limpio

Confirmar que no quedó nada de un intento anterior:

```bash
sudo vgs 2>/dev/null; grep srv /etc/fstab; ls /var/discos 2>/dev/null; losetup -a
```

Todo tiene que salir vacío. Si hay restos, limpiar con la Parte D.

### A4. Primera corrida (el ensayo)

```bash
sudo src/demo/simular_depto.sh finanzas
sudo src/modulos/04_almacenamiento.sh finanzas 256M
```

Salida esperada en el log: disco creado, loop conectado, PV y VG creados, LV de 384 MB con XFS,
línea en fstab, montado, cuota aplicada. Termina con el `df -h /srv/finanzas`.

Verificar las tres cosas que más fallan:

```bash
df -hT /srv/finanzas                                  # tipo xfs, ~315M de tamaño
mount | grep srv/finanzas                             # tiene que decir prjquota
sudo xfs_quota -x -c "report -p -h" /srv/finanzas     # finanzas con límite 256M
```

Si `mount` no muestra `prjquota`, la cuota no va a limitar nada: revisar la línea de fstab.

### A5. Probar la cuota y limpiar

```bash
sudo su - lperez -c "dd if=/dev/zero of=/srv/finanzas/relleno bs=1M count=400"
```

Tiene que cortar con `Disk quota exceeded`, no con `No space left on device`. Después, dejar
todo como estaba para que la demo arranque de cero (Parte D).

### Si algo falla en la implementación

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Falta 'pvcreate'` o `'xfs_quota'` | Paquetes no instalados | `sudo dnf install -y lvm2 xfsprogs` |
| `mkfs.xfs` se queja del tamaño mínimo | RHEL 10 exige 300 MB; con 384 entra, pero si se pidió menos de 200M no | Usar 256M o más como tamaño |
| `mount: /srv/finanzas: can't find in /etc/fstab` | La línea no se escribió | Revisar `grep srv /etc/fstab` y volver a correr el script |
| `dd` corta con `No space left on device` | Se montó sin `pquota` o el LV quedó del tamaño de la cuota | `mount \| grep srv`; revisar la línea de fstab; si hace falta, revocar y rehacer |
| `xfs_quota: cannot set limits: Function not implemented` | Montado sin `prjquota` | Mismo que arriba |
| Después de reiniciar, `/srv/finanzas` no está montado | El loop desapareció (esperado) | `sudo src/modulos/04_almacenamiento.sh finanzas 256M` reconecta y monta |
| El script dice "el grupo no existe" | No corrió `simular_depto.sh` | `sudo src/demo/simular_depto.sh finanzas` |

---

## Parte B — Preparación el día de la demo

```bash
cd ~/tp_sistemasoperativos
sudo src/demo/simular_depto.sh finanzas
sudo vgs 2>/dev/null; grep srv /etc/fstab      # tiene que salir vacío: arrancamos de cero
```

Dos terminales abiertas en la raíz del repo.

---

## Parte C — La demo

### 1. Situación (30 segundos, sin tipear)

*El servidor de PagoSur es el repositorio de archivos de la empresa. Cada departamento necesita su
carpeta, con un tope de espacio que no pueda superar aunque sus usuarios llenen el disco, y que se
pueda agrandar cuando lo pidan sin apagar nada. Finanzas recibe 256 MB.*

### 2. Estado inicial (30 segundos)

```bash
lsblk
df -h
```

*Hoy hay un solo disco. No hay nada de Finanzas. Lo que voy a armar es: un volumen lógico con LVM,
formateado en XFS, montado en /srv/finanzas de forma persistente, con una cuota de proyecto de
256 MB sobre esa carpeta.*

### 3. El alta (1 minuto)

```bash
sudo src/modulos/04_almacenamiento.sh finanzas 256M
```

Mientras sale el log, ir leyendo:

*Primero crea el disco: en el laboratorio no tenemos un disco extra, así que es un archivo de 1,5 GB
que losetup presenta como un dispositivo de bloques. Es un archivo disperso: declara 1,5 GB pero solo
ocupa lo que se escribe. Después lo marca como volumen físico y crea el grupo de volúmenes, que es
el pozo de espacio común a todos los departamentos. De ese pozo saca el volumen lógico de Finanzas,
lo formatea con XFS, lo agrega a fstab y lo monta. Por último aplica la cuota.*

### 4. Las tres capas y el disco disperso (1,5 minutos)

```bash
lsblk
sudo pvs; sudo vgs; sudo lvs
```

*Acá están las tres capas de LVM. El PV es loop0, el disco. El VG es vg_pagosur, el pozo: 1,5 GB.
El LV es lv_finanzas, 384 MB sacados del pozo. Esa es la gracia de LVM frente a las particiones:
el LV se agranda en caliente y el VG puede sumar discos.*

```bash
df -hT /srv/finanzas
grep srv /etc/fstab
ls -ld /srv/finanzas
ls -ls /var/discos/pagosur.img
```

*df muestra que es XFS y que está montado. La línea de fstab tiene dos opciones importantes:
pquota, que activa las cuotas de proyecto, sin eso xfs_quota no limita nada; y nofail, para que si
el loop no está al arrancar la VM no entre en modo de emergencia. En ls -ld, la "s" en el grupo es
el SGID: todo lo que se cree adentro queda del grupo finanzas. Y en ls -ls se ve el archivo
disperso: declara 1,5 GB, ocupa unos pocos MB.*

### 5. La cuota en acción (1,5 minutos, el núcleo)

```bash
sudo xfs_quota -x -c "report -p -h" /srv/finanzas
```

*Proyecto finanzas, usado cero, límite duro 256 MB. Ahora un usuario de Finanzas intenta escribir
400 MB:*

```bash
sudo su - lperez -c "dd if=/dev/zero of=/srv/finanzas/relleno bs=1M count=400"
```

*Corta en 256 con "Disk quota exceeded". Fíjense qué error es: cuota excedida, no disco lleno.*

```bash
sudo xfs_quota -x -c "report -p -h" /srv/finanzas
df -h /srv/finanzas
```

*El reporte dice usado 256, igual al límite. Y df muestra que al volumen todavía le quedan unos
40 MB. Por eso el LV es un 50 % más grande que la cuota (lo medimos: con 25 % no alcanzaba): XFS usa parte del volumen para su journal
y sus metadatos; si midieran lo mismo, el disco se llenaría antes y el que frenaría sería el disco,
no la cuota. Elegimos cuota de proyecto y no de usuario porque limita la carpeta entera, sin
importar quién escriba: es el único límite que de verdad es por departamento.*

### 6. Agrandar a demanda (1 minuto)

*Finanzas pide más espacio. Sin desmontar, sin cortar a nadie:*

```bash
sudo lvextend -r -L +64M /dev/vg_pagosur/lv_finanzas
sudo xfs_quota -x -c "limit -p bhard=320M finanzas" /srv/finanzas
df -h /srv/finanzas
sudo xfs_quota -x -c "report -p -h" /srv/finanzas
```

*lvextend saca 64 MB más del pozo y, con -r, agranda también el XFS de adentro. Después subimos la
cuota. Esto en una partición clásica no se puede hacer en caliente. Un XFS se puede agrandar pero
no achicar: si Finanzas pide menos, solo se baja la cuota.*

### 7. El montaje es persistente (30 segundos)

```bash
sudo umount /srv/finanzas
df -h | grep srv
sudo mount -a
df -h | grep srv
```

*Lo desmonto, desaparece. mount -a monta todo lo que dice fstab, y vuelve. Es lo mismo que pasa en
cada arranque. Se prueba con mount -a y no reiniciando porque un error en fstab puede dejar la VM
sin arrancar; así lo vemos mientras todavía se puede corregir.*

### 8. Opcional si sobra tiempo: el pozo se agota (1 minuto)

```bash
sudo rm /srv/finanzas/relleno
for d in marketing rrhh legales; do sudo groupadd "$d"; sudo src/modulos/04_almacenamiento.sh "$d" 256M; done
sudo vgs
```

*Cada departamento se lleva 384 MB de un pozo de 1,5 GB. Entran tres; el cuarto falla con un mensaje
claro en el log antes de tocar nada. La solución real sería agregar otro disco al VG con vgextend.*
(Si en el paso 6 se agrandó Finanzas, el que falla puede ser el tercero.)

### 9. Cierre (30 segundos)

```bash
tail -8 logs/asignador.log
```

*Todo auditado. En el flujo normal este módulo lo llama asignar.sh al dar de alta el departamento,
después de crear el grupo y antes de la regla de memoria. Y revocar.sh lo deshace en orden inverso:
desmonta, saca la línea de fstab, borra el LV y la cuota.*

---

## Las cinco preguntas que más probablemente hagan

Las demás están en la sección 6 del informe.

**¿Por qué LVM y no una partición?** Un LV se agranda en caliente con `lvextend`, el VG puede sumar
discos con `vgextend`, y un LV puede ocupar más de un disco. Una partición queda limitada por las
que tiene al lado y hay que desmontar para tocarla.

**¿Qué diferencia hay entre cuota de usuario, de grupo y de proyecto?** La de usuario limita lo que
escribe cada persona en todo el sistema de archivos; la de grupo, a los miembros de un grupo; la de
proyecto, lo que hay dentro de una carpeta sin importar quién lo escribió. Para "la carpeta de
Finanzas no pasa de 256 MB" sirve la de proyecto.

**¿Qué es el journaling?** Un registro donde XFS anota los cambios de metadatos antes de hacerlos.
Tras un corte de luz repasa el journal y deja el sistema de archivos consistente sin revisar todo el
disco. Por eso el LV es más grande que la cuota: ese journal ocupa lugar.

**¿Qué es un inodo y guarda el nombre?** La estructura con los metadatos de un archivo: permisos,
dueño, tamaño, fechas y dónde están los datos. El nombre no: está en el directorio, que asocia
nombres con números de inodo. Un disco se puede quedar sin inodos con espacio libre (`df -i`).

**¿Qué pasa si se reinicia la VM?** El loop device no se reconecta solo, por eso fstab lleva
`nofail` y la VM arranca igual. Volver a correr el script reconecta, activa el VG y monta. En
producción el PV sería un disco real y no haría falta.

---

## Si algo falla en vivo

| Síntoma | Qué hacer sin perder la demo |
|---|---|
| El script dice que el grupo no existe | `sudo src/demo/simular_depto.sh finanzas` y repetir |
| `dd` corta con `No space left on device` | Decir que el LV quedó sin margen y mostrar igual el reporte de cuota; revisar `mount \| grep srv` después |
| `lvextend` dice que no hay espacio en el VG | Quedaron LV de otro ensayo: `sudo lvs`; revocar los sobrantes |
| `/srv/finanzas` no está montado al empezar | La VM se reinició: correr el script de nuevo, reconecta en segundos |
| `mount -a` da error | Hay una línea rota en fstab: `cat /etc/fstab`, corregir con `sudo vi`, repetir |

---

## Parte D — Dejar la VM como estaba

```bash
for d in finanzas marketing rrhh legales; do sudo src/revocar.sh --depto "$d" --si 2>/dev/null; done
```

`revocar.sh` borra el LV, la línea de fstab, la cuota y la carpeta de cada departamento. El VG y el
disco simulado son compartidos; para empezar de cero del todo:

```bash
sudo vgremove -y vg_pagosur
sudo pvremove -y "$(losetup -j /var/discos/pagosur.img | cut -d: -f1)"
sudo losetup -d "$(losetup -j /var/discos/pagosur.img | cut -d: -f1)"
sudo rm /var/discos/pagosur.img
```

Verificar con `sudo vgs; losetup -a; grep srv /etc/fstab`: todo vacío.
