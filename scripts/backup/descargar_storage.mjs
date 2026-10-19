// Descarga TODOS los archivos de Supabase Storage (fotos de perfil, fotos de
// recepciones, etc.) a una carpeta local, respetando bucket/carpetas.
// Lo usa el respaldo diario (.github/workflows/backup.yml); también se puede
// correr a mano:
//
//   SUPABASE_URL=https://xxxx.supabase.co SUPABASE_SERVICE_ROLE_KEY=... \
//     node scripts/backup/descargar_storage.mjs ./respaldo/storage
//
// Usa la clave service_role porque tiene que leer los buckets privados: NUNCA
// va en la app ni en el repositorio, solo como secreto de GitHub.
// Sin dependencias: Node 18+ trae fetch.

import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const url = process.env.SUPABASE_URL?.replace(/\/+$/, '');
const clave = process.env.SUPABASE_SERVICE_ROLE_KEY;
const destino = process.argv[2] ?? './storage';

if (!url || !clave) {
  console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const headers = { Authorization: `Bearer ${clave}`, apikey: clave };

async function pedir(ruta, opciones = {}, intentos = 3) {
  for (let i = 1; ; i++) {
    const r = await fetch(`${url}/storage/v1${ruta}`, { ...opciones, headers: { ...headers, ...opciones.headers } });
    if (r.ok) return r;
    // Reintenta lo que suele ser pasajero (límite de pedidos, servidor ocupado).
    if (i < intentos && (r.status === 429 || r.status >= 500)) {
      await new Promise((ok) => setTimeout(ok, 1000 * i));
      continue;
    }
    throw new Error(`${opciones.method ?? 'GET'} ${ruta} → ${r.status} ${await r.text()}`);
  }
}

/** Lista todo lo que hay bajo [prefijo], entrando a las subcarpetas. */
async function listar(bucket, prefijo = '') {
  const archivos = [];
  for (let offset = 0; ; offset += 1000) {
    const r = await pedir(`/object/list/${encodeURIComponent(bucket)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix: prefijo, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } }),
    });
    const items = await r.json();
    for (const it of items) {
      const ruta = prefijo ? `${prefijo}/${it.name}` : it.name;
      // Las "carpetas" vienen sin id.
      if (it.id == null) archivos.push(...(await listar(bucket, ruta)));
      else archivos.push(ruta);
    }
    if (items.length < 1000) return archivos;
  }
}

const buckets = await (await pedir('/bucket')).json();
let total = 0;
let bytes = 0;
for (const b of buckets) {
  const archivos = await listar(b.id);
  console.log(`Bucket "${b.id}": ${archivos.length} archivo(s)`);
  for (const ruta of archivos) {
    const camino = ruta.split('/').map(encodeURIComponent).join('/');
    const r = await pedir(`/object/${encodeURIComponent(b.id)}/${camino}`);
    const datos = Buffer.from(await r.arrayBuffer());
    const archivoLocal = join(destino, b.id, ...ruta.split('/'));
    await mkdir(dirname(archivoLocal), { recursive: true });
    await writeFile(archivoLocal, datos);
    total++;
    bytes += datos.length;
  }
}
console.log(`Listo: ${total} archivo(s), ${(bytes / 1024 / 1024).toFixed(1)} MB.`);
