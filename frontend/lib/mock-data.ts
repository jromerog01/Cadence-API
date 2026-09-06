export type TranscriptSegment = {
  start: string
  speaker: string
  text: string
}

export type Transcription = {
  id: string
  title: string
  fileName: string
  createdAt: string
  duration: string
  language: string
  words: number
  status: 'listo' | 'procesando'
  segments: TranscriptSegment[]
}

export type User = {
  id: string
  name: string
  email: string
  initials: string
}

export const users: User[] = [
  { id: 'u1', name: 'Ana Herrera', email: 'ana@estudio.co', initials: 'AH' },
  { id: 'u2', name: 'Marco Díaz', email: 'marco@estudio.co', initials: 'MD' },
]

export const transcriptionsByUser: Record<string, Transcription[]> = {
  u1: [
    {
      id: 't1',
      title: 'Entrevista — Producto Q3',
      fileName: 'entrevista-producto-q3.mp3',
      createdAt: '2026-08-28T14:20:00',
      duration: '18:42',
      language: 'Español',
      words: 2841,
      status: 'listo',
      segments: [
        {
          start: '00:00',
          speaker: 'Entrevistador',
          text: 'Gracias por acompañarnos hoy. Para empezar, ¿podrías contarnos cómo surgió la idea del proyecto?',
        },
        {
          start: '00:14',
          speaker: 'Ana',
          text: 'Claro. Todo nació de una frustración muy concreta: perdíamos horas transcribiendo reuniones a mano. Queríamos algo que fuera rápido y, sobre todo, preciso.',
        },
        {
          start: '00:41',
          speaker: 'Entrevistador',
          text: 'Y en cuanto a los primeros usuarios, ¿qué tipo de perfil encontraron?',
        },
        {
          start: '01:03',
          speaker: 'Ana',
          text: 'Sobre todo periodistas y equipos de investigación. Gente que trabaja con muchas horas de grabación y necesita citar con exactitud.',
        },
      ],
    },
    {
      id: 't2',
      title: 'Reunión de equipo — Semanal',
      fileName: 'standup-semanal.wav',
      createdAt: '2026-08-25T09:05:00',
      duration: '32:10',
      language: 'Español',
      words: 4930,
      status: 'listo',
      segments: [
        {
          start: '00:00',
          speaker: 'Marco',
          text: 'Buenos días a todos. Vamos a repasar los pendientes de la semana y los bloqueos que tengamos.',
        },
        {
          start: '00:22',
          speaker: 'Ana',
          text: 'Por mi lado, el módulo de subida ya está funcionando. Falta pulir la barra de progreso y los estados de error.',
        },
        {
          start: '00:48',
          speaker: 'Marco',
          text: 'Perfecto. Dejemos la exportación a PDF para el final, una vez cerrado el diseño.',
        },
      ],
    },
    {
      id: 't3',
      title: 'Nota de voz — Ideas',
      fileName: 'notas-ideas.m4a',
      createdAt: '2026-08-30T20:47:00',
      duration: '04:55',
      language: 'Español',
      words: 612,
      status: 'procesando',
      segments: [
        {
          start: '00:00',
          speaker: 'Ana',
          text: 'Recordatorio: revisar el onboarding y añadir un ejemplo de audio de muestra para nuevos usuarios.',
        },
      ],
    },
  ],
  u2: [
    {
      id: 't4',
      title: 'Podcast — Episodio 12',
      fileName: 'podcast-ep12.mp3',
      createdAt: '2026-08-27T17:30:00',
      duration: '54:03',
      language: 'Español',
      words: 8210,
      status: 'listo',
      segments: [
        {
          start: '00:00',
          speaker: 'Marco',
          text: 'Bienvenidos a un nuevo episodio. Hoy hablamos sobre cómo la transcripción automática está cambiando la forma de trabajar con contenido.',
        },
        {
          start: '00:31',
          speaker: 'Invitado',
          text: 'Es un cambio enorme. Antes, publicar la versión en texto de un episodio te llevaba días. Ahora es cuestión de minutos.',
        },
      ],
    },
    {
      id: 't5',
      title: 'Clase grabada — Fundamentos',
      fileName: 'clase-fundamentos.wav',
      createdAt: '2026-08-22T11:00:00',
      duration: '41:18',
      language: 'Español',
      words: 6120,
      status: 'listo',
      segments: [
        {
          start: '00:00',
          speaker: 'Marco',
          text: 'Hoy vamos a cubrir los conceptos básicos antes de pasar a los ejercicios prácticos de la próxima sesión.',
        },
      ],
    },
  ],
}
