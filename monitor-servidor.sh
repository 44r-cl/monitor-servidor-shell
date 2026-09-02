#!/usr/bin/env bash
#
# Monitor de Apache + MySQL/RDS para Ubuntu 18.04+.
#
# Modos de ejecución:
#   --una-vez       Ejecuta una revisión y termina. Ideal para CRON.
#   --daemon        Ejecuta revisiones periódicas. Ideal para nohup/systemd.
#   --probar-alerta Envía una notificación de prueba a Pushover.
#
# Seguridad:
#   - No se pasan contraseñas MySQL en la línea de comandos.
#   - Se recomienda usar un archivo mysql.cnf con permisos 0600.
#   - Para AWS, se recomienda un IAM Role de EC2 en vez de claves estáticas.
#

set -u
set -o pipefail
umask 077
export LC_ALL=C

# PATH explícito para asegurar disponibilidad de herramientas del sistema
# cuando el monitor se ejecuta mediante sudo, CRON o como daemon.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

###############################################################################
# Carga de configuración
###############################################################################

ARCHIVO_CONFIG="${ARCHIVO_CONFIG:-/etc/monitor-servidor/monitor-servidor.conf}"

if [[ -r "$ARCHIVO_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$ARCHIVO_CONFIG"
fi

# Identificación general.
NOMBRE_SERVIDOR="${NOMBRE_SERVIDOR:-$(hostname -f 2>/dev/null || hostname)}"

# Pushover.
USER_KEY="${USER_KEY:-}"
API_TOKEN="${API_TOKEN:-}"
PUSHOVER_HABILITADO="${PUSHOVER_HABILITADO:-1}"
PUSHOVER_URL="${PUSHOVER_URL:-https://api.pushover.net/1/messages.json}"
INTENTOS_PUSHOVER="${INTENTOS_PUSHOVER:-3}"
SEGUNDOS_ENTRE_REINTENTOS="${SEGUNDOS_ENTRE_REINTENTOS:-2}"
SEGUNDOS_COOLDOWN_ALERTA="${SEGUNDOS_COOLDOWN_ALERTA:-1800}"
ALERTAR_RECUPERACION="${ALERTAR_RECUPERACION:-1}"

# Estado y logs.
DIRECTORIO_ESTADO="${DIRECTORIO_ESTADO:-/var/tmp/monitor-servidor-${USER:-usuario}}"
ARCHIVO_LOG="${ARCHIVO_LOG:-${DIRECTORIO_ESTADO}/monitor.log}"
MAX_GAP_ESTADO="${MAX_GAP_ESTADO:-180}"

# Ejecución.
INTERVALO_DAEMON="${INTERVALO_DAEMON:-60}"
SEGUNDOS_MUESTRA_CPU="${SEGUNDOS_MUESTRA_CPU:-2}"

# Umbrales del sistema EC2.
UMBRAL_CPU_SISTEMA_PCT="${UMBRAL_CPU_SISTEMA_PCT:-85}"
TIEMPO_SOSTENIDO_CPU="${TIEMPO_SOSTENIDO_CPU:-300}"
UMBRAL_MEMORIA_SISTEMA_PCT="${UMBRAL_MEMORIA_SISTEMA_PCT:-90}"
TIEMPO_SOSTENIDO_MEMORIA="${TIEMPO_SOSTENIDO_MEMORIA:-120}"

# Apache.
APACHE_SERVICIO="${APACHE_SERVICIO:-apache2}"
APACHE_PROCESO="${APACHE_PROCESO:-apache2}"
APACHE_STATUS_URL="${APACHE_STATUS_URL:-http://127.0.0.1/server-status?auto}"
APACHE_HOST_HEADER="${APACHE_HOST_HEADER:-}"
APACHE_MAX_REQUEST_WORKERS="${APACHE_MAX_REQUEST_WORKERS:-175}"
UMBRAL_APACHE_SATURACION_PCT="${UMBRAL_APACHE_SATURACION_PCT:-90}"
TIEMPO_SOSTENIDO_APACHE="${TIEMPO_SOSTENIDO_APACHE:-120}"
UMBRAL_APACHE_CONEXIONES="${UMBRAL_APACHE_CONEXIONES:-250}"
TIEMPO_SOSTENIDO_CONEXIONES_APACHE="${TIEMPO_SOSTENIDO_CONEXIONES_APACHE:-120}"
APACHE_ERROR_LOG="${APACHE_ERROR_LOG:-/var/log/apache2/error.log}"
APACHE_ACCESS_LOG="${APACHE_ACCESS_LOG:-/var/log/apache2/access.log}"
if ! declare -p APACHE_SITIOS_LOGS >/dev/null 2>&1; then
    APACHE_SITIOS_LOGS=("default|${APACHE_ERROR_LOG}|${APACHE_ACCESS_LOG}")
fi
CHECK_CONFIG_ERRORS="${CHECK_CONFIG_ERRORS:-true}"
UMBRAL_APACHE_CONFIG_ERROR="${UMBRAL_APACHE_CONFIG_ERROR:-1}"
REGEX_APACHE_CONFIG_ERROR="${REGEX_APACHE_CONFIG_ERROR:-Syntax error|Cannot load module|internal redirects}"
CHECK_RESOURCE_ERRORS="${CHECK_RESOURCE_ERRORS:-true}"
UMBRAL_APACHE_RESOURCE_ERROR="${UMBRAL_APACHE_RESOURCE_ERROR:-3}"
REGEX_APACHE_RESOURCE_ERROR="${REGEX_APACHE_RESOURCE_ERROR:-MaxRequestWorkers|Out of memory|Error reading from remote server}"
CHECK_HTTP_ERRORS="${CHECK_HTTP_ERRORS:-true}"
UMBRAL_APACHE_HTTP_ERROR="${UMBRAL_APACHE_HTTP_ERROR:-5}"
REGEX_APACHE_HTTP_ERROR="${REGEX_APACHE_HTTP_ERROR:-\"[[:space:]]5[0-9][0-9][[:space:]]}"
CHECK_SECURITY_ERRORS="${CHECK_SECURITY_ERRORS:-true}"
UMBRAL_APACHE_SECURITY_ERROR="${UMBRAL_APACHE_SECURITY_ERROR:-2}"
REGEX_APACHE_SECURITY_ERROR="${REGEX_APACHE_SECURITY_ERROR:-client denied|AH01630.*client denied|authentication failure}"

# MySQL/RDS: conexión SQL.
MYSQL_CNF="${MYSQL_CNF:-/etc/monitor-servidor/mysql.cnf}"
MYSQL_TIMEOUT="${MYSQL_TIMEOUT:-5}"
MYSQL_INTENTOS="${MYSQL_INTENTOS:-2}"
UMBRAL_MYSQL_CONEXIONES_PCT="${UMBRAL_MYSQL_CONEXIONES_PCT:-80}"
UMBRAL_MYSQL_THREADS_RUNNING="${UMBRAL_MYSQL_THREADS_RUNNING:-30}"
TIEMPO_SOSTENIDO_MYSQL="${TIEMPO_SOSTENIDO_MYSQL:-120}"
UMBRAL_MYSQL_SLOW_POR_MINUTO="${UMBRAL_MYSQL_SLOW_POR_MINUTO:-10}"

# AWS CLI / CloudWatch. Deshabilitado por defecto.
AWS_CLI_HABILITADO="${AWS_CLI_HABILITADO:-0}"
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-}"
RDS_DB_INSTANCE_ID="${RDS_DB_INSTANCE_ID:-}"
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-}"
AWS_INTENTOS="${AWS_INTENTOS:-2}"
UMBRAL_RDS_CPU_PCT="${UMBRAL_RDS_CPU_PCT:-80}"
UMBRAL_RDS_MEMORIA_LIBRE_MB="${UMBRAL_RDS_MEMORIA_LIBRE_MB:-1024}"
UMBRAL_RDS_SWAP_MB="${UMBRAL_RDS_SWAP_MB:-512}"
UMBRAL_RDS_CPU_CREDIT_BALANCE="${UMBRAL_RDS_CPU_CREDIT_BALANCE:-50}"
UMBRAL_RDS_BURST_BALANCE_PCT="${UMBRAL_RDS_BURST_BALANCE_PCT:-20}"
UMBRAL_RDS_CONEXIONES="${UMBRAL_RDS_CONEXIONES:-0}"
TIEMPO_SOSTENIDO_RDS="${TIEMPO_SOSTENIDO_RDS:-300}"

