# Amigo Secreto Navideño

Aplicación React, Vite y TypeScript para organizar intercambios privados. GitHub Pages aloja solo la interfaz; Supabase Auth, PostgreSQL con RLS y Edge Functions mantienen las operaciones privadas en el servidor.

## Requisitos

- Node.js 22 o posterior y npm.
- Una cuenta Supabase y un proyecto GitHub.

## Instalar y ejecutar localmente

```bash
npm install
cp .env.example .env.local
npm run dev
```

En Windows PowerShell, copia el ejemplo con `Copy-Item .env.example .env.local`. Llena `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` y `VITE_PUBLIC_APP_URL` con la URL, la clave pública y la dirección pública de GitHub Pages. No pongas la service role key en variables `VITE_` ni en archivos del frontend. Para compartir invitaciones desde localhost antes de desplegar, `VITE_PUBLIC_APP_URL` debe apuntar al sitio público ya desplegado; los teléfonos externos no pueden abrir una dirección localhost.

## Preparar Supabase

1. Crea un proyecto en Supabase y guarda la URL y la clave anon.
2. Instala Supabase CLI. Inicia sesión (`supabase login`) y vincula esta carpeta (`supabase link --project-ref TU_PROJECT_REF`).
3. Aplica el esquema al proyecto alojado: `supabase db push --remote`.
4. En **Authentication → Users**, crea el usuario administrador con correo y contraseña. Desactiva el registro público de usuarios desde Authentication si no se necesita.
5. Genera un secreto aleatorio largo para el pepper de PIN y configúralo como secreto de Edge Function: `supabase secrets set PIN_PEPPER="un-secreto-largo-aleatorio"`.
6. Despliega la función: `supabase functions deploy api`.
7. En Authentication, configura los redirect URLs locales y el dominio final de Pages.

La migración activa RLS y no concede acceso de navegador a `assignments` ni a los hashes de `invitations`. La vista `invitation_status` solo expone estados para el propietario del evento. La función `api` valida el JWT del administrador para crear invitaciones y usa la clave service role solo en el backend. `check_invitation` bloquea el acceso durante 15 minutos tras cinco PIN incorrectos. Todos los resultados se entregan bajo token y PIN válidos, con respuestas `no-store`.

El sorteo se ejecuta dentro de una transacción PostgreSQL con bloqueo del evento, un solo sorteo y permutaciones aleatorias criptográficas, aceptando uniformemente solo las asignaciones válidas. La función no devuelve asignaciones al panel. El propietario técnico de Supabase conserva acceso de infraestructura a su base de datos; la separación protege frente a participantes y usuarios no autorizados, no frente al operador con control del proyecto.

## Pruebas y build

```bash
npm test
npm run build
```

Las pruebas Vitest cubren propiedades del sorteo y muestreo sin sesgo de rango. Las pruebas SQL en `supabase/tests/` comprueban restricciones y permisos de base de datos y el sorteo transaccional; ejecútalas con `supabase test db` (requiere Supabase CLI y pgTAP).

## Publicar en GitHub Pages

1. Crea el repositorio GitHub `amigo-secreto-navidad` y sube esta carpeta como raíz del repositorio.
2. En **Settings → Secrets and variables → Actions → Variables**, crea `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` y `VITE_PUBLIC_APP_URL`.
3. En **Settings → Pages**, selecciona **GitHub Actions** como fuente.
4. Envía cambios a la rama `main`; `.github/workflows/deploy.yml` construye y publica la app en `https://TU-USUARIO.github.io/amigo-secreto-navidad/`.
5. Cambia `base` en `vite.config.ts` si el repositorio tiene otro nombre. Las rutas usan HashRouter, compatible con Pages.

## Uso del panel

Inicia sesión como usuario administrador, guarda el evento, añade participantes y genera invitaciones. La lista se normaliza para detectar duplicados sin distinguir mayúsculas ni tildes. Realiza el sorteo una vez y comparte los enlaces. Los PIN se muestran solo al momento de generar las invitaciones: descarga el CSV o copia cada mensaje entonces y entrega el PIN por otro canal. El CSV contiene credenciales, guárdalo de forma privada y elimínalo cuando ya no sea necesario.

Al publicar actualizaciones, cambia la rama `main`; Actions vuelve a desplegar el sitio. Para modificar la base de datos, añade una migración SQL numerada nueva y usa `supabase db push --remote`.

El botón **Reiniciar sorteo** aparece después de sortear. Pide escribir `REINICIAR`, valida la propiedad del evento en PostgreSQL y, de forma transaccional, elimina asignaciones, invitaciones y revelaciones. Conserva participantes y exclusiones para corregir la lista y sortear otra vez; las invitaciones anteriores quedan invalidadas.

Los enlaces y PIN de invitación se derivan de forma determinista desde un secreto de Edge Function y la época del evento; la base conserva solo hashes. El panel puede volver a mostrarlos sin cambiar las credenciales. Los enlaces antiguos se conservan como alias hash durante la transición, y el texto de WhatsApp se puede editar antes de abrir el chat. Al reiniciar, cambia la época y los enlaces anteriores dejan de funcionar. Comparte enlaces del sitio HTTPS publicado, no `localhost`.
