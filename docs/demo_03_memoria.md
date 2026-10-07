# Guion de presentación — Ejercicio 3: Memoria

Presentación en vivo de `03_memoria.sh` ante el profesor. Dura entre 6 y 8 minutos.
Todo se corre desde la raíz del repo en la VM (`~/tp_sistemasoperativos`), con dos terminales.
Lo que está en cursiva es lo que se dice. Lo que está en bloques de código es lo que se tipea.

Datos de la VM que condicionan el guion:

- `pam_limits` ya está activo en `/etc/pam.d/system-auth`. No se toca PAM.
- El home de `student` tiene permisos 700: `lperez` no puede ejecutar nada que esté ahí.
  Por eso el binario se instala en `/usr/local/bin`.
- No hay swap y hay 5,5 GB de RAM. En el contraste como root, cortar con Ctrl+C
  cerca de los 3 GB; si no, el OOM killer mata el proceso sin que se vea nada.

---

## Paso 0 — Preparación (antes de la presentación, una sola vez)

```bash
cd ~/tp_sistemasoperativos
git pull
make clean && make
sudo install -m 755 bin/03_carga_ram /usr/local/bin/
sudo src/demo/simular_depto.sh finanzas
sudo rm -f /etc/security/limits.d/depto-finanzas-memoria.conf
```

La última línea garantiza que la demo arranca sin límite (por si quedó de un ensayo).

Comprobación rápida:

```bash
getent group finanzas
which 03_carga_ram
sudo su - lperez -c 'ulimit -v'        # tiene que decir: unlimited
```

Abrir dos terminales en la raíz del repo. Terminal 1 para la carga, terminal 2 para mirar.

---

## 1. Situación (30 segundos, sin tipear nada)

*El servidor de PagoSur es compartido por varios departamentos. Un día un analista de Finanzas
deja corriendo un programa con un bug que pide memoria sin parar y se va a su casa. El proceso
se come toda la RAM, el servidor empieza a swapear, y cuando se agota todo, el kernel activa el
OOM killer, que mata un proceso para liberar memoria. No necesariamente el culpable: puede ser
la base de datos de otro departamento.*

*El objetivo del ejercicio es que un proceso de un usuario de un departamento no pueda pedir
más de 1 GB de memoria. Si lo intenta, falla ese proceso y solo ese. El resto del servidor no se
entera.*

## 2. Mostrar el problema (1 minuto)

*Primero, cómo está hoy. Pregunto cuánta memoria puede pedir un usuario del departamento:*

```bash
sudo su - lperez -c 'ulimit -v'
```

*Dice "unlimited". Ahora corro un programa que simula ese bug: pide 10 MB cada 200 milisegundos
y nunca los devuelve. Lo lanzo como root, que tampoco tiene límite.*

Terminal 1:

```bash
sudo /usr/local/bin/03_carga_ram
```

Terminal 2:

```bash
free -h
```

*Fíjense cómo sube "used" y baja "available". Esta VM no tiene swap, así que esto termina con
el OOM killer. Lo corto antes.*

Ctrl+C alrededor de los 3000 MB.

*Este es el escenario que hay que evitar.*

## 3. La solución (1 minuto)

*La solución es una regla de una línea, aplicada al grupo del departamento. El script la escribe
y la verifica:*

```bash
sudo src/modulos/03_memoria.sh finanzas 1024
```

```bash
cat /etc/security/limits.d/depto-finanzas-memoria.conf
```

*La línea dice: arroba finanzas, guion, "as", 1048576. El arroba significa "grupo". "as" es
address space, el espacio de direcciones, o sea la memoria virtual que un proceso puede tener.
El guion significa que es límite blando y duro a la vez, así el usuario no se lo puede subir.
El número está en kilobytes: 1 GB.*

*Importante: este archivo es solo texto. No hace nada por sí mismo. Quien lo aplica es PAM.*

## 4. Cómo se aplica: PAM y herencia (1,5 minutos, el núcleo de la defensa)

