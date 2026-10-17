#!/usr/bin/env bash
# =============================================================================
# 06_seguridad.sh — Ejercicio 6: Seguridad
#
# Situación: el servidor de PagoSur guarda datos financieros. Si un usuario de
# un departamento corre algo malicioso (o le roban la cuenta), ese programa
# puede usar el servidor para mandar correo directo (spam, phishing, fuga de
# datos) o para hablar con servicios en texto plano (FTP, Telnet) que exponen
# credenciales. El admin bloquea esos puertos de SALIDA para los usuarios del
# departamento; el resto del servidor (root, servicios) no se ve afectado.
#
# Cómo: primero el alta de usuarios del CSV (grupo primario = departamento).
# Después una tabla de nftables propia del departamento, con una cadena en el
# gancho "output" del kernel (netfilter): toda conexión TCP que salga de un
# proceso cuyo grupo sea el del depto hacia un puerto bloqueado se rechaza.
#
# Llamadas al sistema detrás:
#   groupadd/useradd      -> escriben /etc/group, /etc/passwd, /etc/shadow (write)
#   nft -f                -> netlink (socket AF_NETLINK) hacia netfilter: carga la tabla
#   el usuario: connect(2) -> el kernel evalúa la cadena output, la regla hace
#                             match por "meta skgid" (gid del socket) y responde
#                             con TCP RST: connect() devuelve -1, errno ECONNREFUSED
#
# Puertos bloqueados por defecto y por qué:
#   25, 465, 587  SMTP y submission: correo directo desde el servidor (spam/fuga)
#   21            FTP: credenciales en texto plano
#   23            Telnet: todo en texto plano
#
# La regla se aplica en caliente y NO sobrevive a un reinicio (igual criterio
# que el resto del TP: volver a correr el alta). No se usa nftables.service
# para no pisar las reglas de firewalld, que RHEL trae activo.
#
# Herramientas: groupadd, useradd, chpasswd, chage, nft, firewall-cmd, nc, strace
# Teoría:       confidencialidad e integridad, defensa en profundidad, mínimo
#               privilegio, firewalls (filtrado de paquetes), autenticación
#               con contraseñas, DAC (permisos) vs filtrado en el kernel.
#
# Uso: sudo 06_seguridad.sh <depto> <usuarios.csv> [puertos]
#      ej: 06_seguridad.sh finanzas ejemplos/finanzas.csv
#          06_seguridad.sh finanzas ejemplos/finanzas.csv "25,465,587,21,23,6667"
# Formato del CSV (ver ejemplos/finanzas.csv):  usuario,rol  (el rol se guarda
# en el campo comentario del usuario; este módulo no da permisos por rol).
#
# Demo (desde la raíz del repo):
#   sudo ./src/modulos/06_seguridad.sh finanzas ejemplos/finanzas.csv
#   sudo nft list table inet depto_finanzas                 # la regla, con contador en 0
#   Terminal 2: sudo nc -l -k 127.0.0.1 25                   # "servidor SMTP" de prueba
#   nc -zv 127.0.0.1 25                                      # student: Connected
#   sudo su - lperez -c "nc -zv 127.0.0.1 25"                # finanzas: Connection refused
#   sudo su - lperez -c "nc -zv 127.0.0.1 80"                # otro puerto: no lo bloquea
#   sudo nft list table inet depto_finanzas                 # el contador subió
#   Ver la syscall: sudo su - lperez -c "strace -e trace=connect nc -z 127.0.0.1 25"
#       -> connect(...) = -1 ECONNREFUSED
#   Contexto de firewall de entrada (lo que RHEL ya trae): sudo firewall-cmd --list-all
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?Uso: $0 <depto> <usuarios.csv> [puertos]}"
CSV="${2:?Uso: $0 <depto> <usuarios.csv> [puertos]}"
PUERTOS="${3:-25,465,587,21,23}"
CLAVE_INICIAL="${CLAVE_INICIAL:-pagosur}"      # se fuerza el cambio en el primer login
TABLA="depto_${DEPTO//-/_}"                      # nombre de la tabla nft (sin guiones)
ARCHIVO="/etc/nftables/depto-${DEPTO}-red.nft"   # copia de las reglas, para leerlas y rehacerlas

