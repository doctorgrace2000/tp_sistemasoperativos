# Ejercicio 4 – Almacenamiento

**Unidad:** Sistemas de archivos y almacenamiento (LVM, XFS, inodos, journaling, montaje, cuotas)
**Código:** [`src/modulos/04_almacenamiento.sh`](../../src/modulos/04_almacenamiento.sh) (shell script)
**Herramientas Red Hat:** `truncate`, `losetup`, `pvcreate`, `vgcreate`, `lvcreate`, `mkfs.xfs`,
`/etc/fstab`, `mount`, `xfs_quota`, `lvextend`, `lsblk`, `df`

---

## 1. Situación

> Finanzas se incorpora a PagoSur y necesita una carpeta compartida en el servidor. El año pasado,
> un analista de otra área guardó backups de 40 GB en su carpeta, llenó el disco y nadie más pudo
> guardar nada durante una mañana entera.

El administrador quiere que cada departamento tenga su propio espacio con un **tope que no se pueda
superar** (256 MB en la demo), que no afecte al resto si se llena, y que se pueda **agrandar** cuando
el departamento lo pida, sin reinstalar nada ni mover datos.

## 2. Solución

### Uso

```bash
sudo ./src/modulos/04_almacenamiento.sh <depto> <tamaño>
sudo ./src/modulos/04_almacenamiento.sh finanzas 256M
```

`asignar.sh` lo llama con `256M` para todo departamento nuevo.

### Qué arma el script

```
 /var/discos/pagosur.img   (archivo disperso de 1 GB: el "disco")
          │ losetup
          ▼
     /dev/loop0            ── PV  (pvcreate: el disco queda marcado para LVM)
          │
          ▼
     vg_pagosur  (~1 GB)   ── VG  (vgcreate: un "pozo" de espacio para repartir)
      ├── lv_finanzas  320 MB ── LV ── XFS ── montado en /srv/finanzas  (cuota 256 MB)
      ├── lv_marketing 320 MB ── LV ── XFS ── montado en /srv/marketing (cuota 256 MB)
      └── libre
```

Paso a paso:

1. **Disco simulado (una sola vez).** `truncate -s 1G` crea un archivo *disperso*: declara 1 GB pero
   ocupa en disco solo lo que se escribe. `losetup` lo presenta como un dispositivo de bloques
   (`/dev/loop0`), igual que si fuera un disco real. Así la demo no depende de que la VM tenga discos
   extra ni se arriesga ningún disco real.
2. **LVM (una sola vez).** `pvcreate` lo convierte en *volumen físico* y `vgcreate` arma el *grupo de
   volúmenes* `vg_pagosur`. Si el VG ya existe (porque ya hay otros departamentos), se reutiliza.
3. **Volumen del departamento.** Antes verifica que en el VG haya lugar (`vgs -o vg_free`). Si no hay,
   lo registra en el log y termina. Si hay, `lvcreate` crea `lv_<depto>` y `mkfs.xfs` le da formato.
4. **Montaje persistente.** Agrega una línea a `/etc/fstab` y monta con `mount /srv/<depto>`, que lee
   esa línea, así se comprueba en el momento que quedó bien escrita.
5. **Permisos.** `chown root:<depto>` y `chmod 2770`: solo el departamento entra. El `2` (SGID) hace que
   todo archivo creado adentro quede del grupo del departamento.
6. **Cuota de proyecto.** Registra el proyecto en `/etc/projects` y `/etc/projid` (con el GID del grupo
   como número) y con `xfs_quota` le pone un tope duro (`bhard`) igual al tamaño pedido.

Cada paso se saltea si ya estaba hecho, así el script se puede volver a correr sin romper nada.

### Decisiones que hay que poder explicar

