"use client";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { CATEGORIAS, type Insumo } from "@/lib/types";
import { Field, inputCls, PrimaryButton, GhostButton } from "@/components/ui";

async function siguienteCodigo(categoria: string): Promise<string> {
  const supabase = supabaseBrowser();
  const prefix = CATEGORIAS.find((c) => c.key === categoria)!.prefix;
  const { data } = await supabase.from("insumos").select("codigo").ilike("codigo", `${prefix}-%`);
  const max = (data ?? []).reduce((m, r: any) => {
    const n = parseInt(String(r.codigo).split("-")[1], 10) || 0;
    return Math.max(m, n);
  }, 0);
  return `${prefix}-${String(max + 1).padStart(3, "0")}`;
}

export default function InsumoModal({ editing, onClose, onSaved }: { editing?: Insumo; onClose: () => void; onSaved: () => void }) {
  const supabase = supabaseBrowser();
  const isEdit = !!editing;
  const [categoria, setCategoria] = useState(editing?.categoria ?? "esencia");
  const [codigo, setCodigo] = useState(editing?.codigo ?? "");
  const [nombre, setNombre] = useState(editing?.nombre ?? "");
  const [unidad, setUnidad] = useState(editing?.unidad ?? "Kg");
  const [stock, setStock] = useState(editing ? String(editing.stock_real) : "");
  const [consumo, setConsumo] = useState(editing ? String(editing.consumo_dia) : "");
  const [proveedor, setProveedor] = useState(editing?.proveedor ?? "");
  const [stockMin, setStockMin] = useState(editing ? String(editing.stock_min) : "");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!isEdit) siguienteCodigo(categoria).then(setCodigo);
  }, [categoria]); // eslint-disable-line

  async function guardar() {
    if (!nombre.trim()) return;
    setSaving(true);
    const payload = {
      codigo, nombre: nombre.trim(), categoria, unidad,
      stock_real: parseFloat(stock) || 0,
      stock_sistema: parseFloat(stock) || 0,
      consumo_dia: parseFloat(consumo) || 0,
      proveedor, stock_min: parseFloat(stockMin) || 0,
    };
    const { error } = editing
      ? await supabase.from("insumos").update(payload).eq("id", editing.id)
      : await supabase.from("insumos").insert(payload);
    setSaving(false);
    if (error) { alert("No se pudo guardar: " + error.message); return; }
    onSaved();
  }

  async function eliminar() {
    if (!editing || !confirm("¿Eliminar este insumo?")) return;
    await supabase.from("insumos").delete().eq("id", editing.id);
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-navy/60 flex items-center justify-center p-4 z-50">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="px-5 py-4 border-b border-brand-border flex items-center justify-between">
          <h2 className="font-extrabold text-[16px]">{isEdit ? "Editar Insumo" : "Nuevo Insumo"}</h2>
          <button onClick={onClose} className="text-brand-slate text-xl leading-none">×</button>
        </div>
        <div className="p-5 space-y-3.5">
          <Field label="Nombre del insumo"><input className={inputCls} value={nombre} onChange={(e) => setNombre(e.target.value)} /></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Categoría">
              <select className={inputCls} value={categoria} onChange={(e) => setCategoria(e.target.value)}>
                {CATEGORIAS.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
              </select>
            </Field>
            <Field label="Código (automático)"><input className={`${inputCls} font-mono`} value={codigo} onChange={(e) => setCodigo(e.target.value)} /></Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Unidad">
              <select className={inputCls} value={unidad} onChange={(e) => setUnidad(e.target.value)}>
                {["Kg", "L", "Pza", "ml"].map((u) => <option key={u}>{u}</option>)}
              </select>
            </Field>
            <Field label="Proveedor"><input className={inputCls} value={proveedor} onChange={(e) => setProveedor(e.target.value)} /></Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Stock real"><input type="number" className={inputCls} value={stock} onChange={(e) => setStock(e.target.value)} /></Field>
            <Field label="Consumo / día"><input type="number" className={inputCls} value={consumo} onChange={(e) => setConsumo(e.target.value)} /></Field>
          </div>
          <Field label="Stock mínimo de alerta"><input type="number" className={inputCls} value={stockMin} onChange={(e) => setStockMin(e.target.value)} /></Field>
        </div>
        <div className="px-5 py-4 border-t border-brand-border bg-brand-bg flex items-center gap-2">
          {isEdit && <button onClick={eliminar} className="text-bad text-[12.5px] font-bold mr-auto">Eliminar</button>}
          <GhostButton onClick={onClose}>Cancelar</GhostButton>
          <PrimaryButton onClick={guardar} disabled={saving}>{saving ? "Guardando…" : isEdit ? "Guardar cambios" : "Registrar insumo"}</PrimaryButton>
        </div>
      </div>
    </div>
  );
}
