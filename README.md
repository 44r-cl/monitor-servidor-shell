# Monitor de servidor EC2 / Apache / MySQL-RDS

`monitor-servidor.sh` es un monitor en Bash diseñado para ejecutarse en una instancia Ubuntu sobre AWS EC2. Supervisa el sistema operativo, Apache HTTP Server, logs de múltiples VirtualHosts, MySQL/MariaDB en AWS RDS, métricas de CloudWatch y el estado AWS de EC2/RDS. Las alertas se envían mediante Pushover.

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

Contiene la configuración del monitor: nombre del servidor, thresholds, Pushover, sitios Apache, MySQL/RDS y AWS.

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
- lock de ejecución.

No elimine este directorio durante la operación normal. Hacerlo reinicia la memoria persistente del monitor.

### Primera lectura de logs Apache

Cuando el monitor encuentra un log Apache sin cursor previo, posiciona el cursor al final del archivo. Esto evita generar alertas por miles de eventos históricos existentes antes de instalar el monitor.

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

Las categorías Configuración, Recursos y Seguridad se analizan sobre `error.log`. HTTP 5xx se analiza sobre `access.log`.

Cada `sitio + categoría` mantiene su contador independiente y cada `sitio + tipo de log` mantiene su propio cursor.

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

`Slow_queries` es acumulativo; el monitor conserva el valor anterior y calcula la tasa aproximada de nuevas slow queries por minuto.

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

Las métricas de CPU, memoria, Apache, MySQL y RDS utilizan thresholds configurables. Varias condiciones requieren permanecer anómalas durante un tiempo mínimo antes de enviar una alerta.

El monitor persiste el estado para evitar que cada ejecución de CRON reinicie esa ventana.

El cooldown global habitual es:

```bash
SEGUNDOS_COOLDOWN_ALERTA=1800
```

por lo que una condición todavía activa no debe bombardear Pushover cada minuto.

Para errores Apache, las ocurrencias se acumulan por sitio y categoría. La alerta requiere que en la ejecución actual exista al menos una ocurrencia nueva y que el acumulado haya alcanzado el threshold.

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
```

Si un archivo de configuración con credenciales reales fue compartido fuera del entorno controlado, rote esas credenciales.
