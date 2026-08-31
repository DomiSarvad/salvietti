"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { inputCls, PrimaryButton } from "@/components/ui";

export default function LoginPage() {
  const supabase = supabaseBrowser();
  const router = useRouter();
  const [modo, setModo] = useState<"entrar" | "crear">("entrar");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [nombre, setNombre] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      if (modo === "entrar") {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      } else {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: { data: { nombre } },
        });
        if (error) throw error;
      }
      router.push("/dashboard");
      router.refresh();
    } catch (err: any) {
      setError(err.message ?? "No se pudo iniciar sesión.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-navy p-4">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-sm p-7">
        <div className="flex items-center gap-2 mb-6">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-accent to-good flex items-center justify-center text-white font-extrabold text-lg">S</div>
          <div>
            <div className="font-extrabold text-lg leading-tight">Salvietti Control</div>
            <div className="text-[11.5px] text-brand-muted">Sucre · Bolivia</div>
          </div>
        </div>

        <div className="flex gap-2 mb-5 text-[13px] font-bold">
          <button className={`flex-1 py-2 rounded-lg ${modo === "entrar" ? "bg-navy text-white" : "bg-brand-bg text-brand-muted"}`} onClick={() => setModo("entrar")}>
            Iniciar sesión
          </button>
          <button className={`flex-1 py-2 rounded-lg ${modo === "crear" ? "bg-navy text-white" : "bg-brand-bg text-brand-muted"}`} onClick={() => setModo("crear")}>
            Crear cuenta
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-3">
          {modo === "crear" && (
            <input className={inputCls} placeholder="Tu nombre completo" value={nombre} onChange={(e) => setNombre(e.target.value)} required />
          )}
          <input className={inputCls} type="email" placeholder="Correo electrónico" value={email} onChange={(e) => setEmail(e.target.value)} required />
          <input className={inputCls} type="password" placeholder="Contraseña" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} />
          {error && <div className="text-bad text-[12.5px] bg-bad-bg rounded-lg px-3 py-2">{error}</div>}
          <PrimaryButton type="submit" className="w-full" disabled={loading}>
            {loading ? "Cargando..." : modo === "entrar" ? "Entrar" : "Crear cuenta"}
          </PrimaryButton>
        </form>

        {modo === "crear" && (
          <p className="text-[11.5px] text-brand-slate mt-4 leading-relaxed">
            Las cuentas nuevas ingresan con rol <b>Ingeniero</b> (solo lectura) hasta que un
            Gerente les asigne el rol correspondiente desde "Usuarios y Roles".
          </p>
        )}
      </div>
    </div>
  );
}
