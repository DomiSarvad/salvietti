"use client";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import type { Movimiento } from "@/lib/types";
import { Card, SectionTitle, Field, inputCls, PrimaryButton, GhostButton } from "@/components/ui";

function hoyISO() { return new Date().toISOString().slice(0, 10); }
function hace30dias() { const d = new Date(); d.setDate(d.getDate() - 30); return d.toISOString().slice(0, 10); }

export default function InformesPage() {
  const supabase = supabaseBrowser();
  const [desde, setDesde] = useState(hace30dias());
  const [hasta, setHasta] = useState(hoyISO());
  const [tipo, setTipo] = useState<"todos" | "IN" | "OUT" | "TRF">("todos");
  const [movs, setMovs] = useState<Movimiento[]>([]);
  const [seleccionado, setSeleccionado] = useState<Movimiento | null>(null);

  async function buscar() {
    let q = supabase.from("movimientos").select("*").gte("fecha", desde).lte("fecha", hasta).order("fecha", { ascending: false }).order("hora", { ascending: false });
    if (tipo !== "todos") q = q.eq("tipo", tipo);
    const { data } = await q;
    setMovs((data ?? []) as Movimiento[]);
  }
  useEffect(() => { buscar(); }, []); // eslint-disable-line

  function imprimirRango() {
    setSeleccionado(null);
    setTimeout(() => window.print(), 50);
  }
  function imprimirUno(m: Movimiento) {
    setSeleccionado(m);
    setTimeout(() => window.print(), 50);
  }

  return (
    <div className="max-w-5xl space-y-4">
      <div className="no-print">
        <h1 className="text-lg font-extrabold mb-3">Informes de movimientos</h1>
        <Card>
          <div className="grid md:grid-cols-[1fr_1fr_1fr_auto_auto] gap-3 items-end">
            <Field label="Desde"><input type="date" className={inputCls} value={desde} onChange={(e) => setDesde(e.target.value)} /></Field>
            <Field label="Hasta"><input type="date" className={inputCls} value={hasta} onChange={(e) => setHasta(e.target.value)} /></Field>
            <Field label="Tipo">
              <select className={inputCls} value={tipo} onChange={(e) => setTipo(e.target.value as any)}>
                <option value="todos">Todos</option><option value="IN">Entradas</option><option value="OUT">Salidas</option><option value="TRF">Transferencias</option>
              </select>
            </Field>
            <PrimaryButton onClick={buscar}>Buscar</PrimaryButton>
            <GhostButton onClick={imprimirRango}>🖨️ Imprimir listado</GhostButton>
          </div>
        </Card>

        <Card className="mt-4 p-0 divide-y divide-brand-border">
          {movs.map((m) => (
            <div key={m.id} className="flex items-center gap-3 px-4 py-3">
              <span>{m.tipo === "IN" ? "🟢" : m.tipo === "OUT" ? "🔴" : "🔁"}</span>
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-[13px] truncate">{m.insumo_nombre}</div>
                <div className="text-[11px] text-brand-slate font-mono">{m.id} · {m.fecha} {m.hora?.slice(0, 5)} {m.proveedor ? `· ${m.proveedor}` : ""}</div>
              </div>
              <span className="font-mono text-[12.5px] font-bold">{m.cantidad.toLocaleString()} {m.unidad}</span>
              <button onClick={() => imprimirUno(m)} className="text-brand-slate hover:text-accent text-[12px] font-semibold ml-2">🖨️ Imprimir</button>
            </div>
          ))}
          {movs.length === 0 && <p className="text-center text-brand-muted py-8 text-sm">Sin movimientos en este rango.</p>}
        </Card>
      </div>

      {/* --- Área imprimible --- */}
      <div className="print-area hidden print:block">
        {seleccionado ? (
          <div className="p-8">
            <h2 className="text-xl font-bold mb-1">Comprobante de movimiento — Salvietti</h2>
            <p className="text-sm text-gray-500 mb-6">Generado el {hoyISO()}</p>
            <table className="w-full text-sm border-collapse">
              <tbody>
                {[
                  ["Folio", seleccionado.id], ["Tipo", seleccionado.tipo], ["Insumo", seleccionado.insumo_nombre],
                  ["Cantidad", `${seleccionado.cantidad} ${seleccionado.unidad}`], ["Fecha", seleccionado.fecha], ["Hora", seleccionado.hora],
                  ["Lote", seleccionado.lote ?? "—"], ["Vencimiento", seleccionado.vencimiento ?? "—"],
                  ["Proveedor", seleccionado.proveedor ?? "—"], ["Transportador", seleccionado.transportador ?? "—"],
                  ["Precio transporte", seleccionado.precio_transporte ? `Bs. ${seleccionado.precio_transporte}` : "—"],
                  ["Orden", seleccionado.orden ?? "—"], ["Notas", seleccionado.notas ?? "—"],
                ].map(([k, v]) => (
                  <tr key={k as string} className="border-b border-gray-200">
                    <td className="py-2 font-semibold w-48">{k}</td><td className="py-2">{v}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="p-8">
            <h2 className="text-xl font-bold mb-1">Listado de movimientos — Salvietti</h2>
            <p className="text-sm text-gray-500 mb-6">Del {desde} al {hasta}</p>
            <table className="w-full text-sm border-collapse">
              <thead><tr className="border-b-2 border-gray-400 text-left">
                <th className="py-2">Folio</th><th>Tipo</th><th>Insumo</th><th>Cantidad</th><th>Fecha</th><th>Proveedor</th>
              </tr></thead>
              <tbody>
                {movs.map((m) => (
                  <tr key={m.id} className="border-b border-gray-200">
                    <td className="py-1.5">{m.id}</td><td>{m.tipo}</td><td>{m.insumo_nombre}</td>
                    <td>{m.cantidad} {m.unidad}</td><td>{m.fecha}</td><td>{m.proveedor ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
