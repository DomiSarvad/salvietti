"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useState } from "react";
import { useAuth } from "@/lib/auth-context";
import { PERMISOS } from "@/lib/types";

const NAV = [
  { href: "/dashboard", label: "Panel General", icon: "📊", roles: ["gerente", "almacen", "jarabes", "ingeniero"] },
  { href: "/inventario", label: "Inventario", icon: "📦", roles: ["gerente", "almacen", "ingeniero"] },
  { href: "/movimientos", label: "Movimientos", icon: "🔁", roles: ["almacen"] },
  { href: "/produccion", label: "Producción del día", icon: "🧪", roles: ["gerente", "almacen", "ingeniero"] },
  { href: "/jarabes", label: "Jarabes", icon: "🧃", roles: ["gerente", "almacen", "jarabes"] },
  { href: "/informes", label: "Informes", icon: "🖨️", roles: ["gerente", "almacen", "ingeniero"] },
  { href: "/usuarios", label: "Usuarios y Roles", icon: "👥", roles: ["gerente"] },
];

/**
 * Contenedor de toda la app: barra superior con botón para volver al
 * panel principal (el bug reportado de "no hay forma de volver"),
 * sidebar fijo en pantallas grandes y menú inferior en celular.
 */
export default function AppShell({ children }: { children: React.ReactNode }) {
  const { profile, signOut } = useAuth();
  const pathname = usePathname();
  const router = useRouter();
  const [menuOpen, setMenuOpen] = useState(false);

  const rol = profile?.rol ?? "ingeniero";
  const items = NAV.filter((n) => n.roles.includes(rol));
  const current = NAV.find((n) => pathname?.startsWith(n.href));

  return (
    <div className="min-h-screen bg-brand-bg text-brand-text flex flex-col md:flex-row">
      {/* --- Sidebar (laptop/desktop) --- */}
      <aside className="hidden md:flex md:w-60 md:flex-col bg-navy text-navy-text sticky top-0 h-screen">
        <div className="px-5 py-5 border-b border-navy-border flex items-center gap-2">
          <div className="w-9 h-9 rounded-lg bg-gradient-to-br from-accent to-good flex items-center justify-center text-white font-extrabold">S</div>
          <div>
            <div className="text-white font-extrabold text-[15px] leading-tight">Salvietti Control</div>
            <div className="text-[11px] text-navy-text">Sucre · Bolivia</div>
          </div>
        </div>
        <nav className="flex-1 p-3 space-y-1 overflow-y-auto">
          {items.map((it) => {
            const active = pathname?.startsWith(it.href);
            return (
              <Link
                key={it.href}
                href={it.href}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-[13.5px] font-medium transition
                  ${active ? "bg-navy-2 text-white border-l-2 border-accent" : "text-navy-text hover:bg-navy-2/60"}`}
              >
                <span>{it.icon}</span>{it.label}
              </Link>
            );
          })}
        </nav>
        <div className="p-3 border-t border-navy-border">
          <Link href="/perfil" className="flex items-center gap-2 px-2 py-2 rounded-lg hover:bg-navy-2">
            <div className="w-8 h-8 rounded-full bg-navy-2 flex items-center justify-center text-sm">
              {profile?.avatar_url ? <img src={profile.avatar_url} className="w-8 h-8 rounded-full object-cover" alt="" /> : "🙂"}
            </div>
            <div className="min-w-0">
              <div className="text-white text-[12.5px] font-semibold truncate">{profile?.nombre ?? "Usuario"}</div>
              <div className="text-[10.5px] text-navy-text capitalize">{rol}</div>
            </div>
          </Link>
          <button onClick={signOut} className="mt-2 w-full text-[12px] text-navy-text hover:text-white text-left px-2">
            Cerrar sesión
          </button>
        </div>
      </aside>

      {/* --- Barra superior (todas las pantallas) --- */}
      <div className="flex-1 flex flex-col min-w-0">
        <header className="h-16 bg-white border-b border-brand-border flex items-center gap-3 px-4 md:px-6 sticky top-0 z-30">
          {/* Botón "volver al panel" — SIEMPRE visible salvo ya estando en el panel */}
          {pathname !== "/dashboard" && (
            <button
              onClick={() => router.push("/dashboard")}
              className="flex items-center gap-1 text-[12.5px] font-semibold text-brand-muted hover:text-accent px-2 py-1.5 rounded-lg hover:bg-brand-bg shrink-0"
              title="Volver al panel principal"
            >
              ← Menú principal
            </button>
          )}
          <div className="min-w-0 flex-1">
            <div className="text-[15px] md:text-[17px] font-extrabold truncate">{current?.label ?? "Salvietti Control"}</div>
          </div>
          <button className="md:hidden text-2xl" onClick={() => setMenuOpen((o) => !o)} aria-label="Menú">
            ☰
          </button>
        </header>

        {/* Menú desplegable en celular */}
        {menuOpen && (
          <div className="md:hidden bg-navy text-white p-3 space-y-1">
            {items.map((it) => (
              <Link
                key={it.href}
                href={it.href}
                onClick={() => setMenuOpen(false)}
                className={`flex items-center gap-3 px-3 py-3 rounded-lg text-sm ${pathname?.startsWith(it.href) ? "bg-navy-2" : ""}`}
              >
                <span>{it.icon}</span>{it.label}
              </Link>
            ))}
            <Link href="/perfil" onClick={() => setMenuOpen(false)} className="flex items-center gap-3 px-3 py-3 rounded-lg text-sm">
              👤 Mi perfil
            </Link>
            <button onClick={signOut} className="w-full text-left px-3 py-3 rounded-lg text-sm text-red-300">
              Cerrar sesión
            </button>
          </div>
        )}

        <main className="flex-1 p-4 md:p-6 pb-20 md:pb-6">{children}</main>

        {/* --- Menú inferior fijo (celular) --- */}
        <nav className="md:hidden fixed bottom-0 left-0 right-0 bg-white border-t border-brand-border flex justify-around py-1.5 z-30">
          {items.slice(0, 5).map((it) => {
            const active = pathname?.startsWith(it.href);
            return (
              <Link key={it.href} href={it.href} className={`flex flex-col items-center gap-0.5 px-2 py-1 text-[10px] ${active ? "text-accent font-bold" : "text-brand-slate"}`}>
                <span className="text-lg leading-none">{it.icon}</span>
                {it.label.split(" ")[0]}
              </Link>
            );
          })}
        </nav>
      </div>
    </div>
  );
}
