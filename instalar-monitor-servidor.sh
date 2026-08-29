#!/usr/bin/env bash
#
# Instalador de monitor-servidor.sh para Ubuntu 18.04+.
#
# El instalador asume que los siguientes archivos están en el mismo directorio:
#   - monitor-servidor.sh
#   - monitor-servidor.conf
#   - mysql.cnf
#
# Debe ejecutarse como root.

set -euo pipefail
umask 077

###############################################################################
# Constantes de instalación
###############################################################################

DIRECTORIO_ORIGEN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

ARCHIVO_SCRIPT_ORIGEN="${DIRECTORIO_ORIGEN}/monitor-servidor.sh"
ARCHIVO_CONFIG_ORIGEN="${DIRECTORIO_ORIGEN}/monitor-servidor.conf"
ARCHIVO_MYSQL_ORIGEN="${DIRECTORIO_ORIGEN}/mysql.cnf"

ARCHIVO_SCRIPT_DESTINO="/usr/local/sbin/monitor-servidor.sh"
DIRECTORIO_CONFIG_DESTINO="/etc/monitor-servidor"
ARCHIVO_CONFIG_DESTINO="${DIRECTORIO_CONFIG_DESTINO}/monitor-servidor.conf"
ARCHIVO_MYSQL_DESTINO="${DIRECTORIO_CONFIG_DESTINO}/mysql.cnf"

DIRECTORIO_ESTADO="/var/lib/monitor-servidor"
DIRECTORIO_LOG="/var/log/monitor-servidor"
ARCHIVO_LOG="${DIRECTORIO_LOG}/monitor.log"
ARCHIVO_CRON="/etc/cron.d/monitor-servidor"

MARCA_RESPALDO="$(date '+%Y%m%d-%H%M%S')"

###############################################################################
# Utilidades
###############################################################################

informar() {
    printf '[INFO] %s\n' "$*"
}

advertir() {
    printf '[WARN] %s\n' "$*" >&2
}

fallar() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

exigir_root() {
    if (( EUID != 0 )); then
        fallar "Este instalador debe ejecutarse como root. Use: sudo ./instalar-monitor-servidor.sh"
    fi
}

exigir_archivo() {
    local archivo="$1"

    [[ -f "$archivo" ]] || fallar "No se encontró el archivo requerido: ${archivo}"
    [[ -r "$archivo" ]] || fallar "El archivo no es legible: ${archivo}"
}

respaldar_si_existe() {
    local archivo="$1"
    local respaldo

    if [[ -e "$archivo" ]]; then
        respaldo="${archivo}.bak-${MARCA_RESPALDO}"
        cp -a -- "$archivo" "$respaldo"
        informar "Respaldo creado: ${respaldo}"
    fi
}

