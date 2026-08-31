"use client";
import { createBrowserClient } from "@supabase/ssr";

/**
 * Cliente de Supabase para el navegador.
 *
 * IMPORTANTE — causa más común de "no guarda datos":
 * en Next.js, las variables de entorno que se usan en el navegador
 * DEBEN empezar con el prefijo NEXT_PUBLIC_. Si tu .env tenía
 * SUPABASE_URL / SUPABASE_ANON_KEY (sin el prefijo), el cliente
 * quedaba sin URL/clave y todas las escrituras fallaban en silencio.
 * Por eso aquí usamos NEXT_PUBLIC_SUPABASE_URL y NEXT_PUBLIC_SUPABASE_ANON_KEY.
 */
export function supabaseBrowser() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
