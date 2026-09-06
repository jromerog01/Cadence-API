# Cadence — Servicio de transcripción de audio autoalojado

## Contexto

Se quiere una aplicación web propia para subir audio desde cualquier lugar, transcribirlo en un servidor personal, ver el avance en tiempo real, elegir el modelo de transcripción y exportar el resultado en varios formatos. Hoy no hay código: solo un documento de diseño previo (`plan-transcriptor-audio.md`) y dos paquetes de diseño de interfaz ya generados.

Este plan actualiza el documento previo con tres decisiones que ya no están abiertas:

1. **El servidor es conocido** — HP ProDesk 600 G3 DM: Intel i7-7700T (4 núcleos / 8 hilos, Kaby Lake), 16 GB DDR4, disco HGST de 1 TB (mecánico, 930 GB ext4), sin GPU NVIDIA. Esto fija el techo del selector de modelos, que era el punto abierto del plan anterior.
2. **El frontend no se escribe de cero** — se reutiliza `disenoFrontend.zip`: una app Next.js 16 / React 19 / Tailwind v4 / shadcn ya construida para este producto ("Cadence"), con pantalla de subida, biblioteca, menú de exportación y selector de usuario, hoy alimentada con datos falsos. El trabajo de frontend es sustituir los mocks por un cliente de API real, no diseñar pantallas. Esto **anula** la elección de React + Vite del plan previo.
3. **Solo motores locales** — Whisper corriendo en el servidor. Sin APIs de terceros, sin costo por uso, sin audio saliendo de la máquina.

Alcance v1 confirmado: lo básico (subida, cola, progreso, modelos, exportación, acceso remoto) más **login/multiusuario** y **diarización**, ambas explícitamente secundarias: si se complican, se cortan sin bloquear el resto. Por eso van al final del plan y el esquema de datos las deja preparadas desde el primer día.

Resultado esperado: `docker compose up` en el ProDesk, acceso autenticado por HTTPS desde el móvil, y una transcripción de una hora de audio lista en unos minutos.

---

## 1. Lo que impone el hardware

El i7-7700T es un chip de 35 W de 2017: 4 núcleos, AVX2 (que sí acelera CTranslate2), sin AVX-512. Con `faster-whisper` en int8 y 4 hilos, los factores frente a la duración del audio son aproximadamente:

| Modelo | RAM | Factor vs. duración | Papel en la interfaz |
|---|---|---|---|
| `tiny` | ~0.5 GB | ~0.1× | borradores, pruebas |
| `base` | ~0.7 GB | ~0.2× | notas de voz cortas |
| `small` | ~1.2 GB | ~0.6× | **defecto rápido** |
| `medium` | ~2.5 GB | ~2× | calidad media |
| `large-v3-turbo` | ~1.8 GB | ~1.5× | **defecto de calidad** |
| `large-v3` | ~3.5 GB | ~5× | máxima calidad, audio difícil |

`large-v3-turbo` es la pieza clave en esta máquina: calidad muy cercana a `large-v3` a un tercio del costo, y multilingüe (a diferencia de los `distil-*`, que son solo inglés). Una hora de audio con turbo son ~90 minutos de CPU; con `large-v3`, ~5 horas.

Consecuencias que atraviesan todo el diseño:

- **Un solo worker, concurrencia 1.** Dos transcripciones simultáneas con modelos grandes compiten por los 4 núcleos y no terminan antes; solo se arriesga un OOM.
- **`cpu_threads=4`** en el motor (no 8: los hilos lógicos de HyperThreading no ayudan en cargas de matrices densas y suelen empeorar el rendimiento).
- **El disco es mecánico.** Cargar `large-v3` desde disco frío toma decenas de segundos. El modelo se cachea en memoria del worker entre trabajos y los pesos viven en un volumen persistente para no re-descargarlos en cada `docker compose up`.
- **Los números de la tabla son estimaciones.** Medirlos con un audio real de 5 minutos es tarea de la Fase 5, y esos valores medidos son los que alimentan la estimación mostrada al usuario.

---

## 2. Stack

