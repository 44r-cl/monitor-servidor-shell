# Monitor de servidor EC2 / Apache / MySQL-RDS

`monitor-servidor.sh` es un monitor en Bash diseñado para ejecutarse en una instancia Ubuntu sobre AWS EC2. Supervisa el sistema operativo, espacio e inodos de disco, crecimiento de directorios, estado de respaldos programados, Apache HTTP Server, logs de múltiples VirtualHosts, MySQL/MariaDB en AWS RDS, métricas de CloudWatch y el estado AWS de EC2/RDS. Las alertas se envían mediante Pushover.

La instalación recomendada utiliza CRON y ejecuta una revisión cada minuto con `--una-vez`. El monitor usa `flock` para evitar ejecuciones simultáneas.

## 1. Archivos del paquete

Todos los archivos deben encontrarse en el mismo directorio antes de ejecutar el instalador:

```text
monitor-servidor/
├── instalar-monitor-servidor.sh
├── monitor-servidor.sh
├── monitor-servidor.conf
└── mysql.cnf
```

### `instalar-monitor-servidor.sh`

Instala los archivos, dependencias, directorios, permisos y CRON.

### `monitor-servidor.sh`

Shell principal del monitor.

Se instala en:

```text
/usr/local/sbin/monitor-servidor.sh
```

### `monitor-servidor.conf`

Contiene la configuración del monitor: nombre del servidor, thresholds, Pushover, disco y directorios, respaldos programados, sitios Apache, MySQL/RDS y AWS.

Se instala en:

```text
/etc/monitor-servidor/monitor-servidor.conf
```

Permisos instalados:

```text
0600 root:root
```

### `mysql.cnf`

Contiene la configuración que utiliza el cliente MySQL para conectarse al RDS.

Se instala en:

```text
/etc/monitor-servidor/mysql.cnf
```

Permisos instalados:

```text
0600 root:root
```

El instalador exige que contenga una sección `[client]`.

Ejemplo:

```ini
[client]
host=df-instancia-01.xxxxxxxxx.us-east-2.rds.amazonaws.com
port=3306
user=usuario_monitor
password=CAMBIAR_POR_PASSWORD_REAL
```

No coloque la contraseña MySQL directamente en `monitor-servidor.sh` ni en la línea de comandos.

---

## 2. Requisitos

El instalador está orientado a Ubuntu 18.04 o posterior y debe ejecutarse como `root` mediante `sudo`.

El monitor utiliza, entre otros, los siguientes comandos:

- `bash`
- `curl`
- `flock`
- `ss`
- `ps`
- `mysql`
- `cron`
- `awk`
- `grep`
- `sed`
- `stat`
- `df`
- `du`
- `nice`
- `timeout`, cuando está disponible, para limitar la duración de `du`
- `ionice`, cuando está disponible, para ejecutar `du` con baja prioridad de I/O
- `systemctl`
- `aws`, cuando el monitoreo AWS está habilitado

Si faltan `curl`, `ss`, `ps`, `flock`, el cliente `mysql` o `cron`, el instalador intenta instalar los paquetes Ubuntu correspondientes mediante `apt-get`. El instalador también habilita e inicia el servicio `cron` con `systemctl`.

Si `AWS_CLI_HABILITADO=1` y no existe el comando `aws`, intenta instalar el paquete `awscli`.

Apache debe estar instalado y configurado previamente. El instalador **no instala ni modifica Apache**.

---

## 3. Instalación

Copie los cuatro archivos al mismo directorio y ejecute:

```bash
chmod +x instalar-monitor-servidor.sh
sudo ./instalar-monitor-servidor.sh
```

Antes de copiar los archivos, el instalador valida:

```bash
bash -n monitor-servidor.sh
bash -n monitor-servidor.conf
```

También comprueba que `mysql.cnf` exista y contenga una sección `[client]`.

Si ya existen archivos instalados, crea copias con un timestamp antes de reemplazarlos. Ejemplo:

```text
/etc/monitor-servidor/monitor-servidor.conf.bak-20260828-221500
```

---

## 4. Archivos y directorios instalados

Después de la instalación se utiliza esta estructura:

```text
/usr/local/sbin/monitor-servidor.sh
/etc/monitor-servidor/monitor-servidor.conf
/etc/monitor-servidor/mysql.cnf
/etc/cron.d/monitor-servidor
/var/lib/monitor-servidor/
/var/log/monitor-servidor/
/var/log/monitor-servidor/monitor.log
```

Permisos principales:

```text
/usr/local/sbin/monitor-servidor.sh        0755 root:root
/etc/monitor-servidor/                     0750 root:root
/etc/monitor-servidor/monitor-servidor.conf 0600 root:root
/etc/monitor-servidor/mysql.cnf            0600 root:root
/var/lib/monitor-servidor/                 0700 root:root
/var/log/monitor-servidor/                 0750 root:root
/var/log/monitor-servidor/monitor.log      0600 root:root
/etc/cron.d/monitor-servidor               0644 root:root
```

---

## 5. Ejecución mediante CRON

El instalador crea:

```text
/etc/cron.d/monitor-servidor
```

con una ejecución por minuto:

```cron
* * * * * root /usr/local/sbin/monitor-servidor.sh --una-vez >/dev/null 2>&1
```

El propio monitor utiliza `flock`, por lo que una segunda ejecución no continúa si todavía hay otra revisión activa.

No se recomienda ejecutar simultáneamente CRON y `--daemon`.

---

## 6. Modos de ejecución

### Una revisión

```bash
sudo /usr/local/sbin/monitor-servidor.sh --una-vez
```

Es el modo utilizado por CRON.

### Daemon

```bash
sudo /usr/local/sbin/monitor-servidor.sh --daemon
```

No utilice este modo mientras la tarea CRON esté habilitada.

### Probar Pushover

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-alerta
```

### Ayuda

```bash
sudo /usr/local/sbin/monitor-servidor.sh --ayuda
```

---

## 7. Log del monitor

El log principal se encuentra normalmente en:

```text
/var/log/monitor-servidor/monitor.log
```

Para observarlo en tiempo real:

```bash
sudo tail -f /var/log/monitor-servidor/monitor.log
```

El formato es JSON Lines. Ejemplo conceptual:

```json
{"ts":"2026-08-28T22:15:03-04:00","nivel":"INFO","evento":"sistema","host":"df-ec2","mensaje":"cpu_pct=7.78 memoria_usada_pct=4.41 load_average=0.26 0.27 0.23"}
```

Los timestamps locales utilizan ISO 8601 con offset explícito. Las consultas a CloudWatch continúan utilizando UTC.

> **Pendiente operativo:** actualmente no se ha implementado rotación para `/var/log/monitor-servidor/monitor.log`. Debe incorporarse una política de rotación (por ejemplo mediante `logrotate`) para evitar crecimiento indefinido del archivo. Esta tarea queda registrada como mejora pendiente y no forma parte de la funcionalidad de respaldos descrita aquí.

---

## 8. Estado persistente

El monitor conserva información entre ejecuciones de CRON en:

```text
/var/lib/monitor-servidor
```

Ahí se almacenan, entre otros:

- estado de alertas sostenidas;
- último envío de alertas;
- cooldown;
- contadores Apache por sitio y categoría;
- cursores de `error.log` y `access.log`;
- contador anterior de `Slow_queries` de MySQL;
- estado por ID/fingerprint de queries MySQL activas, incluyendo nivel alertado y cooldown;
- cursor de lectura del Slow Query Log en CloudWatch;
- `eventId` recientes de slow queries para evitar reprocesamiento;
- estado por fingerprint de slow queries, incluyendo repeticiones y cooldown;
- último momento de snapshot de directorios;
- snapshots históricos de tamaño de directorios;
- cooldown independiente por ruta para alertas de crecimiento;
- estado de la última anomalía de respaldo y su cooldown;
- momento desde el cual falta el archivo de estado del respaldo, cuando aplica;
- lock de ejecución.

No elimine este directorio durante la operación normal. Hacerlo reinicia la memoria persistente del monitor.

### Primera lectura de logs Apache

Cuando el monitor encuentra un log Apache sin cursor previo, posiciona el cursor al final del archivo. Esto evita generar alertas por miles de eventos históricos existentes antes de instalar el monitor.

---

## 8A. Disco, inodos y crecimiento de directorios

### Espacio e inodos

El monitoreo de filesystem se habilita con:

```bash
CHECK_ESPACIO_DISCO=true
```

Las rutas configuradas se utilizan para identificar los filesystems que deben revisarse. Si varias rutas pertenecen al mismo punto de montaje, el monitor mide ese filesystem una sola vez para evitar alertas duplicadas. La configuración actual es:

```bash
RUTAS_DISCO_MONITOREADAS=(
    "/"
    "/var/log"
    "/var/lib"
    "/var/cache"
    "/ztrabajo/www"
    "/home"
    "/tmp"
)