| Decisión | Por qué |
|---|---|
| Archivo + `losetup` en vez de un disco | No depende de la VM, no hay riesgo de borrar un disco real, y el archivo disperso no gasta espacio de más. |
| LVM en vez de una partición | Un LV se agranda en caliente con `lvextend`; una partición está pegada a las que tiene al lado. |
| XFS | Es el sistema de archivos por defecto de RHEL, tiene journaling y cuotas de proyecto. |
| LV de 320 MB para una cuota de 256 MB | XFS usa parte del volumen para su journal y sus estructuras. Si el LV midiera lo mismo que la cuota, el disco se llenaría **antes** y el error sería "No space left on device": la cuota no estaría haciendo nada. Con un 25 % de margen, lo que corta es la cuota ("Disk quota exceeded"). |
| Opción `pquota` en fstab | Sin ella, XFS no lleva la cuenta de los proyectos y `xfs_quota` no limita nada. En XFS no se puede activar después con un `remount`: tiene que estar desde el primer montaje. |
| Opción `nofail` en fstab | Un loop device no sobrevive a un reinicio. Sin `nofail`, la VM no arrancaría (entraría en modo de emergencia) por no encontrar el volumen. |
| Cuota de **proyecto** y no de usuario | Una cuota de usuario limita a cada persona. La de proyecto limita **la carpeta**, sin importar quién escriba: es un límite por departamento. |
| `chown`/`chmod` **después** de montar | Antes de montar, `/srv/finanzas` es una carpeta vacía del disco principal; los permisos se aplicarían a esa carpeta y no al volumen. |

## 3. Demostración en Red Hat

> **Antes de empezar, sacar un snapshot de la VM**: el script modifica LVM y `/etc/fstab`.
> Las capturas van en `docs/informe/capturas/` con el nombre indicado en cada paso.

### Paso 1 – Estado inicial

```bash
lsblk                       # discos y particiones: todavía no hay loop ni vg_pagosur
df -h                       # sistemas de archivos montados y su espacio
sudo ./src/demo/simular_depto.sh finanzas      # grupo y usuarios (clave: pagosur)
```
📸 `04_01_estado_inicial.png`

### Paso 2 – Alta del almacenamiento de Finanzas

```bash
sudo ./src/modulos/04_almacenamiento.sh finanzas 256M
```
Salida esperada (resumida):
```
... ALMACENAMIENTO: creado disco simulado /var/discos/pagosur.img (1G, disperso)
... ALMACENAMIENTO: /var/discos/pagosur.img conectado como /dev/loop0
... ALMACENAMIENTO: creado PV /dev/loop0 y VG vg_pagosur
... ALMACENAMIENTO: creado /dev/vg_pagosur/lv_finanzas de 320 MB con XFS
... ALMACENAMIENTO: agregado /srv/finanzas a /etc/fstab
... ALMACENAMIENTO: montado /dev/vg_pagosur/lv_finanzas en /srv/finanzas
... ALMACENAMIENTO: cuota de proyecto finanzas (id 1001) = 256M sobre /srv/finanzas
```
📸 `04_02_alta.png`

### Paso 3 – Ver lo que se creó

```bash
lsblk                                   # loop0 -> vg_pagosur-lv_finanzas montado en /srv/finanzas
sudo pvs; sudo vgs; sudo lvs            # las tres capas de LVM
df -hT /srv/finanzas                    # tipo xfs y tamaño
grep srv /etc/fstab                     # la línea persistente
ls -ld /srv/finanzas                    # drwxrws--- root finanzas  (la "s" es el SGID)
ls -ls /var/discos/pagosur.img          # 1 GB declarado, casi nada ocupado (disperso)
```
📸 `04_03_lvm_fstab.png`

### Paso 4 – La cuota en acción

```bash
sudo xfs_quota -x -c "report -p -h" /srv/finanzas       # finanzas: usado 0, límite 256M
sudo su - lperez -c "dd if=/dev/zero of=/srv/finanzas/relleno bs=1M count=400"
```
`dd` intenta escribir 400 MB y se corta cerca de los 256 MB:
```
dd: error writing '/srv/finanzas/relleno': Disk quota exceeded
```
```bash
sudo xfs_quota -x -c "report -p -h" /srv/finanzas       # usado = 256M = límite
df -h /srv/finanzas                                     # el volumen todavía tiene lugar
```
Lo que frenó a `lperez` fue la cuota, no el disco lleno. Y el resto del servidor no se enteró.
📸 `04_04_cuota.png`