###############################################################################
# Utilidades
###############################################################################

preparar_entorno() {
    mkdir -p "$DIRECTORIO_ESTADO" 2>/dev/null || {
        printf 'ERROR: No se puede crear %s\n' "$DIRECTORIO_ESTADO" >&2
        exit 1
    }

    mkdir -p "$(dirname "$ARCHIVO_LOG")" 2>/dev/null || true
    touch "$ARCHIVO_LOG" 2>/dev/null || {
        ARCHIVO_LOG="${DIRECTORIO_ESTADO}/monitor.log"
        touch "$ARCHIVO_LOG" || exit 1
    }

    # Evita dos ejecuciones simultáneas de CRON o daemon + CRON.
    exec 9>"${DIRECTORIO_ESTADO}/monitor.lock"
    if command -v flock >/dev/null 2>&1; then
        if ! flock -n 9; then
            exit 0
        fi
    fi
}

escapar_json() {
    printf '%s' "$1" \
        | sed 's/\\/\\\\/g; s/"/\\"/g' \
        | tr '\r\n\t' '   '
}

registrar() {
    local nivel="$1"
    local evento="$2"
    local mensaje="$3"
    local marca_tiempo

    marca_tiempo="$(date '+%Y-%m-%dT%H:%M:%S%:z')"

    printf '{"ts":"%s","nivel":"%s","evento":"%s","host":"%s","mensaje":"%s"}\n' \
        "$marca_tiempo" \
        "$(escapar_json "$nivel")" \
        "$(escapar_json "$evento")" \
        "$(escapar_json "$NOMBRE_SERVIDOR")" \
        "$(escapar_json "$mensaje")" \
        >> "$ARCHIVO_LOG"
}