UMBRAL_DISCO_USO_PCT=85
UMBRAL_DISCO_INODOS_PCT=90
TIEMPO_SOSTENIDO_DISCO=120
```

Para cada filesystem el monitor registra, cuando están disponibles:

```text
filesystem
punto de montaje
tamaño total
espacio usado
espacio disponible
porcentaje de uso
porcentaje de inodos utilizados
```

El uso de espacio y el uso de inodos mantienen estados de alerta independientes. Una condición debe mantenerse durante `TIEMPO_SOSTENIDO_DISCO` antes de generar Pushover y utiliza el cooldown global de alertas. Cuando una condición previamente alertada vuelve a valores normales, puede generarse la recuperación habitual si `ALERTAR_RECUPERACION=1`.

### Crecimiento de directorios

El monitoreo histórico se habilita con:

```bash
CHECK_CRECIMIENTO_DIRECTORIOS=true
DIRECTORIO_SNAPSHOTS_DIRECTORIOS="${DIRECTORIO_ESTADO}/snapshots-directorios"
INTERVALO_SNAPSHOT_DIRECTORIOS=1800
VENTANA_CRECIMIENTO_DIRECTORIOS=86400
TOLERANCIA_SNAPSHOT_DIRECTORIOS=3600
RETENCION_SNAPSHOTS_DIRECTORIOS_DIAS=7
TIMEOUT_DU_DIRECTORIO=120
SEGUNDOS_COOLDOWN_CRECIMIENTO_DIRECTORIO=86400
```

El intervalo se mide por tiempo real y no por cantidad de ejecuciones del monitor. Con los valores actuales se crea un snapshot aproximadamente cada 30 minutos y se compara cada ruta contra el snapshot más cercano a 24 horas atrás, aceptando una diferencia máxima de una hora. Los snapshots de más de 7 días se eliminan automáticamente.

Las rutas y sus thresholds se declaran con el formato:

```text
ruta|crecimiento_porcentual|minimo_absoluto_mb
```

Configuración inicial:

```bash
RUTAS_CRECIMIENTO_DIRECTORIOS=(
    "/var/log|20|512"
    "/var/lib|20|1024"
    "/var/cache|50|512"
    "/ztrabajo/www|20|1024"
    "/home|20|1024"
    "/tmp|100|512"
)
```

Para generar una alerta deben cumplirse **simultáneamente** el porcentaje y el crecimiento absoluto configurados para esa ruta. Por ejemplo, `/var/log|20|512` requiere al menos 20% de crecimiento y al menos 512 MB adicionales dentro de la ventana histórica.

El tamaño se obtiene con `du -skx`, evitando cruzar a otros filesystems montados debajo de la ruta. El proceso se ejecuta con `nice -n 19`; si `ionice` está disponible se utiliza `ionice -c3`, y si existe `timeout` se limita cada medición a `TIMEOUT_DU_DIRECTORIO`. Un timeout o error de `du` se registra como `WARN` y esa ruta se omite en el snapshot de esa ejecución.

Cuando todavía no existe un snapshot comparable, el tamaño actual se registra pero no se genera alerta. Cada ruta tiene un cooldown independiente de `SEGUNDOS_COOLDOWN_CRECIMIENTO_DIRECTORIO`, actualmente 24 horas.

Los eventos se registran como:

```text
disco
crecimiento_directorio
```

---

## 8B. Verificación de respaldos programados

El monitor puede comprobar el resultado del respaldo ejecutado mediante:

```text
/home/aalcafuz/zrespaldos/z_crea_respaldo.sh backup
```

La verificación se basa en el archivo de estado atómico generado por ese script:

```text
/home/aalcafuz/zrespaldos/logs/ultimo_backup.estado
```

Configuración por defecto:

```bash
CHECK_RESPALDO_HABILITADO=1
ESTADO_RESPALDO_FILE="/home/aalcafuz/zrespaldos/logs/ultimo_backup.estado"
MAX_ANTIGUEDAD_RESPALDO_SEGUNDOS=93600
MAX_DURACION_RESPALDO_SEGUNDOS=7200
SEGUNDOS_COOLDOWN_RESPALDO=86400
```

`MAX_ANTIGUEDAD_RESPALDO_SEGUNDOS=93600` equivale a 26 horas y permite detectar que el respaldo diario dejó de ejecutarse o dejó de completar correctamente. `MAX_DURACION_RESPALDO_SEGUNDOS=7200` considera anómalo un respaldo que permanezca `EN_PROGRESO` durante más de 2 horas.

El monitor reconoce los estados:

```text
EN_PROGRESO
OK
ERROR
```

El comportamiento es:

- `OK` reciente: se registra como `INFO` y **no envía notificación**;
- `ERROR`: genera alerta inmediata;
- `EN_PROGRESO` dentro de la duración permitida: se registra como `INFO` y no alerta;
- `EN_PROGRESO` por más de `MAX_DURACION_RESPALDO_SEGUNDOS`: alerta como respaldo posiblemente bloqueado;
- último `OK` con antigüedad superior a `MAX_ANTIGUEDAD_RESPALDO_SEGUNDOS`: alerta como respaldo atrasado/no ejecutado;
- archivo de estado ausente: se concede inicialmente una gracia equivalente a `MAX_ANTIGUEDAD_RESPALDO_SEGUNDOS`; si continúa ausente, genera alerta;
- archivo existente pero no legible, inconsistente o con un estado desconocido: genera alerta.

Las alertas de respaldo utilizan un cooldown propio de `SEGUNDOS_COOLDOWN_RESPALDO`, actualmente 24 horas. Un mismo problema persistente no genera Pushover cada minuto. Sin embargo, un nuevo intento de respaldo con una firma distinta puede alertar inmediatamente si vuelve a fallar.

La recuperación se considera completa únicamente cuando aparece un estado `OK`. Si `ALERTAR_RECUPERACION=1` y existía una anomalía previamente alertada, ese `OK` puede generar la notificación `RECUPERADO` habitual. Un estado `EN_PROGRESO` normal no cierra prematuramente una alerta anterior.

Cada revisión registra un evento `respaldo` en:

```text
/var/log/monitor-servidor/monitor.log
```

Según el estado, el registro puede incluir:

```text
estado
antiguedad_s o transcurrido_s
duracion_s
exit_code
inicio
fin
s3_bd
s3_pgms
```

Los valores `s3_bd` y `s3_pgms` son las rutas que el script de respaldo declaró como subidas correctamente. **Esta versión del monitor no consulta S3 para verificar nuevamente la existencia de esos objetos**; esa validación remota puede incorporarse como una mejora independiente.

Las variables anteriores pueden agregarse explícitamente a `monitor-servidor.conf`. Si no están presentes, la shell utiliza los valores por defecto mostrados arriba y `--diagnostico-config` las reportará como variables que todavía no están seteadas explícitamente.

---

## 9. Apache

El monitor comprueba el servicio configurado, normalmente:

```text
apache2
```

También obtiene métricas mediante:

```text
http://127.0.0.1/server-status?auto
```

Por lo tanto, `mod_status` debe estar habilitado y el endpoint debe ser accesible localmente.

Una configuración típica es habilitar el módulo:

```bash
sudo a2enmod status
```

El acceso a `/server-status` debe restringirse al servidor local. Ejemplo conceptual de Apache:

```apache
<Location "/server-status">
    SetHandler server-status
    Require local
