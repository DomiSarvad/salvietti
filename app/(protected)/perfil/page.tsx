"use client";
import { useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import { Card, SectionTitle, Field, inputCls, PrimaryButton } from "@/components/ui";

/**
 * Personalización del propio usuario: foto/avatar y tema de color.
 * El nombre y el rol NO son editables aquí — solo el Gerente puede
 * cambiarlos, desde "Usuarios y Roles".
 */
export default function PerfilPage() {
  const supabase = supabaseBrowser();
  const { profile, refreshProfile } = useAuth();
  const [avatarUrl, setAvatarUrl] = useState(profile?.avatar_url ?? "");
  const [tema, setTema] = useState<"claro" | "oscuro">(profile?.tema ?? "claro");
  const [guardando, setGuardando] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function guardar() {
    if (!profile) return;
    setGuardando(true);
    const { error } = await supabase.from("profiles").update({ avatar_url: avatarUrl || null, tema }).eq("id", profile.id);
    setGuardando(false);
    if (error) { alert("No se pudo guardar: " + error.message); return; }
    await refreshProfile();
    setMsg("Perfil actualizado.");
  }

  return (
    <div className="max-w-md space-y-4">
      <h1 className="text-lg font-extrabold">Mi perfil</h1>

      <Card>
        <div className="flex items-center gap-3 mb-4">
          <div className="w-14 h-14 rounded-full bg-brand-bg flex items-center justify-center text-2xl overflow-hidden">
            {avatarUrl ? <img src={avatarUrl} className="w-14 h-14 object-cover" alt="" /> : "🙂"}
          </div>
          <div>
            <div className="font-bold text-[15px]">{profile?.nombre}</div>
            <div className="text-[12px] text-brand-muted capitalize">{profile?.rol} · no editable</div>
          </div>
        </div>

        <div className="space-y-3.5">
          <Field label="URL de foto de perfil" hint="Pega el enlace de una imagen (por ahora no se suben archivos)">
            <input className={inputCls} value={avatarUrl} onChange={(e) => setAvatarUrl(e.target.value)} placeholder="https://..." />
          </Field>
          <Field label="Tema de color">
            <div className="flex gap-2">
              {(["claro", "oscuro"] as const).map((t) => (
                <button key={t} onClick={() => setTema(t)} className={`flex-1 py-2 rounded-lg border text-[12.5px] font-bold capitalize ${tema === t ? "border-accent bg-accent-bg text-accent-dark" : "border-brand-border text-brand-muted"}`}>
                  {t}
                </button>
              ))}
            </div>
          </Field>
          {msg && <div className="bg-good-bg text-good text-[12.5px] font-semibold rounded-lg px-3 py-2">{msg}</div>}
          <PrimaryButton className="w-full" onClick={guardar} disabled={guardando}>{guardando ? "Guardando…" : "Guardar cambios"}</PrimaryButton>
        </div>
      </Card>

      <p className="text-[11.5px] text-brand-slate leading-relaxed px-1">
        Tu nombre y tu rol los define el Gerente desde "Usuarios y Roles" — así se evita que
        alguien cambie su propio nivel de acceso.
      </p>
    </div>
  );
}
