# Servicio de transcripción de audio autoalojado

Plan de proyecto. Stack Python, despliegue en ProDesk vía Docker.

---

## 1. Objetivo

Aplicación web autoalojada que permite subir archivos de audio desde cualquier lugar, transcribirlos con modelos Whisper corriendo en el servidor propio, seguir el avance en tiempo real y exportar el resultado en varios formatos.

### Alcance v1

Dentro:

- Subida de audio desde navegador (varios formatos)
- Cola de trabajos con procesamiento en segundo plano
- Selector de modelo por trabajo
- Progreso en tiempo real
- Exportación a txt, md, srt, vtt, json y pdf
- Historial de transcripciones
- Acceso remoto autenticado

Fuera (candidatos a v2):

- Diarización (quién habla)
- Resumen automático de la transcripción
- Edición de la transcripción en el navegador
- Multiusuario con cuentas separadas
- Transcripción en vivo desde micrófono

---

## 2. Decisiones tomadas

| Decisión | Elección | Razón |
|---|---|---|
| Lenguaje del backend | Python | Toda la sustancia del proyecto está en el worker de ML; un API en Java sería CRUD sin lucimiento y duplicaría modelos entre dos lenguajes |
| Motor de transcripción | faster-whisper | Mejor rendimiento en CPU, cuantización int8, VAD integrado, segmentos como generador (habilita progreso real) |
| Procesamiento | Worker separado con cola | Transcribir dentro del request HTTP provoca timeout garantizado |
| Cola | Redis + RQ | Celery es más potente pero mucho más ceremonia para un solo tipo de trabajo |
| Transporte del progreso | SSE | El flujo es unidireccional servidor → cliente; WebSocket añade gestión de conexión sin beneficio |
| Almacenamiento de audio | Volumen Docker | MinIO es peso muerto en un servidor personal |
| Arquitectura interna | Hexagonal (puertos y adaptadores) | El dominio no debe saber que existe FastAPI ni faster-whisper; facilita cambiar el motor o el framework después |

### Punto abierto

**Especificaciones del ProDesk (CPU, núcleos, RAM).** Determina el techo del selector de modelos. Referencia aproximada en CPU con int8:

| Modelo | RAM aprox. | Velocidad vs. duración del audio |
|---|---|---|
| tiny | ~0.5 GB | mucho más rápido que tiempo real |
| base | ~0.7 GB | más rápido que tiempo real |
| small | ~1.2 GB | cerca de tiempo real |
| medium | ~2.5 GB | 2-3× la duración |
| large-v3 | ~4 GB | 4-6× la duración |

Medir con un audio real de 5 minutos antes de decidir qué modelos exponer en la interfaz.

---

## 3. Stack con versiones

Fijar en el primer commit. Verificar las versiones actuales al momento de instalar; el punto no es usar exactamente estos números sino que estén fijados y escritos.

**Backend**

- Python 3.12
- FastAPI
- Pydantic v2 (explícito: el código de v1 es incompatible y ambos circulan)
- SQLAlchemy 2.x + Alembic para migraciones
- RQ (Redis Queue)
- faster-whisper
- WeasyPrint (generación de PDF vía HTML)
- ffmpeg y ffprobe (binarios del sistema, dentro de la imagen)

**Frontend**

- Node 22
- React + Vite + TypeScript en modo `strict`
- Tailwind (fijar mayor: v3 y v4 tienen configuración incompatible)
- shadcn/ui (copia componentes al repo, no es dependencia opaca)

**Infraestructura**

- PostgreSQL 16
- Redis 7
- Docker Compose
- Caddy como reverse proxy
- Cloudflare Tunnel o Tailscale para acceso remoto

---

## 4. Arquitectura

```
Navegador (React + SSE)
    │  multipart upload
    ▼
API (FastAPI)  ──encola──▶  Redis (RQ)
    │                            │
    │                            ▼
    │                    Worker (faster-whisper + ffmpeg)
    │                            │
    ▼                            ▼
Postgres  ◀────────────  escribe progreso y segmentos
    │
    └──▶ SSE de vuelta al navegador
```

El API y el worker comparten el paquete de dominio y los modelos, pero se despliegan como contenedores distintos.

### Estructura de carpetas

```
transcriptor/
├── docker-compose.yml
├── Caddyfile
├── CLAUDE.md
├── .env.example
├── backend/
│   ├── Dockerfile
│   ├── pyproject.toml
│   ├── alembic/
│   └── src/
│       ├── domain/           # entidades y puertos, sin dependencias externas
│       │   ├── models.py     # Job, Segment, TranscriptionResult
│       │   ├── ports.py      # interfaces: TranscriptionEngine, JobRepository, AudioProbe
│       │   └── exporters/    # txt, md, srt, vtt, json, pdf
│       ├── adapters/
│       │   ├── whisper_engine.py    # implementa TranscriptionEngine
│       │   ├── ffmpeg_probe.py      # implementa AudioProbe
│       │   └── postgres_repo.py     # implementa JobRepository
│       ├── api/
│       │   ├── main.py
│       │   ├── routes/
│       │   └── schemas.py    # Pydantic, solo capa HTTP
│       └── worker/
│           └── tasks.py
└── frontend/
    ├── Dockerfile
    ├── package.json
    └── src/
        ├── components/
        ├── hooks/            # useJobProgress (SSE), useUpload
        └── api/              # cliente tipado
```