</Location>
```

Después de cualquier cambio Apache:

```bash
sudo apache2ctl configtest
sudo systemctl reload apache2
```

Compruebe manualmente:

```bash
curl -s 'http://127.0.0.1/server-status?auto'
```

Debe devolver campos como:

```text
BusyWorkers
IdleWorkers
ReqPerSec
CPULoad
```

`APACHE_MAX_REQUEST_WORKERS` en `monitor-servidor.conf` debe coincidir con el valor efectivo configurado en Apache.

---

## 10. Logs Apache multisitio

Los VirtualHosts se declaran en `monitor-servidor.conf` mediante:

```bash
APACHE_SITIOS_LOGS=(
    "sitio|/ruta/error.log|/ruta/access.log"
)
```

Ejemplo:

```bash
APACHE_SITIOS_LOGS=(
    "vitaticket|/var/log/apache2/vitaticket.error.log|/var/log/apache2/vitaticket.access.log"
    "otro-sitio|/var/log/apache2/otro.error.log|/var/log/apache2/otro.access.log"
)
```

Un campo puede quedar vacío:

```bash
"apache-global|/var/log/apache2/error.log|"
```

No utilice `|` dentro del nombre del sitio ni dentro de las rutas.

Las categorías Configuración, PHP / Aplicación, Recursos y Seguridad se analizan sobre `error.log`. HTTP 5xx se analiza sobre `access.log`.

La categoría **Configuración** se limita a errores propios de Apache, evitando clasificar como configuración un `PHP Parse error` que contenga el texto genérico `syntax error`. La configuración actual es:

```bash
CHECK_CONFIG_ERRORS=true
REGEX_APACHE_CONFIG_ERROR='AH00526: Syntax error|Syntax error on line [0-9]+ of /etc/apache2/|Cannot load module|Invalid command|internal redirects due to probable configuration error'
UMBRAL_APACHE_CONFIG_ERROR=1
```

La categoría **PHP / Aplicación** agrupa errores severos registrados en `error.log`:

```bash
CHECK_PHP_ERRORS=true
REGEX_APACHE_PHP_ERROR='PHP Parse error|PHP Fatal error|PHP Recoverable fatal error|Uncaught (Error|Exception)'
UMBRAL_APACHE_PHP_ERROR=1
```

`PHP Warning`, `PHP Notice` y mensajes `Deprecated` quedan fuera de esta categoría por defecto para reducir ruido. Pueden incorporarse posteriormente ajustando la expresión regular en `monitor-servidor.conf` si se desea vigilarlos.

Cada `sitio + categoría` mantiene su contador independiente y cada `sitio + tipo de log` mantiene su propio cursor. Configuración Apache y PHP / Aplicación utilizan claves de estado separadas, por lo que sus ocurrencias no se mezclan.

---

## 11. MySQL / MariaDB en RDS

La conexión utiliza:

```text
/etc/monitor-servidor/mysql.cnf
```

El usuario MySQL debería tener únicamente los permisos necesarios para consultar el estado y las variables utilizadas por el monitor.

Prueba manual de conectividad:

```bash
sudo mysql \
    --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
    --connect-timeout=5 \
    --execute='SELECT 1;'
```

El monitor consulta principalmente:

```text
Threads_connected
Threads_running
Slow_queries
Uptime
max_connections
long_query_time
information_schema.PROCESSLIST
```

`Slow_queries` es acumulativo; el monitor conserva el valor anterior y calcula la tasa aproximada de nuevas slow queries por minuto. Esta supervisión agregada se mantiene independiente del monitoreo de queries actualmente en ejecución y del análisis detallado del Slow Query Log.

### Queries MySQL actualmente en ejecución

El Slow Query Log solo permite analizar una consulta después de que termina y se publica en el log. Para detectar una query bloqueada, descontrolada o de larga duración mientras todavía está ejecutándose, el monitor consulta `information_schema.PROCESSLIST` en cada revisión.

Esta función se habilita con:

```bash
CHECK_MYSQL_QUERY_ACTIVA_HABILITADO=1
UMBRAL_MYSQL_QUERY_ACTIVA_SEGUNDOS=60
UMBRAL_MYSQL_QUERY_ACTIVA_CRITICA_SEGUNDOS=300
SEGUNDOS_COOLDOWN_MYSQL_QUERY_ACTIVA=3600
```

Se excluyen la propia conexión del monitor, las sesiones con `COMMAND='Sleep'` y las filas sin SQL activo. Para cada query sobre el umbral se registran, entre otros:

```text
ID
usuario
host
base de datos
comando
duración actual
estado
SQL
fingerprint
```

Para usuarios normales, una query se considera prolongada al alcanzar `UMBRAL_MYSQL_QUERY_ACTIVA_SEGUNDOS`, actualmente 60 segundos. Al llegar a `UMBRAL_MYSQL_QUERY_ACTIVA_CRITICA_SEGUNDOS`, actualmente 300 segundos, escala a nivel crítico y se envía una nueva alerta aunque la primera todavía esté dentro del cooldown.

Los usuarios incluidos en `MYSQL_SLOW_QUERY_USUARIOS_BACKUP`, actualmente `backup_user`, reutilizan como umbral de query activa `UMBRAL_MYSQL_SLOW_QUERY_BACKUP_SEGUNDOS`, actualmente 120 segundos. Esto evita alertar por operaciones de respaldo legítimas que suelen durar más que las consultas normales.

La alerta inicial de query prolongada usa prioridad normal de Pushover; la alerta crítica usa prioridad alta. Después de cada nivel se aplica `SEGUNDOS_COOLDOWN_MYSQL_QUERY_ACTIVA`, actualmente una hora. Cuando una query previamente alertada termina, cambia o deja de superar el umbral, puede generarse `RECUPERADO` si `ALERTAR_RECUPERACION=1`.

Como la instalación recomendada ejecuta CRON una vez por minuto, el momento real de aviso depende de la alineación entre el inicio de la consulta y la siguiente revisión. Con los valores actuales, una query normal que supera 60 segundos suele detectarse aproximadamente entre 60 y 120 segundos; para `backup_user`, entre 120 y 180 segundos.

#### Privilegio `PROCESS`

Para que la cuenta usada por `mysql.cnf` pueda ver las sesiones de otros usuarios, necesita el privilegio global `PROCESS`. Sin ese privilegio MySQL limita la visibilidad del process list y el monitor puede no observar una query problemática ejecutada por otra cuenta.

Compruebe la cuenta efectiva y sus grants:

```bash
sudo mysql \
    --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
    -e "SELECT CURRENT_USER(); SHOW GRANTS;"
```

El grant mínimo adicional para esta función es conceptualmente:

```sql
GRANT PROCESS ON *.* TO 'usuario_monitor'@'%';
```

Debe ejecutarlo una cuenta administrativa autorizada. No es necesario otorgar permisos de escritura sobre las bases de aplicación para consultar `PROCESSLIST`.

Prueba manual de visibilidad:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  --batch --skip-column-names \
  -e "SELECT ID, USER, HOST, COALESCE(DB,'-'), COMMAND, TIME, COALESCE(STATE,'-'), LEFT(COALESCE(INFO,''),200)
FROM information_schema.PROCESSLIST
WHERE ID <> CONNECTION_ID()
ORDER BY TIME DESC;"
```

### Detalle de Slow Query Log

Además del contador agregado anterior, el monitor puede leer las entradas reales del Slow Query Log de RDS exportadas a CloudWatch Logs. Esta función se habilita con:

```bash
CHECK_MYSQL_SLOW_QUERY_DETAILS=true
```