es_numero() {
    [[ "${1:-}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

formatear_decimal_log() {
    local valor="$1"

    if [[ "$valor" =~ ^-?[0-9]+([.][0-9]+)$ ]]; then
        awk -v valor="$valor" 'BEGIN { printf "%.2f", valor }'
    else
        printf '%s' "$valor"
    fi
}

mayor_igual() {
    awk -v valor="$1" -v umbral="$2" 'BEGIN { exit !(valor >= umbral) }'
}

menor_igual() {
    awk -v valor="$1" -v umbral="$2" 'BEGIN { exit !(valor <= umbral) }'
}

porcentaje() {
    awk -v parte="$1" -v total="$2" 'BEGIN {
        if (total <= 0) {
            printf "0.00"
        } else {
            printf "%.2f", (parte * 100) / total
        }
    }'
}

enviar_pushover() {
    local titulo="$1"
    local mensaje="$2"
    local prioridad="${3:-0}"
    local intento

    if [[ "$PUSHOVER_HABILITADO" != "1" ]]; then
        registrar "INFO" "pushover" "Notificación omitida: Pushover está deshabilitado. Título=${titulo}"
        return 0
    fi

    if [[ -z "$USER_KEY" || -z "$API_TOKEN" ]]; then
        registrar "ERROR" "pushover" "USER_KEY o API_TOKEN no están configurados."
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        registrar "ERROR" "pushover" "No se encontró curl."
        return 1
    fi

    for ((intento = 1; intento <= INTENTOS_PUSHOVER; intento++)); do
        if curl --fail --silent --show-error \
            --connect-timeout 5 \
            --max-time 15 \
            --request POST \
            --data-urlencode "token=${API_TOKEN}" \
            --data-urlencode "user=${USER_KEY}" \
            --data-urlencode "title=${titulo}" \
            --data-urlencode "message=${mensaje}" \
            --data-urlencode "priority=${prioridad}" \
            "$PUSHOVER_URL" >/dev/null 2>&1; then
            registrar "INFO" "pushover" "Notificación enviada. Título=${titulo}"
            return 0
        fi

        registrar "WARN" "pushover" "Fallo al enviar notificación. Intento=${intento}/${INTENTOS_PUSHOVER}"
        sleep "$SEGUNDOS_ENTRE_REINTENTOS"
    done

    registrar "ERROR" "pushover" "No fue posible enviar la notificación tras ${INTENTOS_PUSHOVER} intentos."
    return 1
}

# Mantiene estado entre ejecuciones para distinguir un pico breve de una anomalía
# sostenida. El archivo contiene:
#   inicio_anomalia|ultima_observacion|ultima_alerta|alertado
#
# Argumentos:
#   1: clave única de la alerta.
#   2: 1 si la condición anómala está presente; 0 en caso contrario.
#   3: segundos que la condición debe sostenerse.
#   4: título de la alerta.
#   5: mensaje de la alerta.
#   6: prioridad Pushover (0 normal, 1 alta).
#   7: mensaje de recuperación.
gestionar_alerta() {
    local clave="$1"
    local condicion="$2"
    local sostenido="$3"
    local titulo="$4"
    local mensaje="$5"
    local prioridad="${6:-0}"
    local mensaje_recuperacion="${7:-Recuperado}"

    local archivo_estado="${DIRECTORIO_ESTADO}/alerta_${clave}.estado"
    local ahora inicio ultima_observacion ultima_alerta alertado duracion

    ahora="$(date +%s)"
    inicio=0
    ultima_observacion=0
    ultima_alerta=0
    alertado=0

    if [[ -r "$archivo_estado" ]]; then
        IFS='|' read -r inicio ultima_observacion ultima_alerta alertado < "$archivo_estado" || true
        inicio="${inicio:-0}"
        ultima_observacion="${ultima_observacion:-0}"
        ultima_alerta="${ultima_alerta:-0}"
        alertado="${alertado:-0}"
    fi

    if [[ "$condicion" == "1" ]]; then
        # Si hubo un hueco largo en el monitoreo, reinicia la ventana sostenida.
        if (( inicio == 0 || ultima_observacion == 0 || ahora - ultima_observacion > MAX_GAP_ESTADO )); then
            inicio="$ahora"
            ultima_alerta=0
            alertado=0
        fi

        duracion=$((ahora - inicio))

        if (( duracion >= sostenido )); then
            if (( alertado == 0 || ahora - ultima_alerta >= SEGUNDOS_COOLDOWN_ALERTA )); then
                if enviar_pushover "$titulo" "$mensaje" "$prioridad"; then
                    ultima_alerta="$ahora"
                    alertado=1
                fi
            fi
        fi

        printf '%s|%s|%s|%s\n' "$inicio" "$ahora" "$ultima_alerta" "$alertado" > "$archivo_estado"
        return 0
    fi

    # Condición normal: avisa una sola vez de la recuperación si antes alertó.
    if (( alertado == 1 )) && [[ "$ALERTAR_RECUPERACION" == "1" ]]; then
        enviar_pushover "RECUPERADO - ${NOMBRE_SERVIDOR}" "$mensaje_recuperacion" 0 || true
    fi

    rm -f "$archivo_estado"
}

###############################################################################
# Métricas Linux / EC2
###############################################################################

leer_contadores_cpu() {
    local etiqueta usuario nice sistema idle iowait irq softirq steal guest guest_nice
    local total inactivo

    read -r etiqueta usuario nice sistema idle iowait irq softirq steal guest guest_nice < /proc/stat

    iowait="${iowait:-0}"
    irq="${irq:-0}"
    softirq="${softirq:-0}"
    steal="${steal:-0}"

    inactivo=$((idle + iowait))
    total=$((usuario + nice + sistema + idle + iowait + irq + softirq + steal))

    printf '%s %s\n' "$total" "$inactivo"
}

medir_cpu_sistema() {
    local total_1 inactivo_1 total_2 inactivo_2 delta_total delta_inactivo

    read -r total_1 inactivo_1 < <(leer_contadores_cpu)
    sleep "$SEGUNDOS_MUESTRA_CPU"
    read -r total_2 inactivo_2 < <(leer_contadores_cpu)

    delta_total=$((total_2 - total_1))
    delta_inactivo=$((inactivo_2 - inactivo_1))

    awk -v total="$delta_total" -v inactivo="$delta_inactivo" 'BEGIN {
        if (total <= 0) {
            printf "0.00"
        } else {
            printf "%.2f", ((total - inactivo) * 100) / total
        }
    }'
}

medir_memoria_sistema() {
    local total_kb disponible_kb

    total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    disponible_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"

    if [[ -z "$disponible_kb" ]]; then
        disponible_kb="$(awk '/^MemFree:/ {libre=$2} /^Buffers:/ {buffers=$2} /^Cached:/ {cache=$2} END {print libre+buffers+cache}' /proc/meminfo)"
    fi

    porcentaje "$((total_kb - disponible_kb))" "$total_kb"
}

monitorear_sistema() {
    local cpu_pct memoria_pct condicion_cpu=0 condicion_memoria=0 carga

    cpu_pct="$(medir_cpu_sistema)"
    memoria_pct="$(medir_memoria_sistema)"
    carga="$(cut -d' ' -f1-3 /proc/loadavg)"

    registrar "INFO" "sistema" "cpu_pct=${cpu_pct} memoria_usada_pct=${memoria_pct} load_average=${carga}"

    if mayor_igual "$cpu_pct" "$UMBRAL_CPU_SISTEMA_PCT"; then
        condicion_cpu=1
    fi

    gestionar_alerta \
        "cpu_sistema" \
        "$condicion_cpu" \
        "$TIEMPO_SOSTENIDO_CPU" \
        "CPU alta - ${NOMBRE_SERVIDOR}" \
        "CPU ${cpu_pct}% >= ${UMBRAL_CPU_SISTEMA_PCT}% durante al menos ${TIEMPO_SOSTENIDO_CPU}s. Load: ${carga}." \
        1 \
        "CPU normalizada en ${NOMBRE_SERVIDOR}: ${cpu_pct}%."

    if mayor_igual "$memoria_pct" "$UMBRAL_MEMORIA_SISTEMA_PCT"; then
        condicion_memoria=1
    fi

    gestionar_alerta \
        "memoria_sistema" \
        "$condicion_memoria" \
        "$TIEMPO_SOSTENIDO_MEMORIA" \
        "Memoria alta - ${NOMBRE_SERVIDOR}" \
        "Memoria utilizada ${memoria_pct}% >= ${UMBRAL_MEMORIA_SISTEMA_PCT}%." \
        1 \
        "Memoria normalizada en ${NOMBRE_SERVIDOR}: ${memoria_pct}% utilizada."
}

###############################################################################
# Apache
###############################################################################

obtener_server_status() {
    local intento cabecera=()

    if [[ -n "$APACHE_HOST_HEADER" ]]; then
        cabecera=(-H "Host: ${APACHE_HOST_HEADER}")
    fi

    for intento in 1 2; do
        if curl --fail --silent --show-error \
            --connect-timeout 2 \
            --max-time 5 \
            "${cabecera[@]}" \
            "$APACHE_STATUS_URL" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done

    return 1
}

contar_conexiones_apache() {
    if ! command -v ss >/dev/null 2>&1; then
        printf '0\n'
        return 0
    fi

    ss -Htan state established 2>/dev/null \
        | awk '$4 ~ /:80$/ || $4 ~ /:443$/ {cantidad++} END {print cantidad+0}'
}

medir_procesos_apache() {
    ps -C "$APACHE_PROCESO" -o %cpu=,rss= 2>/dev/null \
        | awk '
            { cpu += $1; rss += $2; procesos++ }
            END {
                printf "%d %.2f %.2f\n", procesos+0, cpu+0, rss/1024
            }
        '
}

# Devuelve éxito si el valor recibido representa un booleano habilitado.
#
# Argumentos:
#   1: valor booleano (1, true, yes, on o si).
booleano_habilitado() {
    case "${1,,}" in
        1|true|yes|on|si)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Procesa una categoría de errores Apache sobre las líneas nuevas detectadas.
# Acumula ocurrencias entre ejecuciones hasta alcanzar el umbral configurado.
#
# Argumentos:
#   1: nombre del sitio.
#   2: clave interna de la categoría.
#   3: nombre legible de la categoría.
#   4: flag de activación.
#   5: expresión regular extendida.
#   6: umbral de ocurrencias.
#   7: archivo temporal con las líneas nuevas del log.
#   8: ruta del log origen.
#   9: evento usado en el log del monitor.
procesar_categoria_log_apache() {
    local sitio="$1"
    local clave="$2"
    local categoria="$3"
    local habilitado="$4"
    local regex="$5"
    local umbral="$6"
    local archivo_nuevas="$7"
    local ruta_log="$8"
    local evento_log="$9"
    local sitio_clave
    local archivo_contador muestra_errores="" detalles_pushover="" muestras_bloqueadas=""
    local ocurrencias_nuevas=0 ocurrencias_bloqueadas=0 ocurrencias_acumuladas=0 ultima_alerta=0 ahora

    sitio_clave="$(printf '%s' "$sitio" | sed 's/[^[:alnum:]_-]/_/g')"
    if [[ "$clave" == "seguridad" ]]; then
        archivo_contador="${DIRECTORIO_ESTADO}/apache_${sitio_clave}_${clave}_accionable.contador"
    else
        archivo_contador="${DIRECTORIO_ESTADO}/apache_${sitio_clave}_${clave}.contador"
    fi

    if ! booleano_habilitado "$habilitado"; then
        rm -f "$archivo_contador"
        return 0
    fi

    if ! [[ "$umbral" =~ ^[1-9][0-9]*$ ]]; then
        registrar "WARN" "$evento_log" "sitio=${sitio} categoria=${clave} umbral_invalido=${umbral}"
        return 0
    fi

    if [[ -z "$regex" ]]; then
        registrar "WARN" "$evento_log" "sitio=${sitio} categoria=${clave} regex_vacio"
        return 0
    fi

    if [[ "$clave" == "seguridad" ]]; then
        ocurrencias_bloqueadas="$(grep -Eic -- 'client denied by server configuration' "$archivo_nuevas" || true)"
        ocurrencias_bloqueadas="${ocurrencias_bloqueadas:-0}"
        ocurrencias_nuevas="$(grep -Ei -- "$regex" "$archivo_nuevas" \
            | grep -Eiv -- 'client denied by server configuration' \
            | wc -l || true)"
        ocurrencias_nuevas="${ocurrencias_nuevas//[[:space:]]/}"
        ocurrencias_nuevas="${ocurrencias_nuevas:-0}"

        if (( ocurrencias_bloqueadas > 0 )); then
            muestras_bloqueadas="$(grep -Ei -- 'client denied by server configuration' "$archivo_nuevas" \
                | head -n 3 \
                | awk '{gsub(/[[:space:]]+/, " "); printf "%s%s", (NR > 1 ? " || " : ""), substr($0, 1, 500)}')"
            registrar "WARN" "$evento_log" "sitio=${sitio} categoria=seguridad_bloqueada ocurrencias_nuevas=${ocurrencias_bloqueadas} pushover=omitido muestras=${muestras_bloqueadas}"
        fi
    else
        ocurrencias_nuevas="$(grep -Eic -- "$regex" "$archivo_nuevas" || true)"
        ocurrencias_nuevas="${ocurrencias_nuevas:-0}"
    fi

    if (( ocurrencias_nuevas > 0 )); then
        if [[ "$clave" == "seguridad" ]]; then
            muestra_errores="$(grep -Ei -- "$regex" "$archivo_nuevas" \
                | grep -Eiv -- 'client denied by server configuration' \
                | head -n 3 \
                | awk '{gsub(/[[:space:]]+/, " "); printf "%s%s", (NR > 1 ? " || " : ""), substr($0, 1, 500)}')"
        else
            muestra_errores="$(grep -Ei -- "$regex" "$archivo_nuevas" \
                | head -n 3 \
                | awk '{gsub(/[[:space:]]+/, " "); printf "%s%s", (NR > 1 ? " || " : ""), substr($0, 1, 500)}')"
        fi
    fi

    if [[ -r "$archivo_contador" ]]; then
        IFS='|' read -r ocurrencias_acumuladas ultima_alerta < "$archivo_contador" || true
        ocurrencias_acumuladas="${ocurrencias_acumuladas:-0}"
        ultima_alerta="${ultima_alerta:-0}"
    fi

    [[ "$ocurrencias_acumuladas" =~ ^[0-9]+$ ]] || ocurrencias_acumuladas=0
    [[ "$ultima_alerta" =~ ^[0-9]+$ ]] || ultima_alerta=0

    ocurrencias_acumuladas=$((ocurrencias_acumuladas + ocurrencias_nuevas))
    ahora="$(date +%s)"

    if (( ocurrencias_nuevas > 0 )); then
        registrar "WARN" "$evento_log" "sitio=${sitio} categoria=${clave} ocurrencias_nuevas=${ocurrencias_nuevas} ocurrencias_acumuladas=${ocurrencias_acumuladas} umbral=${umbral} muestras=${muestra_errores}"
    fi

    if (( ocurrencias_nuevas > 0 && ocurrencias_acumuladas >= umbral )); then
        if (( ultima_alerta == 0 || ahora - ultima_alerta >= SEGUNDOS_COOLDOWN_ALERTA )); then
            detalles_pushover="$(printf '%s' "$muestra_errores" \
                | awk -v hay_mas="$((ocurrencias_nuevas > 3 ? 1 : 0))" 'BEGIN { RS=" \\|\\| " } { detalle=$0; sub(/^(\[[^]]+\][[:space:]]*)+/, "", detalle); if (length(detalle) > 250) detalle=substr(detalle, 1, 247) "..."; printf "%s- %s", (NR > 1 ? "\n" : ""), detalle } END { if (hay_mas) printf "\n… (más entradas en log)" }')"

            if enviar_pushover \
                "Error Apache ${categoria} - ${NOMBRE_SERVIDOR}" \
                "Sitio=${sitio}; categoría=${categoria}; log=${ruta_log}.
Ocurrencias=${ocurrencias_acumuladas}; umbral=${umbral}.
Detalles:
${detalles_pushover}" \
                1; then
                ocurrencias_acumuladas=0
                ultima_alerta="$ahora"
            fi
        fi
    fi

    printf '%s|%s\n' "$ocurrencias_acumuladas" "$ultima_alerta" > "$archivo_contador"
}

# Obtiene únicamente las líneas nuevas de un log Apache.
# El cursor persiste inode y número de línea para evitar recontar eventos
# históricos y reinicia desde el comienzo cuando detecta rotación o truncado.
#
# Argumentos:
#   1: clave segura del sitio.
#   2: tipo de log (error o access).
#   3: ruta del log.
#   4: archivo temporal donde escribir las líneas nuevas.
#   5: evento usado en el log del monitor.
obtener_lineas_nuevas_log_apache() {
    local sitio_clave="$1"
    local tipo_log="$2"
    local ruta_log="$3"
    local archivo_nuevas="$4"
    local evento_log="$5"
    local archivo_cursor="${DIRECTORIO_ESTADO}/apache_${sitio_clave}_${tipo_log}.cursor"
    local inode_actual lineas_actuales inode_anterior="" lineas_anteriores=0
    local linea_inicio cantidad_nuevas

    if [[ ! -r "$ruta_log" ]]; then
        registrar "WARN" "$evento_log" "log=no_legible ruta=${ruta_log}"
        return 1
    fi

    inode_actual="$(stat -c '%i' "$ruta_log" 2>/dev/null || true)"
    lineas_actuales="$(wc -l < "$ruta_log" 2>/dev/null || printf '0')"
    lineas_actuales="${lineas_actuales//[[:space:]]/}"

    if [[ -z "$inode_actual" || ! "$lineas_actuales" =~ ^[0-9]+$ ]]; then
        registrar "WARN" "$evento_log" "log=no_procesable ruta=${ruta_log}"
        return 1
    fi

    if [[ ! -r "$archivo_cursor" ]]; then
        printf '%s|%s\n' "$inode_actual" "$lineas_actuales" > "$archivo_cursor"
        registrar "INFO" "$evento_log" "cursor_inicializado ruta=${ruta_log} linea=${lineas_actuales}"
        return 1
    fi

    IFS='|' read -r inode_anterior lineas_anteriores < "$archivo_cursor" || true
    lineas_anteriores="${lineas_anteriores:-0}"
    [[ "$lineas_anteriores" =~ ^[0-9]+$ ]] || lineas_anteriores=0

    if [[ "$inode_actual" != "$inode_anterior" ]] || (( lineas_actuales < lineas_anteriores )); then
        linea_inicio=1
        cantidad_nuevas="$lineas_actuales"
    else
        linea_inicio=$((lineas_anteriores + 1))
        cantidad_nuevas=$((lineas_actuales - lineas_anteriores))
    fi

    if (( cantidad_nuevas <= 0 )); then
        printf '%s|%s\n' "$inode_actual" "$lineas_actuales" > "$archivo_cursor"
        return 1
    fi

    tail -n +"$linea_inicio" "$ruta_log" 2>/dev/null \
        | head -n "$cantidad_nuevas" > "$archivo_nuevas"

    printf '%s|%s\n' "$inode_actual" "$lineas_actuales" > "$archivo_cursor"
    return 0
}

# Analiza los error.log y access.log configurados para cada sitio Apache.
# Las categorías Configuración, Recursos y Seguridad se evalúan sobre error.log;
# HTTP 5xx se evalúa sobre access.log usando el código de estado HTTP registrado.
analyze_logs() {
    local definicion sitio error_log access_log sitio_clave
    local archivo_nuevas_error archivo_nuevas_access

    for definicion in "${APACHE_SITIOS_LOGS[@]}"; do
        IFS='|' read -r sitio error_log access_log <<< "$definicion"

        if [[ -z "$sitio" ]]; then
            registrar "WARN" "apache_logs" "sitio_sin_nombre definicion=${definicion}"
            continue
        fi

        sitio_clave="$(printf '%s' "$sitio" | sed 's/[^[:alnum:]_-]/_/g')"
        archivo_nuevas_error="${DIRECTORIO_ESTADO}/apache_${sitio_clave}_error_nuevas.$$"
        archivo_nuevas_access="${DIRECTORIO_ESTADO}/apache_${sitio_clave}_access_nuevas.$$"

        if [[ -n "$error_log" ]] && obtener_lineas_nuevas_log_apache \
            "$sitio_clave" "error" "$error_log" "$archivo_nuevas_error" "apache_error_log"; then

            procesar_categoria_log_apache \
                "$sitio" "configuracion" "Configuración" "$CHECK_CONFIG_ERRORS" \
                "$REGEX_APACHE_CONFIG_ERROR" "$UMBRAL_APACHE_CONFIG_ERROR" \
                "$archivo_nuevas_error" "$error_log" "apache_error_log"

            procesar_categoria_log_apache \
                "$sitio" "recursos" "Recursos" "$CHECK_RESOURCE_ERRORS" \
                "$REGEX_APACHE_RESOURCE_ERROR" "$UMBRAL_APACHE_RESOURCE_ERROR" \
                "$archivo_nuevas_error" "$error_log" "apache_error_log"

            procesar_categoria_log_apache \
                "$sitio" "seguridad" "Seguridad" "$CHECK_SECURITY_ERRORS" \
                "$REGEX_APACHE_SECURITY_ERROR" "$UMBRAL_APACHE_SECURITY_ERROR" \
                "$archivo_nuevas_error" "$error_log" "apache_error_log"
        fi

        if [[ -n "$access_log" ]] && obtener_lineas_nuevas_log_apache \
            "$sitio_clave" "access" "$access_log" "$archivo_nuevas_access" "apache_access_log"; then

            procesar_categoria_log_apache \
                "$sitio" "http_5xx" "HTTP 5xx" "$CHECK_HTTP_ERRORS" \
                "$REGEX_APACHE_HTTP_ERROR" "$UMBRAL_APACHE_HTTP_ERROR" \
                "$archivo_nuevas_access" "$access_log" "apache_access_log"
        fi

        rm -f "$archivo_nuevas_error" "$archivo_nuevas_access"
    done
}

monitorear_apache() {
    local activo=0 condicion_caido=0
    local estado busy idle workers_total saturacion_pct conexiones
    local procesos cpu_apache rss_apache_mb condicion_saturacion=0 condicion_conexiones=0
    local cpu_status req_por_seg cpu_status_log req_por_seg_log

    if systemctl is-active --quiet "$APACHE_SERVICIO" 2>/dev/null; then
        activo=1
    else
        condicion_caido=1
    fi

    gestionar_alerta \
        "apache_caido" \
        "$condicion_caido" \
        0 \
        "Apache caído - ${NOMBRE_SERVIDOR}" \
        "El servicio ${APACHE_SERVICIO} no está activo." \
        1 \
        "Apache (${APACHE_SERVICIO}) volvió a estar activo en ${NOMBRE_SERVIDOR}."

    if (( activo == 0 )); then
        registrar "ERROR" "apache" "servicio=caido servicio_nombre=${APACHE_SERVICIO}"
        return 0
    fi

    read -r procesos cpu_apache rss_apache_mb < <(medir_procesos_apache)
    conexiones="$(contar_conexiones_apache)"

    estado="$(obtener_server_status || true)"

    if [[ -z "$estado" ]]; then
        registrar "WARN" "apache" "servicio=activo server_status=no_disponible procesos=${procesos} cpu_procesos_pct=${cpu_apache} rss_total_aprox_mb=${rss_apache_mb} conexiones_establecidas=${conexiones}"

        gestionar_alerta \
            "apache_status" \
            1 \
            "$TIEMPO_SOSTENIDO_APACHE" \
            "Apache status inaccesible - ${NOMBRE_SERVIDOR}" \
            "Apache está activo, pero ${APACHE_STATUS_URL} no respondió correctamente." \
            0 \
            "El endpoint server-status de Apache volvió a responder en ${NOMBRE_SERVIDOR}."
        return 0
    fi

    gestionar_alerta \
        "apache_status" \
        0 \
        "$TIEMPO_SOSTENIDO_APACHE" \
        "" "" 0 \
        "El endpoint server-status de Apache volvió a responder en ${NOMBRE_SERVIDOR}."

    busy="$(printf '%s\n' "$estado" | awk -F': ' '/^(BusyWorkers|BusyServers):/ {print $2; exit}')"
    idle="$(printf '%s\n' "$estado" | awk -F': ' '/^(IdleWorkers|IdleServers):/ {print $2; exit}')"
    cpu_status="$(printf '%s\n' "$estado" | awk -F': ' '/^CPULoad:/ {print $2; exit}')"
    req_por_seg="$(printf '%s\n' "$estado" | awk -F': ' '/^ReqPerSec:/ {print $2; exit}')"

    busy="${busy:-0}"
    idle="${idle:-0}"
    cpu_status="${cpu_status:-0}"
    req_por_seg="${req_por_seg:-0}"
    workers_total=$((busy + idle))
    saturacion_pct="$(porcentaje "$busy" "$APACHE_MAX_REQUEST_WORKERS")"
    cpu_status_log="$(awk -v valor="$cpu_status" 'BEGIN { if (valor ~ /^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$/) printf "%.4f", valor; else printf "%s", valor }')"
    req_por_seg_log="$(formatear_decimal_log "$req_por_seg")"

    registrar "INFO" "apache" "servicio=activo busy_workers=${busy} idle_workers=${idle} workers_actuales=${workers_total} max_request_workers=${APACHE_MAX_REQUEST_WORKERS} saturacion_pct=${saturacion_pct} conexiones_establecidas=${conexiones} procesos=${procesos} cpu_procesos_pct=${cpu_apache} rss_total_aprox_mb=${rss_apache_mb} req_por_seg=${req_por_seg_log} cpu_status=${cpu_status_log}"

    if mayor_igual "$saturacion_pct" "$UMBRAL_APACHE_SATURACION_PCT"; then
        condicion_saturacion=1
    fi

    gestionar_alerta \
        "apache_saturacion" \
        "$condicion_saturacion" \
        "$TIEMPO_SOSTENIDO_APACHE" \
        "Apache saturado - ${NOMBRE_SERVIDOR}" \
        "BusyWorkers=${busy}/${APACHE_MAX_REQUEST_WORKERS} (${saturacion_pct}%), conexiones=${conexiones}, req/s=${req_por_seg}." \
        1 \
        "Apache dejó la zona de saturación en ${NOMBRE_SERVIDOR}: BusyWorkers=${busy}/${APACHE_MAX_REQUEST_WORKERS} (${saturacion_pct}%)."

    if (( conexiones >= UMBRAL_APACHE_CONEXIONES )); then
        condicion_conexiones=1
    fi

    gestionar_alerta \
        "apache_conexiones" \
        "$condicion_conexiones" \
        "$TIEMPO_SOSTENIDO_CONEXIONES_APACHE" \
        "Conexiones Apache altas - ${NOMBRE_SERVIDOR}" \
        "Conexiones TCP establecidas hacia 80/443=${conexiones}, umbral=${UMBRAL_APACHE_CONEXIONES}." \
        0 \
        "Conexiones Apache normalizadas en ${NOMBRE_SERVIDOR}: ${conexiones}."
}

###############################################################################
# MySQL
###############################################################################

ejecutar_mysql_estado() {
    local intento salida

    if ! command -v mysql >/dev/null 2>&1; then
        return 127
    fi

    if [[ ! -r "$MYSQL_CNF" ]]; then
        return 126
    fi

    for ((intento = 1; intento <= MYSQL_INTENTOS; intento++)); do
        if salida="$(mysql \
            --defaults-extra-file="$MYSQL_CNF" \
            --connect-timeout="$MYSQL_TIMEOUT" \
            --batch \
            --skip-column-names \
            --execute="
                SHOW GLOBAL STATUS
                WHERE Variable_name IN (
                    'Threads_connected',
                    'Threads_running',
                    'Slow_queries',
                    'Uptime'
                );
                SHOW GLOBAL VARIABLES
                WHERE Variable_name IN (
                    'max_connections',
                    'long_query_time'
                );
            " 2>/dev/null)"; then
            printf '%s\n' "$salida"
            return 0
        fi

        sleep "$SEGUNDOS_ENTRE_REINTENTOS"
    done

    return 1
}

calcular_slow_queries_por_minuto() {
    local contador_actual="$1"
    local archivo="${DIRECTORIO_ESTADO}/mysql_slow_queries.contador"
    local ahora contador_anterior=0 tiempo_anterior=0 delta=0 segundos=0 tasa="0.00"

    ahora="$(date +%s)"

    if [[ -r "$archivo" ]]; then
        IFS='|' read -r contador_anterior tiempo_anterior < "$archivo" || true
        contador_anterior="${contador_anterior:-0}"
        tiempo_anterior="${tiempo_anterior:-0}"
    fi

    if (( tiempo_anterior > 0 && ahora > tiempo_anterior )); then
        segundos=$((ahora - tiempo_anterior))

        if (( contador_actual >= contador_anterior )); then
            delta=$((contador_actual - contador_anterior))
        else
            # Reinicio del servidor o FLUSH STATUS.
            delta=0
        fi

        tasa="$(awk -v delta="$delta" -v segundos="$segundos" 'BEGIN {
            if (segundos <= 0) printf "0.00";
            else printf "%.2f", (delta * 60) / segundos;
        }')"
    fi

    printf '%s|%s\n' "$contador_actual" "$ahora" > "$archivo"
    printf '%s\n' "$tasa"
}