### Paso 5 – Agrandar a demanda

Finanzas pide más espacio. Sin desmontar ni mover nada:
```bash
sudo lvextend -r -L +64M /dev/vg_pagosur/lv_finanzas    # -r agranda también el XFS (xfs_growfs)
sudo xfs_quota -x -c "limit -p bhard=320M finanzas" /srv/finanzas
df -h /srv/finanzas
sudo xfs_quota -x -c "report -p -h" /srv/finanzas       # límite nuevo: 320M
```
Ahora `lperez` puede escribir 64 MB más. Un XFS se puede **agrandar** en caliente pero **no achicar**.
📸 `04_05_extender.png`

### Paso 6 – El VG se agota

Cada departamento ocupa 320 MB de un VG de ~1 GB: entran tres, el cuarto no.
```bash
sudo rm /srv/finanzas/relleno
for d in marketing rrhh legales; do
    sudo groupadd "$d"
    sudo ./src/modulos/04_almacenamiento.sh "$d" 256M
done
sudo vgs                                                 # VFree casi en cero
```
El último falla con:
```
... ALMACENAMIENTO: ERROR no hay lugar para legales: hacen falta 320 MB y el VG vg_pagosur tiene ... MB libres
```
(Si en el paso 5 se agrandó finanzas, el que falla puede ser `rrhh`.) La solución real sería agregar
otro disco al VG con `vgextend`.
📸 `04_06_vg_lleno.png`

### Paso 7 – El montaje es persistente

```bash
sudo umount /srv/finanzas
df -h | grep srv            # finanzas ya no aparece
sudo mount -a               # monta todo lo que dice /etc/fstab
df -h | grep srv            # volvió
```
📸 `04_07_fstab.png`

> Después de **reiniciar** la VM, el loop device desaparece y los volúmenes no se montan (por eso
> `nofail`). Para recuperarlos alcanza con volver a correr el script: reconecta el archivo, activa el
> VG y monta, salteando todo lo que ya existe.

### Paso 8 – Limpieza

```bash
for d in finanzas marketing rrhh legales; do sudo ./src/revocar.sh --depto "$d" --si; done
# revocar.sh borra el LV, la línea de fstab, la cuota y la carpeta de cada depto.
# El VG y el disco simulado son compartidos; para empezar de cero del todo:
sudo vgremove -y vg_pagosur
sudo pvremove -y "$(losetup -j /var/discos/pagosur.img | cut -d: -f1)"
sudo losetup -d "$(losetup -j /var/discos/pagosur.img | cut -d: -f1)"
sudo rm /var/discos/pagosur.img
```

## 4. Apartado teórico

### Sistema de archivos

Un **sistema de archivos** es la forma en que el SO organiza los datos en un dispositivo de bloques:
qué bloques pertenecen a qué archivo, dónde está cada directorio, quién es el dueño, los permisos.
Un disco recién creado es solo una secuencia de bloques; `mkfs` escribe las estructuras que lo
convierten en un sistema de archivos. RHEL usa **XFS** por defecto; también existen ext4, Btrfs, vfat.

### Inodos

Cada archivo tiene un **inodo**: una estructura con sus **metadatos** (tipo, permisos, dueño, grupo,
tamaño, fechas, cantidad de enlaces y dónde están sus bloques de datos). El inodo **no guarda el
nombre**: el nombre está en el directorio, que es una tabla `nombre → número de inodo`. Por eso un
archivo puede tener varios nombres (enlaces duros) y por eso un sistema de archivos se puede quedar
sin inodos aunque tenga espacio. Se ven con `ls -i` y `stat archivo`; `df -i` muestra los inodos
libres.

### Journaling

