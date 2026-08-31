"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import { CATEGORIAS, diasExistencia, type Insumo } from "@/lib/types";
import { Card, SectionTitle, StatCard, GaugeBar } from "@/components/ui";

export default function DashboardPage() {
  const supabase = supabaseBrowser();
  const { profile } = useAuth();
  const [insumos, setInsumos] = useState<Insumo[]>([]);
  const [umbrales, setUmbrales] = useState({ critico: 5, bajo: 15 });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const [{ data: ins }, { data: cfg }] = await Promise.all([
        supabase.from("insumos").select("*").order("nombre"),
        supabase.from("config").select("*").eq("id", 1).maybeSingle(),
      ]);
      setInsumos((ins ?? []) as Insumo[]);
      if (cfg) setUmbrales({ critico: cfg.umbral_critico, bajo: cfg.umbral_bajo });
      setLoading(false);
    })();
  }, []); // eslint-disable-line

  const enriched = insumos.map((i) => ({ ...i, dias: diasExistencia(i.stock_real, i.consumo_dia) }));
  const criticos = enriched.filter((i) => i.dias !== null && i.dias < umbrales.critico);
  const bajos = enriched.filter((i) => i.dias !== null && i.dias >= umbrales.critico && i.dias < umbrales.bajo);
  const consumoTotal = insumos.reduce((s, i) => s + (i.consumo_dia || 0), 0);
  const enRiesgo = [...enriched].filter((i) => i.dias !== null).sort((a, b) => a.dias! - b.dias!).slice(0, 6);

  const accesos = [
    { href: "/inventario", label: "Inventario", icon: "📦", roles: ["gerente", "almacen", "ingeniero"] },
    { href: "/movimientos", label: "Registrar movimiento", icon: "🔁", roles: ["almacen"] },
    { href: "/produccion", label: "Producción del día", icon: "🧪", roles: ["gerente", "almacen", "ingeniero"] },
    { href: "/jarabes", label: "Jarabes", icon: "🧃", roles: ["gerente", "almacen", "jarabes"] },
    { href: "/informes", label: "Informes", icon: "🖨️", roles: ["gerente", "almacen", "ingeniero"] },
  ].filter((a) => a.roles.includes(profile?.rol ?? "ingeniero"));

  if (loading) return <div className="text-brand-muted text-sm">Cargando panel…</div>;

  return (
    <div className="space-y-6 max-w-6xl">
      <div>
        <h1 className="text-xl font-extrabold">Hola, {profile?.nombre?.split(" ")[0]} 👋</h1>
        <p className="text-brand-muted text-[13px] mt-0.5 capitalize">Sesión como {profile?.rol}</p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <StatCard icon="📦" label="Total insumos" value={insumos.length} color="#E2672B" />
        <StatCard icon="⚠️" label="Stock crítico" value={criticos.length} color="#D8433A" />
        <StatCard icon="🟡" label="Stock bajo" value={bajos.length} color="#C4880C" />
        <StatCard icon="📈" label="Consumo diario" value={consumoTotal.toLocaleString(undefined, { maximumFractionDigits: 0 })} color="#2F8F5B" />
      </div>

      <div className="grid md:grid-cols-2 gap-4">
        <Card>
          <SectionTitle title="Accesos rápidos" />
          <div className="grid grid-cols-2 gap-2">
            {accesos.map((a) => (
              <Link key={a.href} href={a.href} className="flex items-center gap-2 border border-brand-border rounded-lg px-3 py-3 text-[13px] font-semibold hover:bg-brand-bg">
                <span>{a.icon}</span>{a.label}
              </Link>
            ))}
          </div>
        </Card>

        <Card>
          <SectionTitle title="Insumos en riesgo" sub="Ordenados por urgencia" />
          <div className="space-y-2.5">
            {enRiesgo.length === 0 && <p className="text-[12.5px] text-brand-muted">Sin alertas por el momento. 🎉</p>}
            {enRiesgo.map((i) => (
              <div key={i.id} className="flex items-center gap-3">
                <span className="w-32 truncate text-[12.5px] font-semibold">{i.nombre}</span>
                <div className="flex-1"><GaugeBar dias={i.dias} critico={umbrales.critico} bajo={umbrales.bajo} /></div>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}
