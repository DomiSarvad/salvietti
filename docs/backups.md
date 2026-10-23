# Respaldos (backups) de Salvietti Control

## Qué se respalda y cuándo

Un proceso automático en GitHub (`.github/workflows/backup.yml`) hace una copia
de seguridad, sin que nadie tenga que dejar una computadora prendida:

| Qué | Cuándo | Incluye |
|---|---|---|
| Base de datos | Todos los días, 03:00 (hora de Bolivia) | Todos los datos de la app (inventario, corridas, recepciones, pedidos, mermas…), los usuarios con sus contraseñas (cifradas) y los datos de qué foto pertenece a qué registro |
| Fotos | Domingos (y cada vez que se corre a mano) | Fotos de perfil y fotos de recepciones (Supabase Storage) |

Cada copia:
- se **cifra con una contraseña** (AES-256) antes de guardarse: sin esa
  contraseña el archivo no se puede abrir, aunque alguien lo descargue;
- queda guardada **30 días** en GitHub, en la pestaña **Actions** del
  repositorio (después se borra sola);
- está **fuera de Supabase**, así que sirve aunque el problema sea con la
  cuenta o el proyecto de Supabase.

Si un respaldo falla, GitHub manda un correo a la cuenta que configuró el
proceso.

## Configuración (una sola vez)

En GitHub: repositorio → **Settings → Secrets and variables → Actions → New
repository secret**. Hay que crear cuatro secretos:

| Secreto | Qué poner | Dónde se consigue |
|---|---|---|
| `SUPABASE_DB_URL` | La cadena de conexión a la base | Supabase → botón **Connect** → **Session pooler** (no la "Direct connection": GitHub no puede usarla). Reemplazar `[YOUR-PASSWORD]` por la contraseña de la base. |
| `SUPABASE_URL` | `https://xxxx.supabase.co` | Supabase → Project Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | La clave `service_role` | Supabase → Project Settings → API. **Es secreta**: da acceso total. Nunca va en la app ni en el código, solo acá. |
| `BACKUP_PASSWORD` | Una contraseña larga inventada | **Guardarla en un lugar seguro fuera de la computadora** (ej. anotada y guardada por el Gerente). Sin ella, los respaldos no se pueden abrir. |

Después, probarlo: **Actions → Respaldo diario → Run workflow**. Tiene que
terminar en verde y dejar un archivo `salvietti_respaldo_AAAA-MM-DD` abajo, en
"Artifacts".

## Cómo restaurar

1. Descargar el respaldo: **Actions** → elegir la ejecución del día →
   "Artifacts" → descargar y descomprimir el `.zip`. Queda un archivo
   `salvietti_respaldo_AAAA-MM-DD.tar.gz.enc`.
2. Descifrarlo. **Lo más fácil**: abrir Git Bash en la carpeta del `.enc` y
   correr el script, que pide la contraseña (sin comillas ni comandos) y lo
   abre en una carpeta con el mismo nombre:

   ```bash
   bash ~/ruta/al/proyecto/scripts/backup/abrir_respaldo.sh
   ```

   Se cifra con la contraseña SIN espacios ni saltos de línea en los bordes
   (se quitan solos), y el registro de cada respaldo en Actions ("Comprimir y
   cifrar") dice cuántos caracteres tenía: si no abre, comparar con eso.
   **Ojo**: cambiar el secreto `BACKUP_PASSWORD` no cambia los respaldos ya
   hechos; esos siguen abriéndose solo con la contraseña de ese momento.

   A mano, sin el script (Linux, Mac o Git Bash):

   ```bash
   export BACKUP_PASSWORD='la contraseña'
   mkdir respaldo
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSWORD \
     -in salvietti_respaldo_AAAA-MM-DD.tar.gz.enc | tar -xzf - -C respaldo
   ```

   Queda `respaldo/base_AAAA-MM-DD.dump` (la base) y, si era domingo,
   `respaldo/storage/` con las fotos ordenadas por bucket.
3. Restaurar la base (con PostgreSQL 17 instalado, `pg_restore`):

   ```bash
   pg_restore --no-owner --no-privileges --clean --if-exists \
     --dbname "CADENA_DE_CONEXIÓN_DEL_PROYECTO_DESTINO" respaldo/base_AAAA-MM-DD.dump
   ```

   **Recomendado**: restaurar primero en un proyecto de Supabase nuevo, de
   prueba, revisar que esté todo, y recién ahí decidir. `--clean` borra lo
   que haya en el destino antes de cargar el respaldo.
   Para sacar solo una tabla (ej. recuperar un registro borrado sin pisar el
   resto): `pg_restore --data-only --table=nombre_tabla -f tabla.sql respaldo/base_....dump`
   y copiar de ahí lo que haga falta.
4. Las fotos se vuelven a subir a los mismos buckets y rutas desde
   Supabase → Storage (arrastrando las carpetas de `respaldo/storage/`).

Conviene **probar una restauración de vez en cuando** (por ejemplo, una vez
por mes en un proyecto de prueba): un respaldo que nunca se probó restaurar
no es garantía de nada.

## Límites a tener en cuenta

- GitHub da espacio limitado para estos archivos en cuentas gratuitas
  (del orden de 500 MB en repositorios privados). Por eso las fotos van solo
  los domingos. Si con el tiempo no alcanza, bajar `retention-days` en
  `backup.yml` o pasar a guardar en otro lado.
- Entre un respaldo y el siguiente pueden pasar hasta 24 horas: lo cargado
  en ese lapso se perdería si hubiera que restaurar.

## Recomendación para cuando el sistema se use en Salvietti

Este respaldo propio es una buena base mientras el sistema está en desarrollo
y pruebas. **Cuando se implemente en la empresa, se recomienda contratar el
plan Pro de Supabase** y mantener además este respaldo propio:

- El plan Pro hace copias diarias automáticas que se restauran con un clic
  desde el panel, sin pasos técnicos.
- Con el complemento *Point in Time Recovery* se puede volver la base a un
  momento exacto (ej. "ayer a las 10:32"), lo que reduce la pérdida posible de
  24 horas a minutos.
- El plan gratuito de Supabase además pausa los proyectos sin actividad, algo
  que no es aceptable para un sistema en producción.

Las dos cosas juntas cubren los dos riesgos: el plan Pro, los errores del día a
día (alguien borró algo); el respaldo propio, un problema con la cuenta de
Supabase misma.
