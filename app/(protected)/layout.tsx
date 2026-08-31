"use client";
import { useAuth } from "@/lib/auth-context";
import AppShell from "@/components/AppShell";

/**
 * Envuelve TODAS las páginas internas: exige sesión activa y muestra
 * el AppShell (sidebar/topbar/menú inferior) con el botón para volver
 * siempre disponible. Así se resuelve el bug de "no hay forma de volver
 * al menú principal" para cualquier pantalla nueva que se agregue.
 */
export default function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const { loading, userId, profile } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-brand-muted text-sm">
        Cargando Salvietti Control…
      </div>
    );
  }

  if (!userId) {
    if (typeof window !== "undefined") window.location.href = "/login";
    return null;
  }

  if (!profile) {
    return (
      <div className="min-h-screen flex items-center justify-center text-brand-muted text-sm px-6 text-center">
        Tu cuenta todavía no tiene un perfil asignado. Contacta al Gerente o Almacén.
      </div>
    );
  }

  return <AppShell>{children}</AppShell>;
}