instalar_paquetes_faltantes() {
    local -a paquetes=()
    local paquete

    command -v curl >/dev/null 2>&1 || paquetes+=(curl)
    command -v ss >/dev/null 2>&1 || paquetes+=(iproute2)
    command -v ps >/dev/null 2>&1 || paquetes+=(procps)
    command -v flock >/dev/null 2>&1 || paquetes+=(util-linux)
    command -v mysql >/dev/null 2>&1 || paquetes+=(default-mysql-client)
    command -v cron >/dev/null 2>&1 || paquetes+=(cron)

    # AWS CLI solo es obligatorio cuando está habilitado en la configuración.
    if grep -Eq '^[[:space:]]*AWS_CLI_HABILITADO[[:space:]]*=[[:space:]]*1([[:space:]]*#.*)?$' "$ARCHIVO_CONFIG_ORIGEN"; then
        command -v aws >/dev/null 2>&1 || paquetes+=(awscli)
    fi

    if (( ${#paquetes[@]} == 0 )); then
        informar "Las dependencias principales ya están instaladas."
        return 0
    fi

    command -v apt-get >/dev/null 2>&1 || \
        fallar "Faltan dependencias (${paquetes[*]}) y no se encontró apt-get."

    informar "Instalando dependencias faltantes: ${paquetes[*]}"
    apt-get update

    for paquete in "${paquetes[@]}"; do
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$paquete"
    done
}

validar_archivos_origen() {
    exigir_archivo "$ARCHIVO_SCRIPT_ORIGEN"
    exigir_archivo "$ARCHIVO_CONFIG_ORIGEN"
    exigir_archivo "$ARCHIVO_MYSQL_ORIGEN"

    bash -n "$ARCHIVO_SCRIPT_ORIGEN" || fallar "La shell monitor-servidor.sh contiene errores de sintaxis."
    bash -n "$ARCHIVO_CONFIG_ORIGEN" || fallar "monitor-servidor.conf contiene errores de sintaxis Bash."

    if ! grep -Eq '^[[:space:]]*\[client\][[:space:]]*$' "$ARCHIVO_MYSQL_ORIGEN"; then
        fallar "mysql.cnf debe contener una sección [client]."
    fi

    informar "Archivos de origen validados correctamente."
}

crear_directorios() {
    install -d -o root -g root -m 0750 "$DIRECTORIO_CONFIG_DESTINO"
    install -d -o root -g root -m 0700 "$DIRECTORIO_ESTADO"
    install -d -o root -g root -m 0750 "$DIRECTORIO_LOG"

    touch "$ARCHIVO_LOG"
    chown root:root "$ARCHIVO_LOG"
    chmod 0600 "$ARCHIVO_LOG"
}

instalar_archivos() {
    respaldar_si_existe "$ARCHIVO_SCRIPT_DESTINO"
    respaldar_si_existe "$ARCHIVO_CONFIG_DESTINO"
    respaldar_si_existe "$ARCHIVO_MYSQL_DESTINO"

    install -o root -g root -m 0755 "$ARCHIVO_SCRIPT_ORIGEN" "$ARCHIVO_SCRIPT_DESTINO"
    install -o root -g root -m 0600 "$ARCHIVO_CONFIG_ORIGEN" "$ARCHIVO_CONFIG_DESTINO"
    install -o root -g root -m 0600 "$ARCHIVO_MYSQL_ORIGEN" "$ARCHIVO_MYSQL_DESTINO"

    informar "Shell instalada en ${ARCHIVO_SCRIPT_DESTINO}."
    informar "Configuración instalada en ${ARCHIVO_CONFIG_DESTINO}."
    informar "Configuración MySQL instalada en ${ARCHIVO_MYSQL_DESTINO}."
}

activar_cron() {
    command -v systemctl >/dev/null 2>&1 || \
        fallar "No se encontró systemctl; no es posible asegurar la ejecución periódica mediante CRON."

    if ! systemctl enable --now cron >/dev/null 2>&1; then
        fallar "No fue posible habilitar/iniciar el servicio cron."
    fi

    informar "Servicio cron habilitado y activo."
}

instalar_cron() {
    local temporal

    respaldar_si_existe "$ARCHIVO_CRON"

    temporal="$(mktemp)"
    cat > "$temporal" <<'CRON'
# Monitor de servidor: una revisión por minuto.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root /usr/local/sbin/monitor-servidor.sh --una-vez >/dev/null 2>&1
CRON

    install -o root -g root -m 0644 "$temporal" "$ARCHIVO_CRON"
    rm -f "$temporal"

    informar "CRON instalado en ${ARCHIVO_CRON}."
}

validar_instalacion() {
    local error=0

    bash -n "$ARCHIVO_SCRIPT_DESTINO" || error=1
    bash -n "$ARCHIVO_CONFIG_DESTINO" || error=1

    [[ -x "$ARCHIVO_SCRIPT_DESTINO" ]] || error=1
    [[ "$(stat -c '%a' "$ARCHIVO_CONFIG_DESTINO")" == "600" ]] || error=1
    [[ "$(stat -c '%a' "$ARCHIVO_MYSQL_DESTINO")" == "600" ]] || error=1
    [[ -r "$ARCHIVO_CRON" ]] || error=1

    (( error == 0 )) || fallar "La validación posterior a la instalación falló."

    informar "Validación posterior a la instalación: OK."
}

mostrar_advertencias_aws() {
    local perfil

    if ! grep -Eq '^[[:space:]]*AWS_CLI_HABILITADO[[:space:]]*=[[:space:]]*1([[:space:]]*#.*)?$' "$ARCHIVO_CONFIG_DESTINO"; then
        return 0
    fi

    if ! command -v aws >/dev/null 2>&1; then
        advertir "AWS_CLI_HABILITADO=1, pero no se encontró el comando aws."
        return 0
    fi

    perfil="$(sed -nE 's/^[[:space:]]*AWS_PROFILE[[:space:]]*=[[:space:]]*["'\'' ]*([^"'\'' #]+)["'\'' ]*.*/\1/p' "$ARCHIVO_CONFIG_DESTINO" | tail -n 1)"

    if [[ -n "$perfil" ]]; then
        advertir "AWS_PROFILE=${perfil}. CRON se ejecutará como root; asegúrese de que ese perfil AWS esté disponible para root o ajuste la autenticación antes de habilitar el monitoreo AWS."
    fi
}

###############################################################################
# Instalación
###############################################################################

main() {
    exigir_root

    informar "Directorio de origen: ${DIRECTORIO_ORIGEN}"
    validar_archivos_origen
    instalar_paquetes_faltantes
    crear_directorios
    instalar_archivos
    activar_cron
    instalar_cron
    validar_instalacion
    mostrar_advertencias_aws

    cat <<'FIN'

Instalación completada.

Comandos recomendados para verificar:
  sudo /usr/local/sbin/monitor-servidor.sh --probar-alerta
  sudo /usr/local/sbin/monitor-servidor.sh --una-vez
  sudo tail -f /var/log/monitor-servidor/monitor.log

El monitor quedó programado para ejecutarse cada minuto mediante:
  /etc/cron.d/monitor-servidor
FIN
}

main "$@"