Para utilizarla, MariaDB/RDS debe tener habilitado el Slow Query Log con salida a archivo y la exportación `slowquery` hacia CloudWatch Logs. Para la configuración actual se espera conceptualmente:

```text
log_output=FILE
log_slow_query=ON
slow_query_log=ON
log_slow_query_time=2.000000
long_query_time=2.000000
```

y el log group:

```text
/aws/rds/instance/df-instancia-01/slowquery
```

La configuración utilizada por el monitor es:

```bash
MYSQL_SLOW_QUERY_LOG_GROUP="/aws/rds/instance/df-instancia-01/slowquery"
UMBRAL_MYSQL_SLOW_QUERY_REPETICION_SEGUNDOS=5
UMBRAL_MYSQL_SLOW_QUERY_ALERTA_SEGUNDOS=15
UMBRAL_MYSQL_SLOW_QUERY_REPETICIONES=3
VENTANA_MYSQL_SLOW_QUERY_REPETICIONES=600
SEGUNDOS_COOLDOWN_MYSQL_SLOW_QUERY=3600
MYSQL_SLOW_QUERY_USUARIOS_BACKUP="backup_user"
UMBRAL_MYSQL_SLOW_QUERY_BACKUP_SEGUNDOS=120
MYSQL_SLOW_QUERY_SQL_PUSHOVER_MAX_CHARS=700
CHECK_MYSQL_SLOW_QUERY_SEGURIDAD_HABILITADO=1
REGEX_MYSQL_SLOW_QUERY_SEGURIDAD='SLEEP[[:space:]]*\(|BENCHMARK[[:space:]]*\('
MYSQL_SLOW_QUERY_SOLAPAMIENTO_SEGUNDOS=86400
```

Para usuarios normales se aplican estas reglas:

- una consulta inferior a 5 segundos queda registrada, pero no suma para la alerta por repetición;
- una misma query lógica entre 5 y menos de 15 segundos alerta al alcanzar 3 ocurrencias dentro de 10 minutos;
- una consulta de 15 segundos o más puede alertar desde la primera ocurrencia;
- la misma query lógica puede enviar como máximo un Pushover por hora.

Los usuarios indicados en `MYSQL_SLOW_QUERY_USUARIOS_BACKUP`, actualmente `backup_user`, tienen tratamiento especial para las reglas normales de duración: todas sus slow queries se registran, pero solamente generan Pushover por duración si alcanzan 120 segundos o más.

### Patrones SQL sospechosos

El análisis detallado puede aplicar además una regla de seguridad independiente de los thresholds normales:

```bash
CHECK_MYSQL_SLOW_QUERY_SEGURIDAD_HABILITADO=1
REGEX_MYSQL_SLOW_QUERY_SEGURIDAD='SLEEP[[:space:]]*\(|BENCHMARK[[:space:]]*\('
```

La comparación es case-insensitive. Si el SQL contiene alguno de estos patrones de alta confianza, la entrada alerta desde la primera ocurrencia con el título `SQL sospechoso MySQL - ...` y prioridad alta, sin esperar las 3 repeticiones, los 15 segundos del umbral normal ni los 120 segundos reservados a `backup_user`.

Esta regla está diseñada para detectar rápidamente payloads de temporización como `SLEEP(...)` o `BENCHMARK(...)` que pueden aparecer en intentos de SQL injection. No sustituye el uso de consultas parametrizadas, validación de entrada ni otras medidas preventivas de la aplicación.

El Slow Query Log continúa teniendo una limitación fundamental: una consulta aparece allí cuando termina. Por eso esta regla complementa, pero no reemplaza, el monitoreo de `PROCESSLIST`; una query maliciosa que siga ejecutándose durante minutos u horas debe ser detectada primero por `mysql_query_activa`.

El monitor extrae de cada entrada, cuando están disponibles:

```text
timestamp
usuario
host/IP
base de datos
Query_time
Lock_time
Rows_sent
Rows_examined
SQL
```

El SQL se normaliza para generar un fingerprint. Literales de texto y valores numéricos se sustituyen conceptualmente por marcadores antes de calcular el hash, por lo que consultas equivalentes con IDs o valores diferentes pueden compartir el mismo estado de repetición y cooldown.

El SQL completo procesado se registra en `monitor.log`. Pushover recibe como máximo `MYSQL_SLOW_QUERY_SQL_PUSHOVER_MAX_CHARS` caracteres del SQL para limitar el tamaño de la notificación.

### Lectura incremental de CloudWatch Logs

La primera vez que se habilita esta función, el monitor inicializa el cursor en el momento actual y **no procesa el historial anterior**. En las siguientes ejecuciones reconsulta una ventana anterior de 24 horas (`MYSQL_SLOW_QUERY_SOLAPAMIENTO_SEGUNDOS=86400`) para absorber entradas que RDS/CloudWatch publique con retraso, incluso si la consulta terminó muchas horas después de haber comenzado.

Cada entrada de CloudWatch se identifica mediante su `eventId`. Los IDs ya procesados se conservan temporalmente en el estado persistente, por lo que ampliar el solapamiento a 24 horas no hace que la misma slow query se registre o alerte repetidamente.

Prueba manual del log group actual:

```bash
sudo -H aws logs filter-log-events \
    --log-group-name "/aws/rds/instance/df-instancia-01/slowquery" \
    --limit 10 \
    --profile agente-control-monitoring \
    --region us-east-2
```

---

## 12. AWS CLI, EC2, RDS y CloudWatch

Cuando:

```bash
AWS_CLI_HABILITADO=1
```

el comando `aws` debe estar disponible en el `PATH`.

El monitor soporta:

```bash
AWS_PROFILE="nombre-del-perfil"
AWS_REGION="us-east-2"
RDS_DB_INSTANCE_ID="identificador-rds"
EC2_INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"
```

`RDS_DB_INSTANCE_ID` debe ser el **DBInstanceIdentifier**, no el endpoint DNS de RDS.

### Importante sobre CRON y `AWS_PROFILE`

El CRON instalado ejecuta el monitor como `root`. Si se utiliza un perfil AWS, ese perfil debe estar disponible en el contexto de `root`.

Ejemplo de comprobación:

```bash
sudo aws --profile nombre-del-perfil --region us-east-2 sts get-caller-identity
```

El instalador **no copia, genera ni modifica credenciales AWS**.

Para EC2 es preferible utilizar un IAM Role cuando la arquitectura lo permita. Si se conserva `AWS_PROFILE`, asegúrese de que el perfil exista para el usuario que ejecuta el monitor.

### Permisos AWS mínimos utilizados por el monitor

El código invoca estas operaciones:

```text
cloudwatch:GetMetricStatistics
rds:DescribeDBInstances
ec2:DescribeInstanceStatus
logs:FilterLogEvents
```

