#!/usr/bin/env bash
# =============================================================================
# 06_seguridad.sh — Ejercicio 6: Seguridad
#
# Objetivo: alta de usuarios desde un CSV, grupo por departamento, permisos
# por rol, un auditor de solo lectura (ACL), sudo limitado y contexto SELinux
# sobre el directorio del departamento.
#
# Herramientas: useradd, groupadd, chage, chmod, SGID, setfacl, getfacl,
#               /etc/sudoers.d, semanage fcontext, restorecon
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
#   [ ] leer el CSV línea por línea: useradd -m -G "$DEPTO" -s /bin/bash "$usuario"
#   [ ] chage -M 90 -d 0 "$usuario"  (vence en 90 días, cambiar clave al primer login)
#   [ ] rol jefe:     sudoers.d/$DEPTO con permisos limitados (ej. systemctl status)
#   [ ] rol auditor:  setfacl -m u:$usuario:rx "$PUNTO"  (solo lectura)
#   [ ] SGID en "$PUNTO" para que los archivos hereden el grupo del depto
#   [ ] semanage fcontext -a -t <tipo> "$PUNTO(/.*)?" && restorecon -Rv "$PUNTO"
#   [ ] loguear cada alta en logs/asignador.log

log "SEGURIDAD: grupo=$DEPTO csv=$CSV (pendiente de implementar)"
