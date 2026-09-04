# Monitor de servidor EC2 / Apache / MySQL-RDS

`monitor-servidor.sh` es un monitor en Bash diseñado para ejecutarse en una instancia Ubuntu sobre AWS EC2. Supervisa el sistema operativo, espacio e inodos de disco, crecimiento de directorios, Apache HTTP Server, logs de múltiples VirtualHosts, MySQL/MariaDB en AWS RDS, métricas de CloudWatch y el estado AWS de EC2/RDS. Las alertas se envían mediante Pushover.

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

Contiene la configuración del monitor: nombre del servidor, thresholds, Pushover, disco y directorios, sitios Apache, MySQL/RDS y AWS.

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
- cursor de lectura del Slow Query Log en CloudWatch;
- `eventId` recientes de slow queries para evitar reprocesamiento;
- estado por fingerprint de slow queries, incluyendo repeticiones y cooldown;
- último momento de snapshot de directorios;
- snapshots históricos de tamaño de directorios;
- cooldown independiente por ruta para alertas de crecimiento;
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
```

`Slow_queries` es acumulativo; el monitor conserva el valor anterior y calcula la tasa aproximada de nuevas slow queries por minuto. Esta supervisión agregada existente se mantiene independiente del análisis detallado descrito a continuación.

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
MYSQL_SLOW_QUERY_SOLAPAMIENTO_SEGUNDOS=3600
```

Para usuarios normales se aplican estas reglas:

- una consulta inferior a 5 segundos queda registrada, pero no suma para la alerta por repetición;
- una misma query lógica entre 5 y menos de 15 segundos alerta al alcanzar 3 ocurrencias dentro de 10 minutos;
- una consulta de 15 segundos o más puede alertar desde la primera ocurrencia;
- la misma query lógica puede enviar como máximo un Pushover por hora.

Los usuarios indicados en `MYSQL_SLOW_QUERY_USUARIOS_BACKUP`, actualmente `backup_user`, tienen tratamiento especial: todas sus slow queries se registran, pero solamente generan Pushover si alcanzan 120 segundos o más.

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

La primera vez que se habilita esta función, el monitor inicializa el cursor en el momento actual y **no procesa el historial anterior**. En las siguientes ejecuciones reconsulta una ventana anterior de una hora para absorber posibles retrasos de ingestión desde RDS.

Cada entrada de CloudWatch se identifica mediante su `eventId`. Los IDs ya procesados se conservan temporalmente en el estado persistente, por lo que el solapamiento no hace que la misma slow query se registre o alerte repetidamente.

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

`CPUCreditBalance` aplica a familias RDS burstable como T2/T3/T4g.

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

Para errores Apache, las ocurrencias se acumulan por sitio y categoría. La alerta requiere que en la ejecución actual exista al menos una ocurrencia nueva y que el acumulado haya alcanzado el threshold.

El crecimiento de directorios utiliza un cooldown independiente por ruta:

```bash
SEGUNDOS_COOLDOWN_CRECIMIENTO_DIRECTORIO=86400
```

Por lo tanto, una misma ruta puede enviar como máximo una alerta de crecimiento cada 24 horas con la configuración actual.

Las slow queries detalladas utilizan un cooldown independiente:

```bash
SEGUNDOS_COOLDOWN_MYSQL_SLOW_QUERY=3600
```

Este cooldown se aplica por fingerprint, por lo que una query lógica ya alertada no vuelve a enviar Pushover durante una hora aunque reaparezca. Otras queries con fingerprint diferente pueden alertar de forma independiente.

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

El monitoreo detallado de slow queries registra el SQL completo en `monitor.log`. Una consulta puede contener datos de aplicación o literales sensibles, por lo que ese archivo debe tratarse como información protegida y no debe publicarse ni copiarse a ubicaciones de acceso amplio.

Si un archivo de configuración con credenciales reales fue compartido fuera del entorno controlado, rote esas credenciales.
