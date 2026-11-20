// =====================================================================
// Pulso: función del servidor para gestionar cuentas (fase 2, borrador)
// Solo el super administrador puede usarla. Usa la llave de servicio,
// que vive en el servidor y nunca llega al celular.
//
// Publicar desde el panel: Edge Functions > Deploy a new function > Via Editor,
// nombre admin-usuarios. Luego desactiva "Verify JWT" en sus ajustes:
// esa verificación automática solo entiende las llaves antiguas. Esta
// función valida la sesión del usuario por su cuenta (auth.getUser).
// Llamar desde la app:
//   supabase.functions.invoke('admin-usuarios', { body: { accion: 'crear', usuario, nombre, rol, clave } })
//   acciones: crear | actualizar | restablecer | eliminar
// =====================================================================
import { createClient } from 'npm:@supabase/supabase-js@2';

const DOMINIO = 'pulso.app'; // usuario "leidy" => leidy@pulso.app (cuenta técnica)
const MIN_CLAVE = 6;
const ROLES = ['superadmin', 'profesor'];

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405);

  // Llave secreta: Supabase la pone sola en el entorno de la función.
  // Proyectos con llaves nuevas: SUPABASE_SECRET_KEYS = {"default": "sb_secret_..."}.
  // Proyectos con llaves antiguas: SUPABASE_SERVICE_ROLE_KEY.
  let secreta: string | undefined;
  try { secreta = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}').default; } catch { secreta = undefined; }
  secreta = secreta || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!secreta) return json({ error: 'La función no encuentra la llave secreta del proyecto.' }, 500);

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, secreta, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. ¿Quién llama? Debe ser un super administrador con perfil vigente.
  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
  if (authErr || !auth?.user) return json({ error: 'Tu sesión no es válida. Vuelve a entrar.' }, 401);
  const yoId = auth.user.id;
  const { data: yo } = await admin.from('perfiles').select('id, rol').eq('id', yoId).maybeSingle();
  if (!yo || yo.rol !== 'superadmin') return json({ error: 'Solo el super administrador puede gestionar cuentas.' }, 403);

  // Cuenta la llamada para el panel de uso (si uso.sql no se ha ejecutado, se ignora).
  try { await admin.rpc('contar_funcion'); } catch { /* sin contador */ }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'Solicitud inválida.' }, 400); }

  const contarSupers = async () => {
    const { count } = await admin.from('perfiles').select('id', { count: 'exact', head: true }).eq('rol', 'superadmin');
    return count ?? 0;
  };
  const perfilDe = async (id: string) =>
    (await admin.from('perfiles').select('id, usuario, nombre, rol').eq('id', id).maybeSingle()).data;

  switch (body.accion) {
    case 'crear': {
      const usuario = String(body.usuario ?? '').trim().toLowerCase();
      const nombre = String(body.nombre ?? '').trim();
      const rol = ROLES.includes(String(body.rol)) ? String(body.rol) : 'profesor';
      const clave = String(body.clave ?? '');
      if (!nombre) return json({ error: 'Escribe el nombre del profesor.' }, 400);
      if (!/^[a-z0-9._]{3,20}$/.test(usuario)) return json({ error: 'El usuario debe tener de 3 a 20 letras o números, sin espacios ni tildes.' }, 400);
      if (clave.length < MIN_CLAVE) return json({ error: `La contraseña debe tener al menos ${MIN_CLAVE} caracteres.` }, 400);

      const { data, error } = await admin.auth.admin.createUser({
        email: `${usuario}@${DOMINIO}`, password: clave, email_confirm: true, user_metadata: { usuario, nombre },
      });
      if (error || !data.user) {
        const existe = /already|registered|exists/i.test(error?.message ?? '');
        return json({ error: existe ? `Ya existe el usuario ${usuario}. Elige otro.` : (error?.message ?? 'No se pudo crear la cuenta.') }, 400);
      }
      const { error: e2 } = await admin.from('perfiles').insert({ id: data.user.id, usuario, nombre, rol });
      if (e2) { await admin.auth.admin.deleteUser(data.user.id); return json({ error: e2.message }, 400); }
      return json({ id: data.user.id, usuario, nombre, rol });
    }

    case 'actualizar': {
      const id = String(body.id ?? '');
      const p = await perfilDe(id);
      if (!p) return json({ error: 'Esta cuenta ya no existe.' }, 404);
      const cambios: Record<string, string> = {};
      if (body.nombre != null) {
        const nombre = String(body.nombre).trim();
        if (!nombre) return json({ error: 'Escribe el nombre.' }, 400);
        cambios.nombre = nombre;
      }
      if (body.rol != null && ROLES.includes(String(body.rol))) {
        if (p.rol === 'superadmin' && body.rol !== 'superadmin' && (await contarSupers()) <= 1)
          return json({ error: 'Debe quedar al menos un super administrador.' }, 400);
        cambios.rol = String(body.rol);
      }
      const { error } = await admin.from('perfiles').update(cambios).eq('id', id);
      if (error) return json({ error: error.message }, 400);
      return json({ ...p, ...cambios });
    }

    case 'restablecer': {
      const id = String(body.id ?? '');
      const clave = String(body.clave ?? '');
      if (id === yoId) return json({ error: 'Para tu propia cuenta usa "Cambiar mi contraseña".' }, 400);
      if (clave.length < MIN_CLAVE) return json({ error: `La contraseña debe tener al menos ${MIN_CLAVE} caracteres.` }, 400);
      if (!(await perfilDe(id))) return json({ error: 'Esta cuenta ya no existe.' }, 404);
      const { error } = await admin.auth.admin.updateUserById(id, { password: clave });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    case 'eliminar': {
      const id = String(body.id ?? '');
      if (id === yoId) return json({ error: 'No puedes eliminar tu propia cuenta.' }, 400);
      const p = await perfilDe(id);
      if (!p) return json({ ok: true });
      if (p.rol === 'superadmin' && (await contarSupers()) <= 1)
        return json({ error: 'Debe quedar al menos un super administrador.' }, 400);
      // Borra el usuario de Auth; su perfil se borra en cascada y las
      // reglas RLS le cierran el acceso en la siguiente consulta.
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    default:
      return json({ error: 'Acción desconocida.' }, 400);
  }
});
