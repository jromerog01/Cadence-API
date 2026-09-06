# Cadence — contexto para trabajar en este repo

Servicio autoalojado de transcripción de audio (Whisper local, sin APIs de
terceros). El plan de diseño autoritativo está en
`quiero-hacer-una-pagina-functional-pancake.md` — léelo antes de tomar
decisiones de arquitectura que no estén ya resueltas aquí.

## Stack y versiones fijadas

- **Backend**: Python 3.12, FastAPI, **Pydantic v2** (el código de v1 es
  incompatible, y ambos siguen circulando — verificar siempre que se usa la
  API de v2), SQLAlchemy 2.x **sync** + psycopg3, Alembic, RQ sobre Redis,
  faster-whisper (CTranslate2). Versiones exactas en `backend/pyproject.toml`.
- **Frontend**: Next.js 16 / React 19 / **Tailwind v4** (no v3 — este
  proyecto no tiene `tailwind.config.js`, la configuración vive en CSS con
  `@theme`; recetas de v3 no fallan ruidosamente, simplemente no hacen nada).
  shadcn sobre `@base-ui/react`. `@tanstack/react-query` + `zod` para el
  cliente de API. Paquetes con **npm**, no pnpm (no está instalado aquí).
- **Infra**: PostgreSQL 16, Redis 7, Docker Compose, Caddy (reverse proxy +
  estáticos).

## Restricciones de hardware (producción: ProDesk 600 G3 DM)

i7-7700T (4 núcleos/8 hilos, Kaby Lake, AVX2 sin AVX-512), 16GB RAM, disco
mecánico de 1TB, sin GPU. Consecuencias que no se deben romper:

- Un solo worker RQ, concurrencia 1 (dos transcripciones grandes simultáneas
  no van más rápido, solo arriesgan OOM).
- `cpu_threads=4` en faster-whisper, nunca 8 (los hilos lógicos de
  HyperThreading empeoran CTranslate2 en cargas de matrices densas).
- Pesos de modelos en un volumen Docker persistente (`model_weights`) — sin
  él, cada recreación del contenedor re-descarga gigabytes a un disco lento.
- Modelo por defecto: `small` (rápido) / `large-v3-turbo` (calidad). En esta
  máquina de **desarrollo** usar siempre `tiny` (poca RAM libre).

## Regla de arquitectura

`backend/src/domain/` no importa `fastapi`, `sqlalchemy` ni `faster_whisper`
bajo ninguna circunstancia. Los puertos (`TranscriptionEngine`,
`JobRepository`, `AudioProbe`, `Diarizer`) viven en `domain/ports.py`; las
implementaciones concretas van en `adapters/`. Esto se verifica con
`backend/tests/test_architecture.py` — si ese test falla, es una señal de
que algo se filtró donde no debía, no que el test esté mal.

## Comandos

```bash
# Levantar todo
docker compose up -d --build

# Aplicar migraciones
docker compose exec api alembic upgrade head

# Generar una nueva migración (a mano, no autogenerar — ver por qué abajo)
# crear el archivo en backend/alembic/versions/ siguiendo 0001_initial.py

# Tests
docker compose exec api pytest

# Logs de un servicio
docker compose logs -f worker

# Retención: borra audio de trabajos terminados más viejos que
# AUDIO_RETENTION_DAYS (0 = nunca). Programar como cron del host, p. ej.
# diario a las 3am: 0 3 * * * cd <repo> && docker compose exec -T worker \
#   python -m worker.retention
docker compose exec worker python -m worker.retention

# Probar el flujo end-to-end con curl (Fase 1)
ffmpeg -f lavfi -i "sine=frequency=440:duration=3" -ar 16000 -ac 1 /tmp/sample.wav
curl -sf -X POST http://localhost:8000/api/jobs -F "file=@/tmp/sample.wav"
curl -sf http://localhost:8000/api/jobs/<id>
```

## Trampas conocidas

- **El generador de faster-whisper es perezoso.** `model.transcribe()`
  vuelve de inmediato; el trabajo real ocurre al iterar los segmentos. Causa
  #1 de barras de progreso que saltan de 0 a 100.
- **Buffering del proxy con SSE.** Caddy bufea por defecto; rompe streaming
  en silencio (funciona en dev, no en producción). Requiere configuración
  explícita en el `Caddyfile` (Fase 4).
- **`job_timeout` de RQ.** El default de 180s mata cualquier transcripción
  seria en este hardware — siempre pasar `job_timeout` explícito al
  encolar.
- **`cpu_threads` > 4** empeora CTranslate2 en este CPU, no lo mejora.
- **Redes de Docker Compose.** Los servicios se llaman por nombre
  (`postgres`, `redis`), nunca `localhost`.
- **Volumen de pesos de modelos.** Sin `model_weights` persistente, cada
  `docker compose up --build` vuelve a descargar los modelos.
- **Tailwind v4, no v3.** Sin `tailwind.config.js`; configuración en
  `app/globals.css` vía `@theme`.
- **`output: 'export'` prohíbe server actions, route handlers dinámicos y
  `next/image` con optimización.** La app no los usa; que siga así.
- **Flags de ffmpeg.** Verificar contra la documentación oficial antes de
  asumir que un flag hace lo que parece.
- **Timestamps SRT vs VTT.** SRT usa coma en los milisegundos
  (`00:01:23,456`), VTT usa punto (`00:01:23.456`).
- **Memoria del worker.** Concurrencia 1; un modelo grande + otro trabajo
  simultáneo puede provocar OOM kill.
- **Esta máquina de desarrollo no es el ProDesk.** Poca RAM libre aquí —
  usar siempre `WHISPER_MODEL=tiny` localmente; la medición de modelos
  grandes (Fase 5) y el despliegue real (Fase 7) ocurren en el ProDesk.

## Convenciones

- Commits en inglés, imperativo, sin firma manual (se añade
  `Co-Authored-By`/`Claude-Session` automáticamente cuando aplica).
- Migraciones de Alembic escritas a mano, no autogeneradas — los CHECK
  constraints, CITEXT y el INSERT semilla de `0001_initial.py` no salen
  bien de `alembic revision --autogenerate`.
- `status` de `jobs` es `VARCHAR` + `CHECK`, no ENUM nativo de Postgres (los
  ENUM son dolorosos de migrar). Valores: `queued`, `processing`, `done`,
  `error`.
- `stage` es independiente de `status` (`normalizing`, `transcribing`,
  `diarizing`, o `NULL`).
- `segments.speaker` es nullable desde la primera migración — el frontend
  simplemente no dibuja el chip de hablante cuando es `NULL` (diarización es
  Fase 9, opcional).