La regla de la arquitectura hexagonal aquí: nada dentro de `domain/` importa FastAPI, SQLAlchemy ni faster-whisper. Si se rompe esa regla, se rompió la arquitectura.

---

## 5. Modelo de datos

**jobs**

| Columna | Tipo | Nota |
|---|---|---|
| id | UUID | PK |
| original_filename | VARCHAR | nombre que subió el usuario |
| stored_path | VARCHAR | ruta en el volumen |
| mime_type | VARCHAR | |
| size_bytes | BIGINT | |
| duration_seconds | NUMERIC | de ffprobe, null hasta que se procesa |
| model | VARCHAR | tiny, base, small, medium, large-v3 |
| language | VARCHAR | null = autodetección |
| status | VARCHAR | pending, processing, done, error, cancelled |
| progress | NUMERIC | 0.0 a 1.0 |
| error_message | TEXT | null salvo status=error |
| detected_language | VARCHAR | lo que reportó el modelo |
| created_at | TIMESTAMPTZ | |
| started_at | TIMESTAMPTZ | |
| finished_at | TIMESTAMPTZ | |

**segments**

| Columna | Tipo | Nota |
|---|---|---|
| id | BIGSERIAL | PK |
| job_id | UUID | FK, ON DELETE CASCADE |
| idx | INTEGER | orden dentro del trabajo |
| start_seconds | NUMERIC | |
| end_seconds | NUMERIC | |
| text | TEXT | |

Índice en `segments(job_id, idx)`. Los segmentos se insertan por lotes conforme llegan, no todos al final: así el usuario puede ver texto parcial mientras corre.

`status` como VARCHAR con CHECK, no como BOOLEAN ni ENUM nativo de Postgres. Los ENUM de Postgres son dolorosos de modificar con migraciones.

---

## 6. API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/health` | estado de API, Redis y Postgres |
| GET | `/api/models` | modelos disponibles con estimación de velocidad |
| POST | `/api/jobs` | multipart; crea el trabajo y lo encola |
| GET | `/api/jobs` | lista paginada |
| GET | `/api/jobs/{id}` | detalle con segmentos |
| GET | `/api/jobs/{id}/events` | SSE: progreso y estado |
| GET | `/api/jobs/{id}/export?format=txt` | descarga |
| DELETE | `/api/jobs/{id}` | borra registro y archivo |

Eventos SSE:

```
event: progress
data: {"progress": 0.42, "status": "processing", "elapsed_seconds": 63}

event: done
data: {"status": "done", "segment_count": 214}

event: error
data: {"status": "error", "message": "..."}
```

---

## 7. Plan por fases

Cada fase es una rebanada vertical: algo que se puede ejecutar y ver funcionando. No construir por capas (todo el backend, luego todo el frontend); eso produce mucho código que nadie ha corrido.

### Fase 0 — Infraestructura base

Levantar el esqueleto vacío.

- `docker-compose.yml` con postgres, redis, api, worker
- `/api/health` que verifica conexión a Redis y Postgres
- Alembic configurado con la primera migración (tablas vacías)
- `.env.example` con todas las variables

**Terminada cuando:** `docker compose up` levanta los cuatro servicios y `/api/health` responde ok.

### Fase 1 — Rebanada end-to-end mínima

El camino completo con todo lo demás simplificado al máximo.

- `POST /api/jobs` acepta un `.wav`, lo guarda en el volumen, crea la fila y encola
- El worker toma el trabajo, transcribe con `tiny` y guarda segmentos
- `GET /api/jobs/{id}` devuelve el texto
- Sin frontend: se prueba con curl

**Terminada cuando:** se sube un wav por curl y unos segundos después el mismo endpoint devuelve el texto.

Esta es la fase más importante del proyecto. Todo lo demás son mejoras sobre este esqueleto.

### Fase 2 — Frontend base

- Página de subida con drag and drop
- Barra de progreso de *subida* (`onUploadProgress` de axios; distinta del progreso de transcripción)
- Lista de trabajos con estado, refrescando por polling cada 2 segundos
- Vista de detalle con el texto

**Terminada cuando:** se puede hacer todo el flujo de la fase 1 desde el navegador.

### Fase 3 — Formatos de audio

- ffmpeg en la imagen del worker
- Primer paso del worker: normalizar a WAV mono 16 kHz PCM
- ffprobe para obtener duración y validar que el archivo tiene pista de audio
- Rechazar en el API archivos sin audio o mayores al límite configurado
- Borrar el archivo normalizado al terminar (solo se conserva el original)

