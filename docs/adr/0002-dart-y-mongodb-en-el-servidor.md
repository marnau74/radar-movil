# 2. Dart y MongoDB en el servidor del seguimiento

## Contexto

El radar ya tiene su API (Java, Spring Boot, PostgreSQL). El seguimiento de ofertas es otra cosa: datos propios de
cada empresa, con un historial de cambios de etapa por licitación y campos que crecerán (notas, responsable, fechas,
quizá documentos).

## Decisión

- Un servidor aparte en **Dart** (shelf y shelf_router), en el mismo repositorio que la app: un solo lenguaje para el
  modelo y la validación en los dos lados, y un servidor que compila a un ejecutable nativo en una imagen mínima.
- **MongoDB**: un documento por usuario y licitación, con el historial dentro y el resumen de la licitación copiado
  (el embudo funciona sin consultar al radar). Índice único `{usuario, licitacionId}` y otro para el embudo; las cifras
  del embudo se calculan con una agregación (`$group`).
- La sesión es la del radar: el servidor verifica los JWT de Keycloak con el JWKS del realm (firma RS256, emisor,
  audiencia `radar-api`, caducidad), con las claves en caché y recarga limitada si Keycloak las rota.

## Alternativas descartadas

- **Añadir el seguimiento a la API del radar**: mezclaría datos públicos con datos privados de cada empresa en la
  misma base y el mismo despliegue.
- **PostgreSQL**: encaja igual de bien con un `jsonb` para el historial; se elige MongoDB porque el documento es la
  unidad natural aquí y para cubrir esa tecnología en el portfolio.
- **Firebase / Firestore**: la sesión tendría que ser la de Firebase, no la de Keycloak, y los datos saldrían de la
  infraestructura propia.
