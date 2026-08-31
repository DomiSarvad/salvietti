"use client";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import { CATEGORIAS, categoriaInfo, diasExistencia, type Insumo } from "@/lib/types";
import { Card, Chip, EstadoBadge, GaugeBar, PrimaryButton, GhostButton, inputCls } from "@/components/ui";
import InsumoModal from "@/components/InsumoModal";

export default function InventarioPage() {
  const supabase = supabaseBrowser();
  const { profile } = useAuth();
  const puedeEditar = profile?.rol === "almacen";

  const [insumos, setInsumos] = useState<Insumo[]>([]);
  const [umbrales, setUmbrales] = useState({ critico: 5, bajo: 15 });
  const [cat, setCat] = useState<string>("todos");
  const [q, setQ] = useState("");
  const [modal, setModal] = useState<{ open: boolean; editing?: Insumo }>({ open: false });
  const [loading, setLoading] = useState(true);

  async function cargar() {
    setLoading(true);
    const [{ data: ins }, { data: cfg }] = await Promise.all([
      supabase.from("insumos").select("*").order("nombre"),
      supabase.from("config").select("*").eq("id", 1).maybeSingle(),
    ]);
    setInsumos((ins ?? []) as Insumo[]);
    if (cfg) setUmbrales({ critico: cfg.umbral_critico, bajo: cfg.umbral_bajo });
    setLoading(false);
  }
  useEffect(() => { cargar(); }, []); // eslint-disable-line

  const filtrados = useMemo(() => {
    return insumos.filter((i) => {
      if (cat !== "todos" && i.categoria !== cat) return false;
      const qq = q.trim().toLowerCase();
      if (qq && !(i.nombre.toLowerCase().includes(qq) || i.codigo.toLowerCase().includes(qq))) return false;
      return true;
    });
  }, [insumos, cat, q]);

  return (
    <div className="max-w-6xl space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-lg font-extrabold">Inventario de Insumos</h1>
        {puedeEditar && (
          <div className="flex gap-2">
            <Link href="/inventario/carga-masiva">
              <GhostButton>📋 Carga masiva</GhostButton>
            </Link>
            <PrimaryButton onClick={() => setModal({ open: true })}>+ Nuevo Insumo</PrimaryButton>
          </div>
        )}
      </div>

      <Card>
        <div className="flex flex-col md:flex-row md:items-center gap-3 mb-4">
          <div className="flex flex-wrap gap-2">
            <Chip active={cat === "todos"} onClick={() => setCat("todos")}>Todos</Chip>
            {CATEGORIAS.map((c) => (
              <Chip key={c.key} active={cat === c.key} onClick={() => setCat(c.key)}>{c.label}</Chip>
            ))}
          </div>
          <input className={`${inputCls} md:ml-auto md:max-w-xs`} placeholder="Buscar por nombre o código…" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>

        {loading ? (
          <p className="text-brand-muted text-sm py-6 text-center">Cargando inventario…</p>
        ) : (
          <div className="overflow-x-auto -mx-5">
            <table className="w-full text-sm min-w-[760px]">
              <thead>
                <tr className="text-left text-[11px] uppercase tracking-wide text-brand-slate border-b border-brand-border">
                  <th className="px-5 py-2 font-bold">Código</th>
                  <th className="px-5 py-2 font-bold">Insumo</th>
                  <th className="px-5 py-2 font-bold">Categoría</th>
                  <th className="px-5 py-2 font-bold">Stock real</th>
                  <th className="px-5 py-2 font-bold">Días existencia</th>
                  <th className="px-5 py-2 font-bold">Estado</th>
                  {puedeEditar && <th className="px-5 py-2 font-bold"></th>}
                </tr>
              </thead>
              <tbody>
                {filtrados.map((i) => {
                  const dias = diasExistencia(i.stock_real, i.consumo_dia);
                  return (
                    <tr key={i.id} className="border-b border-brand-border hover:bg-brand-bg">
                      <td className="px-5 py-3 font-mono text-[12px] text-brand-muted">{i.codigo}</td>
                      <td className="px-5 py-3">
                        <div className="font-bold text-[13px]">{i.nombre}</div>
                        <div className="text-[11px] text-brand-slate">{i.proveedor}</div>
                      </td>
                      <td className="px-5 py-3 text-[12px] text-brand-muted flex items-center gap-1.5">
                        <span className="w-2 h-2 rounded-full inline-block" style={{ background: categoriaInfo(i.categoria).color }} />
                        {categoriaInfo(i.categoria).label}
                      </td>
                      <td className="px-5 py-3 font-semibold">{i.stock_real.toLocaleString()} {i.unidad}</td>
                      <td className="px-5 py-3"><GaugeBar dias={dias} critico={umbrales.critico} bajo={umbrales.bajo} /></td>
                      <td className="px-5 py-3"><EstadoBadge dias={dias} critico={umbrales.critico} bajo={umbrales.bajo} /></td>
                      {puedeEditar && (
                        <td className="px-5 py-3">
                          <button onClick={() => setModal({ open: true, editing: i })} className="text-brand-slate hover:text-accent">✏️</button>
                        </td>
                      )}
                    </tr>
                  );
                })}
                {filtrados.length === 0 && (
                  <tr><td colSpan={7} className="text-center text-brand-muted py-8">No se encontraron insumos.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {modal.open && (
        <InsumoModal
          editing={modal.editing}
          onClose={() => setModal({ open: false })}
          onSaved={() => { setModal({ open: false }); cargar(); }}
        />
      )}
    </div>
  );
}
