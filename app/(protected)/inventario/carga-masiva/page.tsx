"use client";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import { CATEGORIAS, type Insumo } from "@/lib/types";
import { Card, Chip, PrimaryButton, GhostButton } from "@/components/ui";

/**
 * Pantalla de "conteo físico": el equipo de almacén recorre la planta,
 * cuenta muchos insumos seguidos y va anotando la cantidad real de cada
 * uno en esta lista (como hacían en papel). Recién al final, cuando ya
 * verificaron todo, se presiona "Guardar conteo" y se actualiza el
 * sistema de una sola vez — nada se pierde si se cierra la pestaña a
 * mitad de camino, porque cada cambio se guarda en el navegador.
 */
export default function CargaMasivaPage() {
  const supabase = supabaseBrowser();
  const { profile } = useAuth();
  const [insumos, setInsumos] = useState<Insumo[]>([]);
  const [valores, setValores] = useState<Record<string, string>>({});
  const [cat, setCat] = useState("todos");
  const [guardando, setGuardando] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);

  useEffect(() => {
    supabase.from("insumos").select("*").order("categoria").order("nombre").then(({ data }) => {
      setInsumos((data ?? []) as Insumo[]);
      const draft = localStorage.getItem("salvietti_carga_masiva_draft");
      if (draft) setValores(JSON.parse(draft));
    });
  }, []); // eslint-disable-line

  function actualizar(id: string, v: string) {
    const next = { ...valores, [id]: v };
    setValores(next);
    localStorage.setItem("salvietti_carga_masiva_draft", JSON.stringify(next));
  }

  const contados = Object.keys(valores).filter((k) => valores[k] !== "" && !isNaN(parseFloat(valores[k]))).length;
  const filtrados = cat === "todos" ? insumos : insumos.filter((i) => i.categoria === cat);

  if (profile?.rol !== "almacen") {
    return <p className="text-brand-muted text-sm">Solo Almacén puede hacer conteos masivos.</p>;
  }

  async function guardarConteo() {
    setGuardando(true);
    const actualizaciones = Object.entries(valores)
      .filter(([, v]) => v !== "" && !isNaN(parseFloat(v)))
      .map(([id, v]) => ({ id, stock_real: parseFloat(v), stock_sistema: parseFloat(v) }));

    for (const upd of actualizaciones) {
      await supabase.from("insumos").update({ stock_real: upd.stock_real, stock_sistema: upd.stock_sistema }).eq("id", upd.id);
    }
    localStorage.removeItem("salvietti_carga_masiva_draft");
    setValores({});
    setGuardando(false);
    setMensaje(`Conteo guardado: ${actualizaciones.length} insumos actualizados.`);
  }

  return (
    <div className="max-w-4xl space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-lg font-extrabold">Carga masiva / Conteo físico</h1>
          <p className="text-[12.5px] text-brand-muted mt-0.5">Recorre la lista, anota lo contado y guarda todo al final. {contados} de {insumos.length} anotados.</p>
        </div>
        <PrimaryButton onClick={guardarConteo} disabled={guardando || contados === 0}>
          {guardando ? "Guardando…" : `Guardar conteo (${contados})`}
        </PrimaryButton>
      </div>

      {mensaje && <div className="bg-good-bg text-good text-[13px] font-semibold rounded-lg px-4 py-2.5">{mensaje}</div>}

      <div className="flex flex-wrap gap-2">
        <Chip active={cat === "todos"} onClick={() => setCat("todos")}>Todos</Chip>
        {CATEGORIAS.map((c) => <Chip key={c.key} active={cat === c.key} onClick={() => setCat(c.key)}>{c.label}</Chip>)}
      </div>

      <Card className="p-0 divide-y divide-brand-border">
        {filtrados.map((i) => (
          <div key={i.id} className="flex items-center gap-3 px-4 py-3">
            <div className="flex-1 min-w-0">
              <div className="font-semibold text-[13px] truncate">{i.nombre}</div>
              <div className="text-[11px] text-brand-slate font-mono">{i.codigo} · sistema: {i.stock_real.toLocaleString()} {i.unidad}</div>
            </div>
            <input
              type="number"
              placeholder="Cantidad contada"
              className={`w-36 border rounded-lg px-3 py-2 text-sm text-right ${valores[i.id] ? "border-accent bg-accent-bg font-bold" : "border-brand-border"}`}
              value={valores[i.id] ?? ""}
              onChange={(e) => actualizar(i.id, e.target.value)}
            />
            <span className="text-[12px] text-brand-slate w-8">{i.unidad}</span>
          </div>
        ))}
        {filtrados.length === 0 && <p className="text-center text-brand-muted py-8">No hay insumos en esta categoría.</p>}
      </Card>
    </div>
  );
}
