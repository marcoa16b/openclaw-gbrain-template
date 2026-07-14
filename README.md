# OpenClaw + AlphaClaw + GBrain (self-hosted, Docker + Dokploy)

Imagen Docker que empaqueta AlphaClaw (gestiona el gateway de OpenClaw) y
GBrain (brain de conocimiento sobre PGLite/Postgres-WASM), pensada para
correr en un VPS propio detrás de Traefik, gestionado vía Dokploy.

Adaptado del template original para Render — la única diferencia real es
cómo se declara el disco persistente y el enrutamiento TLS.

## Archivos

- `Dockerfile` — build de la imagen (Node 22 + Bun + AlphaClaw + GBrain).
- `entrypoint.sh` — inicializa el brain PGLite y siembra los skills en el
  primer arranque; luego ejecuta `alphaclaw start`.
- `package.json` — **verificar contra el repo original de AlphaClaw**
  antes de usar en producción.
- `docker-compose.yml` — deploy para Dokploy (o cualquier Docker+Traefik).
- `.env.example` — variables de entorno requeridas.

## Deploy en Dokploy

1. Sube este repo a GitHub.
2. En Dokploy: **Create Application → Docker Compose**, apunta al repo.
3. En la sección **Environment**, carga las variables de `.env.example`
   (`SETUP_PASSWORD`, `OPENCLAW_GATEWAY_TOKEN`, `OPENROUTER_API_KEY`, y
   opcionalmente `ANTHROPIC_API_KEY`). Los dos primeros los generas tú
   mismo, por ejemplo:
   ```bash
   openssl rand -hex 32
   ```

## Sobre usar solo OpenRouter en vez de OpenAI + Anthropic

Este setup usa una única `OPENROUTER_API_KEY` para:
- El agente OpenClaw en sí (chat principal).
- Embeddings de GBrain (`openrouter:openai/text-embedding-3-small`).
- Query expansion / chat de GBrain (`openrouter:anthropic/claude-haiku-4.5`).

**Excepción real**: la infraestructura de subagentes de GBrain (`gbrain
takes extract`, autopilot/dream-cycle) está fijada a Anthropic-directo por
estabilidad de `tool_use_id` entre reintentos, y rechaza explícitamente las
llamadas a Anthropic ruteadas por OpenRouter. Si quieres esas features
específicas, agrega también `ANTHROPIC_API_KEY` (queda opcional en este
template — sin ella, esas dos features quedan deshabilitadas pero todo lo
demás funciona normal).
4. En **Domains**, asigna tu dominio y el puerto interno `10000`.
   Dokploy configura las labels de Traefik y el certificado TLS
   automáticamente — no necesitas descomentar las labels manuales del
   `docker-compose.yml` a menos que quieras declarar el enrutamiento
   fuera del panel.
5. Verifica que el volumen `alphaclaw-data` (montado en `/data`) sea
   persistente entre redeploys — es donde vive el brain PGLite y la
   config de AlphaClaw/OpenClaw.
6. Deploy. Sigue los logs del contenedor durante el primer arranque:
   deberías ver `Running first-time gbrain init (PGLite engine)...`
   seguido de `Starting AlphaClaw...`.
7. Visita `https://tu-dominio` y completa el wizard con el
   `SETUP_PASSWORD` que definiste.

## Recursos recomendados

El template original en Render usa el plan `pro` (4 GB) como default con
margen sobre el mínimo de 2 GB de OpenClaw. En tu VPS, no bajes de 2 GB
de RAM disponibles para el contenedor; si vas a hacer ingest masivo con
GBrain (miles de páginas de una vez), considera 4 GB o más.

## Actualizar versiones

- **GBrain**: cambia `GBRAIN_REF` (build arg) en el Dockerfile o pásalo
  vía `args` en `docker-compose.yml`, apuntando a un commit SHA nuevo.
- **AlphaClaw**: sube la versión en `package.json`.
- **Bun**: cambia la versión pineada en el `RUN curl -fsSL https://bun.sh/install`.