Escribir un archivo implica varias escrituras (datos, inodo, directorio, mapa de bloques libres). Si
la máquina se apaga en el medio, el sistema de archivos queda inconsistente. Con **journaling**, antes
de modificar los metadatos se anota la operación en un registro (el *journal* o *log*); al arrancar
después de un corte, el SO repasa el journal y termina o descarta las operaciones a medias, en
segundos, sin revisar todo el disco. XFS hace journaling de metadatos; parte del volumen se reserva
para ese log (por eso el LV tiene que ser más grande que la cuota).

### LVM

LVM agrega una capa entre los discos y los sistemas de archivos:

| Capa | Qué es | Comando |
|---|---|---|
| **PV** (volumen físico) | Un disco o partición marcado para LVM | `pvcreate`, `pvs` |
| **VG** (grupo de volúmenes) | Uno o más PV juntos, como un pozo de espacio | `vgcreate`, `vgextend`, `vgs` |
| **LV** (volumen lógico) | Un pedazo del VG, que se usa como si fuera una partición | `lvcreate`, `lvextend`, `lvs` |

El espacio se reparte en bloques fijos llamados **extents** (4 MB por defecto). Ventajas frente a las
particiones: un LV se agranda sin desmontar, un VG puede sumar discos nuevos (`vgextend`) y un LV
puede ocupar varios discos.

### Montaje y `/etc/fstab`

En Linux hay un solo árbol de directorios que empieza en `/`. **Montar** es "colgar" un sistema de
archivos en una carpeta de ese árbol (el *punto de montaje*). `mount` lo hace hasta el próximo
reinicio; para que sea **persistente** se agrega a `/etc/fstab`, que se lee al arrancar:

```
/dev/vg_pagosur/lv_finanzas  /srv/finanzas  xfs  defaults,pquota,nofail  0 0
   dispositivo                punto          tipo  opciones                dump fsck
```

`mount -a` monta todo lo de fstab que no esté montado: sirve para probar el archivo sin reiniciar.
Un error en fstab puede impedir que la VM arranque; por eso se prueba siempre con `mount -a`.

### Cuotas de disco

Una cuota limita cuánto espacio (bloques) o cuántos archivos (inodos) se pueden usar. Tiene un
límite **blando** (*soft*: se puede pasar por un tiempo de gracia, con aviso) y uno **duro** (*hard*:
no se puede pasar; `write()` falla con el error `EDQUOT`, "Disk quota exceeded"). En XFS hay tres
tipos: de **usuario** (`uquota`), de **grupo** (`gquota`) y de **proyecto** (`pquota`). La de proyecto
se aplica a un árbol de directorios y es la que limita una carpeta compartida.

### Archivos dispersos y loop devices

Un **archivo disperso** (*sparse*) tiene "agujeros": rangos que nunca se escribieron y no ocupan
bloques reales (se leen como ceros). `ls -l` muestra el tamaño declarado y `ls -s` / `du` lo que
realmente ocupa. Un **loop device** (`/dev/loopN`) hace que un archivo se comporte como un disco de
bloques. Se usa para imágenes ISO, contenedores y pruebas como esta.

## 5. Limitaciones y posibles mejoras

- **El loop device no es persistente.** En producción el PV sería un disco real (`/dev/sdb`) y no habría
  que reconectar nada. Para dejarlo automático con el archivo se podría usar un servicio de `systemd`
  que corra `losetup` al arrancar.
- **Todos los departamentos comparten un solo "disco".** Si ese archivo se daña, se pierden todos. Lo
  real sería un VG con varios discos o RAID.
- **XFS no se achica.** Si un departamento pide menos espacio, solo se puede bajar la cuota, no el LV.
- **Tamaños de demo.** En RHEL 9 `mkfs.xfs` acepta volúmenes chicos, pero en versiones más nuevas
  (RHEL 10) el mínimo es 300 MB. Con 320 MB por departamento funciona en las dos.

## 6. Preguntas para la defensa