Fijar versiones exactas en el primer commit. Verificar cuál es la vigente al instalar; lo importante es que queden escritas, no que sean exactamente estos números.

**Backend** — Python 3.12 · FastAPI · **Pydantic v2** (explícito: el código de v1 es incompatible y ambos siguen circulando) · SQLAlchemy 2.x + Alembic · RQ sobre Redis · faster-whisper (CTranslate2) · WeasyPrint para PDF · ffmpeg/ffprobe como binarios de la imagen.

**Frontend** — el `package.json` que ya viene en `disenoFrontend.zip`: Next.js 16.3.3 · React 19 · **Tailwind v4** (nota: v3 y v4 tienen configuración incompatible; este proyecto es v4, con `@tailwindcss/postcss` y sin `tailwind.config`) · shadcn sobre `@base-ui/react`, estilo `base-nova` · lucide-react · TypeScript 5.7 en `strict`. Se añaden `@tanstack/react-query` para el estado del servidor y `zod` para validar las respuestas del API.

**Infraestructura** — PostgreSQL 16 · Redis 7 · Docker Compose · Caddy como reverse proxy y servidor del frontend estático · Cloudflare Tunnel para el acceso remoto.

Decisiones que se conservan del plan previo, con su razón: **faster-whisper** por el int8 en CPU, el VAD integrado y porque devuelve los segmentos como generador (es lo que hace posible un progreso real); **worker separado con cola** porque transcribir dentro del request HTTP es un timeout garantizado; **RQ** en vez de Celery porque hay un solo tipo de trabajo; **SSE** en vez de WebSocket porque el flujo es unidireccional; **volumen de Docker** en vez de MinIO porque MinIO es peso muerto aquí.

### Por qué el frontend se sirve como export estático

La app de v0 es enteramente cliente (`'use client'`, sin server actions, sin fetching en servidor). Con `output: 'export'` en `next.config.mjs` se compila a HTML/JS estático que Caddy sirve directamente: no hay proceso Node en producción, no hay ~200 MB de RSS extra, no hay un segundo runtime que mantener. Caddy sirve `/` desde los archivos y hace proxy de `/api/*` al contenedor de FastAPI, así que todo queda en un mismo origen y la cookie de sesión funciona sin CORS ni configuración especial.

---

## 3. Arquitectura

```
Navegador (Next.js estático + EventSource)
    │  multipart / chunked upload
    ▼
Caddy  ──/api/*──▶  API (FastAPI)  ──encola──▶  Redis (RQ)
    │                    │                          │
    └──/──▶ estáticos    │                          ▼
                         │                  Worker (faster-whisper + ffmpeg)
                         ▼                          │
                     Postgres  ◀───── progreso y segmentos por lotes
                         │
                         └──▶ SSE de vuelta al navegador
```

API y worker comparten el paquete de dominio pero son contenedores distintos, construidos desde la misma imagen con distinto comando.

**Arquitectura hexagonal.** La regla operativa: nada dentro de `domain/` importa FastAPI, SQLAlchemy ni faster-whisper. Los puertos son `TranscriptionEngine`, `JobRepository`, `AudioProbe`, `Diarizer`. Esto no es ceremonia: es lo que permite que los exportadores se prueben como funciones puras sin base de datos, y que la diarización se enchufe en la Fase 9 sin tocar el worker.

```
cadenceAPI/
├── docker-compose.yml
├── Caddyfile
├── CLAUDE.md
├── .env.example
├── backend/
│   ├── Dockerfile              # una imagen, dos comandos (api / worker)
│   ├── pyproject.toml
│   ├── alembic/
│   ├── tests/
│   └── src/
│       ├── domain/             # sin dependencias externas
│       │   ├── models.py       # Job, Segment, TranscriptionResult
│       │   ├── ports.py        # TranscriptionEngine, JobRepository, AudioProbe, Diarizer
│       │   └── exporters/      # txt, md, json, srt, vtt, pdf
│       ├── adapters/
│       │   ├── whisper_engine.py
│       │   ├── ffmpeg_probe.py
│       │   ├── postgres_repo.py
│       │   └── pyannote_diarizer.py    # Fase 9
│       ├── api/
│       │   ├── main.py
│       │   ├── routes/
│       │   ├── schemas.py      # Pydantic, solo capa HTTP
│       │   └── security.py     # Fase 8
│       └── worker/
│           └── tasks.py
└── frontend/                   # contenido de disenoFrontend.zip
    ├── Dockerfile              # build multi-etapa → export estático
    ├── app/
    ├── components/             # top-nav, upload-section, library-section, export-menu
    └── lib/
        ├── api/                # cliente tipado — reemplaza mock-data.ts
        └── hooks/              # useJobProgress (SSE), useUpload
```