monitorear_mysql() {
    local salida rc condicion_caido=0
    local conexiones threads_running slow_queries uptime max_connections long_query_time
    local conexiones_pct slow_por_minuto long_query_time_log
    local condicion_conexiones=0 condicion_threads=0 condicion_slow=0

    salida="$(ejecutar_mysql_estado)"
    rc=$?

    if (( rc != 0 )); then
        condicion_caido=1

        case "$rc" in
            127)
                registrar "ERROR" "mysql" "cliente_mysql=no_instalado"
                ;;
            126)
                registrar "ERROR" "mysql" "archivo_mysql_cnf=no_legible ruta=${MYSQL_CNF}"
                ;;
            *)
                registrar "ERROR" "mysql" "conexion=no_disponible intentos=${MYSQL_INTENTOS}"
                ;;
        esac

        gestionar_alerta \
            "mysql_caido" \
            "$condicion_caido" \
            0 \
            "MySQL/RDS no disponible - ${NOMBRE_SERVIDOR}" \
            "No fue posible consultar MySQL usando ${MYSQL_CNF}." \
            1 \
            "MySQL/RDS volvió a responder desde ${NOMBRE_SERVIDOR}."
        return 0
    fi

    gestionar_alerta \
        "mysql_caido" \
        0 \
        0 \
        "" "" 0 \
        "MySQL/RDS volvió a responder desde ${NOMBRE_SERVIDOR}."

    conexiones="$(printf '%s\n' "$salida" | awk '$1=="Threads_connected" {print $2; exit}')"
    threads_running="$(printf '%s\n' "$salida" | awk '$1=="Threads_running" {print $2; exit}')"
    slow_queries="$(printf '%s\n' "$salida" | awk '$1=="Slow_queries" {print $2; exit}')"
    uptime="$(printf '%s\n' "$salida" | awk '$1=="Uptime" {print $2; exit}')"
    max_connections="$(printf '%s\n' "$salida" | awk '$1=="max_connections" {print $2; exit}')"
    long_query_time="$(printf '%s\n' "$salida" | awk '$1=="long_query_time" {print $2; exit}')"

    conexiones="${conexiones:-0}"
    threads_running="${threads_running:-0}"
    slow_queries="${slow_queries:-0}"
    uptime="${uptime:-0}"
    max_connections="${max_connections:-0}"
    long_query_time="${long_query_time:-0}"

    conexiones_pct="$(porcentaje "$conexiones" "$max_connections")"
    slow_por_minuto="$(calcular_slow_queries_por_minuto "$slow_queries")"
    long_query_time_log="$(formatear_decimal_log "$long_query_time")"

    registrar "INFO" "mysql" "disponible=si conexiones=${conexiones} max_connections=${max_connections} conexiones_pct=${conexiones_pct} threads_running=${threads_running} slow_queries_total=${slow_queries} slow_queries_por_min=${slow_por_minuto} long_query_time_s=${long_query_time_log} uptime_s=${uptime}"

    if mayor_igual "$conexiones_pct" "$UMBRAL_MYSQL_CONEXIONES_PCT"; then
        condicion_conexiones=1
    fi

    gestionar_alerta \
        "mysql_conexiones" \
        "$condicion_conexiones" \
        "$TIEMPO_SOSTENIDO_MYSQL" \
        "Conexiones MySQL altas - ${NOMBRE_SERVIDOR}" \
        "MySQL usa ${conexiones}/${max_connections} conexiones (${conexiones_pct}%), umbral=${UMBRAL_MYSQL_CONEXIONES_PCT}%." \
        1 \
        "Conexiones MySQL normalizadas: ${conexiones}/${max_connections} (${conexiones_pct}%)."

    if (( threads_running >= UMBRAL_MYSQL_THREADS_RUNNING )); then
        condicion_threads=1
    fi

    gestionar_alerta \
        "mysql_threads" \
        "$condicion_threads" \
        "$TIEMPO_SOSTENIDO_MYSQL" \
        "MySQL con alta concurrencia - ${NOMBRE_SERVIDOR}" \
        "Threads_running=${threads_running}, umbral=${UMBRAL_MYSQL_THREADS_RUNNING}." \
        1 \
        "Threads_running de MySQL volvió a nivel normal: ${threads_running}."

    if mayor_igual "$slow_por_minuto" "$UMBRAL_MYSQL_SLOW_POR_MINUTO"; then
        condicion_slow=1
    fi

    gestionar_alerta \
        "mysql_slow" \
        "$condicion_slow" \
        "$TIEMPO_SOSTENIDO_MYSQL" \
        "Queries lentas MySQL - ${NOMBRE_SERVIDOR}" \
        "Slow_queries=${slow_por_minuto}/min, umbral=${UMBRAL_MYSQL_SLOW_POR_MINUTO}/min, long_query_time=${long_query_time}s." \
        0 \
        "Tasa de queries lentas MySQL normalizada: ${slow_por_minuto}/min."
}