**¿Qué es un sistema de archivos y para qué sirve `mkfs`?**
La estructura que organiza los datos en un dispositivo de bloques (qué bloques son de qué archivo,
directorios, permisos). `mkfs` escribe esas estructuras en un dispositivo vacío; borra lo que hubiera.

**¿Qué es un inodo? ¿Guarda el nombre del archivo?**
La estructura con los metadatos de un archivo: permisos, dueño, tamaño, fechas y ubicación de los
datos. No guarda el nombre: el nombre está en el directorio, que asocia nombres con números de inodo.

**¿Se puede quedar un disco sin lugar teniendo espacio libre?**
Sí, si se acaban los inodos (muchos archivos muy chicos). Se ve con `df -i`.

**¿Qué es el journaling y qué problema resuelve?**
Un registro donde se anotan los cambios de metadatos antes de hacerlos. Después de un corte de luz,
el SO repasa el journal y deja el sistema de archivos consistente sin revisar todo el disco.

**¿Qué son PV, VG y LV?**
PV: un disco preparado para LVM. VG: uno o más PV juntos, un pozo de espacio. LV: un pedazo del VG
que se formatea y monta como si fuera una partición.

**¿Qué ventaja tiene LVM sobre las particiones?**
Un LV se agranda en caliente (`lvextend`), el VG puede sumar discos nuevos (`vgextend`) y un LV puede
ocupar más de un disco. Una partición queda limitada por las que tiene al lado.

**¿Qué hace `lvextend -r`?**
Agranda el LV y, con `-r`, también el sistema de archivos que tiene adentro (para XFS llama a
`xfs_growfs`). Sin `-r`, el LV crece pero el sistema de archivos sigue del tamaño anterior.

**¿Se puede achicar un XFS?**
No. Solo se puede agrandar. ext4 sí se puede achicar, pero desmontado.

**¿Qué es montar? ¿Qué diferencia hay entre `mount` y `/etc/fstab`?**
Conectar un sistema de archivos a una carpeta del árbol. `mount` dura hasta el reinicio; lo que está
en `/etc/fstab` se monta en cada arranque.

**¿Para qué sirven `pquota` y `nofail` en fstab?**
`pquota` activa las cuotas de proyecto (sin eso no limitan). `nofail` evita que la VM se quede en
modo de emergencia si el volumen no está disponible al arrancar.

**¿Por qué se prueba fstab con `mount -a` antes de reiniciar?**
Porque un error en fstab puede impedir que el sistema arranque. `mount -a` muestra el error en el
momento, cuando todavía se puede corregir.

**¿Qué diferencia hay entre cuota de usuario, de grupo y de proyecto?**
La de usuario limita lo que escribe cada persona en todo el sistema de archivos; la de grupo, lo de
todos los miembros de un grupo; la de proyecto, lo que hay dentro de una carpeta, sin importar quién
lo escribió. Para "la carpeta de Finanzas no puede pasar de 256 MB" sirve la de proyecto.

**¿Qué diferencia hay entre límite soft y hard?**
El soft se puede superar durante un tiempo de gracia, con aviso. El hard no se puede superar: la
escritura falla con "Disk quota exceeded".

**¿Por qué el LV es más grande que la cuota?**
Porque XFS reserva parte del volumen para su journal y metadatos. Si midieran lo mismo, el disco se
llenaría antes que la cuota y el que frenaría al usuario sería el disco lleno, no la cuota.

**¿Qué es un archivo disperso? ¿Cómo se ve la diferencia?**
Un archivo con "agujeros" que no ocupan bloques reales. `ls -l` muestra el tamaño declarado (1 GB) y
`ls -s` o `du -h` lo que ocupa de verdad.

**¿Qué es un loop device?**
Un dispositivo (`/dev/loopN`) que hace que un archivo se comporte como un disco. Se crea con `losetup`.

**¿Qué significan el `2` y la `s` en `drwxrws---`?**
Es el bit **SGID** en un directorio: todo lo que se cree adentro hereda el grupo del directorio
(`finanzas`) en vez del grupo de quien lo creó, así los archivos quedan compartidos por el departamento.
