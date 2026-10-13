# 3. Avisos locales y tarea periódica, sin Firebase

## Contexto

La app avisa de dos cosas: que va a cerrar el plazo de algo que se sigue (72 y 24 horas antes, y el día de la fecha
interna) y que las alertas del radar han encontrado licitaciones nuevas.

## Decisión

- Los avisos de plazo se **programan en el móvil** (flutter_local_notifications) a partir de la base local, con un
  identificador estable por licitación y tipo: reprogramarlos los sustituye en vez de duplicarlos, y se cancelan los
  que sobran. Se programan inexactos (sin pedir alarmas exactas): unos minutos de margen no importan en un plazo de
  días.
- Una **tarea periódica** (WorkManager, cada seis horas y solo con red) sincroniza, reprograma y consulta cuántos
  avisos sin leer tiene el usuario en el radar; si hay más que la última vez, lo notifica. La tarea monta los
  servicios a mano en su propio isolate y comparte la base de datos con la app (un isolate de drift compartido).
- El permiso de notificaciones se pide al seguir la primera licitación, cuando se entiende para qué es.

## Alternativas descartadas

- **Firebase Cloud Messaging**: avisos al momento, pero exige un proyecto de Firebase, Google Play Services y que el
  radar envíe las notificaciones. Para avisos de plazos de días no compensa.
- **Alarmas exactas**: piden un permiso especial desde Android 14 que no está justificado aquí.