Una política de referencia es:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "rds:DescribeDBInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:FilterLogEvents"
      ],
      "Resource": "arn:aws:logs:us-east-2:ID_CUENTA:log-group:/aws/rds/instance/df-instancia-01/slowquery"
    }
  ]
}
```

Adapte la política a las normas de seguridad de su cuenta AWS.

---

## 13. Métricas CloudWatch RDS

Se consultan métricas como:

```text
CPUUtilization
FreeableMemory
SwapUsage
CPUCreditBalance
BurstBalance
DatabaseConnections
```

Los thresholds se definen en `monitor-servidor.conf`.

`SwapUsage` se correlaciona con `FreeableMemory`; un valor de swap por sí solo no significa necesariamente presión activa de memoria.

`CPUCreditBalance` aplica a familias RDS burstable como T2/T3/T4g. El umbral actual es:

```bash
UMBRAL_RDS_CPU_CREDIT_BALANCE=50
SEGUNDOS_COOLDOWN_RDS_CPU_CREDITOS=21600
```

La primera alerta continúa respetando `TIEMPO_SOSTENIDO_RDS`. Si el saldo permanece bajo, `SEGUNDOS_COOLDOWN_RDS_CPU_CREDITOS=21600` limita las repeticiones de esta condición a una cada 6 horas, en lugar de usar el cooldown global de 30 minutos. La recuperación sigue notificándose cuando el saldo vuelve a un nivel normal.

Para la familia T3, un cambio entre `db.t3.medium` y `db.t3.small` no requiere por sí solo modificar este umbral: ambas clases utilizan 2 vCPU, obtienen 24 créditos de CPU por hora y tienen una utilización base de 20% por vCPU. Por ello se mantiene inicialmente el valor `50` y se recomienda evaluar la tendencia del saldo después del cambio de clase.

Interpretación práctica:

- si `CPUCreditBalance` se recupera progresivamente, la instancia vuelve a acumular reserva de CPU;
- si permanece durante periodos prolongados cerca del umbral, la carga consume una parte importante de los créditos que se generan;
- si la tendencia continúa hacia `0`, la instancia tiene poca reserva para burst y conviene revisar la carga o el dimensionamiento.

En instancias T3 también resulta útil observar `CPUSurplusCreditBalance` y `CPUSurplusCreditsCharged`, especialmente si el saldo llega a cero, porque permiten identificar uso de créditos excedentes y posibles cargos asociados. Estas métricas complementarias no forman parte actualmente de las alertas de `monitor-servidor.sh`.

`BurstBalance` es relevante para almacenamiento que expone créditos de I/O, como gp2.

---

## 14. Pushover

Configure en `monitor-servidor.conf`:

```bash
USER_KEY="..."
API_TOKEN="..."
PUSHOVER_HABILITADO=1
SEGUNDOS_COOLDOWN_ALERTA=1800
ALERTAR_RECUPERACION=1
```

Después de instalar, pruebe explícitamente:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-alerta
```

Las credenciales Pushover son secretos. Mantenga `monitor-servidor.conf` con permisos `0600` y no publique ese archivo en repositorios ni lo distribuya sin eliminar los secretos.

---

## 15. Thresholds y cooldown

Las métricas de CPU, memoria, espacio de disco, inodos, Apache, MySQL y RDS utilizan thresholds configurables. Varias condiciones requieren permanecer anómalas durante un tiempo mínimo antes de enviar una alerta.

El monitor persiste el estado para evitar que cada ejecución de CRON reinicie esa ventana.

El cooldown global habitual es:

```bash
SEGUNDOS_COOLDOWN_ALERTA=1800
```

por lo que una condición todavía activa no debe bombardear Pushover cada minuto.

`CPUCreditBalance` de RDS utiliza un cooldown independiente:

```bash
SEGUNDOS_COOLDOWN_RDS_CPU_CREDITOS=21600
```

Con la configuración actual, una condición persistente de créditos CPU bajos puede repetirse como máximo cada 6 horas. Este cooldown no altera la primera alerta ni la notificación de recuperación, y no modifica el comportamiento de las demás alertas que continúan usando `SEGUNDOS_COOLDOWN_ALERTA`.

Para errores Apache, las ocurrencias se acumulan por sitio y categoría. La alerta requiere que en la ejecución actual exista al menos una ocurrencia nueva y que el acumulado haya alcanzado el threshold.

El crecimiento de directorios utiliza un cooldown independiente por ruta:

```bash
SEGUNDOS_COOLDOWN_CRECIMIENTO_DIRECTORIO=86400
```

Por lo tanto, una misma ruta puede enviar como máximo una alerta de crecimiento cada 24 horas con la configuración actual.

Los respaldos programados utilizan un cooldown independiente:

```bash
SEGUNDOS_COOLDOWN_RESPALDO=86400
```

Un mismo problema persistente puede volver a notificarse después de 24 horas. Un nuevo intento de respaldo que falle se considera un evento distinto y puede alertar inmediatamente. Los estados `OK` normales solo se registran; no generan Pushover salvo la recuperación de una anomalía previamente alertada.

Las queries MySQL actualmente en ejecución utilizan un cooldown independiente:

```bash
SEGUNDOS_COOLDOWN_MYSQL_QUERY_ACTIVA=3600
```

El estado se mantiene por conexión activa. Una query puede alertar al superar el umbral normal y volver a alertar inmediatamente si escala al umbral crítico de 300 segundos; después se aplica el cooldown propio. Cuando la query termina o deja de superar el umbral, su estado se elimina y puede generarse recuperación.

Las slow queries detalladas utilizan otro cooldown independiente:

```bash
SEGUNDOS_COOLDOWN_MYSQL_SLOW_QUERY=3600
```

Este cooldown se aplica por fingerprint, por lo que una query lógica ya alertada no vuelve a enviar Pushover durante una hora aunque reaparezca. Otras queries con fingerprint diferente pueden alertar de forma independiente. Una coincidencia con `REGEX_MYSQL_SLOW_QUERY_SEGURIDAD` conserva este cooldown por fingerprint, pero no necesita cumplir los thresholds normales de duración o repetición para generar su primera alerta.

---

## 16. Verificación posterior a la instalación

### 1. Sintaxis

```bash
sudo bash -n /usr/local/sbin/monitor-servidor.sh
```

No debe producir salida ni error.

### 2. Pushover

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-alerta
```

### 3. Revisión manual

```bash
sudo /usr/local/sbin/monitor-servidor.sh --una-vez
```

### 4. Log

```bash
sudo tail -n 100 /var/log/monitor-servidor/monitor.log
```

### 5. CRON

```bash
sudo cat /etc/cron.d/monitor-servidor
```

Después de algunos minutos debe observarse una secuencia de eventos `inicio_revision` y `fin_revision` en el log.

### 6. Disco y crecimiento de directorios

Compruebe las mediciones de filesystem:

```bash
sudo grep '"evento":"disco"' /var/log/monitor-servidor/monitor.log | tail -20
```

Los snapshots de crecimiento no se ejecutan cada minuto. Después de alcanzar `INTERVALO_SNAPSHOT_DIRECTORIOS`, compruebe:

```bash
sudo grep '"evento":"crecimiento_directorio"' /var/log/monitor-servidor/monitor.log | tail -20
sudo ls -lh /var/lib/monitor-servidor/snapshots-directorios/
```

### 7. Estado del respaldo

Compruebe primero el archivo producido por `z_crea_respaldo.sh`:

```bash
sudo cat /home/aalcafuz/zrespaldos/logs/ultimo_backup.estado
```

Luego ejecute una revisión y consulte los eventos del monitor:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --una-vez
sudo grep '"evento":"respaldo"' /var/log/monitor-servidor/monitor.log | tail -20
```

Un respaldo sano debe mostrar `estado=OK` sin generar Pushover.

### 8. Queries MySQL activas

Compruebe primero que la cuenta del monitor pueda ver sesiones de otros usuarios:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  --batch --skip-column-names \
  -e "SELECT ID,USER,HOST,COMMAND,TIME,STATE,INFO
FROM information_schema.PROCESSLIST
WHERE ID <> CONNECTION_ID()
ORDER BY TIME DESC;"
```

Para una prueba controlada con la cuenta `backup_user`, puede mantener una consulta inofensiva durante más tiempo que su umbral de 120 segundos:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  -e "SELECT SLEEP(200);"
```

En otra consola observe:

```bash
sudo tail -f /var/log/monitor-servidor/monitor.log \
  | grep --line-buffered -E 'mysql_query_activa|mysql_slow_query|pushover'
```

Con CRON cada minuto, `backup_user` debería generar `Query MySQL Backup activa prolongada` cuando alguna revisión la observe sobre 120 segundos, normalmente entre 120 y 180 segundos desde el inicio. Al terminar debería generarse la recuperación. Como `SLEEP(...)` coincide además con la regla de SQL sospechoso, después de que RDS publique la entrada en el Slow Query Log puede aparecer una segunda alerta independiente con el título `SQL sospechoso MySQL - ...`.

---

## 17. Diagnóstico rápido

### `cliente_mysql=no_instalado`

Compruebe:

```bash
command -v mysql
```