###############################################################################
# AWS CLI: estado EC2/RDS y métricas CloudWatch
###############################################################################

aws_base() {
    # Fuerza de forma explícita el perfil configurado. Esto evita depender de
    # que AWS_PROFILE haya sido exportado y hace el comportamiento consistente
    # entre ejecución interactiva, sudo, CRON y modo daemon.
    if [[ -n "$AWS_PROFILE" && -n "$AWS_REGION" ]]; then
        aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
    elif [[ -n "$AWS_PROFILE" ]]; then
        aws --profile "$AWS_PROFILE" "$@"
    elif [[ -n "$AWS_REGION" ]]; then
        aws --region "$AWS_REGION" "$@"
    else
        aws "$@"
    fi
}

# Salida y error de la última invocación AWS. Se asignan por ejecutar_aws().
AWS_SALIDA_COMANDO=""
AWS_ERROR_COMANDO=""

ejecutar_aws() {
    local archivo_error codigo

    AWS_SALIDA_COMANDO=""
    AWS_ERROR_COMANDO=""
    archivo_error="${DIRECTORIO_ESTADO}/aws-error.$$"

    if AWS_SALIDA_COMANDO="$(aws_base "$@" 2>"$archivo_error")"; then
        codigo=0
    else
        codigo=$?
    fi

    if [[ -s "$archivo_error" ]]; then
        AWS_ERROR_COMANDO="$(tr '\r\n' '  ' < "$archivo_error" | sed 's/[[:space:]]\+/ /g')"
    fi
    rm -f "$archivo_error"

    return "$codigo"
}

