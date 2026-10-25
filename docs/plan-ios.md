# Cadence para iPhone — plan de la app nativa

## Contexto

Cadence ya existe como servicio web: backend FastAPI + worker de
faster-whisper en el ProDesk, frontend Next.js estático detrás de Caddy, y
acceso remoto por Cloudflare Tunnel. Las fases 0–8 y 10 del plan original
(`quiero-hacer-una-pagina-functional-pancake.md`) están implementadas.

Este plan añade una **app nativa para iPhone escrita en Swift**, con el
lenguaje visual de iOS 26 (Liquid Glass) y **dos motores de transcripción**
que el usuario elige en cada trabajo:

- **Servidor.** El audio se sube al ProDesk y lo transcribe el mismo
  backend, con los mismos modelos de Whisper, la misma cola y las mismas
  cuentas que la web.
- **En este iPhone.** El audio lo transcribe el propio teléfono con el
  motor de voz local de Apple (`SpeechAnalyzer` / `SpeechTranscriber`, iOS
  26). El audio **nunca sale del dispositivo**, no hace falta conexión y no
  se ocupa la cola del servidor.

**Los dos motores trabajan en segundo plano.** Con el servidor, la subida
sigue con la pantalla bloqueada y el ProDesk procesa por su cuenta; la app
avisa cuando termina. En el iPhone, la transcripción sigue al salir de la
app gracias a `BGContinuedProcessingTask`, con el progreso visible en la
interfaz del sistema.

**El audio puede venir de cualquier sitio, no hace falta grabarlo en la
app.** La vía principal es la hoja de compartir del sistema: en Notas de
Voz, WhatsApp, Telegram, Archivos o cualquier app con audio, *Compartir →
Cadence*. También se puede elegir un archivo desde la propia app, o
grabarlo dentro de ella (esto último es opcional, sección 6).

Lo que la app aporta frente a la web en Safari:

- **Recibir audio de otras apps** con la hoja de compartir.
- **Transcribir sin conexión** en el propio teléfono.
- **Subidas que sobreviven** al cambio de app y a la pantalla bloqueada
  (en Safari, una subida de 200 MB por datos móviles muere en cuanto el
  usuario cambia de app).
- **Avisar cuando termina** una transcripción larga, sin tener la app
  abierta.
- **Leer las transcripciones sin conexión.**
- **Grabar directamente**, incluso con la pantalla bloqueada.

Resultado esperado: grabar una reunión en Notas de Voz, compartirla a
Cadence, elegir servidor o iPhone, bloquear el teléfono, y recibir una
notificación con la transcripción lista para compartir en `.srt`, `.pdf` o
texto plano.

Restricción de principio que se conserva: **nada de audio sale hacia
terceros.** La app solo habla con el servidor propio, y en modo local ni
siquiera con él. Las excepciones son mínimas y explícitas: el sistema
descarga una vez el modelo de voz de cada idioma desde Apple (sección 5), y
APNs (notificaciones push, Fase iOS-13, opcional) solo transporta un
identificador de trabajo y un título, nunca audio ni texto transcrito.

---

## 1. Prerrequisitos que no son código

Conviene resolverlos antes de escribir una línea, porque condicionan todo lo
demás.

**Compilar en Fedora con xtool, sin Mac.** La app se compila, firma e
instala desde la laptop con Fedora usando el toolchain de Swift para Linux y
**xtool**, que reemplaza a Xcode para proyectos de SwiftPM: extrae el SDK de
iOS de un `Xcode.xip` descargado de Apple, compila con `swift build` contra
ese SDK, firma con el Apple ID y la instala en el iPhone por USB. (El ProDesk
no participa: solo corre el backend.) Esto funciona, pero tiene
consecuencias que atraviesan todo el plan:

- **No hay simulador ni previews de SwiftUI.** Cada prueba es compilar e
  instalar en el iPhone real (`xtool dev`). El ciclo es de decenas de
  segundos, no instantáneo; conviene aislar la lógica en `CadenceKit` y
  probarla con `swift test` nativo en Fedora, que es inmediato.
- **No hay `.xcodeproj`.** El proyecto es un paquete de SwiftPM con un
  `xtool.yml` (identificador, Info.plist, entitlements). Ventaja: ningún
  `project.pbxproj` que cause conflictos de merge.
- **Las herramientas exclusivas de Xcode no están**: el compilador de
  catálogos de assets (`actool`), el de catálogos de cadenas
  (`.xcstrings`), Icon Composer, el editor de modelos de Core Data, y
  probablemente los **macros que vienen con los frameworks del SDK** (como
  `@Model` de SwiftData o `#Preview`), cuyos plugins se distribuyen con
  Xcode y no con el toolchain de Linux. El plan se ajusta para no depender
  de ninguno (secciones 2, 3 y 7), y la Fase iOS-0 verifica cada uno.
- **No hay depurador gráfico.** Diagnóstico con `os.Logger` y los logs del
  dispositivo (`idevicesyslog` de libimobiledevice).

La sección 10 detalla la instalación de xtool, el emparejamiento del iPhone
y la firma.

**iPhone 15 con iOS 26.** El motor local (`SpeechAnalyzer`), el
procesamiento continuado en segundo plano (`BGContinuedProcessingTask`) y
Liquid Glass son de iOS 26, que el iPhone 15 soporta. Aun así,
`SpeechTranscriber` no está disponible en todos los modelos (sección 11);
confirmarlo en el propio iPhone 15 en la Fase iOS-0. Como no hay simulador,
todo se mide directamente en el dispositivo.

**Cuenta de Apple Developer.** Dos opciones con consecuencias reales:

| | Apple ID gratuito | Programa de pago (99 USD/año) |
|---|---|---|
| Instalar en el iPhone propio con xtool | sí | sí |
| Duración de la firma | **7 días**, luego hay que reinstalar | 1 año |
| TestFlight (instalar sin cable, compartir con otros usuarios) | no | sí |
| Notificaciones push (APNs) | no | sí |
| Capacidades restringidas (App Groups, etc.) | limitado; verificar al crear el proyecto | sí |

Para uso personal se puede empezar con la cuenta gratuita y migrar después:
las fases iOS-0 a iOS-12 no dependen de la cuenta de pago (las
notificaciones locales del motor del iPhone no necesitan APNs). Las
notificaciones push de trabajos del servidor (iOS-13) y la distribución por
TestFlight (iOS-15) sí. Que la share extension (iOS-7) funcione con la
cuenta gratuita depende de que esta permita App Groups: es lo primero que se
verifica en esa fase.

**Cloudflare Access frente a la API.** La Fase 7 del plan original puso
Cloudflare Access como autenticación provisional. Si sigue activo, **bloquea
a la app nativa**: Access responde a las peticiones sin su cookie con una
redirección a su propia página de login, que `URLSession` no puede
completar. Ahora que existe login propio (Fase 8), la solución es una regla
de **bypass para `/api/*`** en la política de Access (o retirar Access por
completo). Los service tokens de Access no son una alternativa: habría que
incrustar un secreto en la app. Verificar el estado actual en el panel de
Cloudflare antes de la Fase iOS-2.

**HTTPS obligatorio.** App Transport Security (ATS) de iOS rechaza HTTP
plano por defecto. En producción no es problema (Cloudflare da HTTPS). Para
desarrollo contra el servidor en la red local por `http://`, la build de
depuración declara `NSAllowsLocalNetworking`, que permite IPs locales y
`.local` sin abrir HTTP en general. La build de release no lleva esa
excepción.

---

## 2. Stack

Fijar versiones exactas (Swift, xtool, Xcode del que sale el SDK, iOS
mínimo) en el primer commit,
igual que con el backend; lo importante es que queden escritas.

- **Swift 6** con concurrencia estricta (`async/await`, actores). Los
  errores de aislamiento que marca el compilador son reales, no ruido:
  resolverlos, no silenciarlos con `@preconcurrency` o `nonisolated(unsafe)`.
- **SwiftUI** para toda la interfaz, con `@Observable` (framework
  Observation) para el estado. Sin UIKit salvo donde SwiftUI no llega
  (QuickLook, renderizado de PDF, el controlador de la share extension).
- **iOS 26 como mínimo, compilado con el SDK de iOS 26** (extraído por
  xtool de un `Xcode.xip` de la versión 26 o posterior). Tres razones apuntan
  a lo mismo: el motor local (`SpeechAnalyzer`), el segundo plano
  (`BGContinuedProcessingTask`) y Liquid Glass no existen antes. El iPhone 15
  lo corre, así que no hace falta soportar versiones anteriores.
- **SwiftPM + xtool** en vez de un proyecto de Xcode (sección 1). El
  toolchain de Swift en Fedora debe ser de la misma versión mayor que el
  Swift del Xcode del que sale el SDK; si no, el SDK no compila.
