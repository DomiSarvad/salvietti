"use client";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import type { Profile, Rol } from "@/lib/types";
import { Card, SectionTitle } from "@/components/ui";

const ROLES: { key: Rol; label: string; desc: string }[] = [
  { key: "gerente", label: "Gerente", desc: "Solo observa: analítica y administración de usuarios" },
  { key: "almacen", label: "Almacén", desc: "Control total: inventario, movimientos y Jarabes" },
  { key: "jarabes", label: "Jarabes", desc: "Solo sus propios movimientos de Jarabes" },
  { key: "ingeniero", label: "Ingeniero", desc: "Solo observa y arma la producción del día" },
];

export default function UsuariosPage() {
  const supabase = supabaseBrowser();
  const { profile } = useAuth();
  const [usuarios, setUsuarios] = useState<Profile[]>([]);
  const [cambiando, setCambiando] = useState<string | null>(null);

  async function cargar() {
    const { data } = await supabase.from("profiles").select("*").order("nombre");
    setUsuarios((data ?? []) as Profile[]);
  }
  useEffect(() => { cargar(); }, []); // eslint-disable-line

  if (profile?.rol !== "gerente") {
    return <p className="text-brand-muted text-sm">Solo el Gerente puede administrar usuarios y roles.</p>;
  }

  async function cambiarRol(id: string, rol: Rol) {
    setCambiando(id);
    await supabase.from("profiles").update({ rol }).eq("id", id);
    setCambiando(null);
    cargar();
  }

  async function alternarActivo(u: Profile) {
    await supabase.from("profiles").update({ activo: !u.activo }).eq("id", u.id);
    cargar();
  }

  return (
    <div className="max-w-3xl space-y-4">
      <div>
        <h1 className="text-lg font-extrabold">Usuarios y Roles</h1>
        <p className="text-[12.5px] text-brand-muted mt-0.5">
          Las cuentas nuevas se crean desde la pantalla de inicio de sesión con rol Ingeniero por defecto.
          Aquí les asignas el rol que corresponda.
        </p>
      </div>

      <Card className="p-0 divide-y divide-brand-border">
        {usuarios.map((u) => (
          <div key={u.id} className="flex flex-wrap items-center gap-3 px-4 py-3.5">
            <div className="w-9 h-9 rounded-full bg-brand-bg flex items-center justify-center text-sm shrink-0">
              {u.avatar_url ? <img src={u.avatar_url} className="w-9 h-9 rounded-full object-cover" alt="" /> : "🙂"}
            </div>
            <div className="min-w-[140px] flex-1">
              <div className="font-bold text-[13.5px]">{u.nombre}</div>
              <div className="text-[11px] text-brand-slate">{u.activo ? "Activo" : "Inactivo"}</div>
            </div>
            <select
              className="border border-brand-border rounded-lg px-2.5 py-1.5 text-[12.5px] font-semibold"
              value={u.rol}
              disabled={cambiando === u.id}
              onChange={(e) => cambiarRol(u.id, e.target.value as Rol)}
            >
              {ROLES.map((r) => <option key={r.key} value={r.key}>{r.label}</option>)}
            </select>
            <button onClick={() => alternarActivo(u)} className={`text-[11.5px] font-bold px-2.5 py-1.5 rounded-lg ${u.activo ? "text-bad hover:bg-bad-bg" : "text-good hover:bg-good-bg"}`}>
              {u.activo ? "Desactivar" : "Activar"}
            </button>
          </div>
        ))}
      </Card>

      <Card>
        <SectionTitle title="Descripción de roles" />
        <div className="grid sm:grid-cols-2 gap-3">
          {ROLES.map((r) => (
            <div key={r.key} className="border border-brand-border rounded-lg p-3">
              <div className="font-bold text-[13px]">{r.label}</div>
              <div className="text-[12px] text-brand-muted mt-0.5">{r.desc}</div>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}