# Obtiene el punto más reciente de una métrica de RDS.
#
# Argumentos:
#   1: nombre de la métrica CloudWatch.
#   2: estadística (por defecto: Average).
#   3: período en segundos (por defecto: 60).
#   4: ventana hacia atrás en minutos (por defecto: 10).
#
# CPUCreditBalance se publica cada 5 minutos, por lo que se consulta con
# período de 300 segundos y una ventana mayor para evitar falsos "sin datos".
obtener_metrica_rds() {
    local metrica="$1"
    local estadistica="${2:-Average}"
    local periodo="${3:-60}"
    local minutos_atras="${4:-10}"
    local ahora inicio intento

    ahora="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    inicio="$(date -u -d "${minutos_atras} minutes ago" '+%Y-%m-%dT%H:%M:%SZ')"

    for ((intento = 1; intento <= AWS_INTENTOS; intento++)); do
        if ejecutar_aws cloudwatch get-metric-statistics \
            --namespace AWS/RDS \
            --metric-name "$metrica" \
            --dimensions "Name=DBInstanceIdentifier,Value=${RDS_DB_INSTANCE_ID}" \
            --start-time "$inicio" \
            --end-time "$ahora" \
            --period "$periodo" \
            --statistics "$estadistica" \
            --query "Datapoints | sort_by(@,&Timestamp)[-1].${estadistica}" \
            --output text; then
            if es_numero "$AWS_SALIDA_COMANDO"; then
                printf '%s\n' "$AWS_SALIDA_COMANDO"
                return 0
            fi
        else
            registrar "WARN" "aws" "operacion=GetMetricStatistics metrica=${metrica} intento=${intento}/${AWS_INTENTOS} error=${AWS_ERROR_COMANDO:-desconocido}"
        fi

        if (( intento < AWS_INTENTOS )); then
            sleep "$SEGUNDOS_ENTRE_REINTENTOS"
        fi
    done

    return 1
}

