#!/usr/bin/env bash
# =============================================================================
# 03_memoria.sh — Ejercicio 3: Memoria
#
# Situación: un proceso de un usuario pide memoria sin parar y el servidor
# empieza a swapear hasta que el OOM killer mata cualquier cosa. El admin
# limita la memoria virtual que puede pedir cada proceso de los usuarios de
# un departamento (1 GB). Al superarla, malloc falla solo en ese proceso y
# el resto del servidor no se entera.
#
# Cómo: una línea en /etc/security/limits.d/ para el GRUPO del departamento,
# con el límite "as" (address space, en KB). El archivo es solo texto: quien
# lo aplica es pam_limits en cada login del usuario, llamando a setrlimit()
# sobre su shell. Todo proceso que el usuario lance hereda ese RLIMIT_AS, y
# el kernel rechaza con ENOMEM cualquier mmap/brk que lo supere.
#
# Este script NO toca a los usuarios ya logueados: el límite se ve recién en
# el próximo login completo (su - usuario, ssh). Un "su usuario" sin guion
# no pasa por PAM y no lo carga.
#
# Herramientas: limits.conf (pam_limits), ulimit -v, free, vmstat, pmap
# Teoría:       memoria virtual, espacio de direcciones, paginación, swap,
#               OOM killer.
#
# Uso:  03_memoria.sh <depto> [mb]     ej: 03_memoria.sh finanzas 1024
#       El grupo <depto> tiene que existir (lo crea 06_seguridad.sh o
#       demo/simular_depto.sh).
#
# Demo (desde la raíz del repo, con el depto ya creado):
#   sudo src/modulos/03_memoria.sh finanzas 1024
#   su - lperez -c 'ulimit -v'                      -> 1048576
#   su - lperez -c "$PWD/bin/03_carga_ram"          -> "malloc: Cannot allocate memory"
#                                                      al llegar a ~1000 MB
#   en otra terminal: free -h y vmstat 1            -> el servidor sigue normal
#   pmap <pid> mientras corre                       -> crece el espacio de direcciones
#   Contraste: sudo bin/03_carga_ram (root, sin límite) -> no para hasta que
#   el OOM killer lo mata; cortarlo con Ctrl+C antes de que swapee de más.
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
MB="${2:-1024}"
ARCHIVO="/etc/security/limits.d/depto-${DEPTO}-memoria.conf"

# ---- validaciones ----
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root (sudo)"; exit 1; }
[[ "$MB" =~ ^[0-9]+$ && "$MB" -gt 0 ]] || { echo "mb debe ser un entero positivo: '$MB'"; exit 1; }
getent group "$DEPTO" >/dev/null || { echo "El grupo '$DEPTO' no existe: crear el depto primero (06_seguridad.sh)"; exit 1; }
[[ -d /etc/security/limits.d ]] || { echo "No existe /etc/security/limits.d (¿falta el paquete pam?)"; exit 1; }

# pam_limits tiene que estar en la pila de sesión de PAM, si no el archivo es
# letra muerta. Debian/Ubuntu: common-session. RHEL/Fedora: system-auth.
if ! grep -rqs 'pam_limits\.so' /etc/pam.d/; then
    echo "AVISO: pam_limits.so no aparece en /etc/pam.d/: el límite no se va a aplicar en el login" >&2
fi

KB=$((MB * 1024))   # limits.conf mide "as" en KB

# ---- escribir la regla ----
# Formato: <dominio> <tipo> <recurso> <valor>
#   @depto  -> aplica a todo miembro del grupo (el @ lo distingue de un usuario)
#   -       -> soft y hard a la vez: el usuario no puede subirlo con ulimit
#   as      -> address space: tope de memoria VIRTUAL por proceso (RLIMIT_AS)
cat > "$ARCHIVO" <<EOF
# Generado por 03_memoria.sh el $(date '+%Y-%m-%d %H:%M:%S') para el departamento "$DEPTO".
# Memoria virtual máxima por proceso de los usuarios del grupo: ${MB} MB.
# Lo aplica pam_limits en cada login. Se revoca borrando este archivo (revocar.sh).
@${DEPTO}    -    as    ${KB}
EOF
chmod 644 "$ARCHIVO"
log "MEMORIA: grupo=@$DEPTO as=${MB}MB (${KB} KB) escrito en $ARCHIVO"

# ---- verificar con un login real ----
# Tomamos cualquier usuario cuyo grupo PRIMARIO sea el depto (así los crea el
# ej. 6) y abrimos un login completo con "su -" para que PAM aplique la regla.
GID=$(getent group "$DEPTO" | cut -d: -f3)
USUARIO=$(getent passwd | awk -F: -v g="$GID" '$4 == g {print $1; exit}')

if [[ -z "$USUARIO" ]]; then
    log "MEMORIA: el grupo $DEPTO todavía no tiene usuarios, verificación pendiente"
    exit 0
fi

VISTO=$(su - "$USUARIO" -c 'ulimit -v' 2>/dev/null || echo "error")
if [[ "$VISTO" == "$KB" ]]; then
    log "MEMORIA: verificado, 'su - $USUARIO -c ulimit -v' devuelve $VISTO KB"
else
    log "MEMORIA: AVISO, 'su - $USUARIO -c ulimit -v' devolvió '$VISTO' y se esperaba $KB (¿pam_limits deshabilitado?)"
    exit 1
fi
