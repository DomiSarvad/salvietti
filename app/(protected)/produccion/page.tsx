"use client";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import type { ProduccionDiaria } from "@/lib/types";
import { Card, Field, inputCls, PrimaryButton, GhostButton } from "@/components/ui";

function hoyISO() { return new Date().toISOString().slice(0, 10); }

export default function ProduccionPage() {
  const supabase = supabaseBrowser();
  const { profile, userId } = useAuth();
  const puedeCrear = profile?.rol === "ingeniero" || profile?.rol === "almacen";

  const [lista, setLista] = useState<ProduccionDiaria[]>([]);
  const [sabores, setSabores] = useState<string[]>([]);
  const [modal, setModal] = useState(false);
  const [sabor, setSabor] = useState("");
  const [litros, setLitros] = useState("");
  const [guardando, setGuardando] = useState<string | null>(null);
  const [fecha, setFecha] = useState(hoyISO());

  async function cargar() {
    const [{ data: prod }, { data: rec }] = await Promise.all([
      supabase.from("produccion_diaria").select("*").eq("fecha", fecha).order("created_at"),
      supabase.from("recetas").select("sabor"),
    ]);
    setLista((prod ?? []) as ProduccionDiaria[]);
    setSabores(Array.from(new Set((rec ?? []).map((r: any) => r.sabor))));
  }
  useEffect(() => { cargar(); }, [fecha]); // eslint-disable-line

  async function agregar() {
    if (!sabor.trim() || !litros) return;
    await supabase.from("produccion_diaria").insert({
      fecha, sabor: sabor.trim(), litros_planificados: parseFloat(litros), creado_por: userId,
    });
    setModal(false); setSabor(""); setLitros("");
    cargar();
  }

  async function marcarCompletado(id: string) {
    setGuardando(id);
    // Llama a la función de Postgres que descuenta automáticamente los
    // insumos de la receta del sabor (azúcar, esencia, ácidos, etc.).
    const { error } = await supabase.rpc("fn_completar_produccion", { p_id: id });
    setGuardando(null);
    if (error) { alert("No se pudo marcar como completado: " + error.message); return; }
    cargar();
  }

  return (
    <div className="max-w-3xl space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-lg font-extrabold">Producción del día</h1>
          {/* Texto explicativo corto — antes salía gigante y en mayúsculas por error de estilo */}
          <p className="text-[12.5px] text-brand-muted mt-0.5 max-w-md">
            Marca cada sabor cuando termine de producirse: el sistema descuenta
            automáticamente azúcar, esencias y demás insumos según la fórmula registrada.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input type="date" className={`${inputCls} w-auto`} value={fecha} onChange={(e) => setFecha(e.target.value)} />
          {puedeCrear && <PrimaryButton onClick={() => setModal(true)}>+ Agregar sabor</PrimaryButton>}
        </div>
      </div>

      <Card className="p-0 divide-y divide-brand-border">
        {lista.map((p) => (
          <div key={p.id} className="flex items-center gap-3 px-4 py-3.5">
            <span className={`w-6 h-6 rounded-full flex items-center justify-center text-[13px] ${p.estado === "completado" ? "bg-good text-white" : "bg-brand-bg text-brand-slate border border-brand-border"}`}>
              {p.estado === "completado" ? "✓" : ""}
            </span>
            <div className="flex-1">
              <div className="font-bold text-[13.5px]">{p.sabor}</div>
              <div className="text-[11.5px] text-brand-muted">{p.litros_planificados.toLocaleString()} litros planificados</div>
            </div>
            {p.estado === "pendiente" ? (
              puedeCrear ? (
                <GhostButton onClick={() => marcarCompletado(p.id)} disabled={guardando === p.id}>
                  {guardando === p.id ? "Descontando…" : "Marcar completado"}
                </GhostButton>
              ) : <span className="text-[11px] text-brand-slate">Pendiente</span>
            ) : (
              <span className="text-[11px] font-bold text-good bg-good-bg px-2.5 py-1 rounded-full">Completado</span>
            )}
          </div>
        ))}
        {lista.length === 0 && <p className="text-center text-brand-muted py-8 text-sm">No hay producción planificada para esta fecha.</p>}
      </Card>

      {modal && (
        <div className="fixed inset-0 bg-navy/60 flex items-center justify-center p-4 z-50">
          <div className="bg-white rounded-2xl w-full max-w-sm p-5">
            <h2 className="font-extrabold text-[16px] mb-4">Agregar sabor a producir</h2>
            <div className="space-y-3">
              <Field label="Sabor">
                <input list="sabores" className={inputCls} value={sabor} onChange={(e) => setSabor(e.target.value)} placeholder="Ej. Lima Limón" />
                <datalist id="sabores">{sabores.map((s) => <option key={s} value={s} />)}</datalist>
              </Field>
              <Field label="Litros planificados"><input type="number" className={inputCls} value={litros} onChange={(e) => setLitros(e.target.value)} /></Field>
            </div>
            <div className="flex gap-2 mt-5">
              <GhostButton onClick={() => setModal(false)}>Cancelar</GhostButton>
              <PrimaryButton className="flex-1" onClick={agregar}>Agregar</PrimaryButton>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