---

## 4. Modelo de datos

**`users`** — `id` UUID PK · `email` CITEXT UNIQUE · `password_hash` VARCHAR (argon2) · `display_name` VARCHAR · `is_active` BOOL · `created_at` TIMESTAMPTZ.

Se crea en la primera migración aunque el login llegue en la Fase 8. Hasta entonces hay una fila `default` sembrada y `jobs.owner_id` apunta siempre a ella. Añadir una FK obligatoria a una tabla con datos es una migración incómoda; sembrarla desde el inicio cuesta nada.

**`jobs`** — `id` UUID PK · `owner_id` UUID FK→users · `original_filename` · `stored_path` · `mime_type` · `size_bytes` BIGINT · `duration_seconds` NUMERIC (de ffprobe, null hasta procesar) · `model` VARCHAR · `language` VARCHAR (null = autodetección) · `detected_language` VARCHAR · `diarize` BOOL DEFAULT false · `status` VARCHAR · `progress` NUMERIC 0–1 · `stage` VARCHAR (`normalizing`, `transcribing`, `diarizing`) · `error_message` TEXT · `created_at` / `started_at` / `finished_at` TIMESTAMPTZ.

**`segments`** — `id` BIGSERIAL PK · `job_id` UUID FK ON DELETE CASCADE · `idx` INTEGER · `start_seconds` / `end_seconds` NUMERIC · `text` TEXT · `speaker` VARCHAR NULL.

Índice en `segments(job_id, idx)` e índice en `jobs(owner_id, created_at DESC)`.

Notas de diseño:

- **`speaker` nullable desde la primera migración.** El diseño de v0 ya pinta chips de hablante en cada segmento; con la columna presente, la Fase 9 rellena datos en vez de migrar el esquema, y hasta entonces el frontend simplemente no dibuja el chip cuando es null.
- **Los segmentos se insertan por lotes conforme llegan**, no todos al final. Es lo que permite mostrar texto parcial mientras el trabajo corre.
- **`status` es VARCHAR con CHECK**, no ENUM nativo de Postgres: los ENUM de Postgres son dolorosos de modificar con migraciones.
- **`stage` separado de `status`** porque un trabajo `processing` puede estar normalizando, transcribiendo o diarizando, y cada etapa tiene su propia curva de progreso.

---

## 5. API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/health` | estado de API, Redis y Postgres |
| GET | `/api/models` | modelos habilitados con factor de velocidad medido |
| POST | `/api/jobs` | multipart; crea el trabajo y lo encola |
| GET | `/api/jobs` | lista paginada del usuario |
| GET | `/api/jobs/{id}` | detalle con segmentos |
| GET | `/api/jobs/{id}/events` | SSE: progreso, etapa y estado |
| GET | `/api/jobs/{id}/export?format=` | `txt`\|`md`\|`json`\|`srt`\|`vtt`\|`pdf` |
| DELETE | `/api/jobs/{id}` | borra registro y archivo |
| POST | `/api/uploads` · PUT `/api/uploads/{id}/parts/{n}` · POST `/api/uploads/{id}/complete` | subida por trozos (Fase 7) |
| POST | `/api/auth/login` · `/api/auth/logout` · GET `/api/auth/me` | Fase 8 |

Eventos SSE:

```
event: progress
data: {"progress":0.42,"status":"processing","stage":"transcribing","elapsed_seconds":63}

event: done
data: {"status":"done","segment_count":214,"detected_language":"es"}

event: error
data: {"status":"error","message":"..."}
```

---