- **Speech** (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`) para
  la transcripción en el dispositivo, y **BackgroundTasks**
  (`BGContinuedProcessingTask`) para que siga en segundo plano.
- **Almacén local en archivos JSON**, no SwiftData, para los trabajos
  locales (Fase iOS-8) y el caché de los del servidor (Fase iOS-14): un
  archivo `Codable` por trabajo en *Application Support*, detrás de un actor.
  SwiftData depende del macro `@Model`, que probablemente no se puede
  expandir sin Xcode (sección 1), y Core Data necesita el compilador de
  modelos de Xcode o definir el modelo a mano en código. Para unas cientos de
  transcripciones, archivos JSON sobran, y además el almacén queda en
  `CadenceKit` como Foundation pura, que se prueba con `swift test` en Fedora. Si
  la Fase iOS-0 demuestra que `@Model` sí compila con xtool, se puede
  reconsiderar, pero no hace falta.
- **Cero dependencias de terceros.** Todo lo necesario está en el SDK:
  `URLSession` (incluido streaming de bytes para SSE y sesiones en segundo
  plano), Keychain vía `Security`, `AVFoundation` para grabar, convertir y
  leer audio, `ActivityKit` si se hacen Live Activities. Esto encaja con el
  espíritu del proyecto y evita que una actualización de una librería rompa
  la app.

Alternativas descartadas, con su razón:

- **Envolver la web en un `WKWebView`** (o una PWA). Sería lo más rápido,
  pero no resuelve ninguno de los motivos para hacer la app: no hay hoja de
  compartir, no hay subida en segundo plano, no hay transcripción local, no
  hay Liquid Glass real y las notificaciones web en iOS son muy limitadas.
- **React Native / Flutter.** Permitirían reutilizar algo de lógica del
  frontend, pero añaden un runtime entero para una app de pocas pantallas,
  dibujan sus propios controles en vez de los del sistema (así que Liquid
  Glass queda como imitación), y las piezas que importan (`SpeechAnalyzer`,
  sesiones de `URLSession` en segundo plano, share extension,
  `AVAudioSession`) igual se terminan escribiendo en código nativo.
- **Whisper en el iPhone** (WhisperKit, whisper.cpp) como motor local en vez
  del de Apple. Daría el mismo modelo que el servidor, pero es una
  dependencia de terceros, los pesos (cientos de MB a GB) van dentro de la
  app o se descargan aparte, y los modelos grandes calientan y agotan la
  batería de un teléfono. El motor de Apple viene en el sistema, sus modelos
  los gestiona iOS sin engordar la app, y está optimizado para el Neural
  Engine. Si en la Fase iOS-8 la calidad del motor de Apple resulta
  insuficiente para algún idioma, el puerto `TranscriptionEngine` (sección
  3) permite añadir WhisperKit como tercer motor sin tocar lo demás.
- **`SFSpeechRecognizer`** (la API de voz anterior). Pensada para dictado
  corto, no para archivos de una hora; `SpeechAnalyzer` la sustituye
  precisamente para audio largo.

---

## 3. Arquitectura

```
iPhone
┌──────────────────────────────────────────────────────────────┐
│ CadenceApp (SwiftUI)             ShareExtension              │
│   Vistas · ViewModels              recibe audio → App Group  │
│        │                                │                    │
│        ▼                                ▼                    │
│ CadenceKit (Swift Package local, sin UI ni frameworks de SO) │
│   Models · APIClient · SSEParser · ChunkedUploader           │
│   Exporters (txt/md/json/srt/vtt) · Inbox · FileJobStore     │
│   Puertos: TranscriptionEngine, HTTPTransport, TokenStore,   │
│            JobStore                                          │
│        │                                                     │
│ Adaptadores:                                                 │
│   ServerEngine ──────────── sube + sigue SSE                 │
│   AppleSpeechEngine ─────── SpeechAnalyzer, en el dispositivo│
│   URLSessionTransport · BackgroundUploadSession              │
│   KeychainTokenStore                                         │
│   ContinuedProcessingRunner (BGContinuedProcessingTask)      │
└────────┼─────────────────────────────────────────────────────┘
         │ HTTPS + Authorization: Bearer <jwt>   (solo motor Servidor
         ▼                                        y sincronización)
Cloudflare Tunnel → Caddy → /api/* → FastAPI (el mismo backend)
```

**La misma regla hexagonal que el backend.** `CadenceKit` es un Swift
Package local que no importa `SwiftUI`, `UIKit`, `SwiftData`,
`AVFoundation`, `Speech` ni `BackgroundTasks`. Define los modelos (`Job`,
`Segment`, `ModelInfo`, `User`), el cliente de API sobre un puerto
`HTTPTransport`, el parser de SSE como función pura sobre una secuencia de
líneas, la lógica del protocolo de subida por trozos, los exportadores de
texto, el almacén local en JSON (`FileJobStore`, Foundation pura) y la
*bandeja de entrada* (`Inbox`) por la que la share extension le pasa
archivos a la app. Las implementaciones que dependen de frameworks de iOS
viven en la app.

**El puerto `TranscriptionEngine`** es el mismo concepto que en
`backend/src/domain/ports.py`, y es lo que hace que los dos motores sean
intercambiables para el resto de la app:

```swift
protocol TranscriptionEngine: Sendable {
    func transcribe(_ request: TranscriptionRequest) -> AsyncThrowingStream<TranscriptionEvent, Error>
}

enum TranscriptionEvent: Sendable {
    case progress(fraction: Double, stage: Stage)   // uploading, queued, transcribing...
    case segments([Segment])                        // parciales, a medida que salen
    case finished(Job)
}
```

`ServerEngine` produce esos eventos a partir de la subida por trozos y del
SSE; `AppleSpeechEngine`, a partir de los resultados de `SpeechAnalyzer`.
La biblioteca, el detalle, la exportación y las notificaciones no saben qué
motor generó un trabajo, salvo por una etiqueta (`origin: .server | .device`)
que la interfaz muestra como distintivo.

Así:

- El parser de SSE, la decodificación de JSON, el protocolo de subida y los
  exportadores se prueban con `swift test` contra dobles, sin simulador ni
  red.
- La share extension reutiliza el mismo paquete sin arrastrar la app.
- Se puede verificar con un test que `CadenceKit` no importa frameworks de
  UI ni de sistema, igual que `backend/tests/test_architecture.py`.

### Estructura en el repo

```
ios/
├── Package.swift            # SwiftPM: productos Cadence (app) y CadenceKit
├── xtool.yml                # bundle ID, rutas a Info.plist y entitlements
├── Sources/
│   ├── Cadence/             # la app (SwiftUI)
│   │   ├── App/             # @main, raíz de navegación, scenePhase, onOpenURL
│   │   ├── Features/
│   │   │   ├── Onboarding/  # URL del servidor + login
│   │   │   ├── Library/     # lista, búsqueda, borrado
│   │   │   ├── JobDetail/   # transcripción, progreso, exportar
│   │   │   ├── NewJob/      # origen, motor, modelo, idioma
│   │   │   └── Recorder/    # grabación con AVAudioRecorder (opcional)
│   │   ├── DesignSystem/    # colores, estilos de vidrio, accesorio inferior
│   │   ├── Engines/         # ServerEngine, AppleSpeechEngine
│   │   └── Adapters/        # URLSession, Keychain, BGTask
│   ├── CadenceShare/        # share extension (Fase iOS-7; ver Fase iOS-0)
│   └── CadenceKit/          # lógica pura, sin frameworks de iOS
├── Tests/CadenceKitTests/   # corren con `swift test` en Fedora
└── Resources/
    ├── Info.plist
    ├── Cadence.entitlements
    └── AppIcon.png
```

Partir de la plantilla que genera `xtool new` y adaptar sus nombres; la
estructura exacta de `xtool.yml` es la que documente la versión de xtool
instalada. `CadenceKit` es un *target* del mismo paquete, sin dependencias
de UIKit/SwiftUI, así que `swift test` lo compila y prueba en Fedora como
cualquier paquete de Linux.

---

## 4. Cambios necesarios en el backend

Acotados a `api/`, `adapters/` y una migración; ninguno cambia el
comportamiento del worker ni de la web.

**4.1 Autenticación por token Bearer (imprescindible).** Hoy la sesión es un
JWT en una cookie `httpOnly`. `URLSession` podría manejar cookies, pero un
token explícito en el Keychain es más predecible: se comparte con la share
extension vía Keychain access group, y funciona igual en las sesiones de
subida en segundo plano. Cambios:

- `POST /api/auth/token`: mismas credenciales que `/login`, pero devuelve
  `{"token": "...", "user": {...}}` en el cuerpo en vez de poner la cookie.
  Endpoint separado a propósito: así la web nunca ve el token desde
  JavaScript y conserva la protección de `httpOnly`.
- `get_current_user` en `api/deps.py` acepta `Authorization: Bearer <jwt>`
  además de la cookie. Mismo `decode_session_token`, mismo secreto, misma
  caducidad de 30 días.
- Tests: login por token, petición con Bearer válido, inválido y caducado.

Limitación que hay que conocer: el JWT es sin estado, así que "cerrar
sesión" en la app solo borra el token del teléfono. Si se pierde el iPhone,
la forma de revocar es rotar `SESSION_SECRET`, lo que cierra la sesión de
todos los usuarios en todos los dispositivos. Para un servidor personal es
aceptable; si deja de serlo, la solución es una tabla de sesiones, fuera de
este plan.

**4.2 Estado de una subida por trozos (para reanudar, Fase iOS-11).**
`GET /api/uploads/{id}` que devuelva `{total_parts, received: [0, 1, 4, ...]}`
a partir de los archivos `part-NNNNN` que ya existen en disco. Hoy la única
forma de saber qué falta es llamar a `complete` y leer el 409.

**4.3 Importar una transcripción hecha en el iPhone (Fase iOS-12).** Para
que una transcripción local pueda aparecer también en la biblioteca de la
web, **subiendo solo el texto, nunca el audio**:

- `POST /api/jobs/import` con JSON: `original_filename`,
  `duration_seconds`, `language`, `model` (p. ej. `"apple-speech"`) y la
  lista de `segments`. Crea el trabajo directamente en `status = 'done'`,
  `progress = 1`, sin encolar nada. Validar que los segmentos estén
  ordenados y no se solapen, y un límite razonable de cantidad.
- Migración `0003` (escrita a mano, como las demás): `jobs.stored_path` y
  `jobs.size_bytes` pasan a nullable, porque un trabajo importado no tiene
  archivo. `domain.models.Job.stored_path` pasa a `str | None`, y los tres
  sitios que lo usan (`worker/retention.py`, `DELETE /api/jobs/{id}` y el
  worker) toleran `None`. El worker nunca debería recibir un trabajo
  importado, pero que lo ignore en vez de fallar si ocurre.
- El `model` de un trabajo importado no se valida contra el catálogo de
  Whisper (`adapters/model_catalog.py`): es una etiqueta informativa. La web
  lo muestra tal cual.
- Los exportadores del servidor funcionan sin cambios, porque solo leen
  segmentos.

**4.4 Registro de dispositivos para push (opcional, Fase iOS-13).** Tabla
`devices (user_id, apns_token, created_at)` con migración escrita a mano, y
`POST`/`DELETE /api/devices`. El worker, al pasar un trabajo a `done` o
`error`, envía la notificación a APNs. Solo si se decide hacer push real;
la Fase iOS-13 tiene una variante sin backend.

**No hace falta cambiar:**

- Los formatos aceptados. Lo que llega a un iPhone es `.m4a` (Notas de Voz,
  grabaciones), `.opus`/`.ogg` (notas de voz de WhatsApp y Telegram),
  `.mp3`, o video `.mov`/`.mp4`; todos menos `.mov` ya están en
  `ALLOWED_EXTENSIONS`. En vez de añadir `.mov` al backend, la app **extrae
  la pista de audio a `.m4a` en el dispositivo** con `AVAssetExportSession`:
  además de evitar el formato, reduce un video de cientos de MB a unos
  pocos, que es justo lo que importa en datos móviles.
- El SSE. A diferencia del `EventSource` del navegador, `URLSession` puede
  mandar la cabecera `Authorization` en el stream sin problema.

---

## 5. Los dos motores

| | Servidor (Whisper en el ProDesk) | En este iPhone (Speech de Apple) |
|---|---|---|
| Dónde va el audio | se sube al ProDesk | **no sale del teléfono** |
| Conexión | necesaria para subir | no (solo la primera vez por idioma, para descargar el modelo) |
| Velocidad | ~1.5× la duración con `large-v3-turbo`, en una cola compartida de concurrencia 1 | depende del iPhone; **medir** en la Fase iOS-8 |
| Calidad | Whisper, seleccionable de `tiny` a `large-v3` | un modelo por idioma, gestionado por iOS; **medir** con el mismo audio |
| Idioma | detección automática o elegido | se elige antes de empezar (sección 11) |
| Batería del iPhone | casi nada, solo la subida | consume CPU/Neural Engine durante toda la transcripción |
| Formatos | todos los de `ALLOWED_EXTENSIONS` | los que lea `AVFoundation`; `.opus`/`.ogg` **verificar** (sección 11) |
| Límites | 500 MB por archivo, 5 trabajos activos | almacenamiento libre del teléfono |
| Biblioteca | aparece en la app y en la web | solo en el iPhone, salvo que se sincronice el texto (Fase iOS-12) |

La elección se hace **por trabajo**, en la hoja de nueva transcripción
(tanto en la app como en la share extension), con un valor por defecto en
Ajustes. Reglas de la interfaz:

- Sin conexión, el motor Servidor aparece deshabilitado con el motivo, y se
  preselecciona el iPhone.
- Si el modelo del idioma elegido no está descargado, se ofrece descargarlo
  con su tamaño y progreso (`AssetInventory`) antes de empezar; sin
  conexión y sin modelo, el motor iPhone queda deshabilitado para ese
  idioma.
- Si el dispositivo no soporta `SpeechTranscriber`, el selector de motor no
  aparece y todo va al servidor.
- La estimación de tiempo se muestra para los dos motores: la del servidor
  con `speed_factor` de `GET /api/models`; la del iPhone con un factor
  medido en el propio dispositivo en la Fase iOS-8 (y luego refinado con el
  promedio de los trabajos reales hechos en ese teléfono).

### Cómo funciona el motor del iPhone

1. El audio (compartido desde otra app, elegido en Archivos o grabado) ya
   está en el contenedor de la app.
2. `AppleSpeechEngine` crea un `SpeechTranscriber` para el idioma elegido,
   pidiendo resultados con marcas de tiempo (`audioTimeRange`), y un
   `SpeechAnalyzer` con ese módulo.
3. La app **no le pasa el archivo entero al analizador**: lo lee ella misma
   con `AVAudioFile` en bloques, lo convierte al formato que pide el
   analizador (`bestAvailableAudioFormat`, con `AVAudioConverter`) y lo
   entrega como flujo de entrada. Esto da dos cosas: progreso exacto
   (posición leída ÷ duración total, el mismo concepto que el progreso de
   faster-whisper en el worker) y la capacidad de **reanudar desde un
   punto** si el sistema interrumpe la tarea (paso 5).
4. Cada resultado final se convierte en un `Segment` (inicio, fin, texto) y
   se guarda de inmediato en el almacén local, igual que el worker escribe los
   segmentos por lotes en Postgres. La interfaz muestra texto parcial
   mientras avanza.
5. Si el sistema expira la tarea en segundo plano o la app muere, el trabajo
   queda con sus segmentos hasta el último tiempo guardado. Al volver, se
   reanuda leyendo el audio desde esa posición y sumando el desplazamiento a
   las marcas de tiempo nuevas. Nunca se reinicia desde cero.

### Segundo plano en el motor del iPhone

`BGContinuedProcessingTask` (iOS 26) existe para esto exactamente: una
tarea **iniciada por el usuario** que puede seguir cuando la app pasa a
segundo plano, con su progreso visible en la interfaz del sistema y la
opción de cancelarla desde ahí.

- Al tocar "Transcribir en este iPhone", la app envía un
  `BGContinuedProcessingTaskRequest` con título ("Transcribiendo
  reunión.m4a") y subtítulo. Tiene que ser **en respuesta a esa acción y
  con la app en primer plano**; no se puede lanzar sola más tarde.
- El manejador de la tarea ejecuta `AppleSpeechEngine` y actualiza el
  `progress` de la tarea con la fracción del paso 3. **Reportar progreso
  con regularidad no es cosmético**: el sistema usa esa señal para decidir
  si la tarea sigue viva.
- Al terminar, se marca la tarea como completada y se lanza una
  **notificación local** ("Transcripción lista"). Esto no necesita APNs ni
  cuenta de pago.
- Si el sistema la expira (poca batería, temperatura alta, presión de
  memoria), el manejador de expiración guarda el estado y el trabajo queda
  como "pausado" con un botón de continuar; al abrir la app se ofrece
  reanudarlo (paso 5).
- Un solo trabajo local a la vez, en cola, por la misma razón que el worker
  del servidor tiene concurrencia 1: dos en paralelo no terminan antes y
  calientan más el teléfono.

**Esto hay que verificarlo primero, antes de construir encima.** La
documentación de `BGContinuedProcessingTask` y la de `SpeechAnalyzer`
existen por separado; que la combinación funcione con la pantalla
bloqueada durante una transcripción de 40 minutos, sin que el sistema la
expire, es lo que la Fase iOS-9 prueba antes de nada. Si resulta que no es
fiable, el respaldo es el paso 5: la transcripción avanza siempre que la app
tiene tiempo de ejecución y se reanuda sola al volver, sin perder trabajo.

---

## 6. De dónde sale el audio

Grabar dentro de Cadence **no es obligatorio**: lo normal es grabar con la
app que ya se usa (Notas de Voz, la grabadora de una reunión, un audio de
WhatsApp) y mandarlo a Cadence después. Hay tres entradas, de más a menos
importante:

1. **Hoja de compartir → Cadence (share extension, Fase iOS-7).** Funciona
   desde cualquier app que comparta archivos de audio o video: Notas de Voz
   (botón de compartir de una grabación), WhatsApp y Telegram (mantener
   pulsado el audio → Reenviar/Compartir), Archivos, Mail, Safari. Aparece
   una hoja compacta de Cadence encima de la app de origen, con el nombre y
   la duración del audio y los selectores de motor, modelo e idioma; se
   pulsa *Transcribir* y se vuelve a lo que se estaba haciendo.
2. **Elegir un archivo desde la app (Fase iOS-4).** `.fileImporter`
   muestra Archivos e iCloud Drive. Además la app se declara como
   manejadora de audio (`CFBundleDocumentTypes` para `public.audio` y
   `public.movie`), así que en las apps que ofrecen *Abrir con…* aparece
   Cadence, y al elegirla se abre directamente la hoja de nueva
   transcripción con el archivo cargado (`.onOpenURL`).
3. **Grabar dentro de la app (Fase iOS-10, opcional).** Útil para no salir de
   Cadence, pero prescindible: si se corta, las otras dos entradas cubren el
   caso.

Lo que la app **no** puede hacer: listar ni leer la biblioteca de Notas de
Voz por su cuenta. iOS no expone esas grabaciones a otras apps; siempre hay
que compartirlas desde Notas de Voz (o guardarlas antes en Archivos).

---

## 7. Diseño: Liquid Glass y estilo Apple

El objetivo es que Cadence parezca una app hecha por Apple, en la línea de
Notas de Voz, Música y Podcasts (que también muestra transcripciones
sincronizadas). Liquid Glass es el lenguaje visual de iOS 26: una capa de
vidrio translúcido para la navegación y los controles, que flota sobre el
contenido y refleja lo que hay debajo.

**La mayor parte llega gratis.** Al compilar con el SDK de iOS 26, los
componentes estándar de SwiftUI (`TabView`, barras de herramientas de
`NavigationStack`, hojas, búsqueda, menús, `ShareLink`) ya se dibujan con
Liquid Glass. Por eso la regla de la app es **usar los componentes del
sistema siempre que existan** y no fabricar equivalentes propios: un control
propio se queda con el aspecto de iOS 18 y además no hereda la
accesibilidad del sistema.

**La regla de Apple para el vidrio: navegación sí, contenido no.** El vidrio
es para lo que flota (barra de pestañas, barras de herramientas, botones
flotantes, hojas). El texto de una transcripción, las filas de la biblioteca
y los formularios van sobre fondo sólido, porque la legibilidad manda.
Ponerle `.glassEffect()` a cada fila es el error típico: se ve peor, se lee
peor y cuesta rendimiento.

Piezas concretas:

- **Pestañas.** `TabView` con *Biblioteca* y *Ajustes*, y una pestaña de
  búsqueda con `role: .search`, que en iOS 26 se separa de las demás en su
  propia burbuja de vidrio. `.tabBarMinimizeBehavior(.onScrollDown)` para
  que la barra se encoja al leer una transcripción larga.
- **El accesorio inferior, la pieza característica.** Con
  `.tabViewBottomAccessory`, una barra de vidrio encima de las pestañas,
  como el mini reproductor de Música, muestra el trabajo activo: "Subiendo
  reunión.m4a · 42 %", "Transcribiendo en el iPhone · 3 min restantes" o
  "Grabando 12:04". Tocarla abre el detalle. Así el progreso está siempre a
  la vista sin ocupar pantalla.
- **Nueva transcripción.** Botón `+` en la barra de herramientas que abre
  una hoja con *detents* (`.medium`, `.large`), que en iOS 26 es de vidrio
  cuando está a media altura. Motor como `Picker` segmentado; modelo e
  idioma como menús.
- **Barras de herramientas.** Exportar (`square.and.arrow.up`), copiar y
  borrar como `ToolbarItem`, agrupados en cápsulas de vidrio con
  `ToolbarSpacer`.
- **Controles propios, los mínimos.** Solo el botón de grabar y los
  controles de la grabadora: `.buttonStyle(.glassProminent)` teñido con el
  color de acento, dentro de un `GlassEffectContainer`, con
  `glassEffectID` para que el botón *grabar* se transforme en *pausa /
  detener* con la animación de fusión del vidrio.
- **SF Symbols con efectos.** `waveform` animado mientras se graba o
  transcribe (`.symbolEffect(.variableColor)`), transición a
  `checkmark.circle.fill` al terminar (`.contentTransition(.symbolEffect(.replace))`),
  `iphone` y `server.rack` como distintivos de motor.
- **Tipografía.** SF del sistema con estilos de texto (`.largeTitle`,
  `.body`, `.caption`), títulos grandes en las listas, y
  `.monospacedDigit()` en marcas de tiempo y duraciones para que no
  "bailen" mientras cambian. Dynamic Type en todo.
- **Color.** Colores semánticos del sistema (`.primary`, `.secondary`,
  fondos agrupados) más **un solo color de acento** derivado de la paleta de
  `frontend/app/globals.css`. Como sin Xcode no hay catálogo de assets
  compilado, el acento se define en código en `DesignSystem/` (un
  `UIColor` dinámico con variante clara y oscura, expuesto como `Color` y
  aplicado con `.tint()` en la raíz). Ningún color escrito a mano en las
  vistas: todas usan los de `DesignSystem/`.
- **Hápticos.** `.sensoryFeedback(.success, trigger:)` al terminar una
  transcripción, `.impact` al empezar a grabar, `.warning` en errores.
- **Detalle de la transcripción.** Inspirado en las transcripciones de
  Podcasts: texto grande y legible por bloques, marca de tiempo discreta a
  la izquierda, y (con audio local, Fase iOS-15) el segmento actual
  resaltado mientras suena.
- **Icono.** Los iconos en capas de iOS 26 (con variantes clara, oscura,
  teñida y transparente) se hacen con Icon Composer y se compilan con
  `actool`, ambos exclusivos de macOS. Con xtool, el icono es un PNG de
  1024×1024 declarado en el Info.plist o en `xtool.yml` (según lo que
  soporte la versión instalada; verificar en la Fase iOS-0). Diseñarlo
  sobrio y centrado (una onda de audio sobre el color de acento) para que se
  vea bien aunque iOS no le aplique las variantes.
- **Pantalla de bloqueo.** La interfaz de progreso de
  `BGContinuedProcessingTask` y, si se hace, la Live Activity (Fase iOS-13)
  ya son del sistema y salen con su estilo.
- **Accesibilidad.** El vidrio estándar se adapta solo a *Reducir
  transparencia*, *Aumentar contraste* y *Reducir movimiento*; comprobar
  que el accesorio inferior y el botón de grabar también lo hacen, y que
  todo se puede usar con VoiceOver.

Los nombres exactos de estas APIs de Liquid Glass se estrenaron en iOS 26 y
algunos cambiaron durante las betas: verificar contra la documentación del
SDK instalado en vez de confiar en ejemplos de blogs.

---

## 8. Pantallas

Se replica la estructura de la web (`upload-section.tsx`,
`library-section.tsx`, `top-nav.tsx`), adaptada a convenciones de iOS y al
diseño de la sección 7. Toda la interfaz en español, con las cadenas
escritas directamente en las vistas: los catálogos `.xcstrings` necesitan
el compilador de Xcode. Si algún día se añade inglés, se pasa a archivos
`.strings` clásicos, que son texto plano y se copian tal cual al paquete.

1. **Configuración inicial.** Campo para la URL del servidor (es autoalojado:
   no puede ir fija en el código), validada con `GET /api/health` antes de
   continuar. Después, login con correo y contraseña. Ambos valores se
   recuerdan; la URL se puede cambiar desde Ajustes. Se puede **saltar** y
   usar la app solo con el motor del iPhone; el servidor se configura
   después desde Ajustes. Una última pantalla explica cómo mandar audio
   desde Notas de Voz (*Compartir → Cadence*), porque es la forma principal
   de usar la app y no es obvia.
2. **Biblioteca** (pestaña principal). Trabajos del servidor y locales en
   una sola lista ordenada por fecha, con título, fecha, duración, idioma,
   palabras y estado; los locales llevan un distintivo "En este iPhone".
   Los trabajos en proceso muestran su barra y etapa en la propia fila, y el
   activo además en el accesorio inferior. Búsqueda por título y archivo
   (filtro local, igual que la web). Deslizar para borrar, con confirmación.
   *Pull to refresh.* Menú contextual (mantener pulsado) con exportar,
   copiar y borrar.
3. **Detalle de la transcripción.** Segmentos con su marca de tiempo; chip de
   hablante solo si `speaker` no es `nil` (igual que la web). Selección y
   copia de texto. Si el trabajo sigue en proceso: progreso en vivo con la
   etapa y el tiempo transcurrido, y el texto que ya existe. Si falló o quedó
   pausado: el motivo y el botón de reintentar o continuar. En trabajos
   locales: "Subir texto al servidor" (Fase iOS-12).
4. **Nueva transcripción** (hoja desde `+`, desde *Abrir con…* o desde la
   share extension). Origen: *Elegir archivo* o *Grabar* (si el audio llega
   de otra app, ya viene cargado). **Motor: Servidor / En este iPhone**, con
   las reglas de la sección 5. Con Servidor: selector de modelo alimentado
   por `GET /api/models`, con el papel de cada uno ("defecto rápido",
   "defecto de calidad"). Selector de idioma con las mismas opciones que la
   web (`upload-section.tsx`); con el motor iPhone, "Detectar
   automáticamente" se sustituye por el idioma del sistema como valor por
   defecto, y cada idioma indica si su modelo ya está descargado. Estimación
   de tiempo para el motor elegido.
5. **Grabadora** (opcional). Botón grande de vidrio, tiempo transcurrido,
   medidor de nivel, pausa/continuar. Al terminar: escuchar, descartar o
   enviar al motor elegido.
6. **Exportar.** Menú con los seis formatos; se genera un archivo temporal
   con el nombre correcto y se abre la hoja de compartir del sistema
   (`ShareLink`), que ya permite guardarlo en Archivos, mandarlo por
   WhatsApp, AirDrop, etc. Vista previa del PDF con QuickLook. Para trabajos
   del servidor, el archivo viene de `GET /export`; para trabajos locales,
   lo generan los exportadores de `CadenceKit` en el teléfono.
7. **Ajustes.** Usuario activo, URL del servidor, cerrar sesión, motor,
   modelo e idioma por defecto, modelos de voz descargados en el iPhone (con
   su tamaño y opción de borrarlos), sincronizar automáticamente el texto de
   los trabajos locales (apagado por defecto), versión de la app y del
   servidor.

---

## 9. Plan por fases

Igual que en el plan original: cada fase es una rebanada vertical que se
ejecuta y se ve funcionando, no una capa. Las fases iOS-0 a iOS-7 forman
una app completa con el motor del servidor, incluida la hoja de compartir;
iOS-8 e iOS-9 añaden el motor del iPhone con segundo plano; de iOS-10 en
adelante son mejoras independientes que se pueden reordenar o cortar.

El diseño de la sección 7 no es una fase aparte del final: cada pantalla se
construye directamente con los componentes del sistema y Liquid Glass desde
la fase en que aparece. La Fase iOS-15 solo pule.

### Fase iOS-0 — Esqueleto

En Fedora: instalación de xtool y del SDK según la sección 10, y proyecto
en `ios/` a partir de `xtool new`, con el target de la app y `CadenceKit`.
Versiones fijadas. `CadenceKit` con los modelos `Codable` que reflejan
`api/schemas.py` (`JobOut`, `SegmentOut`, `UserOut`, `ModelOut`), probados
contra JSON real capturado del backend con `curl` (guardado como fixture en
`Tests/`). Puerto `TranscriptionEngine` definido. Test de arquitectura:
`CadenceKit` no importa frameworks de UI ni de sistema.

**Lo más importante de esta fase es comprobar los límites de xtool antes de
escribir nada encima**, con una app de prueba mínima instalada en el iPhone
15. Cada punto que falle cambia una parte concreta del plan:

| Comprobar | Si falla |
|---|---|
| `@Observable` compila (macro del toolchain, debería) | estado con `ObservableObject` + `@Published`, sin macros |
| Liquid Glass aparece en un `TabView` con el SDK de iOS 26 | revisar que el SDK extraído sea el de Xcode 26+ |
| `SpeechTranscriber` disponible en el iPhone 15 y con español (`supportedLocales`) | el motor local se evalúa con `DictationTranscriber` o se corta |
| xtool soporta un target de share extension | Fase iOS-7 se reduce a *Abrir con…* (sección 6) hasta que lo soporte |
| Entitlements: App Groups, Keychain Sharing, Background Modes con la cuenta del usuario | sin App Groups no hay share extension; sin `processing` no hay segundo plano local |
| Icono PNG visible en la pantalla de inicio | probar la otra forma de declararlo (Info.plist o `xtool.yml`) |
| Logs de `os.Logger` visibles con `idevicesyslog` | es la única herramienta de diagnóstico; resolverlo antes de seguir |

*Terminada cuando:* la app abre en el iPhone 15 con un `TabView` vacío (ya
con la barra de vidrio de iOS 26), `swift test` pasa en Fedora (incluyendo
decodificar un `JobOut` real con fechas y segmentos), y la tabla de arriba
está respondida y anotada en el `CLAUDE.md`.

### Fase iOS-1 — Autenticación por token en el backend

Los cambios de la sección 4.1, con sus tests en `backend/tests/`.

*Terminada cuando:* `curl -X POST .../api/auth/token` devuelve un token,
`curl -H "Authorization: Bearer <token>" .../api/jobs` lista los trabajos, y
la web sigue funcionando con cookie sin ningún cambio.

### Fase iOS-2 — Conexión y login

Pantalla de URL del servidor con validación por `/api/health`, login contra
`/api/auth/token`, token guardado en Keychain
(`kSecAttrAccessibleAfterFirstUnlock`, para que las tareas en segundo plano
puedan leerlo con el teléfono bloqueado). Al arrancar: si hay token, se
valida con `/api/auth/me`; un 401 en cualquier momento lleva de vuelta al
login. Cerrar sesión borra el token.

*Terminada cuando:* desde el iPhone con datos móviles (no solo en la red
local) se inicia sesión contra el dominio de Cloudflare, se
cierra la app, se vuelve a abrir y la sesión sigue activa.

### Fase iOS-3 — Biblioteca y detalle (solo lectura)

Lista desde `GET /api/jobs`, detalle desde `GET /api/jobs/{id}`, búsqueda
con la pestaña `role: .search`, *pull to refresh*, borrado con `DELETE`.
Estados vacíos y de error con mensajes en español (sin conexión, servidor
caído, sesión caducada), con `ContentUnavailableView`.

*Terminada cuando:* la app muestra exactamente los mismos trabajos que la
web para el mismo usuario, se puede leer una transcripción completa y borrar
un trabajo desde el iPhone hace que desaparezca también de la web.

### Fase iOS-4 — Elegir audio y subirlo (motor Servidor)

Entradas 2 de la sección 6: `.fileImporter` y *Abrir con Cadence*
(`CFBundleDocumentTypes` + `.onOpenURL`). El archivo se copia de inmediato
al contenedor de la app, porque el acceso con *security-scoped URL* es
temporal. Si es video, se extrae el audio a `.m4a` con
`AVAssetExportSession`. Hoja de nueva transcripción con modelo, idioma y
estimación. Subida por trozos de 8 MB (`/api/uploads` → `PUT parts/{n}` →
`complete`), secuencial, con barra de progreso real por bytes enviados, que
ya se muestra en el accesorio inferior. En esta fase la subida ocurre en
primer plano (con `beginBackgroundTask` para tener unos segundos de gracia
si el usuario cambia de app); la subida de verdad en segundo plano es la
Fase iOS-11. Manejar los errores que ya devuelve el backend: 413 (tamaño),
429 (demasiados trabajos en cola), 400 (formato o modelo).

*Terminada cuando:* una grabación de Notas de Voz de 30 minutos, guardada en
Archivos, se elige desde la app, se sube por datos móviles, aparece en la
biblioteca de la app y de la web, y se transcribe.

### Fase iOS-5 — Progreso en vivo

Cliente de SSE para `GET /api/jobs/{id}/events`: `URLSession.bytes(for:)`
con la cabecera `Authorization`, cuyas líneas pasan a un parser puro en
`CadenceKit` que produce eventos `progress` / `done` / `error`, probado con
tests. El detalle, las filas de la biblioteca en proceso y el accesorio
inferior se actualizan en vivo. Al recibir `done` se recarga el trabajo con
sus segmentos. Con esto, `ServerEngine` implementa el puerto
`TranscriptionEngine` completo.

iOS suspende la app poco después de ir a segundo plano y el stream muere sin
avisar. No se intenta evitarlo: el servidor sigue procesando de todos modos,
y al volver a primer plano (`scenePhase == .active`) se recargan los
trabajos activos y se reabren sus streams.

*Terminada cuando:* la barra avanza de forma continua (no a saltos) durante
una transcripción real, y bloquear el teléfono a mitad y desbloquearlo
retoma el progreso correcto en menos de dos segundos.

### Fase iOS-6 — Exportación

Los seis formatos de `GET /api/jobs/{id}/export?format=`, descargados a un
archivo temporal con el nombre que dicta `Content-Disposition` (que ya viene
con `filename*` en UTF-8 para tildes y eñes), compartidos con `ShareLink`.
Vista previa del PDF. "Copiar texto" en el detalle usa los segmentos ya
cargados, sin petición extra.

*Terminada cuando:* los seis formatos se guardan en Archivos o se mandan por
correo a la laptop y abren correctamente, incluyendo un archivo cuyo nombre
lleva tildes y eñes.

### Fase iOS-7 — Compartir desde otras apps

Entrada 1 de la sección 6, la principal. Target de share extension que
acepta audio y video (`NSExtensionActivationRule` para `public.audio` y
`public.movie`, un archivo a la vez).

Lo primero es verificar que la cuenta de desarrollador permite App Groups
(sección 1). Después:

- La extensión **nunca carga el audio en memoria** ni transcribe: tiene un
  límite de unos 120 MB. Copia el archivo al contenedor compartido del App
  Group (la `Inbox` de `CadenceKit`) junto con las opciones elegidas.
- Muestra una hoja compacta de Cadence, en SwiftUI con el mismo estilo que
  la app: nombre, duración, motor, modelo, idioma, y *Transcribir*.
- En esta fase, la app procesa la bandeja de entrada la próxima vez que se
  activa, y la extensión lo dice ("Listo. Se enviará al abrir Cadence"). Con
  la sesión en segundo plano de la Fase iOS-11, el motor Servidor pasa a
  subir directamente desde la extensión sin abrir la app. El motor iPhone
  siempre necesita abrir la app, porque `BGContinuedProcessingTask` se lanza
  desde la app en primer plano (sección 5).
- Token compartido con la app vía Keychain access group.
- Verificar en el iPhone real cada origen: Notas de Voz (`.m4a`), WhatsApp y
  Telegram (`.opus`/`.ogg`), Archivos, Mail.

*Terminada cuando:* en Notas de Voz, *Compartir → Cadence* con una
grabación de 20 minutos, y en WhatsApp, reenviar una nota de voz a Cadence,
terminan las dos transcritas en el servidor y visibles en la web.

**Con esto hay una app completa con el motor del servidor.**

### Fase iOS-8 — Transcripción en el iPhone (primer plano)

`AppleSpeechEngine` según la sección 5, pasos 1–4, todavía sin segundo
plano:

- Comprobar disponibilidad de `SpeechTranscriber` en el dispositivo e
  idiomas soportados; descargar el modelo del idioma con `AssetInventory`,
  con progreso, y listar los ya instalados.
- Lectura del audio en bloques, conversión de formato, envío al analizador,
  conversión de resultados a `Segment` con sus marcas de tiempo. Si
  `AVFoundation` no lee `.opus`/`.ogg` (notas de WhatsApp/Telegram), esos
  archivos solo ofrecen el motor Servidor, con el motivo a la vista.
- Trabajos locales en `FileJobStore` (`origin = .device`): la biblioteca los
  muestra mezclados con los del servidor; borrarlos borra también el audio
  local.
- **Exportadores en `CadenceKit`**: `txt`, `md`, `json`, `srt` y `vtt`
  portados desde `backend/src/domain/exporters/`. Para garantizar que
  producen exactamente lo mismo que el servidor, se generan archivos de
  referencia con los exportadores de Python sobre un fixture de segmentos,
  se commitean en `ios/CadenceKit/Tests/`, y los tests de Swift comparan
  byte a byte. El PDF local se genera con `UIGraphicsPDFRenderer` en la app
  (no en `CadenceKit`), con un diseño sencillo; no tiene que ser idéntico al
  de WeasyPrint.
- Selector de motor en la hoja de nueva transcripción y en la share
  extension.
- **Medición**, como la Fase 5 del servidor: el mismo audio de 5 minutos en
  español por los dos motores; anotar tiempo, calidad percibida y consumo de
  batería. El factor de velocidad medido alimenta la estimación del motor
  iPhone.

*Terminada cuando:* con el modo avión activado (y el modelo de español ya
descargado), se transcribe en el iPhone una nota de Notas de Voz de 10
minutos con la app abierta, el texto va apareciendo mientras avanza, y el
`.srt` exportado se reproduce sincronizado con el audio en VLC.

### Fase iOS-9 — Transcripción en el iPhone en segundo plano

**Primero, una prueba de concepto aislada**: `BGContinuedProcessingTask`
ejecutando `AppleSpeechEngine` sobre un audio de 40 minutos con la pantalla
bloqueada. Si el sistema la expira antes de terminar, saberlo ahora cambia
el diseño de la interfaz (más énfasis en "pausado, toca para continuar").

Después, la integración de la sección 5 ("Segundo plano en el motor del
iPhone"): envío de la tarea al tocar transcribir, progreso reportado al
sistema, cancelación desde la interfaz del sistema, notificación local al
terminar, cola de un trabajo local a la vez, y reanudación desde el último
segmento guardado tras una expiración o un cierre forzado (sección 5, paso
5). Permiso de notificaciones pedido la primera vez que se lanza un trabajo
en segundo plano, no al abrir la app.

*Terminada cuando:* se inicia una transcripción local de 40 minutos, se
bloquea el teléfono de inmediato, el progreso se ve en la pantalla de
bloqueo, y llega la notificación de terminado. Y: cerrar la app a la fuerza
a la mitad y volver a abrirla reanuda desde donde iba, sin segmentos
duplicados ni huecos en las marcas de tiempo.

### Fase iOS-10 — Grabar en la app *(opcional)*

`AVAudioRecorder` en AAC mono a 16 kHz (que es lo que Whisper usa
internamente: grabar a más calidad solo agranda la subida sin mejorar la
transcripción) en un `.m4a`. Permiso de micrófono con
`NSMicrophoneUsageDescription` en español. Modo de fondo `audio` y
`AVAudioSession` en categoría `.record` para que la grabación siga con la
pantalla bloqueada. Manejar interrupciones (llamada entrante): pausar y
dejar que el usuario continúe, no perder lo grabado. Botón de grabar con
vidrio y transformación de estados (sección 7). Al terminar, el audio va al
motor elegido.

**Si se complica, se corta aquí:** grabar en Notas de Voz y compartir a
Cadence (Fase iOS-7) cubre el mismo caso con un paso más.

*Terminada cuando:* se graba una reunión de 40 minutos con la pantalla
bloqueada todo el tiempo, se recibe una llamada a la mitad, y la grabación
completa se transcribe con cada uno de los dos motores.

### Fase iOS-11 — Subida en segundo plano y reanudación (motor Servidor)

Pasar la subida a una `URLSessionConfiguration.background`, compartida
entre la app y la share extension (`sharedContainerIdentifier` del App
Group). Esto exige cambios de diseño que no son opcionales en este tipo de
sesión:

- Cada trozo se escribe a un archivo temporal y se sube con
  `uploadTask(with:fromFile:)` (las sesiones de fondo no aceptan cuerpos en
  memoria).
- Nada de `async/await` ni *completion handlers*: solo delegados. El
  sistema puede relanzar la app en segundo plano cuando terminan las tareas
  (`handleEventsForBackgroundURLSession`), incluidas las que inició la
  extensión, así que el estado de la subida (upload_id, partes enviadas) se
  persiste en el App Group, no en memoria.
- Al terminar la última parte, el delegado llama a `complete`.

Con el endpoint de la sección 4.2, si la subida se corta (sin cobertura, app
cerrada a la fuerza) se reanuda pidiendo qué partes faltan y mandando solo
esas, en vez de reiniciar los 200 MB.

*Terminada cuando:* desde Notas de Voz se comparte a Cadence un audio de
200 MB con el motor Servidor, se bloquea el teléfono de inmediato **sin
haber abierto Cadence**, y al desbloquearlo 10 minutos después el trabajo ya
está en cola en el servidor. Y: activar el modo avión a mitad de una subida
y desactivarlo la reanuda desde la parte correcta.

### Fase iOS-12 — Sincronizar transcripciones locales *(secundaria)*

Los cambios de backend de la sección 4.3, y en la app: "Subir texto al
servidor" en el detalle de un trabajo local, más la opción de hacerlo
automáticamente en Ajustes (apagada por defecto, porque quien elige el motor
local puede hacerlo precisamente para que nada salga del teléfono). Tras
sincronizar, el trabajo local guarda el `id` del servidor para no subirlo
dos veces, y el distintivo cambia a "En este iPhone · sincronizado".

*Terminada cuando:* una transcripción hecha en modo avión, al recuperar la
conexión y pulsar "Subir texto", aparece en la biblioteca de la web, se
exporta desde la web en los seis formatos, y el servidor no recibió ningún
byte de audio (comprobable en `docker compose logs api` y en el volumen
`audio_storage`).

### Fase iOS-13 — Notificaciones de trabajos del servidor *(secundaria)*

Los trabajos locales ya notifican desde la Fase iOS-9. Para los del
servidor hay dos variantes; empezar por la A.

- **A — Sin backend.** Notificaciones locales. Mientras haya trabajos
  activos en el servidor, una `BGAppRefreshTask` consulta su estado y
  notifica si alguno terminó. Gratis y sin cuenta de pago, pero **iOS decide
  cuándo la ejecuta** (a veces en minutos, a veces en horas), así que es un
  aviso "eventual", no inmediato.
- **B — Push real con APNs.** Los cambios de la sección 4.4. Inmediato y
  fiable, pero requiere la cuenta de pago, una clave `.p8` de APNs en el
  servidor y que el worker haga una petición saliente a Apple. Solo
  transporta el id del trabajo y su título.

Opcional encima de B: una **Live Activity** con el progreso en la pantalla
de bloqueo y la Dynamic Island. Sin push, una Live Activity solo se
actualiza mientras la app está en primer plano, así que no compensa sin B.

*Terminada cuando (A):* con la app cerrada, termina una transcripción del
servidor y en algún momento llega una notificación que al tocarla abre ese
trabajo. *(B):* la notificación llega en menos de 10 segundos.

### Fase iOS-14 — Biblioteca sin conexión

Caché de los trabajos del servidor en el mismo `FileJobStore`. Los
trabajos terminados y sus segmentos se guardan al abrirse; la biblioteca y
el detalle se leen del caché y se refrescan desde la red cuando la hay. Un
trabajo borrado en el servidor se borra del caché en la siguiente
sincronización. (Los trabajos locales ya viven ahí desde la Fase iOS-8.)

*Terminada cuando:* con el modo avión activo se puede leer y exportar en
texto una transcripción del servidor abierta antes.

### Fase iOS-15 — Pulido y distribución

- Revisión de diseño contra la sección 7 en todas las pantallas, en claro y
  oscuro, con *Reducir transparencia* y *Aumentar contraste* activados, y
  con el tamaño de texto más grande de Dynamic Type.
- Icono final (PNG, sección 7).
- Reproducir el audio local (cuando se compartió, eligió, grabó o
  transcribió desde este iPhone) sincronizado con la transcripción: tocar un
  segmento salta a ese momento y el segmento actual se resalta, como en
  Podcasts. Solo con el audio que el dispositivo ya tiene; el servidor no
  expone el audio y además lo borra por retención.
- Retención local: borrar el audio de trabajos locales con más de N días,
  conservando el texto, igual que `worker/retention.py` en el servidor.
- Distribución definitiva según la sección 10.

---

## 10. Compilar, firmar e instalar desde Fedora (xtool)

iOS solo ejecuta apps firmadas con un certificado que el iPhone reconoce.
xtool obtiene ese certificado con el Apple ID del usuario (igual que Xcode),
firma la app y la instala por USB. No hace falta Mac en ningún paso del
desarrollo.

**Preparación (una vez, en la laptop con Fedora):**

1. **Toolchain de Swift.** Ya instalado. Comprobar con `swift --version`
   que su versión mayor coincide con la del Swift que trae el Xcode del que
   se va a sacar el SDK (lo dicen las notas de versión de ese Xcode). Si no
   coinciden, actualizar el toolchain (con `swiftly`, si se instaló así).
2. **Comunicación USB con el iPhone.** `usbmuxd` y las utilidades de
   `libimobiledevice` (en Fedora, `sudo dnf install usbmuxd
   libimobiledevice-utils`; confirmar los nombres con `dnf search` si
   cambian). El servicio `usbmuxd` tiene que estar corriendo.
3. **xtool.** Instalarlo según las instrucciones de su repositorio para
   Linux, y fijar la versión usada en el `CLAUDE.md`.
4. **SDK de iOS.** Descargar el `.xip` de **Xcode 26 o posterior** desde
   developer.apple.com (basta un Apple ID gratuito) y ejecutar `xtool
   setup`, que extrae el SDK del `.xip` e inicia sesión con el Apple ID para
   firmar. El `.xip` y el SDK extraído **nunca** van al repo: pesan varios GB
   y su licencia no permite redistribuirlos.
5. **iPhone 15.** Conectarlo por USB-C, aceptar *Confiar en esta
   computadora* y comprobar con `idevicepair validate`. Activar *Ajustes →
   Privacidad y seguridad → Modo de desarrollador* (pide reiniciar); si la
   opción no aparece, suele aparecer tras el primer intento de instalar una
   app de desarrollo (libimobiledevice también tiene una utilidad para
   mostrarla, `idevicedevmodectl`; verificar que la versión instalada la
   incluya). Con cuenta gratuita, tras la primera instalación hay que
   confiar en el certificado en *Ajustes → General → VPN y gestión de
   dispositivos*.

**Ciclo de trabajo diario:**

- `swift test` en `ios/`: compila y prueba `CadenceKit` en Fedora, sin
  iPhone. Es inmediato; toda la lógica que se pueda probar aquí, se prueba
  aquí.
- `xtool dev` en `ios/`: compila contra el SDK de iOS, firma, instala en el
  iPhone conectado y abre la app. Reinstalar encima conserva los datos de la
  app.
- `idevicesyslog`, filtrado por el proceso `Cadence`: los logs de
  `os.Logger`. Usar un subsistema propio (`com.<usuario>.cadence`) y
  categorías por módulo (`upload`, `sse`, `speech`, `bgtask`) para poder
  filtrar.

**Cuenta gratuita o de pago, con xtool:**

| | Apple ID gratuito | Programa de pago |
|---|---|---|
| Firma dura | 7 días: volver a ejecutar `xtool dev` con el iPhone conectado | 1 año |
| Apps instaladas a la vez | pocas (la share extension tiene su propio identificador y cuenta para los límites) | sin límite práctico |
| Notificaciones push (APNs) | no | sí |
| App Groups y otras capacidades | limitadas: verificar en la Fase iOS-0 | sí |

Para no depender del cable cada semana con la cuenta gratuita, SideStore
puede renovar la firma de 7 días desde el propio iPhone una vez
configurado; es opcional y se evalúa si la reinstalación semanal molesta.

**Dar la app a otros usuarios del servidor.** Con firma de desarrollo, la
app solo se instala en dispositivos del propio Apple ID. Para otros hace
falta la cuenta de pago y TestFlight, y subir una build a App Store Connect
se hace normalmente con herramientas de macOS. Si llega a hacer falta,
verificar en ese momento si xtool lo soporta; si no, compilar y subir esa
build desde macOS en la nube (runners de macOS de GitHub Actions). No es
necesario para el uso personal.

---

## 11. Trampas conocidas

Van íntegras a una sección de iOS en el `CLAUDE.md` cuando empiece la Fase
iOS-0.

**Las fechas del backend llevan microsegundos.** Pydantic serializa
`created_at` como `2026-10-25T18:48:38.123456Z`. La estrategia `.iso8601`
de `JSONDecoder` **no acepta fracciones de segundo** y falla con un error
poco claro. Usar una estrategia personalizada con
`Date.ISO8601FormatStyle(includingFractionalSeconds: true)` y un respaldo
sin fracciones. Por esto la Fase iOS-0 prueba contra JSON real.

**`snake_case` del backend.** `duration_seconds`, `start_seconds`, etc.
Usar `keyDecodingStrategy = .convertFromSnakeCase` de forma consistente en
un solo decodificador compartido, no `CodingKeys` sueltos en cada modelo.

**Cloudflare Access bloquea la app en silencio.** El síntoma no es un 401
sino un 302 a una página HTML de login, que el decodificador de JSON
reporta como "datos corruptos". Ver la sección 1.

**ATS y HTTP.** Si la app no conecta al servidor local, revisar primero si
es `http://`. `NSAllowsLocalNetworking` solo en Debug.

**Las URLs de `.fileImporter` y de *Abrir con…* caducan.** Son
*security-scoped*: hay que llamar a `startAccessingSecurityScopedResource()`
y copiar el archivo de inmediato al contenedor propio. Guardar la URL para
después no funciona.

**Notas de Voz no es accesible desde otras apps.** No hay API para listar
ni leer sus grabaciones; siempre se comparten desde Notas de Voz. No
prometer en la interfaz un "importar de Notas de Voz".

**Lo que comparte cada app varía.** WhatsApp y Telegram mandan sus notas de
voz como `.opus`/`.ogg` (y a veces con nombres genéricos tipo
`PTT-20261025-WA0003.opus`); Notas de Voz manda `.m4a` con el título de la
grabación. Algunas apps comparten una URL de archivo, otras los datos. La
extensión debe aceptar ambos casos y conservar el nombre más útil como
título.

**Límite de memoria de la share extension (~120 MB).** Cargar un audio con
`Data(contentsOf:)` dentro de la extensión la mata sin aviso. Trabajar
siempre con URLs de archivo, y nunca transcribir dentro de la extensión.

**`SpeechTranscriber` no está en todos los iPhone con iOS 26, ni en todos
los idiomas.** Comprobar disponibilidad del módulo y `supportedLocales` en
tiempo de ejecución, nunca asumirla. Apple ofrece `DictationTranscriber`
como alternativa de mayor compatibilidad; evaluarla como respaldo en la
Fase iOS-8 solo si el iPhone del usuario lo necesita.

**El motor local no detecta el idioma.** Se le indica el idioma antes de
empezar; un audio en inglés transcrito como español produce texto
plausible pero incorrecto, sin error. Verificar en la Fase iOS-8 si el SDK
vigente ya ofrece identificación de idioma; si no, el selector lo deja claro.

**El motor local y `.opus`.** No dar por hecho que `AVAudioFile` abre las
notas de voz de WhatsApp/Telegram. Probarlo en la Fase iOS-8; si no, esos
archivos van solo al servidor (ffmpeg los lee sin problema).

**Los modelos de voz se descargan aparte.** La primera transcripción local
en un idioma necesita conexión para que iOS descargue su modelo con
`AssetInventory`. Comprobar los idiomas instalados antes de ofrecer el modo
local sin conexión.

**El formato de audio del analizador.** `SpeechAnalyzer` espera un formato
concreto; pedírselo (`bestAvailableAudioFormat`) y convertir con
`AVAudioConverter`. Pasarle audio en otro formato no siempre falla: a veces
produce texto malo.

**Las marcas de tiempo al reanudar.** Al reanudar una transcripción local
desde la mitad, los tiempos que devuelve el analizador empiezan de cero:
hay que sumarles el desplazamiento. Error clásico que produce un `.srt` con
la segunda mitad desincronizada.

**`BGContinuedProcessingTask` solo se puede lanzar por una acción del
usuario con la app en primer plano**, y el sistema puede expirarla. Por eso
el estado se guarda segmento a segmento y la reanudación es parte del diseño
desde el principio, no un añadido. Y por eso la share extension no puede
lanzar una transcripción local por sí sola.

**Temperatura y batería.** Una transcripción local larga calienta el
teléfono. Vigilar `ProcessInfo.thermalState` y, en `.serious` o
`.critical`, pausar y avisar en vez de dejar que el sistema mate la tarea.

**Liquid Glass solo aparece compilando con el SDK de iOS 26.** Si xtool
extrajo el SDK de un `.xip` anterior, la app muestra el diseño viejo aunque
corra en iOS 26. Y el
vidrio se pierde en cuanto se reemplaza un componente del sistema por uno
dibujado a mano (un `HStack` con botones en vez de una barra de
herramientas, un `ZStack` en vez de una hoja).

**Vidrio sobre vidrio.** Apilar elementos con `.glassEffect()` sin un
`GlassEffectContainer` produce reflejos incorrectos y animaciones que no
se fusionan. Y vidrio sobre el texto de la transcripción lo vuelve ilegible
sobre ciertos fondos.

**Las sesiones de `URLSession` en segundo plano son otro mundo.** Solo
subidas desde archivo, solo delegados, la app puede ser relanzada en frío
para recibir los eventos, también los de tareas que inició la extensión.
Escribir el uploader de la Fase iOS-4 como algo que se pueda reemplazar, no
extender.

**El stream de SSE muere al suspender la app.** No hay error, simplemente
deja de llegar. Siempre reconectar en `scenePhase == .active`.

**Exportadores duplicados en dos lenguajes.** Los de Swift son copia de los
de Python; si se cambia uno y no el otro, una transcripción exportada desde
la web y desde el iPhone deja de coincidir. Los archivos de referencia de la
Fase iOS-8 son la red de seguridad: regenerarlos cada vez que cambie un
exportador del backend.

**Firma de 7 días con la cuenta gratuita.** Cuando la app "deja de abrir"
de repente, no es un bug: caducó el perfil. Reinstalar con `xtool dev` (o
dejar que SideStore la renueve).

**Recetas de internet que asumen Xcode.** Casi todos los tutoriales de iOS
dicen "añade un target en Xcode", "marca la capacidad en *Signing &
Capabilities*", "arrastra la imagen a Assets.xcassets". Con xtool, el
equivalente es editar `Package.swift`, `xtool.yml`, el Info.plist o el
archivo de entitlements a mano. Ninguna receta de Xcode se aplica tal cual.

**Macros de los frameworks de Apple.** `@Observable` es del toolchain y
debería funcionar; `@Model` (SwiftData), `#Preview` y otros macros cuyos
plugins vienen con Xcode probablemente no. El error aparece al compilar con
xtool como "plugin no encontrado", no como un problema del código. La Fase
iOS-0 lo verifica; el plan ya no depende de SwiftData.

**`swift test` en Fedora no ve los frameworks de iOS.** Si un archivo de
`CadenceKit` importa `UIKit`, `AVFoundation` o `Speech`, los tests dejan de
compilar en Linux. Es la misma señal que `test_architecture.py`: algo se
filtró donde no debía. Ojo también con APIs de Foundation que existen en
Apple y no en la Foundation de Linux (algunos formateadores y
`URLSession.bytes`): el transporte HTTP va detrás de un puerto y sus
implementaciones con `URLSession` viven en la app.

**Versión del toolchain y del SDK.** Un Swift de Linux de una versión mayor
distinta a la del Xcode del que sale el SDK produce errores de módulos
incompatibles al importar `SwiftUI`. Fijar ambas versiones juntas.

**`usbmuxd` y permisos.** Si `xtool dev` no encuentra el iPhone, revisar
primero que el servicio `usbmuxd` esté corriendo, que el iPhone esté
desbloqueado y que se haya aceptado *Confiar en esta computadora*; luego
`idevicepair validate`.

**Swift 6 y concurrencia.** Las vistas y los ViewModels van en
`@MainActor`; el cliente de API es `Sendable`; el estado de las subidas en
segundo plano y la cola de trabajos locales viven en actores. Silenciar las
advertencias del compilador convierte errores de compilación en *data
races* en tiempo de ejecución.

**Los mismos límites del servidor.** 500 MB por archivo, 5 trabajos activos
como máximo (429), y la cola es de concurrencia 1: una hora de audio con
`large-v3-turbo` tarda ~90 minutos en el ProDesk sin importar que se haya
mandado desde el iPhone. La interfaz debe mostrar la estimación, no
prometer rapidez.

---

## 12. Verificación

**Tests automatizados** en `CadenceKit` (`swift test`): decodificación de
cada modelo contra fixtures reales del backend; parser de SSE (eventos
completos, partidos entre lecturas, líneas vacías, reconexión); cálculo de
partes y reanudación del protocolo de subida contra un transporte falso;
la bandeja de entrada de la share extension (escritura y lectura
concurrentes, archivos huérfanos); exportadores comparados byte a byte con
los archivos de referencia generados por el backend; la lógica de
reanudación local (desplazamiento de marcas de tiempo, sin duplicados ni
huecos) con un motor falso; y el test de arquitectura. En el backend: los
tests de autenticación por token (Fase iOS-1) y de importación (Fase
iOS-12).

**Prueba de extremo a extremo en un iPhone real**, contra el ProDesk por datos móviles (no
en la red local), que es la que cierra el proyecto:

1. Instalar la app limpia, configurar la URL del dominio de Cloudflare e
   iniciar sesión, con datos móviles.
2. Grabar 40 minutos en **Notas de Voz**, *Compartir → Cadence*, motor
   **Servidor** con `large-v3-turbo` y español; bloquear el teléfono sin
   abrir Cadence.
3. Recibir la notificación al terminar; abrirla lleva al trabajo correcto.
4. Desde **WhatsApp**, reenviar una nota de voz a Cadence con el motor
   Servidor y `small`; ver la barra de subida y luego la de transcripción en
   el accesorio inferior, avanzando de forma continua.
5. Activar el **modo avión**. Compartir otra nota de Notas de Voz de 20
   minutos, motor **En este iPhone**; bloquear el teléfono de inmediato. Ver
   el progreso en la pantalla de bloqueo y recibir la notificación local al
   terminar.
6. Exportar las transcripciones en los seis formatos; abrir los `.srt` en
   VLC junto a sus audios y comprobar la sincronía.
7. Con el modo avión todavía activo, leer las transcripciones desde el
   caché.
8. Desactivar el modo avión, subir el texto de la transcripción local, y
   confirmar en la web que los tres trabajos aparecen en la biblioteca del
   mismo usuario, y que el servidor no tiene el audio de la local.
9. Recorrer la app con *Reducir transparencia*, *Aumentar contraste*, modo
   oscuro y el texto más grande: todo legible, nada cortado.

---

## 13. Decisiones abiertas

Necesitan respuesta del usuario; el plan propone un valor por defecto para
cada una.

Ya resueltas: se compila en Fedora con Swift + xtool, sin Mac (secciones 1
y 10), y el dispositivo es un iPhone 15 con iOS 26.

1. **¿Cuenta de Apple Developer de pago?** Decide si la firma dura 7 días o
   un año, si hay push y si se puede usar TestFlight. *Por defecto:*
   empezar con la gratuita y reinstalar con `xtool dev`; decidir antes de la
   Fase iOS-13.
2. **¿Sigue activo Cloudflare Access?** *Por defecto:* bypass para `/api/*`.
3. **¿Qué motor por defecto?** *Por defecto:* Servidor (mejor calidad
   esperada con Whisper, no gasta batería), revisable tras la medición de la
   Fase iOS-8.
4. **¿Sincronizar automáticamente el texto de las transcripciones
   locales?** *Por defecto:* no; un botón manual por trabajo.
5. **¿Hace falta la grabadora propia?** *Por defecto:* sí, pero como fase
   opcional (iOS-10) después de la hoja de compartir.
6. **¿La app es solo para el dueño del servidor o también para los otros
   usuarios?** Cambia si TestFlight es necesario. *Por defecto:* solo
   personal al principio.
7. **¿iPad?** SwiftUI lo da casi gratis con `NavigationSplitView`, pero
   probarlo es trabajo. *Por defecto:* solo iPhone en v1.