monitorear_aws() {
    local estado_rds="" estado_ec2=""
    local rds_cpu="" rds_memoria_bytes="" rds_memoria_mb="" rds_conexiones=""
    local rds_swap_bytes="" rds_swap_mb="" rds_cpu_credit_balance="" rds_burst_balance=""
    local rds_cpu_log rds_memoria_mb_log rds_swap_mb_log rds_cpu_credit_balance_log rds_burst_balance_log rds_conexiones_log
    local condicion_estado_rds=0 condicion_rds_cpu=0 condicion_rds_memoria=0 condicion_rds_conexiones=0
    local condicion_rds_swap=0 condicion_rds_creditos_cpu=0 condicion_rds_burst=0
    local condicion_estado_ec2=0

    if [[ "$AWS_CLI_HABILITADO" != "1" ]]; then
        return 0
    fi

    if ! command -v aws >/dev/null 2>&1; then
        registrar "ERROR" "aws" "aws_cli=no_instalado"
        return 0
    fi

    if [[ -n "$RDS_DB_INSTANCE_ID" ]]; then
        if ejecutar_aws rds describe-db-instances \
            --db-instance-identifier "$RDS_DB_INSTANCE_ID" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text; then
            estado_rds="$AWS_SALIDA_COMANDO"
        else
            estado_rds=""
            registrar "WARN" "aws" "operacion=DescribeDBInstances db_instance=${RDS_DB_INSTANCE_ID} error=${AWS_ERROR_COMANDO:-desconocido}"
        fi

        if [[ -z "$estado_rds" || "$estado_rds" == "None" ]]; then
            registrar "WARN" "aws" "No fue posible obtener DBInstanceStatus de RDS ${RDS_DB_INSTANCE_ID}."
        else
            if [[ "$estado_rds" != "available" ]]; then
                condicion_estado_rds=1
            fi

            gestionar_alerta \
                "rds_estado" \
                "$condicion_estado_rds" \
                0 \
                "Estado RDS anómalo - ${NOMBRE_SERVIDOR}" \
                "RDS ${RDS_DB_INSTANCE_ID} está en estado '${estado_rds}'." \
                1 \
                "RDS ${RDS_DB_INSTANCE_ID} volvió al estado available."
        fi

        rds_cpu="$(obtener_metrica_rds CPUUtilization Average 60 10 || true)"
        rds_memoria_bytes="$(obtener_metrica_rds FreeableMemory Average 60 10 || true)"
        rds_swap_bytes="$(obtener_metrica_rds SwapUsage Average 60 10 || true)"
        # Las métricas de créditos CPU de RDS se publican cada 5 minutos.
        rds_cpu_credit_balance="$(obtener_metrica_rds CPUCreditBalance Average 300 30 || true)"
        rds_burst_balance="$(obtener_metrica_rds BurstBalance Average 60 10 || true)"
        rds_conexiones="$(obtener_metrica_rds DatabaseConnections Average 60 10 || true)"

        if es_numero "$rds_memoria_bytes"; then
            rds_memoria_mb="$(awk -v bytes="$rds_memoria_bytes" 'BEGIN {printf "%.2f", bytes/1024/1024}')"
        fi

        if es_numero "$rds_swap_bytes"; then
            rds_swap_mb="$(awk -v bytes="$rds_swap_bytes" 'BEGIN {printf "%.2f", bytes/1024/1024}')"
        fi

        rds_cpu_log="$(formatear_decimal_log "${rds_cpu:-NA}")"
        rds_memoria_mb_log="$(formatear_decimal_log "${rds_memoria_mb:-NA}")"
        rds_swap_mb_log="$(formatear_decimal_log "${rds_swap_mb:-NA}")"
        rds_cpu_credit_balance_log="$(formatear_decimal_log "${rds_cpu_credit_balance:-NA}")"
        rds_burst_balance_log="$(formatear_decimal_log "${rds_burst_balance:-NA}")"
        rds_conexiones_log="$(formatear_decimal_log "${rds_conexiones:-NA}")"

        registrar "INFO" "rds_cloudwatch" "db_instance=${RDS_DB_INSTANCE_ID} estado=${estado_rds:-desconocido} cpu_pct=${rds_cpu_log} memoria_libre_mb=${rds_memoria_mb_log} swap_mb=${rds_swap_mb_log} cpu_credit_balance=${rds_cpu_credit_balance_log} burst_balance_pct=${rds_burst_balance_log} conexiones=${rds_conexiones_log}"

        if es_numero "$rds_cpu"; then
            if mayor_igual "$rds_cpu" "$UMBRAL_RDS_CPU_PCT"; then
                condicion_rds_cpu=1
            fi

            gestionar_alerta \
                "rds_cpu" \
                "$condicion_rds_cpu" \
                "$TIEMPO_SOSTENIDO_RDS" \
                "CPU RDS alta - ${NOMBRE_SERVIDOR}" \
                "RDS ${RDS_DB_INSTANCE_ID}: CPU=${rds_cpu}% >= ${UMBRAL_RDS_CPU_PCT}%." \
                1 \
                "CPU de RDS ${RDS_DB_INSTANCE_ID} volvió a nivel normal: ${rds_cpu}%."
        else
            registrar "WARN" "rds_cloudwatch" "Sin dato válido para CPUUtilization de ${RDS_DB_INSTANCE_ID}."
        fi

        if es_numero "$rds_memoria_mb"; then
            if menor_igual "$rds_memoria_mb" "$UMBRAL_RDS_MEMORIA_LIBRE_MB"; then
                condicion_rds_memoria=1
            fi

            gestionar_alerta \
                "rds_memoria" \
                "$condicion_rds_memoria" \
                "$TIEMPO_SOSTENIDO_RDS" \
                "Memoria RDS baja - ${NOMBRE_SERVIDOR}" \
                "RDS ${RDS_DB_INSTANCE_ID}: FreeableMemory=${rds_memoria_mb} MB <= ${UMBRAL_RDS_MEMORIA_LIBRE_MB} MB." \
                1 \
                "Memoria libre de RDS ${RDS_DB_INSTANCE_ID} volvió a nivel normal: ${rds_memoria_mb} MB."
        else
            registrar "WARN" "rds_cloudwatch" "Sin dato válido para FreeableMemory de ${RDS_DB_INSTANCE_ID}."
        fi

        # SwapUsage: alerta cuando el consumo de swap supera el umbral y
        # FreeableMemory está por debajo del umbral configurado.
        # Un valor distinto de cero no es necesariamente un problema.
        if (( UMBRAL_RDS_SWAP_MB > 0 )); then
            if es_numero "$rds_swap_mb"; then
                if mayor_igual "$rds_swap_mb" "$UMBRAL_RDS_SWAP_MB" &&
                   es_numero "$rds_memoria_mb" &&
                   menor_igual "$rds_memoria_mb" "$UMBRAL_RDS_MEMORIA_LIBRE_MB"; then
                    condicion_rds_swap=1
                fi

                gestionar_alerta \
                    "rds_swap" \
                    "$condicion_rds_swap" \
                    "$TIEMPO_SOSTENIDO_RDS" \
                    "Swap RDS alto - ${NOMBRE_SERVIDOR}" \
                    "RDS ${RDS_DB_INSTANCE_ID}: SwapUsage=${rds_swap_mb} MB >= ${UMBRAL_RDS_SWAP_MB} MB; FreeableMemory=${rds_memoria_mb:-NA} MB." \
                    1 \
                    "SwapUsage de RDS ${RDS_DB_INSTANCE_ID} volvió a nivel normal: ${rds_swap_mb} MB."
            else
                registrar "WARN" "rds_cloudwatch" "Sin dato válido para SwapUsage de ${RDS_DB_INSTANCE_ID}."
            fi
        fi

        # CPUCreditBalance: solo aplica a familias burstable (db.t2/db.t3/db.t4g).
        # 0 deshabilita el umbral. Se alerta cuando el saldo cae por debajo del
        # valor configurado.
        if mayor_igual "$UMBRAL_RDS_CPU_CREDIT_BALANCE" "0.01"; then
            if es_numero "$rds_cpu_credit_balance"; then
                if menor_igual "$rds_cpu_credit_balance" "$UMBRAL_RDS_CPU_CREDIT_BALANCE"; then
                    condicion_rds_creditos_cpu=1
                fi

                gestionar_alerta \
                    "rds_cpu_creditos" \
                    "$condicion_rds_creditos_cpu" \
                    "$TIEMPO_SOSTENIDO_RDS" \
                    "Créditos CPU RDS bajos - ${NOMBRE_SERVIDOR}" \
                    "RDS ${RDS_DB_INSTANCE_ID}: CPUCreditBalance=${rds_cpu_credit_balance} <= ${UMBRAL_RDS_CPU_CREDIT_BALANCE} créditos." \
                    1 \
                    "CPUCreditBalance de RDS ${RDS_DB_INSTANCE_ID} volvió a nivel normal: ${rds_cpu_credit_balance} créditos."
            else
                registrar "WARN" "rds_cloudwatch" "Sin dato válido para CPUCreditBalance de ${RDS_DB_INSTANCE_ID}."
            fi
        fi

        # BurstBalance: porcentaje de créditos I/O del bucket gp2 disponibles.
        # 0 deshabilita el umbral.
        if mayor_igual "$UMBRAL_RDS_BURST_BALANCE_PCT" "0.01"; then
            if es_numero "$rds_burst_balance"; then
                if menor_igual "$rds_burst_balance" "$UMBRAL_RDS_BURST_BALANCE_PCT"; then
                    condicion_rds_burst=1
                fi

                gestionar_alerta \
                    "rds_burst_balance" \
                    "$condicion_rds_burst" \
                    "$TIEMPO_SOSTENIDO_RDS" \
                    "Créditos I/O RDS bajos - ${NOMBRE_SERVIDOR}" \
                    "RDS ${RDS_DB_INSTANCE_ID}: BurstBalance=${rds_burst_balance}% <= ${UMBRAL_RDS_BURST_BALANCE_PCT}%." \
                    1 \
                    "BurstBalance de RDS ${RDS_DB_INSTANCE_ID} volvió a nivel normal: ${rds_burst_balance}%."
            else
                registrar "WARN" "rds_cloudwatch" "Sin dato válido para BurstBalance de ${RDS_DB_INSTANCE_ID}."
            fi
        fi

        if (( UMBRAL_RDS_CONEXIONES > 0 )); then
            if es_numero "$rds_conexiones"; then
                if mayor_igual "$rds_conexiones" "$UMBRAL_RDS_CONEXIONES"; then
                    condicion_rds_conexiones=1
                fi

                gestionar_alerta \
                    "rds_conexiones" \
                    "$condicion_rds_conexiones" \
                    "$TIEMPO_SOSTENIDO_RDS" \
                    "Conexiones RDS altas - ${NOMBRE_SERVIDOR}" \
                    "RDS ${RDS_DB_INSTANCE_ID}: DatabaseConnections=${rds_conexiones}, umbral=${UMBRAL_RDS_CONEXIONES}." \
                    0 \
                    "DatabaseConnections de RDS ${RDS_DB_INSTANCE_ID} volvió a nivel normal: ${rds_conexiones}."
            else
                registrar "WARN" "rds_cloudwatch" "Sin dato válido para DatabaseConnections de ${RDS_DB_INSTANCE_ID}."
            fi
        fi
    fi

    if [[ -n "$EC2_INSTANCE_ID" ]]; then
        if ejecutar_aws ec2 describe-instance-status \
            --include-all-instances \
            --instance-ids "$EC2_INSTANCE_ID" \
            --query 'InstanceStatuses[0].[InstanceState.Name,SystemStatus.Status,InstanceStatus.Status]' \
            --output text; then
            estado_ec2="$AWS_SALIDA_COMANDO"
        else
            estado_ec2=""
            registrar "WARN" "aws" "operacion=DescribeInstanceStatus instance_id=${EC2_INSTANCE_ID} error=${AWS_ERROR_COMANDO:-desconocido}"
        fi

        registrar "INFO" "ec2_aws" "instance_id=${EC2_INSTANCE_ID} estado=${estado_ec2:-desconocido}"

        if [[ -z "$estado_ec2" || "$estado_ec2" == "None" ]]; then
            registrar "WARN" "aws" "No fue posible obtener instance-status de EC2 ${EC2_INSTANCE_ID}."
        else
            # Salida esperada: running<TAB>ok<TAB>ok
            if ! printf '%s\n' "$estado_ec2" | awk '($1=="running" && $2=="ok" && $3=="ok") {exit 0} {exit 1}'; then
                condicion_estado_ec2=1
            fi

            gestionar_alerta \
                "ec2_estado_aws" \
                "$condicion_estado_ec2" \
                0 \
                "Estado EC2 anómalo - ${NOMBRE_SERVIDOR}" \
                "AWS reporta para ${EC2_INSTANCE_ID}: ${estado_ec2}." \
                1 \
                "AWS vuelve a reportar EC2 ${EC2_INSTANCE_ID} como running/ok/ok."
        fi
    fi
}