*PAM es la capa que gestiona el login en Linux. Uno de sus módulos, pam_limits, lee este archivo
cada vez que un usuario entra al sistema, busca las líneas que coinciden con su usuario o sus
grupos, y le fija los límites a la shell con la syscall setrlimit. Lo muestro:*

```bash
sudo su - lperez -c 'ulimit -v'
```

*Ahora dice 1048576. Y para demostrar que es PAM y no el archivo, hago lo mismo sin el guion:*

```bash
sudo su lperez -c 'ulimit -v'
```

*Sin guion sigue en "unlimited". Mismo usuario, mismo archivo. La diferencia es que "su -" es
un login completo y pasa por pam_limits; "su" sin guion solo cambia de usuario.*

*Y lo segundo: los límites se heredan. Cuando un proceso crea otro con fork, el kernel copia su
tabla de límites. Entonces todo lo que lperez lance desde su shell nace con el 1 GB. El programa
no sabe nada del límite y no lo puede evitar, porque un proceso puede bajar su límite duro pero
nunca subirlo.*

## 5. La carga, ahora limitada (1,5 minutos)

*El mismo programa de antes, pero lanzado como lperez:*

Terminal 1:

```bash
sudo su - lperez -c 03_carga_ram
```

Terminal 2, mientras corre:

```bash
pmap $(pgrep 03_carga_ram) | tail -1
```

```bash
free -h
```

*pmap muestra el espacio de direcciones del proceso, que va creciendo hacia 1 GB. free casi no
se mueve.*

Cuando corta:

*Cerca de los 1000 MB, el programa imprime "malloc: Cannot allocate memory" y termina solo.
Lo que pasó es que malloc le pidió al kernel 10 MB más con mmap, el kernel sumó lo que el
proceso ya tenía, vio que superaba su límite y rechazó el pedido. malloc devolvió NULL, el
programa lo detectó y salió. Nadie lo mató: se enteró y se fue solo.*

*No llega a 1024 exactos porque la libc, la pila y el ejecutable ya ocupan unos 20 MB del
espacio de direcciones antes de la primera reserva.*

## 6. Cierre (30 segundos)

```bash
tail -5 logs/asignador.log
```

*Todo queda auditado: cuándo se escribió la regla, para qué grupo, con qué valor, y que se
verificó con un login real. En la demo lo corrí a mano, pero en el flujo normal este módulo lo
llama asignar.sh al dar de alta un departamento, después de crear el grupo y los usuarios.*

*Resumen: el problema era que un proceso podía tumbar el servidor. La solución es una regla de
una línea que PAM aplica en el login y que el kernel hace cumplir en cada pedido de memoria.
Falla el proceso que se pasa, y solo ese.*

---

## Preguntas probables y respuestas

**¿Qué diferencia hay entre memoria virtual y memoria física? ¿Qué estás limitando?**
Limito la virtual, el espacio de direcciones. Es lo que el proceso tiene derecho a usar, no lo
que ocupa en RAM. Cuando malloc pide 10 MB, el kernel solo anota que ese rango es válido; la RAM
física se asigna página por página, de 4 KB, recién cuando el proceso escribe en ella (eso es
demand paging, y cada primera escritura dispara un page fault). Por eso el programa de carga
hace memset sobre cada bloque: para que la memoria se asigne de verdad y se vea en free.

**¿Por qué limitar la virtual y no la física (RSS)?**
Porque el límite de virtual se puede chequear en el momento del pedido: el kernel sabe cuánto
tiene el proceso y rechaza el mmap con ENOMEM, y malloc devuelve NULL. El proceso se entera y
puede reaccionar. Un límite de RSS, como el de cgroups, solo se puede hacer cumplir cuando la
memoria ya se tocó, y la única salida es matar el proceso con SIGKILL. Para una política que
busca que el proceso falle de forma controlada, el límite de espacio de direcciones es el
adecuado. La contra es que es más conservador: cuenta memoria pedida y no usada, y las
bibliotecas compartidas.

