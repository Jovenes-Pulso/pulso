# Pulso: asistencia del grupo de jóvenes (fase 1: interfaz)

PWA sin dependencias. Los datos se guardan por ahora en el navegador (localStorage)
a través del objeto `DB` dentro de `index.html`. En la fase 2 se reemplaza solo `DB`
por la base de datos remota; las pantallas no cambian.

## Archivos
- index.html: app completa (estilos, pantallas, lógica)
- manifest.webmanifest: nombre, colores e íconos para instalar en el celular
- sw.js: funcionamiento sin conexión (cambia VERSION al publicar cambios)
- icons/: íconos 192, 512, maskable y SVG

## Probar en el computador
    cd pulso
    python3 -m http.server 8080
Abre http://localhost:8080. Para instalarla en el celular hay que publicarla con HTTPS
(GitHub Pages, Netlify o Vercel) y abrirla desde Chrome o Safari: "Agregar a pantalla de inicio".

## Modelo de datos
students: id, nombres, apellidos, edad, fechaNacimiento, acudiente, telefono,
          fechaIngreso, foto, notas, placeholder
classes:  id, fecha (AAAA-MM-DD), servicio, tema, ponente, notas, asistentes [ids]
settings: grupo, servicio, riesgo, inactivo

## Estadísticas y Excel
- Panel en Inicio > "Panel de estadísticas": periodo (8 clases, 3 meses, año, todo) y servicio;
  promedio por clase, % del grupo activo, jóvenes distintos, nuevos, edades, asistencia por curso
  y por edad, por quién dio la clase, los que más vinieron y qué tan completos están los datos.
- Excel (.xlsx) generado en el celular, sin librerías: hojas Jóvenes, Asistencia por clase, Clases y Resumen.
  Botón en Jóvenes, en Estadísticas y en Más. Los jóvenes sin celular aparecen en rojo.
- Alerta en Inicio de jóvenes sin celular de acudiente, filtro "Sin celular" en Jóvenes y aviso en cada perfil.
- Nuevo campo: curso o grado (también se puede importar desde CSV).

## Cuentas y roles
En modo local (sin config.js): usuario `admin`, contraseña `pulso2026`. Con Supabase: la cuenta que creas en la guía.

| Puede... | Profesor | Super admin |
|---|---|---|
| Tomar lista, crear y editar jóvenes y clases | sí | sí |
| Ver estadísticas y descargar reportes CSV | sí | sí |
| Eliminar jóvenes o clases | no | sí |
| Importar CSV, copias de seguridad, ajustes, borrar todo | no | sí |
| Crear, editar, dar nueva contraseña y eliminar cuentas | no | sí |

- Nadie usa correo: el usuario `leidy` entra en Supabase como `leidy@pulso.app`, una cuenta técnica.
- No puedes eliminar tu propia cuenta y siempre queda al menos un super administrador.
- Tras 5 intentos fallidos el ingreso se pausa 30 segundos.
- Cada clase guarda qué profesor la registró, aunque después se elimine su cuenta.

**Fase 1 (esta versión):** las cuentas se guardan solo en el dispositivo, para probar la interfaz.
Una cuenta creada en un celular no existe en otro hasta conectar Supabase.

## Uso de servicios (solo super admin)
- Más > Uso de servicios: base de datos, tráfico de salida estimado y proyección del mes, usuarios activos,
  llamadas a funciones, archivos, días desde la última actividad (pausa del plan gratuito), tamaño por tabla,
  y para GitHub Pages el tamaño del repositorio y la última actualización.
- Requiere ejecutar `supabase/uso.sql` (tabla uso_diario y funciones registrar_uso, contar_funcion, uso_proyecto).
- Límites del plan gratuito en la constante LIMITES de index.html (revisados en noviembre de 2026).
- Sin Supabase muestra una vista de ejemplo.

## Conexión con Supabase
- `config.js`: URL del proyecto y llave publicable (`sb_publishable_...`). Vacío = modo local.
- Cada cambio se aplica en el celular y entra a una cola que se envía en orden; sin señal, espera y se envía al volver.
- La app trae todo al abrir y al volver a primer plano; en tiempo real recibe las marcas de otros profesores.
- `supabase/schema.sql`: tablas, reglas RLS por rol y publicación de tiempo real.
- `supabase/functions/admin-usuarios/index.ts`: crear, actualizar, restablecer y eliminar cuentas (solo super admin).
  Lee la llave secreta de `SUPABASE_SECRET_KEYS` (o `SUPABASE_SERVICE_ROLE_KEY` en proyectos antiguos).
  Publicarla con "Verify JWT" desactivado: la función valida la sesión por su cuenta.
- La guía paso a paso está en el documento "Pulso: conectar Supabase y publicar la app".