# ---- validaciones ----
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }
[[ -f "$CSV" ]] || { echo "No existe el CSV: $CSV"; exit 1; }
[[ "$PUERTOS" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "Puertos inválidos '$PUERTOS': usar por ej. 25,465,587"; exit 1; }
command -v nft >/dev/null || { echo "Falta nft: sudo dnf install -y nftables"; exit 1; }

# ---- 1. Grupo y usuarios (lo que el resto de los módulos necesita) ----
if getent group "$DEPTO" >/dev/null; then
    log "SEGURIDAD: grupo $DEPTO ya existe"
else
    groupadd "$DEPTO"
    log "SEGURIDAD: creado grupo $DEPTO"
fi

# CSV: usuario,rol (la primera línea es el encabezado). -g minúscula: grupo
# PRIMARIO = departamento, así lo encuentran ps -G (ej. 2), la verificación del
# ej. 3 y la regla de red de abajo (meta skgid).
tail -n +2 "$CSV" | while IFS=, read -r usuario rol; do
    usuario="${usuario//[[:space:]]/}"; rol="${rol//[[:space:]]/}"
    [[ -z "$usuario" ]] && continue
    if id -u "$usuario" >/dev/null 2>&1; then
        log "SEGURIDAD: usuario $usuario ya existe ($rol)"
        continue
    fi
    useradd -m -g "$DEPTO" -s /bin/bash -c "$DEPTO/$rol" "$usuario"
    echo "$usuario:$CLAVE_INICIAL" | chpasswd
    chage -d 0 -M 90 "$usuario"      # cambiar la clave al entrar; vence a los 90 días
    log "SEGURIDAD: creado usuario $usuario rol=$rol grupo=$DEPTO (clave inicial, cambio forzado)"
done

# ---- 2. Bloqueo de puertos de salida para el grupo ----
GID=$(getent group "$DEPTO" | cut -d: -f3)
LISTA="{ ${PUERTOS//,/, } }"       # "25,465" -> "{ 25, 465 }" (set de nftables)

# Tabla propia del depto: se crea si no existe y se borra, así el archivo es
# idempotente y revocar.sh la saca con un solo "delete table".
# meta skgid: grupo del proceso dueño del socket. reject with tcp reset: el
# cliente recibe "Connection refused" al instante en vez de esperar un timeout.
mkdir -p "$(dirname "$ARCHIVO")"
cat > "$ARCHIVO" <<EOF
#!/usr/sbin/nft -f
# Generado por 06_seguridad.sh el $(date '+%Y-%m-%d %H:%M:%S') para el departamento "$DEPTO" (gid $GID).
# Bloquea conexiones TCP de SALIDA de los procesos del grupo hacia los puertos: $PUERTOS
# Aplicar:  nft -f $ARCHIVO      Quitar:  nft delete table inet $TABLA
table inet $TABLA
delete table inet $TABLA
table inet $TABLA {
    chain salida {
        type filter hook output priority filter; policy accept;
        meta skgid $GID tcp dport $LISTA counter reject with tcp reset comment "$DEPTO: puertos bloqueados"
    }
}
EOF
chmod 644 "$ARCHIVO"
nft -f "$ARCHIVO"
log "SEGURIDAD: tabla nft $TABLA: grupo $DEPTO (gid $GID) sin salida TCP a puertos $PUERTOS"

# ---- verificar ----
nft list table inet "$TABLA" | grep -q "skgid $GID" \
    && log "SEGURIDAD: verificado, la regla está cargada en el kernel (nft list table inet $TABLA)" \
    || { log "SEGURIDAD: AVISO, la regla no aparece en el kernel"; exit 1; }
