# 1. Sin conexión: la base local manda y la cola es una fila por seguimiento

## Contexto

El seguimiento se edita en el móvil, a menudo sin cobertura (en una visita, en el tren), y se comparte entre
dispositivos a través del servidor. Hay que poder:

- ver y cambiar el seguimiento sin red;
- subir lo cambiado cuando vuelva la red;
- no pisar en silencio lo que se haya cambiado en otro dispositivo.

## Decisión

- La interfaz lee siempre de la base local (drift sobre SQLite), nunca directamente de la API. La red solo sirve para
  subir los cambios y traer los de otros dispositivos.
- La cola de cambios no es una tabla de operaciones: cada fila de `seguimientos_locales` guarda **el último estado**
  del seguimiento y su estado (`sincronizado`, `pendiente`, `borrando` o `conflicto`). Tres cambios sin red se suben
  como uno.
- Concurrencia optimista: cada cambio viaja con la `version` del servidor sobre la que se hizo. Si no coincide, el
  servidor responde 409 con lo guardado y la fila pasa a `conflicto` con las dos versiones. El usuario elige; mientras
  tanto no se puede volver a editar ese seguimiento.
- Si se edita mientras se sube un cambio, al terminar la subida el cambio nuevo sigue pendiente pero pasa a la
  versión recién guardada, para no chocar consigo mismo.
- Al refrescar desde el servidor, solo se tocan las filas sincronizadas: lo pendiente y los conflictos se respetan.

## Alternativas descartadas

- **Registro de operaciones** (una fila por cambio, reproducidas en orden): más fiel, pero en este dominio solo
  importa el estado final de cada seguimiento y obligaría a fusionar operaciones viejas con el estado del servidor.
- **Última escritura gana**: más simple, pero un cambio de etapa hecho en el portátil desaparecería sin aviso al
  sincronizar el móvil.
- **Leer de la API con caché**: la app quedaría inservible sin red justo cuando más se usa.
