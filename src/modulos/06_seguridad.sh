#!/usr/bin/env bash
# =============================================================================
# 06_seguridad.sh — Ejercicio 6: Seguridad
#
# Objetivo: alta de usuarios desde un CSV, grupo por departamento, permisos
# por rol, un auditor de solo lectura (ACL) y sudo limitado para el jefe.
# SELinux se muestra en la demo (getenforce, ls -Z) y se explica en la teoría
# como ejemplo de MAC; en el script es una sola línea.
#
# Herramientas: useradd, groupadd, chage, chmod, SGID, setfacl, getfacl,
#               /etc/sudoers.d, ls -Z, restorecon
# Teoría:       DAC vs MAC, principio de mínimo privilegio.
#
# Uso: 06_seguridad.sh <depto> <usuarios.csv>
# Formato del CSV (ver ejemplos/finanzas.csv):  usuario,rol
#   rol ∈ { jefe | analista | auditor }
# =============================================================================
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

DEPTO="${1:?falta depto}"
CSV="${2:?falta csv}"
PUNTO="/srv/${DEPTO}"

# TODO:
#   [ ] groupadd "$DEPTO" (si no existe)
#   [ ] leer el CSV línea por línea: useradd -m -g "$DEPTO" -s /bin/bash "$usuario"
#       (-g minúscula: grupo PRIMARIO = departamento, así `ps -G $DEPTO` del ej. 2 lo encuentra)
#   [ ] chage -M 90 -d 0 "$usuario"  (vence en 90 días, cambiar clave al primer login)
#   [ ] rol jefe:     sudoers.d/$DEPTO con permisos limitados (ej. systemctl status)
#   [ ] rol auditor:  setfacl -m u:$usuario:rx "$PUNTO"  (solo lectura)
#   [ ] SGID en "$PUNTO" para que los archivos hereden el grupo del depto
#   [ ] SELinux (una línea): restorecon -Rv "$PUNTO" y mostrar ls -Z "$PUNTO" en la demo
#   [ ] loguear cada alta en logs/asignador.log

log "SEGURIDAD: grupo=$DEPTO csv=$CSV (pendiente de implementar)"