**¿Por qué no usaron cgroups?**
Porque no están en el programa de la materia y porque limits.conf resuelve el problema con
las herramientas de la unidad: rlimits, syscalls, PAM. cgroups sería la opción en un servidor
moderno con systemd, pero exige otra capa de conceptos.

**¿Qué pasa con un proceso que ya estaba corriendo cuando se escribió la regla?**
Nada. La regla se aplica en el login. Las sesiones abiertas conservan sus límites viejos hasta
que el usuario vuelva a entrar. Por eso el script avisa que no toca a los usuarios ya logueados.

**¿Qué es soft y hard?**
El límite blando es el que está en vigor; el duro es el techo. Un proceso puede subir su
blando hasta el duro y puede bajar el duro, pero nunca subirlo, salvo root. Con el guion en
limits.conf se fijan los dos iguales, así el usuario no tiene margen.

**¿Qué pasa si no hay límite? ¿Por qué malloc no falla igual cuando se acaba la RAM?**
Por el overcommit de Linux: el kernel acepta pedidos de memoria virtual aunque no haya RAM
física para respaldarlos, apostando a que no se va a usar toda. Entonces malloc sigue
devolviendo punteros válidos, el proceso va tocando páginas, se llena la RAM, se llena el swap,
y cuando no queda nada actúa el OOM killer. Elige a quién matar con un puntaje que favorece a
los procesos grandes, pero no es garantía de que mate al culpable.

**¿Qué es el OOM killer?**
Out Of Memory killer. Es el mecanismo de último recurso del kernel: cuando no puede satisfacer
un page fault porque no hay memoria física ni swap, elige un proceso y le manda SIGKILL. Es lo
que el ejercicio evita que pase.

**¿Qué es la syscall que aplica el límite?**
setrlimit. Y getrlimit para leerlo. ulimit es solo un comando de la shell que llama a esas dos.
Se puede ver el límite instalado en un proceso con `cat /proc/<pid>/limits`.

**¿Por qué el programa de carga pone un 1 con memset y no un 0?**
Porque gcc reconoce el patrón malloc seguido de memset a cero y lo convierte en calloc. Y calloc
sobre memoria recién mapeada se saltea la escritura, porque el kernel ya entrega las páginas en
cero. Resultado: no se tocaría ninguna página y la memoria física nunca crecería. Con un 1 el
compilador no puede hacer esa optimización.

**¿Un usuario puede saltarse el límite?**
No desde su sesión: el límite duro no se puede subir sin ser root. Podría entrar sin pasar por
PAM si tuviera un servicio que no usa pam_limits, pero eso es un problema de configuración del
servicio, no del mecanismo.

**¿El límite es por proceso o por usuario?**
Por proceso. Un usuario con diez procesos de 900 MB cada uno pasa el límite diez veces sin que
ninguno falle. Para limitar al usuario entero habría que sumar, y eso es lo que hace cgroups.
En el informe se explica como una limitación conocida del diseño.

---

## Si algo falla en vivo

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `ulimit -v` sigue en `unlimited` después del paso 3 | Se usó `su` sin guion, o el archivo no se escribió | Repetir con `su -`; `cat` el archivo |
| `Permission denied` al lanzar `03_carga_ram` | El binario está en el home de `student` | Usar el de `/usr/local/bin` (paso 0) |
| `install: cannot stat 'bin/03_carga_ram'` | No se compiló | `make` (y `sudo dnf install -y gcc make` si falta) |
| El script dice "el grupo no existe" | No corrió `simular_depto.sh` | `sudo src/demo/simular_depto.sh finanzas` |
| Como root no para y la VM se pone lenta | Se pasó el Ctrl+C | Ctrl+C; si no responde, desde otra terminal `sudo pkill -KILL 03_carga_ram` |

---

## Después de la presentación: dejar la VM como estaba

```bash
sudo src/revocar.sh --depto finanzas --si
```

O a mano, solo lo del ejercicio 3:

```bash
sudo rm /etc/security/limits.d/depto-finanzas-memoria.conf
sudo src/demo/simular_depto.sh finanzas --borrar
```