## 6. Plan por fases

Cada fase es una rebanada vertical: algo que se ejecuta y se ve funcionando. No construir por capas —todo el backend y luego todo el frontend— porque eso produce mucho código que nadie ha corrido.

### Fase 0 — Infraestructura base

`git init` en `/home/jesusrg/cadenceAPI` (hoy no es repo) con `.gitignore` para `.env`, `__pycache__`, `node_modules`, `.next`, volúmenes y los `.zip`. Extraer `disenoFrontend.zip` en `frontend/` y commitearlo tal cual antes de tocarlo, para que el diff posterior muestre exactamente qué se cambió del diseño original. Los `.zip` y `plan-transcriptor-audio.md` se mueven a `docs/`.

`docker-compose.yml` con `postgres`, `redis`, `api`, `worker`. `/api/health` verificando ambas conexiones. Alembic configurado con la primera migración (las tres tablas de la sección 4, más la fila `default` de `users`). `.env.example` con todas las variables.

*Terminada cuando:* `docker compose up` levanta los cuatro servicios y `/api/health` responde ok.

### Fase 1 — Rebanada end-to-end mínima

El camino completo con todo lo demás simplificado al máximo: `POST /api/jobs` acepta un `.wav`, lo guarda en el volumen, crea la fila y encola. El worker lo toma, transcribe con `tiny` y guarda los segmentos. `GET /api/jobs/{id}` devuelve el texto. Sin frontend; se prueba con curl.

*Terminada cuando:* se sube un wav por curl y unos segundos después el mismo endpoint devuelve el texto.

**Esta es la fase más importante del proyecto.** Todo lo demás son mejoras sobre este esqueleto.

### Fase 2 — Conectar el frontend existente

No se diseñan pantallas: se sustituye el relleno por datos reales.

- `lib/api/client.ts` — cliente tipado con `zod` para validar respuestas; los tipos `Transcription`, `TranscriptSegment` y `User` de `lib/mock-data.ts` se convierten en los tipos del API y `mock-data.ts` se elimina.
- `upload-section.tsx` — reemplazar la función `simulate()` (que hoy anima una barra falsa con `setInterval`) por una subida real. El `stage` que ya modela el componente (`uploading` → `transcribing` → `done`) coincide con el diseño del backend, así que la estructura del componente se conserva; solo cambia de dónde vienen los números.
- `library-section.tsx` — listar desde `GET /api/jobs` con React Query, polling cada 2 s por ahora.
- `next.config.mjs` — `output: 'export'`; `Dockerfile` multi-etapa que deja los estáticos donde Caddy los sirve.

*Terminada cuando:* se puede hacer todo el flujo de la Fase 1 desde el navegador.

### Fase 3 — Formatos de audio

ffmpeg en la imagen del worker. Primer paso del worker: normalizar a WAV mono 16 kHz PCM. ffprobe para obtener la duración y validar que el archivo tiene pista de audio. El API rechaza archivos sin audio o mayores al límite configurado. El archivo normalizado se borra al terminar; solo se conserva el original.

*Terminada cuando:* funcionan mp3, m4a, ogg, opus, flac, wav, webm y mp4 con pista de audio.

### Fase 4 — Progreso real y SSE

El worker calcula `segment.end / duration_seconds` en cada segmento y actualiza el progreso. Endpoint SSE que emite los cambios. Hook `useJobProgress` en el frontend, reemplazando el polling, con fallback a polling si el `EventSource` falla. Configuración de Caddy para no bufear la respuesta SSE.

*Terminada cuando:* la barra avanza suavemente durante una transcripción larga, no a saltos.

### Fase 5 — Selector de modelos y medición

`GET /api/models` devuelve los modelos habilitados con su factor de velocidad. Selector de modelo e idioma (con autodetección) en la pantalla de subida, guardado en `localStorage` como preferencia. Estimación mostrada al usuario: duración × factor. El modelo se mantiene cacheado en memoria del worker entre trabajos.

**Medir en el ProDesk** con un audio real de 5 minutos los seis modelos de la tabla de la sección 1, y sustituir las estimaciones por los números reales. Si `large-v3` resulta insoportable en la práctica, se deshabilita del selector por variable de entorno; el resto del sistema no cambia.