**Terminada cuando:** funcionan mp3, m4a, ogg, opus, flac, webm y mp4 con pista de audio.

### Fase 4 — Progreso real y SSE

- El worker calcula `segment.end / duration_seconds` en cada segmento y actualiza progreso
- Endpoint SSE que emite cambios
- Hook `useJobProgress` en el frontend, reemplazando el polling
- Fallback a polling si el `EventSource` falla
- Configuración de Caddy para no bufear la respuesta SSE

**Terminada cuando:** la barra avanza suavemente durante una transcripción larga, no a saltos.

### Fase 5 — Selector de modelos

- `GET /api/models` con los modelos habilitados y su estimación de tiempo
- Selector en la subida, guardado como preferencia en localStorage
- Selector de idioma con opción de autodetección
- Estimación mostrada al usuario: duración del audio × factor del modelo
- Caché del modelo en memoria del worker entre trabajos (cargarlo cuesta segundos)

**Terminada cuando:** se puede elegir modelo e idioma, y la estimación se acerca al tiempo real.

### Fase 6 — Exportación

Orden de implementación por dificultad ascendente:

1. txt (concatenar texto)
2. json (volcado de segmentos con timestamps)
3. md (con encabezado de metadatos)
4. srt y vtt (formateo de timestamps; ojo con la coma vs. punto en los milisegundos)
5. pdf (plantilla HTML + WeasyPrint)

Los cinco primeros son funciones puras sobre la lista de segmentos, viven en `domain/exporters/` y se prueban con tests unitarios sin tocar la base de datos. El PDF se genera bajo demanda, no se almacena.

**Terminada cuando:** los seis formatos descargan correctamente y el srt se abre en VLC sincronizado.

### Fase 7 — Despliegue y acceso remoto

- Caddy con el frontend estático y proxy al API
- Cloudflare Tunnel (o Tailscale si el acceso es solo personal)
- Autenticación: lo más simple que sirva. Cloudflare Access o basic auth en Caddy antes que montar un sistema de usuarios
- Subida por trozos si se usa Cloudflare (límite de 100 MB por request en el plan gratuito)
- Límite de tamaño y de trabajos concurrentes
- Política de retención: borrar audios más viejos que N días

**Terminada cuando:** funciona desde el celular con datos móviles, sobre HTTPS y con autenticación.

### Fase 8 — Robustez

- Reintentos de RQ con límite y `job_timeout` generoso
- Marcar como error los trabajos que quedaron en `processing` al reiniciar el worker
- Cancelación de trabajos en cola
- Logs estructurados
- Backup de Postgres

---

## 8. Trampas conocidas

Estas son las que más tiempo cuestan si se descubren tarde.

**El generador de faster-whisper es perezoso.** `model.transcribe()` devuelve de inmediato sin haber transcrito nada; el trabajo real ocurre al iterar los segmentos. Es la causa número uno de barras de progreso que saltan de 0 a 100 de golpe.

**Buffering del proxy con SSE.** Caddy y nginx bufean respuestas por defecto y eso rompe el streaming en silencio: en desarrollo funciona, en producción no. Requiere configuración explícita.

**Redes de Docker.** Dentro de Compose los servicios se llaman por nombre (`postgres`, `redis`), no `localhost`. Error clásico y el mensaje no siempre lo delata.

**Flags de ffmpeg.** Verificar contra la documentación oficial; es fácil terminar con flags plausibles que no hacen lo que se cree.

**Carga del modelo.** Cargar `medium` toma varios segundos. Si se carga en cada trabajo, se paga ese costo cada vez. Mantenerlo en memoria del worker.

**Timestamps de SRT vs VTT.** SRT usa coma para los milisegundos (`00:01:23,456`), VTT usa punto (`00:01:23.456`). Confundirlos produce archivos que algunos reproductores aceptan y otros rechazan.

**Memoria del worker.** Un solo worker con concurrencia 1. Dos transcripciones simultáneas con `medium` pueden agotar la RAM del ProDesk y provocar OOM kill.

---

## 9. CLAUDE.md

Archivo en la raíz del repo con el contexto que el agente debe tener siempre a la mano:

- Versiones exactas de todo el stack, con nota explícita de Pydantic v2 y la mayor de Tailwind
- Restricción de hardware: CPU sin GPU, RAM disponible
- Regla de arquitectura: `domain/` no importa framework alguno
- Comandos: cómo levantar, correr tests, aplicar migraciones
- La lista de trampas de la sección 8
- Convención de commits y de nombres

Es lo que más mejora la calidad del código generado por unidad de esfuerzo invertido.

---

## 10. Ideas para v2

- Diarización con pyannote (pesada en CPU, medir antes de prometer)
- Resumen y extracción de puntos clave con un LLM local o vía API
- Editor de transcripción con sincronización al reproductor de audio
- Búsqueda de texto completo sobre todas las transcripciones (`tsvector` en Postgres)
- Traducción de la transcripción
- Subida desde URL (YouTube, podcasts) con yt-dlp