En Ubuntu puede instalarse con:

```bash
sudo apt-get install default-mysql-client
```

### `archivo_mysql_cnf=no_legible`

Compruebe:

```bash
sudo ls -l /etc/monitor-servidor/mysql.cnf
sudo chmod 600 /etc/monitor-servidor/mysql.cnf
sudo chown root:root /etc/monitor-servidor/mysql.cnf
```

### `server_status=no_disponible`

Pruebe:

```bash
curl -v 'http://127.0.0.1/server-status?auto'
```

Revise `mod_status`, las reglas `Require` y `APACHE_HOST_HEADER` si el endpoint depende de un VirtualHost concreto.

### Eventos `disco` con `ruta=... estado=no_existe`

Compruebe que las rutas declaradas en `RUTAS_DISCO_MONITOREADAS` existan en ese servidor. Las rutas inexistentes se registran como `WARN` y se omiten.

### Eventos `crecimiento_directorio` con `estado=timeout` o `du_error`

Compruebe manualmente el tamaño de la ruta afectada y el tiempo que tarda `du`:

```bash
sudo time du -skx -- /ruta/a/revisar
```

Si el directorio es muy grande, revise `TIMEOUT_DU_DIRECTORIO` antes de aumentarlo. El objetivo es evitar que una medición pesada bloquee una ejecución completa del monitor.

### Eventos `respaldo` con `estado=ERROR`

Revise el log propio del script de respaldo y el archivo de estado:

```bash
sudo tail -n 100 /home/aalcafuz/zrespaldos/logs/backup_s3.log
sudo cat /home/aalcafuz/zrespaldos/logs/ultimo_backup.estado
```

El `exit_code`, inicio, fin y duración registrados ayudan a identificar el intento que falló.

### Eventos `respaldo` con `resultado=ATRASADO`

El último `OK` supera `MAX_ANTIGUEDAD_RESPALDO_SEGUNDOS`. Compruebe que el CRON de `z_crea_respaldo.sh backup` siga instalado y ejecutándose en el horario esperado.

### Eventos `respaldo` con `resultado=EXCEDIDO`

El archivo continúa en `EN_PROGRESO` durante más de `MAX_DURACION_RESPALDO_SEGUNDOS`. Revise si siguen activos `mysqldump`, `tar`, `aws s3 cp` o el propio `z_crea_respaldo.sh` antes de finalizar procesos manualmente.

### Eventos `respaldo` con `estado=SIN_ESTADO`, `NO_LEGIBLE` o `INVALIDO`

Compruebe existencia, permisos y contenido:

```bash
sudo ls -l /home/aalcafuz/zrespaldos/logs/ultimo_backup.estado
sudo cat /home/aalcafuz/zrespaldos/logs/ultimo_backup.estado
```

`SIN_ESTADO` no alerta inmediatamente en una instalación nueva: el monitor concede la ventana configurada por `MAX_ANTIGUEDAD_RESPALDO_SEGUNDOS` antes de considerarlo una anomalía.

### `aws_cli=no_instalado`

Compruebe:

```bash
command -v aws
aws --version
```

### Errores `AccessDenied` o `UnauthorizedOperation`

Valide el perfil/rol, la región y los permisos IAM.

Si utiliza perfil:

```bash
sudo aws --profile nombre-del-perfil --region us-east-2 sts get-caller-identity
```

### `mysql_query_activa` con `processlist=no_disponible` o sin visibilidad de otras sesiones

Pruebe directamente `information_schema.PROCESSLIST` con la misma cuenta del monitor:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  --batch --skip-column-names \
  -e "SELECT ID,USER,HOST,COMMAND,TIME,STATE,INFO
FROM information_schema.PROCESSLIST
WHERE ID <> CONNECTION_ID()
ORDER BY TIME DESC;"
```

Si el comando falla, revise conectividad, `mysql.cnf` y permisos. Si funciona pero solo permite ver las propias sesiones, compruebe `SHOW GRANTS` y que la cuenta tenga el privilegio global `PROCESS`.

### `mysql_slow_query` con `cloudwatch=no_disponible`

Compruebe directamente el acceso al Slow Query Log:

```bash
sudo -H aws logs filter-log-events \
    --log-group-name "/aws/rds/instance/df-instancia-01/slowquery" \
    --limit 1 \
    --profile agente-control-monitoring \
    --region us-east-2
```

El principal permiso requerido por el monitor para esta función es `logs:FilterLogEvents` sobre ese log group.

### El CRON parece no ejecutar

Compruebe:

```bash
sudo cat /etc/cron.d/monitor-servidor
sudo systemctl status cron
sudo grep -E 'inicio_revision|fin_revision' /var/log/monitor-servidor/monitor.log | tail
```

---

## 18. Reinstalación y actualización

Para actualizar la shell o la configuración:

1. coloque las nuevas versiones de `monitor-servidor.sh`, `monitor-servidor.conf` y `mysql.cnf` junto al instalador;
2. vuelva a ejecutar:

```bash
sudo ./instalar-monitor-servidor.sh
```

Los archivos existentes se respaldan antes de ser reemplazados.

El directorio persistente:

```text
/var/lib/monitor-servidor
```

no se elimina durante una reinstalación, por lo que se conservan cursores, cooldowns y contadores.

---

## 19. Desinstalación manual

Detenga primero la ejecución periódica:

```bash
sudo rm -f /etc/cron.d/monitor-servidor
```

Luego puede retirar programa y configuración:

```bash
sudo rm -f /usr/local/sbin/monitor-servidor.sh
sudo rm -rf /etc/monitor-servidor
```

El estado y los logs se dejan separados deliberadamente para evitar una pérdida accidental de información. Si desea eliminarlos definitivamente:

```bash
sudo rm -rf /var/lib/monitor-servidor
sudo rm -rf /var/log/monitor-servidor
```

Esta última operación elimina cursores, contadores, historial de alertas y logs del monitor.

---

## 20. Seguridad

No registre ni publique:

- password MySQL;
- AWS Access Key;
- AWS Secret Key;
- Pushover `USER_KEY`;
- Pushover `API_TOKEN`.

Mantenga al menos:

```text
/etc/monitor-servidor/monitor-servidor.conf 0600 root:root
/etc/monitor-servidor/mysql.cnf             0600 root:root
/var/log/monitor-servidor/monitor.log       0600 root:root
```

El monitoreo de queries MySQL activas y el análisis detallado de slow queries registran el SQL completo en `monitor.log`. Una consulta puede contener datos de aplicación o literales sensibles, por lo que ese archivo debe tratarse como información protegida y no debe publicarse ni copiarse a ubicaciones de acceso amplio. Pushover recibe una versión limitada por `MYSQL_SLOW_QUERY_SQL_PUSHOVER_MAX_CHARS`.

Si un archivo de configuración con credenciales reales fue compartido fuera del entorno controlado, rote esas credenciales.

## 21. Cheat sheet operativo

Comandos de referencia rápida para ejecutar directamente en `df-ec2`. Están pensados para diagnóstico y verificación manual, evitan imprimir secretos y no sustituyen las secciones anteriores.

### Monitor

Ejecutar una revisión completa manual:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --una-vez
```

Probar Pushover desde el propio monitor:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-alerta
```

Probar ntfy:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-ntfy
```

Diagnosticar variables faltantes del `.conf`:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --diagnostico-config
```

Ver ayuda:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --ayuda
```

Validar sintaxis:

```bash
sudo bash -n /usr/local/sbin/monitor-servidor.sh
echo "exit=$?"
```

Ejecutar ShellCheck:

```bash
sudo shellcheck -s bash -f gcc /usr/local/sbin/monitor-servidor.sh
echo "exit=$?"
```

Ver SHA-256 de la versión instalada:

```bash
sudo sha256sum /usr/local/sbin/monitor-servidor.sh
```

Contar líneas:

```bash
sudo wc -l /usr/local/sbin/monitor-servidor.sh
```

Comprobar que existe la detección de queries activas:

```bash
sudo grep -n 'monitorear_mysql_queries_activas' \
  /usr/local/sbin/monitor-servidor.sh
```

Comprobar las variables nuevas:

```bash
sudo grep -nE \
'CHECK_MYSQL_QUERY_ACTIVA_HABILITADO|UMBRAL_MYSQL_QUERY_ACTIVA_SEGUNDOS|UMBRAL_MYSQL_QUERY_ACTIVA_CRITICA_SEGUNDOS|SEGUNDOS_COOLDOWN_MYSQL_QUERY_ACTIVA|CHECK_MYSQL_SLOW_QUERY_SEGURIDAD_HABILITADO|REGEX_MYSQL_SLOW_QUERY_SEGURIDAD|MYSQL_SLOW_QUERY_SOLAPAMIENTO_SEGUNDOS|SEGUNDOS_COOLDOWN_RDS_CPU_CREDITOS' \
/usr/local/sbin/monitor-servidor.sh
```

Comprobar las variables explícitas en configuración:

```bash
sudo grep -E \
'^(CHECK_MYSQL_QUERY_ACTIVA_HABILITADO|UMBRAL_MYSQL_QUERY_ACTIVA_SEGUNDOS|UMBRAL_MYSQL_QUERY_ACTIVA_CRITICA_SEGUNDOS|SEGUNDOS_COOLDOWN_MYSQL_QUERY_ACTIVA|CHECK_MYSQL_SLOW_QUERY_SEGURIDAD_HABILITADO|REGEX_MYSQL_SLOW_QUERY_SEGURIDAD|MYSQL_SLOW_QUERY_SOLAPAMIENTO_SEGUNDOS|SEGUNDOS_COOLDOWN_RDS_CPU_CREDITOS)=' \
/etc/monitor-servidor/monitor-servidor.conf
```

### Logs del monitor

Seguir el log completo:

```bash
sudo tail -f /var/log/monitor-servidor/monitor.log
```

Ver ciclos recientes:

```bash
sudo grep -E \
'"evento":"monitor".*(inicio_revision|fin_revision)' \
/var/log/monitor-servidor/monitor.log \
| tail -50
```

Ver Pushover:

```bash
sudo grep '"evento":"pushover"' \
/var/log/monitor-servidor/monitor.log \
| tail -50
```

Seguir queries activas y Pushover en tiempo real:

```bash
sudo tail -f /var/log/monitor-servidor/monitor.log \
  | grep --line-buffered -E 'mysql_query_activa|mysql_slow_query|pushover'
```

Ver últimas queries activas detectadas:

```bash
sudo grep '"evento":"mysql_query_activa"' \
/var/log/monitor-servidor/monitor.log \
| tail -30
```

Ver slow queries:

```bash
sudo grep '"evento":"mysql_slow_query"' \
/var/log/monitor-servidor/monitor.log \
| tail -30
```

Ver métricas RDS registradas:

```bash
sudo grep '"evento":"rds_cloudwatch"' \
/var/log/monitor-servidor/monitor.log \
| tail -30
```

Ver eventos de respaldo:

```bash
sudo grep '"evento":"respaldo"' \
/var/log/monitor-servidor/monitor.log \
| tail -30
```

Buscar errores y warnings recientes:

```bash
sudo grep -E '"nivel":"(ERROR|WARN)"' \
/var/log/monitor-servidor/monitor.log \
| tail -50
```

### CRON

Ver CRON de root:

```bash
sudo crontab -l
```

Buscar específicamente el monitor:

```bash
sudo crontab -l | grep monitor-servidor
```

Comprobar si existe además `/etc/cron.d/monitor-servidor`:

```bash
sudo cat /etc/cron.d/monitor-servidor
```

Detectar posibles programaciones duplicadas:

```bash
sudo grep -R "monitor-servidor.sh" \
  /etc/cron.d /etc/crontab /var/spool/cron/crontabs 2>/dev/null
```

Estado de cron:

```bash
sudo systemctl status cron
```

### MySQL: conectividad

Prueba mínima:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  -e "SELECT 1;"
```

Ver usuario efectivo:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  -e "SELECT USER(), CURRENT_USER();"
```

Ver grants:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  -e "SHOW GRANTS;"
```

### MySQL: PROCESSLIST

Ver todo lo que el usuario configurado puede observar:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  --batch --skip-column-names \
  -e "
SELECT
    ID,
    USER,
    HOST,
    COALESCE(DB,'-'),
    COMMAND,
    TIME,
    COALESCE(STATE,'-'),
    LEFT(COALESCE(INFO,''),200)
FROM information_schema.PROCESSLIST
WHERE ID <> CONNECTION_ID()
ORDER BY TIME DESC;
"
```

Ver solamente queries realmente activas:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  --batch --skip-column-names \
  -e "
SELECT
    ID,
    USER,
    HOST,
    COALESCE(DB,'-'),
    COMMAND,
    TIME,
    COALESCE(STATE,'-'),
    LEFT(INFO,500)
FROM information_schema.PROCESSLIST
WHERE ID <> CONNECTION_ID()
  AND COMMAND <> 'Sleep'
  AND INFO IS NOT NULL
ORDER BY TIME DESC;
"
```

Ver queries activas con más de 60 segundos:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  --batch --skip-column-names \
  -e "
SELECT
    ID,
    USER,
    HOST,
    COALESCE(DB,'-'),
    TIME,
    COALESCE(STATE,'-'),
    LEFT(INFO,500)
FROM information_schema.PROCESSLIST
WHERE ID <> CONNECTION_ID()
  AND COMMAND <> 'Sleep'
  AND INFO IS NOT NULL
  AND TIME >= 60
ORDER BY TIME DESC;
"
```

### Prueba controlada de query activa

La prueba que se validó como más fiable para el umbral de `backup_user` (ver sección 15):

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  -e "SELECT SLEEP(200);"
```

Mientras corre, observar desde otra terminal:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  --batch --skip-column-names \
  -e "
SELECT
    ID,
    USER,
    HOST,
    COMMAND,
    TIME,
    STATE,
    INFO
FROM information_schema.PROCESSLIST
WHERE COMMAND <> 'Sleep'
  AND INFO IS NOT NULL
  AND ID <> CONNECTION_ID()
ORDER BY TIME DESC;
"
```

Y simultáneamente:

```bash
sudo tail -f /var/log/monitor-servidor/monitor.log \
  | grep --line-buffered -E 'mysql_query_activa|pushover'
```

Para `backup_user`, `SLEEP(200)` es una prueba mucho más fiable que `SLEEP(130)` porque el umbral es de 120 segundos y CRON muestrea cada minuto: `SLEEP(130)` solo deja 10 segundos de margen por encima del umbral.

### Estado MySQL

Ver conexiones, threads, slow queries y uptime:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  -e "
SHOW GLOBAL STATUS
WHERE Variable_name IN (
    'Threads_connected',
    'Threads_running',
    'Slow_queries',
    'Uptime'
);
"
```

Ver configuración relevante:

```bash
sudo mysql \
  --defaults-extra-file=/etc/monitor-servidor/mysql.cnf \
  -e "
SHOW GLOBAL VARIABLES
WHERE Variable_name IN (
    'max_connections',
    'long_query_time',
    'slow_query_log',
    'log_output',
    'general_log'
);
"
```

### AWS: identidad y configuración

Ver identidad AWS efectiva:

```bash
sudo -H aws sts get-caller-identity \
  --profile agente-control-monitoring \
  --region us-east-2
```

Ver versión AWS CLI:

```bash
sudo -H aws --version
```

### AWS RDS

Estado general de la instancia:

```bash
sudo -H aws rds describe-db-instances \
  --db-instance-identifier df-instancia-01 \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,Engine,EngineVersion,Endpoint.Address]' \
  --output table
```

Ver solo la clase:

```bash
sudo -H aws rds describe-db-instances \
  --db-instance-identifier df-instancia-01 \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --query 'DBInstances[0].DBInstanceClass' \
  --output text