*Terminada cuando:* se puede elegir modelo e idioma, y la estimación se acerca al tiempo real medido.

### Fase 6 — Exportación

En orden de dificultad ascendente: `txt` (concatenar) → `json` (volcado con timestamps) → `md` (con encabezado de metadatos) → `srt` y `vtt` → `pdf` (plantilla HTML + WeasyPrint).

Los cinco primeros son funciones puras sobre la lista de segmentos, viven en `domain/exporters/` y se prueban con tests unitarios sin tocar la base de datos. El PDF se genera bajo demanda y no se almacena.

`lib/export-utils.ts` del frontend —que hoy genera txt/md en el navegador y "imprime" el PDF abriendo una ventana— se reemplaza por descargas desde `GET /api/jobs/{id}/export`. `components/export-menu.tsx` se amplía de tres formatos a seis. Ganancia concreta: el PDF pasa de depender del diálogo de impresión del navegador a ser un archivo real, y funciona igual desde el móvil.

*Terminada cuando:* los seis formatos descargan correctamente y el `.srt` se abre sincronizado en VLC.

### Fase 7 — Despliegue y acceso remoto

Caddy sirviendo los estáticos y haciendo proxy a `/api`. Cloudflare Tunnel para exponer el ProDesk sin abrir puertos ni IP fija, con Cloudflare Access delante como autenticación provisional.

**Subida por trozos.** El plan gratuito de Cloudflare corta los requests en 100 MB. Una hora de mp3 a 128 kbps son ~57 MB, pero dos horas o cualquier WAV lo superan. Los tres endpoints de `/api/uploads` parten el archivo en trozos de 8 MB desde el navegador; como efecto secundario, una subida desde datos móviles se puede reanudar en vez de reiniciarse.

Además: límite de tamaño y de trabajos concurrentes, y política de retención (borrar audios más viejos que N días, conservando la transcripción).

*Terminada cuando:* funciona desde el celular con datos móviles, sobre HTTPS y con autenticación.

### Fase 8 — Login y multiusuario *(secundaria)*

Lo mínimo que sirve, sin librería de autenticación: hash argon2, sesión en JWT dentro de una cookie `httpOnly`+`Secure`+`SameSite=Lax`, y **sin auto-registro** — los usuarios se crean con un comando de CLI. Todas las consultas de `jobs` se filtran por `owner_id`.

En el frontend, el selector de usuarios de `top-nav.tsx` (hoy un `<select>` sobre datos falsos) pasa a ser el menú de la sesión activa, con logout, más una pantalla de login.

**Si se complica, se corta aquí:** Cloudflare Access de la Fase 7 ya protege el sitio con una contraseña, y el sistema sigue siendo perfectamente usable con el usuario `default`. Nada de las fases 0–7 depende de esta.

### Fase 9 — Diarización *(secundaria)*

Casilla opcional por trabajo, apagada por defecto, que rellena `segments.speaker`. `pyannote.audio` 3.1 tras el puerto `Diarizer` (requiere token de Hugging Face y aceptar la licencia del modelo). Se ejecuta después de la transcripción, como etapa `diarizing` con su propia barra de progreso, y sus turnos se cruzan con los segmentos por solapamiento temporal.

El costo real en este hardware es lo que decide si se queda: pyannote en 4 núcleos ronda 0.5–1× la duración del audio, que sumado a `large-v3-turbo` lleva una hora de grabación a ~2.5 horas de proceso. **Medir antes de prometerlo en la interfaz.** Si el costo no compensa, la casilla no se expone: los chips de hablante del diseño simplemente no se dibujan, porque `speaker` ya es nullable desde la Fase 0.

### Fase 10 — Robustez

Reintentos de RQ con límite y `job_timeout` generoso (una hora de audio con `large-v3` puede tardar 5 horas: el timeout por defecto de RQ, 180 s, mata el trabajo). Marcar como error los trabajos que quedaron en `processing` al reiniciar el worker. Cancelación de trabajos en cola. Logs estructurados. Backup de Postgres.

