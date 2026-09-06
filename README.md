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

Requiere `sudo`: `monitor-servidor.conf` tiene permisos `0600 root:root`, y sin privilegios de lectura el comando no puede acceder a `USER_KEY`/`API_TOKEN`. Este modo imprime en pantalla si la notificación se envió o no, junto con la causa del fallo cuando corresponde (config no legible, Pushover deshabilitado, credenciales vacías, etc.). Prueba Pushover en aislamiento real: si `NTFY_HABILITADO=1`, este modo desactiva el respaldo solo para esta prueba puntual, para que un ntfy.sh funcional no enmascare un fallo real de Pushover.

### Probar ntfy.sh (respaldo)

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-ntfy
```

Envía una notificación de prueba directamente por ntfy.sh (ver [sección 14B](#14b-respaldo-de-notificaciones-con-ntfysh)), sin pasar por Pushover ni depender de que Pushover falle de verdad.

### Probar cambio de horario (dry run)

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-cambio-horario
```

Ejecuta los mismos 3 chequeos que la verificación real (sistema, PHP vía Apache, MySQL — ver [sección 15A](#15a-verificación-puntual-de-cambio-de-horario-dst)), pero **sin depender de `FECHA_CAMBIO_HORARIO` ni tocar el estado persistente**: es seguro correrlo cualquier día, incluso repetidamente, sin riesgo de marcar el evento real como ya procesado. Sirve para validar *antes* del cambio que las tres fuentes son alcanzables y devuelven un formato parseable.

Como todavía no ocurrió el cambio, es normal que el offset actual no coincida con `OFFSET_CAMBIO_HORARIO_ESPERADO`; el comando lo aclara explícitamente. Lo que sí debe cumplirse hoy es que **las tres fuentes coincidan entre sí** (mismo offset entre sistema, PHP y MySQL) — si no coinciden, hay algo que corregir antes de confiar en la verificación real de esta noche. Si `PUSHOVER_HABILITADO=1`, además envía una notificación de prueba con el título `PRUEBA cambio de horario - ...`, para no confundirla con el resultado real.

### Diagnóstico de configuración

```bash
sudo /usr/local/sbin/monitor-servidor.sh --diagnostico-config
```

Cada variable que el script reconoce está declarada internamente como `VAR="${VAR:-valor_por_defecto}"`. Este modo enumera esas variables comparándolas contra lo que está explícitamente seteado en `monitor-servidor.conf`, y las muestra **agrupadas por área funcional**, en este orden:

1. Pushover
2. ntfy.sh (respaldo)
3. Heartbeat externo
4. Estado y ejecución
5. Linux / EC2
6. Disco y crecimiento de directorios
7. Apache
8. SSH: fuerza bruta
9. Certificados TLS
10. MySQL / RDS
11. AWS CLI / CloudWatch
12. Cambio de horario (DST)
13. Otras (variables futuras que todavía no fueron agregadas a la categorización)

Son las mismas áreas que organiza `monitor-servidor.conf.sample`. Un grupo sin ninguna variable asociada (por ejemplo "Otras", mientras no haga falta) no se muestra. Dentro de cada grupo, cada variable aparece con su valor real (`= valor`) si está configurada explícitamente, o marcada `(valor por defecto: ...)` si está corriendo silenciosamente con el valor embebido en el script, sin una decisión explícita del administrador.

`USER_KEY`, `API_TOKEN`, `HEALTHCHECKS_URL`, `NTFY_URL` y `NTFY_TOKEN` se muestran enmascarados (solo los primeros caracteres, ej. `abcd...`) porque son secretos: lo suficiente para confirmar visualmente que el valor cargado es el esperado, sin exponerlo completo si la salida se comparte por accidente (un ticket, un chat, una captura de pantalla).

Use este comando después de actualizar `monitor-servidor.sh` (por ejemplo tras un `git pull`) para detectar de inmediato si una funcionalidad nueva quedó a medio configurar, en vez de descubrirlo por un aviso de Pushover que nunca llegó o un `WARN` en el log días después. Termina con código de salida `1` si encuentra alguna variable sin setear, útil para incorporarlo a un chequeo posterior a un despliegue.

Limitaciones conocidas:

- Solo cubre variables escalares (`VAR="${VAR:-...}"`); no audita arreglos como `APACHE_SITIOS_LOGS`, `SITIOS_TLS` o `RUTAS_DISCO_MONITOREADAS`.
- No sabe qué variables son relevantes según qué funcionalidades tiene habilitadas: si `CHECK_TLS_HABILITADO=0`, seguirá listando `UMBRAL_TLS_DIAS_RESTANTES` aunque no importe. Es una ayuda para revisar, no un validador estricto.
- El agrupamiento por categoría (`categoria_de_variable()` en `monitor-servidor.sh`) es una lista curada a mano; una variable nueva que no se agregue ahí cae en "Otras" sin romper nada, pero conviene mantenerla al día junto con cada funcionalidad nueva.

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
- fecha ya verificada del cambio de horario (DST), para no repetir la verificación hasta el próximo evento;
- cursor de lectura de `auth.log` y acumulador de fallos SSH con cooldown por IP;
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

### Comportamiento cuando `server-status` no responde

Las conexiones TCP establecidas hacia 80/443 se miden con `ss` y no dependen de `mod_status`. Por eso la alerta de conexiones altas (`apache_conexiones`) se sigue evaluando y notificando —incluida su recuperación— aunque `server-status` no responda.

La saturación de workers (`apache_saturacion`) sí depende de `BusyWorkers`, un dato que solo entrega `server-status`. Si el endpoint deja de responder, esa alerta queda en su último estado conocido hasta que vuelva a responder: no se genera una nueva notificación ni su recuperación mientras tanto, porque no hay forma de saber si la saturación se mantuvo, se resolvió o empeoró. Esa falta de datos queda señalizada de forma independiente por la alerta `apache_status`, que se activa mientras el endpoint esté inaccesible.

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

## 10A. SSH: intentos de fuerza bruta

Fuera de los logs de Apache, el monitor no tenía visibilidad de intentos de acceso al propio host. Esta función cuenta las líneas `Failed password` de `auth.log`, agrupadas por IP origen, para detectar fuerza bruta contra SSH.

Se habilita con:

```bash
CHECK_SSH_AUTH_HABILITADO=1
SSH_AUTH_LOG="/var/log/auth.log"
UMBRAL_SSH_FALLOS_IP=5
VENTANA_SSH_FALLOS_IP_SEGUNDOS=600
SEGUNDOS_COOLDOWN_SSH_FALLOS_IP=3600
```

El conteo es **por IP**, no un total global: 50 fallos repartidos entre 50 usuarios que se equivocaron de contraseña es ruido, mientras que 5 fallos desde una sola IP en 10 minutos es un patrón de ataque. Cuando una misma IP acumula `UMBRAL_SSH_FALLOS_IP` fallos dentro de `VENTANA_SSH_FALLOS_IP_SEGUNDOS`, se envía un Pushover con la IP, la cantidad de intentos y hasta 3 nombres de usuario distintos probados. Esa IP respeta además un cooldown independiente (`SEGUNDOS_COOLDOWN_SSH_FALLOS_IP`): mientras el ataque siga activo, no se manda más de una alerta por hora para la misma IP.

Si no hay actividad nueva dentro de la ventana configurada, el contador de esa IP se reinicia en la siguiente ocurrencia; no se acumula indefinidamente a lo largo de días.

El cursor de lectura sigue el mismo mecanismo que los logs Apache: la primera vez que se encuentra `auth.log` sin cursor previo, se posiciona al final del archivo para no generar una alerta con el historial completo ya existente.

Esta función es **solo de visibilidad, no bloquea IPs**. Si además se quiere banear automáticamente a los atacantes, use `fail2ban` (herramienta dedicada a eso) en paralelo; este monitor no reimplementa esa funcionalidad.

---

## 10B. Vencimiento de certificados TLS

Certbot puede fallar en silencio de varias formas: su timer se desactiva, el hook post-renovación no recarga Apache y el sitio sigue sirviendo el certificado viejo, la validación HTTP-01 se rompe por un cambio de config o de DNS, o se agotan los rate limits de Let's Encrypt. Esta verificación es independiente de certbot: mide directamente cuántos días le quedan al certificado que Apache **realmente está sirviendo**.

Se habilita con:

```bash
CHECK_TLS_HABILITADO=1
SITIOS_TLS=(
    "vitaticket.cl"
    "vitacuracorporacioncultural.cl"
    "www.defacto.cl"
)
UMBRAL_TLS_DIAS_RESTANTES=14
TLS_TIMEOUT_SEGUNDOS=10
SEGUNDOS_COOLDOWN_TLS=86400
```

### Por qué se conecta a `127.0.0.1`, no al hostname público

El chequeo hace `openssl s_client -connect 127.0.0.1:443 -servername <sitio>`, usando SNI para seleccionar el vhost en vez de resolver `<sitio>` por DNS pública. Dos razones:

1. **Detecta un hook de recarga que falló.** Si certbot renovó el certificado en disco pero el `--deploy-hook` que recarga Apache no corrió, el archivo en disco está al día pero Apache sigue sirviendo el certificado viejo. Leer el archivo directamente no vería el problema; conectarse de verdad sí.
2. **No depende de que el DNS público siga apuntando a este servidor.** Si se resolviera `<sitio>` por DNS, un cambio de nameservers o de IP haría que el chequeo evalúe el certificado de otro servidor, no el de este. Conectando siempre a `127.0.0.1` se evalúa exactamente lo que este Apache presenta ahora mismo, sin ese intermediario.

Nota: si un dominio ya no se sirve desde este servidor pero su entrada sigue en `SITIOS_TLS`, esto seguiría evaluando el vhost local (si todavía existe) — no detecta por sí solo que un dominio "se mudó" a otro servidor; para eso haría falta un chequeo de resolución DNS aparte, que queda fuera del alcance de esta función.

### Mecánica

Reutiliza `gestionar_alerta()` — el mismo mecanismo que CPU, memoria y disco — en vez de un acumulador propio, porque "días restantes por debajo de un umbral" es exactamente ese patrón: una métrica que sube y baja, con alerta y recuperación. Esto tiene una ventaja concreta: cuando el certificado vuelve a tener vigencia normal (una renovación real, con recarga de Apache incluida), se envía un Pushover de recuperación — es la confirmación positiva de que el problema se resolvió de punta a punta, no solo que certbot corrió.

Se alerta de inmediato (sin esperar un tiempo sostenido) apenas los días restantes caen a `UMBRAL_TLS_DIAS_RESTANTES` o menos, ya que es una métrica que no fluctúa de un minuto a otro. Si `openssl` no logra conectar o no puede parsear el certificado, se trata como la misma condición de alerta: "no se pudo verificar" es tan accionable como "vence pronto".

`SEGUNDOS_COOLDOWN_TLS` es independiente del cooldown global (`SEGUNDOS_COOLDOWN_ALERTA`) y bastante más largo (24 horas por defecto): re-notificar cada 30 minutos durante dos semanas seguidas sería puro ruido. En cambio, un recordatorio diario mientras el problema siga sin resolverse evita que se pierda entre otras notificaciones, a diferencia de un aviso único de certbot que puede pasar desapercibido.

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
FreeStorageSpace
SwapUsage
CPUCreditBalance
BurstBalance
DatabaseConnections
```

Los thresholds se definen en `monitor-servidor.conf`.

`SwapUsage` se correlaciona con `FreeableMemory`; un valor de swap por sí solo no significa necesariamente presión activa de memoria.

`FreeStorageSpace` (`UMBRAL_RDS_STORAGE_LIBRE_MB`) alerta cuando el espacio en disco libre de la instancia cae por debajo del umbral. Sin espacio, RDS puede pasar a modo de solo lectura o caerse — a diferencia de espacio en disco del EC2 (sección 8A), este no se resuelve liberando archivos locales, requiere aumentar el storage asignado a la instancia (o habilitar/ajustar el auto-scaling de storage de RDS).

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

### Ícono de la aplicación Pushover

La carpeta `imagenes/` contiene el ícono usado en la aplicación Pushover asociada a `API_TOKEN` (`monitor-servidor.png`, `monitor-servidor.jpeg` y `monitor-servidor-128x128.png`). Súbalo al configurar o editar la aplicación en el panel de Pushover; no lo utiliza el script en tiempo de ejecución.

---

## 14A. Heartbeat externo ("dead man's switch")

Todas las alertas anteriores dependen de que el propio host esté vivo y de que el monitor se siga ejecutando. Si el servidor se cae por completo, se congela, o el daemon/CRON dejan de ejecutar el monitor, no hay quién dispare Pushover para avisarlo.

Para cubrir ese caso, el monitor puede enviar un ping de heartbeat a un servicio externo tipo [Healthchecks.io](https://healthchecks.io) al final de cada revisión exitosa. Ese servicio, no el propio host, es quien detecta la ausencia de pings y notifica.

Se habilita con:

```bash
HEALTHCHECKS_HABILITADO=1
HEALTHCHECKS_URL="https://hc-ping.com/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
HEALTHCHECKS_TIMEOUT=10
```

Configuración recomendada del lado de Healthchecks.io:

- período de chequeo igual a la cadencia de CRON (1 minuto);
- un margen de gracia razonable para absorber una revisión puntualmente lenta;
- la notificación (Pushover, email, etc.) se configura en Healthchecks.io, no en este monitor.

El ping se envía siempre al final de `ejecutar_revision()`, sin importar si algún check anterior generó una alerta. Su único propósito es certificar que el monitor completó un ciclo; no reemplaza ni depende del resto de las alertas. Un fallo aislado al enviarlo solo se registra como `WARN` en `monitor.log`: no se reintenta, porque la garantía real la aporta el servicio externo al notificar la ausencia de pings, no un reintento local.

`HEALTHCHECKS_URL` actúa como secreto y debe tratarse igual que las credenciales de Pushover o MySQL.

---

## 14B. Respaldo de notificaciones con ntfy.sh

Pushover puede fallar sin que nadie se entere: `enviar_notificacion()` ya reintenta (`INTENTOS_PUSHOVER`) y deja un `ERROR` en `monitor.log` si todos los intentos fallan, pero eso solo se ve si alguien está mirando el log en ese momento. Como Pushover es el único canal de salida, una falla suya (API caída, credenciales revocadas, egress bloqueado hacia ese dominio específico) degrada en silencio **todas** las alertas del monitor a "una línea de log", sin ninguna señal externa.

[ntfy.sh](https://ntfy.sh) sirve como respaldo para ese caso puntual. Se habilita con:

```bash
NTFY_HABILITADO=1
NTFY_URL="https://ntfy.sh/un-topico-largo-y-aleatorio"
NTFY_TOKEN=""
NTFY_TIMEOUT=15
```

### Cuándo se usa

Solo cuando Pushover está habilitado (`PUSHOVER_HABILITADO=1`) pero falla genuinamente: credenciales faltantes, o agotó sus `INTENTOS_PUSHOVER` reintentos. **No** se envía en paralelo con cada notificación normal, y **no** se usa como sustituto si Pushover está deshabilitado a propósito (`PUSHOVER_HABILITADO=0`) — eso es una decisión del administrador, no una falla, y redirigir todo en silencio a otro canal sería sorpresivo.

Cuando el respaldo se usa, queda un `WARN` explícito en el log (`"Pushover falló tras N intentos; ntfy.sh se usó como respaldo"`), y si **ambos** canales fallan, un `ERROR` distinto (`"Pushover y ntfy.sh (si estaba habilitado) fallaron ambos"`) — ese sí es el peor caso real: nadie se enteró de nada por ningún canal.

`NTFY_URL` es la URL completa, tópico incluido: funciona igual con el ntfy.sh público que con una instancia propia self-hosted (en cuyo caso `NTFY_TOKEN` permite autenticarse con `Authorization: Bearer`). En el ntfy.sh público, cualquiera que adivine el nombre del tópico puede leer las notificaciones ahí publicadas o publicar mensajes falsos — use un nombre largo y aleatorio, no algo predecible como `monitor-df-ec2`. Trátelo con el mismo cuidado que `HEALTHCHECKS_URL`.

### Probar el respaldo de forma aislada

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-ntfy
```

Envía una notificación de prueba directamente por ntfy.sh, sin pasar por Pushover ni depender de que Pushover falle de verdad. Es el análogo de `--probar-alerta` para este canal. A su vez, `--probar-alerta` desactiva el respaldo de ntfy.sh solo durante esa prueba puntual, para que un fallo real de Pushover no quede enmascarado por un ntfy.sh que sí funciona.

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

### Snapshot de diagnóstico en alertas de CPU/memoria

```bash
DIAGNOSTICO_PROCESOS_HABILITADO=1
DIAGNOSTICO_PROCESOS_CANTIDAD=5
```

Cuando `UMBRAL_CPU_SISTEMA_PCT` o `UMBRAL_MEMORIA_SISTEMA_PCT` se superan, el monitor captura el top de procesos (`pid`, usuario, `%cpu`, `%mem` y nombre del binario) ordenado por la métrica que se disparó, y lo agrega tanto al mensaje de Pushover como a un evento `WARN` en `monitor.log`. El objetivo es evitar tener que entrar por SSH a investigar qué proceso causó el pico, que para cuando se investigue puede que ya haya pasado.

Se registra en cada ejecución donde la condición esté activa, no solo cuando efectivamente se envía Pushover, de modo que el snapshot enviado sea siempre el más cercano posible al momento real del envío.

Solo se incluye el nombre del binario (`comm`), no la línea de comando completa, para no exponer posibles secretos pasados como argumentos a algún proceso.

---

## 15A. Verificación puntual de cambio de horario (DST)

Chile cambia de huso horario dos veces al año, en fechas fijadas por decreto (no siempre coinciden con la regla "de libro" que trae `tzdata`). Esta verificación confirma que, tras el cambio, sistema operativo, PHP (vía Apache) y MySQL/RDS reflejen el nuevo offset UTC — evitando tener que entrar por SSH a comprobarlo manualmente.

Se habilita con:

```bash
CHECK_CAMBIO_HORARIO_HABILITADO=1
FECHA_CAMBIO_HORARIO="2026-09-06 00:00:00"
OFFSET_ANTES_CAMBIO_HORARIO="-04:00"
OFFSET_CAMBIO_HORARIO_ESPERADO="-03:00"
CAMBIO_HORARIO_PHP_URL="https://www.defacto.cl/monitor-servidor/hora.php"
VENTANA_CAMBIO_HORARIO_SEGUNDOS=3600
```

### `OFFSET_ANTES_CAMBIO_HORARIO`: por qué es obligatorio en un adelanto de reloj

En un adelanto de reloj, el instante configurado en `FECHA_CAMBIO_HORARIO` (típicamente `00:00:00`) es una hora local que **nunca llega a existir**: el reloj salta directo de las 00:00:00 a las 01:00:00. Si el propio host ya corre en esa zona horaria, `date -d "2026-09-06 00:00:00"` la rechaza como fecha inválida, porque no hay forma de ubicar ese instante en la línea de tiempo local sin más contexto — y el monitor lo registra como:

```text
WARN ... [cambio_horario] fecha_invalida=2026-09-06 00:00:00
```

`OFFSET_ANTES_CAMBIO_HORARIO` resuelve la ambigüedad ancorando la fecha al offset que regía justo antes del cambio (`date -d "2026-09-06 00:00:00 -04:00"`), en vez de dejar que `date` intente adivinarlo con la zona horaria vigente del sistema en ese momento. Para el cambio a horario de invierno (retraso de reloj) esto no es estrictamente necesario porque ahí no hay hueco, solo hora duplicada, pero configurarlo siempre evita tener que recordar en qué caso hace falta.

### Mecánica

En cada ejecución de CRON, si ya pasó `FECHA_CAMBIO_HORARIO` (interpretada según se explica arriba) y esa fecha exacta todavía no fue marcada como procesada:

1. **Sistema operativo**: compara `date +%:z` contra `OFFSET_CAMBIO_HORARIO_ESPERADO`.
2. **PHP vía Apache**: hace `curl` a `CAMBIO_HORARIO_PHP_URL`, que debe devolver texto plano con el formato `AAAA-mm-dd HH:MM:SS|+HH:MM` (ver más abajo el contenido de `hora.php`), y compara el segundo campo.
3. **MySQL/RDS**: ejecuta `SELECT TIMESTAMPDIFF(MINUTE, UTC_TIMESTAMP(), NOW());` usando `mysql.cnf`, y convierte la diferencia en minutos a formato `+HH:MM`/`-HH:MM` para compararla. Se calcula por diferencia contra `UTC_TIMESTAMP()` en vez de leer `@@time_zone`, para no depender de si esa variable devuelve un nombre de zona (`America/Santiago`) o un offset numérico.

Si los tres coinciden con `OFFSET_CAMBIO_HORARIO_ESPERADO`, se envía un Pushover de éxito y esa fecha queda marcada como procesada en `/var/lib/monitor-servidor/cambio_horario.estado`: la verificación no se repite hasta que se configure una `FECHA_CAMBIO_HORARIO` distinta (el próximo cambio, típicamente el del año siguiente). Si algo falla, se reintenta en cada ciclo de CRON hasta agotar `VENTANA_CAMBIO_HORARIO_SEGUNDOS` desde `FECHA_CAMBIO_HORARIO`; al agotarse esa ventana sin éxito total, se envía un Pushover de fallo con el detalle de qué chequeo no coincidió, y también se marca como procesada para no reintentar indefinidamente.

Antes de que llegue `FECHA_CAMBIO_HORARIO` la función no hace nada ni deja rastro en el log; no genera ruido mientras espera.

Para validar conectividad y formato de las 3 fuentes antes del cambio real, sin esperar la fecha ni arriesgar el estado persistente, use `--probar-cambio-horario` (ver [sección 6](#6-modos-de-ejecución)).

### Página PHP de referencia

Debe existir en el docroot del sitio, por ejemplo:

```text
/ztrabajo/www/prod/zsitios/defacto.cl/monitor-servidor/hora.php
```

Con este contenido:

```php
<?php
declare(strict_types=1);

function obtenerOffsetChile(): string
{
    $zonaHoraria = new DateTimeZone('America/Santiago');
    $fechaActual = new DateTime('now', $zonaHoraria);

    return $fechaActual->format('P');
}

$zonaHoraria = new DateTimeZone('America/Santiago');
$fechaActual = new DateTime('now', $zonaHoraria);

header('Content-Type: text/plain; charset=utf-8');
printf("%s|%s\n", $fechaActual->format('Y-m-d H:i:s'), obtenerOffsetChile());
```

Esta página no la instala ni la gestiona `instalar-monitor-servidor.sh`; debe copiarse manualmente al servidor.

### Para el próximo cambio de horario

Basta con actualizar en `monitor-servidor.conf`:

```bash
FECHA_CAMBIO_HORARIO="<fecha y hora local del próximo cambio>"
OFFSET_ANTES_CAMBIO_HORARIO="<offset vigente justo antes, ej. -03:00 antes del retraso a horario de invierno>"
OFFSET_CAMBIO_HORARIO_ESPERADO="<nuevo offset esperado, ej. -04:00 para el cambio a horario de invierno>"
```

Al ser distinta de la fecha ya marcada como procesada, la verificación se rearma automáticamente sin tocar `CHECK_CAMBIO_HORARIO_HABILITADO` ni ningún otro archivo.

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

### Evento `heartbeat` con `WARN`

Compruebe manualmente el ping:

```bash
curl -v "https://hc-ping.com/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Revise conectividad de salida hacia Healthchecks.io, `HEALTHCHECKS_URL` en `monitor-servidor.conf` y `HEALTHCHECKS_HABILITADO=1`. Un fallo aislado no es crítico: el propio Healthchecks.io notificará si los pings dejan de llegar dentro del período configurado ahí.

### Evento `cambio_horario` con `fecha_invalida=...`

`FECHA_CAMBIO_HORARIO` cae en una hora local que no existe (típico en un adelanto de reloj, ej. `00:00:00` cuando el reloj salta directo a la `01:00:00`) y `date -d` no puede resolverla sin ayuda. Configure `OFFSET_ANTES_CAMBIO_HORARIO` con el offset vigente justo antes del cambio (ver [sección 15A](#15a-verificación-puntual-de-cambio-de-horario-dst)). Puede validar la corrección con:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --probar-cambio-horario
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

**Nota importante:** el instalador reemplaza `monitor-servidor.conf` por completo; no fusiona variables nuevas con la configuración existente. Si en vez de usar el instalador se actualiza `monitor-servidor.conf` a mano (copiando bloques nuevos desde `monitor-servidor.conf.sample`), corra después:

```bash
sudo /usr/local/sbin/monitor-servidor.sh --diagnostico-config
```

para confirmar que ninguna variable de una funcionalidad nueva quedó sin setear.

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
