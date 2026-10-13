# Cambios

Formato de [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones con
[versionado semántico](https://semver.org/lang/es/).

## [0.1.0] - 2026-10-14

Primera versión.

### Añadido

- App de Android en Flutter: búsqueda y ficha de licitaciones contra la API del radar.
- Inicio de sesión con la cuenta de Keycloak del radar (código + PKCE) y tokens cifrados.
- Seguimiento de ofertas por etapas con notas, responsable y fecha interna; embudo con importe en juego y tasa de
  éxito.
- Funcionamiento sin conexión con drift y resolución de conflictos entre dispositivos.
- Avisos de plazo locales y aviso de novedades de las alertas del radar con una tarea periódica.
- Servidor en Dart (shelf) con MongoDB: concurrencia optimista, agregación del embudo y verificación de JWT con JWKS.
- Docker y compose para el servidor; script del cliente de Keycloak.
- Pruebas del servidor contra MongoDB real; pruebas de la app (lógica, repositorio, pantallas y *golden*).
- CI escrita para GitHub Actions.
