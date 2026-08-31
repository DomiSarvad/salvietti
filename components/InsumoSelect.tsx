"use client";
import { useEffect, useRef, useState } from "react";
import type { Insumo } from "@/lib/types";

export default function InsumoSelect({ insumos, value, onChange }: { insumos: Insumo[]; value: Insumo | null; onChange: (i: Insumo) => void }) {
  const [open, setOpen] = useState(false);
  const [term, setTerm] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClick(e: MouseEvent) { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); }
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const filtered = insumos.filter((i) => {
    const t = term.trim().toLowerCase();
    if (!t) return true;
    return i.nombre.toLowerCase().includes(t) || i.codigo.toLowerCase().includes(t);
  }).slice(0, 40);

  return (
    <div className="relative" ref={ref}>
      <button type="button" onClick={() => setOpen((o) => !o)} className="w-full flex items-center gap-2 border border-brand-border rounded-lg px-3 py-2.5 text-left">
        {value ? (
          <span className="text-[13.5px]"><span className="font-mono text-accent font-bold mr-1.5">{value.codigo}</span>{value.nombre}</span>
        ) : (
          <span className="text-[13.5px] text-brand-slate">Buscar por nombre o código…</span>
        )}
        <span className="ml-auto text-brand-slate">▾</span>
      </button>
      {open && (
        <div className="absolute z-20 mt-1 w-full bg-white border border-brand-border rounded-lg shadow-lg max-h-72 overflow-y-auto">
          <div className="p-2 sticky top-0 bg-white border-b border-brand-border">
            <input autoFocus className="w-full border border-brand-border rounded-md px-2.5 py-1.5 text-sm" placeholder="Escribe para filtrar…" value={term} onChange={(e) => setTerm(e.target.value)} />
          </div>
          {filtered.map((i) => (
            <button type="button" key={i.id} onClick={() => { onChange(i); setOpen(false); setTerm(""); }} className="w-full text-left px-3 py-2 text-[13px] hover:bg-brand-bg flex justify-between gap-2">
              <span><span className="font-mono text-brand-muted mr-1.5">{i.codigo}</span>{i.nombre}</span>
              <span className="text-brand-slate text-[11px] shrink-0">{i.stock_real.toLocaleString()} {i.unidad}</span>
            </button>
          ))}
          {filtered.length === 0 && <div className="px-3 py-3 text-[12.5px] text-brand-muted">Sin resultados.</div>}
        </div>
      )}
    </div>
  );
}