---

## 7. Trampas conocidas

Son las que más tiempo cuestan si se descubren tarde. Van íntegras en el `CLAUDE.md`.

**El generador de faster-whisper es perezoso.** `model.transcribe()` devuelve de inmediato sin haber transcrito nada; el trabajo real ocurre al iterar los segmentos. Es la causa número uno de barras de progreso que saltan de 0 a 100 de golpe.

**Buffering del proxy con SSE.** Caddy y nginx bufean respuestas por defecto y eso rompe el streaming en silencio: en desarrollo funciona, en producción no. Requiere configuración explícita en el `Caddyfile`.

**`job_timeout` de RQ.** El defecto de 180 segundos mata cualquier transcripción seria en esta máquina.

**`cpu_threads` mayor que 4.** Poner 8 (los hilos lógicos) en un i7-7700T típicamente empeora el rendimiento de CTranslate2, no lo mejora.

**Redes de Docker.** Dentro de Compose los servicios se llaman por nombre (`postgres`, `redis`), no `localhost`. Error clásico y el mensaje no siempre lo delata.

**Volumen para los pesos de los modelos.** Sin él, cada recreación del contenedor vuelve a descargar gigabytes y a escribirlos en un disco mecánico.

**Tailwind v4, no v3.** Este frontend no tiene `tailwind.config.js`: la configuración vive en CSS con `@theme`. Aplicarle recetas de v3 no falla ruidosamente, simplemente no surte efecto.

**`output: 'export'` prohíbe partes de Next.** Nada de server actions, route handlers dinámicos ni `next/image` con optimización. La app actual no usa ninguno; conviene que siga así.

**Flags de ffmpeg.** Verificar contra la documentación oficial; es fácil terminar con flags plausibles que no hacen lo que se cree.

**Timestamps de SRT vs VTT.** SRT usa coma para los milisegundos (`00:01:23,456`), VTT usa punto (`00:01:23.456`). Confundirlos produce archivos que unos reproductores aceptan y otros rechazan.

**Memoria del worker.** Concurrencia 1. Dos transcripciones simultáneas con modelos grandes pueden agotar la RAM y provocar un OOM kill.

---

## 8. `CLAUDE.md`

En la raíz del repo, con el contexto que conviene tener siempre a mano: versiones exactas del stack (con la nota explícita de Pydantic v2 y Tailwind v4); las restricciones de hardware de la sección 1; la regla de que `domain/` no importa framework alguno; los comandos para levantar, correr tests y aplicar migraciones; la lista de trampas de la sección 7; y las convenciones de commits y nombres.

---

## 9. Verificación

**Por fase**, el criterio de "terminada cuando" de cada una es la prueba.

**Tests automatizados** — unitarios para los seis exportadores (funciones puras sobre listas de segmentos, sin base de datos ni ficheros); de integración para el ciclo `POST /api/jobs` → worker → `GET /api/jobs/{id}` con un wav de 3 segundos y el modelo `tiny`; y un test que verifique que ningún módulo bajo `domain/` importa `fastapi`, `sqlalchemy` ni `faster_whisper` (un `grep` en un test basta y evita que la arquitectura se erosione en silencio).

**Prueba end-to-end manual en el ProDesk**, que es la que de verdad cierra el proyecto:

1. Desde el móvil con datos móviles, entrar por el dominio de Cloudflare y autenticarse.
2. Subir un `.m4a` de ~40 minutos eligiendo `large-v3-turbo` y español.
3. Ver la barra de subida por trozos, y luego la de transcripción avanzando de forma continua (no a saltos) con la etapa correcta.
4. Confirmar que aparece texto parcial en la biblioteca mientras el trabajo sigue corriendo.
5. Al terminar, exportar en los seis formatos; abrir el `.srt` en VLC junto al audio original y comprobar la sincronía.
6. Reiniciar el worker a mitad de otra transcripción y verificar que el trabajo queda marcado como error, no colgado en `processing` para siempre.
7. `docker stats` durante una transcripción con `large-v3` para confirmar que la RAM se mantiene lejos del límite de 16 GB.