###############################################################################
# Ciclo principal
###############################################################################

ejecutar_revision() {
    registrar "INFO" "monitor" "inicio_revision"

    monitorear_sistema
    monitorear_apache
    analyze_logs
    monitorear_mysql
    monitorear_aws

    registrar "INFO" "monitor" "fin_revision"
}

mostrar_ayuda() {
    cat <<'AYUDA'
Uso:
  monitor-servidor.sh --una-vez
  monitor-servidor.sh --daemon
  monitor-servidor.sh --probar-alerta
  monitor-servidor.sh --ayuda

Variables:
  ARCHIVO_CONFIG=/ruta/monitor-servidor.conf

Recomendación:
  - Use --una-vez desde CRON.
  - Use --daemon con nohup o, preferentemente, con systemd.
  - No ejecute CRON y --daemon simultáneamente; el lock evita duplicados.
AYUDA
}

main() {
    local modo="${1:---una-vez}"

    preparar_entorno

    case "$modo" in
        --una-vez)
            ejecutar_revision
            ;;
        --daemon)
            registrar "INFO" "monitor" "daemon_iniciado intervalo_s=${INTERVALO_DAEMON}"
            trap 'registrar "INFO" "monitor" "daemon_detenido"; exit 0' INT TERM

            while true; do
                ejecutar_revision
                sleep "$INTERVALO_DAEMON"
            done
            ;;
        --probar-alerta)
            enviar_pushover \
                "Prueba monitor - ${NOMBRE_SERVIDOR}" \
                "Pushover está configurado correctamente para ${NOMBRE_SERVIDOR}." \
                0
            ;;
        --ayuda|-h|--help)
            mostrar_ayuda
            ;;
        *)
            printf 'Modo desconocido: %s\n\n' "$modo" >&2
            mostrar_ayuda >&2
            exit 2
            ;;
    esac
}

main "$@"