```

Ver exportaciones de logs habilitadas:

```bash
sudo -H aws rds describe-db-instances \
  --db-instance-identifier df-instancia-01 \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --query 'DBInstances[0].EnabledCloudwatchLogsExports' \
  --output table
```

### CloudWatch: CPU de RDS

Última hora:

```bash
sudo -H aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=df-instancia-01 \
  --start-time "$(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average Maximum \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --output table
```

Últimas 24 horas:

```bash
sudo -H aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=df-instancia-01 \
  --start-time "$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average Maximum \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --output table
```

### CloudWatch: CPUCreditBalance

```bash
sudo -H aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUCreditBalance \
  --dimensions Name=DBInstanceIdentifier,Value=df-instancia-01 \
  --start-time "$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average Minimum Maximum \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --output table
```

Ver solamente el punto más reciente:

```bash
sudo -H aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUCreditBalance \
  --dimensions Name=DBInstanceIdentifier,Value=df-instancia-01 \
  --start-time "$(date -u -d '30 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --query 'Datapoints | sort_by(@,&Timestamp)[-1]' \
  --output table
```

### CloudWatch: memoria RDS

```bash
sudo -H aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value=df-instancia-01 \
  --start-time "$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average Minimum Maximum \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --output table
```

### CloudWatch: conexiones RDS

```bash
sudo -H aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=df-instancia-01 \
  --start-time "$(date -u -d '6 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --period 300 \
  --statistics Average Maximum \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --output table
```

### Slow Query Log en CloudWatch

Ver eventos recientes:

```bash
sudo -H aws logs filter-log-events \
  --log-group-name "/aws/rds/instance/df-instancia-01/slowquery" \
  --limit 20 \
  --profile agente-control-monitoring \
  --region us-east-2
```

Buscar `SLEEP`:

```bash
sudo -H aws logs filter-log-events \
  --log-group-name "/aws/rds/instance/df-instancia-01/slowquery" \
  --filter-pattern "SLEEP" \
  --limit 50 \
  --profile agente-control-monitoring \
  --region us-east-2
```

Buscar `BENCHMARK`:

```bash
sudo -H aws logs filter-log-events \
  --log-group-name "/aws/rds/instance/df-instancia-01/slowquery" \
  --filter-pattern "BENCHMARK" \
  --limit 50 \
  --profile agente-control-monitoring \
  --region us-east-2
```

### EC2 en AWS

Estado AWS de la instancia:

```bash
sudo -H aws ec2 describe-instance-status \
  --include-all-instances \
  --instance-ids i-0502108d733ea74c3 \
  --profile agente-control-monitoring \
  --region us-east-2 \
  --output table
```

### Apache

Estado:

```bash
sudo systemctl status apache2
```

Configuración:

```bash
sudo apache2ctl configtest
```

Server-status:

```bash
curl -s 'http://127.0.0.1/server-status?auto'
```

Workers relevantes:

```bash
curl -s 'http://127.0.0.1/server-status?auto' \
  | grep -E 'BusyWorkers|IdleWorkers|ReqPerSec|CPULoad'
```

Procesos Apache:

```bash
ps -eo pid,ppid,user,%cpu,%mem,etime,cmd \
  | grep '[a]pache2'
```

Conexiones HTTP/HTTPS establecidas:

```bash
sudo ss -Htan state established \
  '( sport = :80 or sport = :443 )'
```

Contarlas:

```bash
sudo ss -Htan state established \
  '( sport = :80 or sport = :443 )' \
  | wc -l
```

### Logs Apache por sitio

Sustituya `<vhost>` por el nombre real del VirtualHost (por ejemplo `vitaticket` o `vitacuracorporacioncultural`) y `<ruta>` por la ruta de la aplicación a inspeccionar.

Últimas peticiones a una ruta concreta:

```bash
sudo grep '<ruta>' \
  /var/log/apache2/<vhost>.cl-access.log \
  | tail -100
```

Solo POST:

```bash
sudo grep '"POST <ruta>' \
  /var/log/apache2/<vhost>.cl-access.log \
  | tail -100
```

Contar IPs que hicieron POST a esa ruta:

```bash
sudo grep '"POST <ruta>' \
  /var/log/apache2/<vhost>.cl-access.log \
  | awk '{print $1}' \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -30
```

Buscar errores PHP recientes:

```bash
sudo grep -Ei \
'PHP (Fatal|Parse|Recoverable)|Uncaught (Error|Exception)' \
/var/log/apache2/<vhost>.cl-error.log \
| tail -100
```

### Búsqueda de código PHP ante sospecha de SQL injection

Patrón genérico para localizar concatenaciones de variables HTTP en el código de la aplicación afectada. Sustituya `<ruta-aplicacion>` por la ruta real del código a revisar y `<campo1>|<campo2>|...` por los nombres de columnas/parámetros involucrados en el incidente concreto.

Buscar concatenaciones relevantes:

```bash
grep -RIn \
  -E '<campo1>|<campo2>|<campo3>' \
  <ruta-aplicacion>/
```

Buscar uso directo de variables HTTP sin sanitizar:

```bash
grep -RIn \
  -E '\$_(GET|POST|REQUEST)' \
  <ruta-aplicacion>/
```

No documente aquí rutas ni nombres de campos de incidentes reales; regístrelos en el sistema de seguimiento de incidentes correspondiente, no en este README.

### Pushover

Validar usuario/dispositivo sin mostrar las credenciales:

```bash
sudo bash -c '
source /etc/monitor-servidor/monitor-servidor.conf

curl --silent --show-error --fail \
  --data-urlencode "token=${API_TOKEN}" \
  --data-urlencode "user=${USER_KEY}" \
  https://api.pushover.net/1/users/validate.json

echo
'
```

Enviar prueba directa:

```bash
sudo bash -c '
source /etc/monitor-servidor/monitor-servidor.conf

curl --silent --show-error --fail \
  --request POST \
  --data-urlencode "token=${API_TOKEN}" \
  --data-urlencode "user=${USER_KEY}" \
  --data-urlencode "title=PRUEBA DIRECTA df-ec2" \
  --data-urlencode "message=Prueba directa desde df-ec2" \
  --data-urlencode "priority=1" \
  https://api.pushover.net/1/messages.json

echo
'
```

### Backup

Ver estado actual:

```bash
sudo cat /home/aalcafuz/zrespaldos/logs/ultimo_backup.estado
```

Log reciente:

```bash
sudo tail -100 /home/aalcafuz/zrespaldos/logs/backup_s3.log
```

Ver procesos relacionados con backup:

```bash
ps -ef \
  | grep -E '[z]_crea_respaldo|[m]ysqldump|[t]ar|[a]ws s3'
```

### Sistema

CPU y carga:

```bash
uptime
```

```bash
top
```

Memoria:

```bash
free -h
```

Discos:

```bash
df -h
```

Inodos:

```bash
df -ih
```

Procesos por CPU:

```bash
ps -eo pid,user,%cpu,%mem,etime,cmd \
  --sort=-%cpu \
  | head -30
```

Procesos por RAM:

```bash
ps -eo pid,user,%cpu,%mem,etime,cmd \
  --sort=-%mem \
  | head -30
```

### Comparación antes de desplegar

Sintaxis:

```bash
bash -n monitor-servidor.sh
```

ShellCheck:

```bash
shellcheck -s bash -f gcc monitor-servidor.sh
```

Diff contra la copia previa:

```bash
diff -u \
  monitor-servidor-anterior.sh \
  monitor-servidor.sh
```

Hashes:

```bash
sha256sum \
  monitor-servidor-anterior.sh \
  monitor-servidor.sh
```

Líneas:

```bash
wc -l \
  monitor-servidor-anterior.sh \
  monitor-servidor.sh
```

Comparar repositorio local contra producción sin modificar nada:

```bash
sudo diff -u \
  /usr/local/sbin/monitor-servidor.sh \
  ./monitor-servidor.sh
```
