"use client";
import { useEffect, useMemo, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import type { Insumo, Movimiento } from "@/lib/types";
import { Card, SectionTitle, Field, inputCls, PrimaryButton, GhostButton } from "@/components/ui";
import InsumoSelect from "@/components/InsumoSelect";
import ComboboxCreatable, { asegurarExiste } from "@/components/ComboboxCreatable";

function hoyISO() { return new Date().toISOString().slice(0, 10); }
function horaAhora() { return new Date().toTimeString().slice(0, 5); }

async function siguienteMovId(tipo: string): Promise<string> {
  const supabase = supabaseBrowser();
  const { data } = await supabase.from("movimientos").select("id").ilike("id", `${tipo}-%`);
  const max = (data ?? []).reduce((m, r: any) => Math.max(m, parseInt(String(r.id).split("-")[1], 10) || 0), 0);
  return `${tipo}-${String(max + 1).padStart(3, "0")}`;
}
async function siguienteLote(): Promise<string> {
  const supabase = supabaseBrowser();
  const ymd = hoyISO().replace(/-/g, "");
  const { data } = await supabase.from("movimientos").select("lote").ilike("lote", `LT-${ymd}-%`);
  const max = (data ?? []).reduce((m, r: any) => Math.max(m, parseInt(String(r.lote).split("-")[2], 10) || 0), 0);
  return `LT-${ymd}-${String(max + 1).padStart(2, "0")}`;
}

/** Trae el proveedor más frecuente para este insumo en sus últimas entradas. */
async function proveedorHabitual(insumoId: string): Promise<string> {
  const supabase = supabaseBrowser();
  const { data } = await supabase
    .from("movimientos").select("proveedor")
    .eq("insumo_id", insumoId).eq("tipo", "IN").not("proveedor", "is", null)
    .order("fecha", { ascending: false }).limit(5);
  const conteo: Record<string, number> = {};
  (data ?? []).forEach((r: any) => { if (r.proveedor) conteo[r.proveedor] = (conteo[r.proveedor] || 0) + 1; });
  const top = Object.entries(conteo).sort((a, b) => b[1] - a[1])[0];
  return top ? top[0] : "";
}

export default function MovimientosPage() {
  const supabase = supabaseBrowser();
  const { profile, userId } = useAuth();
  const [insumos, setInsumos] = useState<Insumo[]>([]);
  const [recientes, setRecientes] = useState<Movimiento[]>([]);

  const [tipo, setTipo] = useState<"IN" | "OUT" | "TRF">("IN");
  const [insumo, setInsumo] = useState<Insumo | null>(null);
  const [cantidad, setCantidad] = useState("");
  const [fecha, setFecha] = useState(hoyISO());
  const [hora, setHora] = useState(horaAhora());
  const [lote, setLote] = useState("");
  const [vencimiento, setVencimiento] = useState("");
  const [proveedor, setProveedor] = useState("");
  const [transportador, setTransportador] = useState("");
  const [precioTransporte, setPrecioTransporte] = useState("");
  const [orden, setOrden] = useState("");
  const [notas, setNotas] = useState("");
  const [idSugerido, setIdSugerido] = useState("IN-001");
  const [guardando, setGuardando] = useState(false);
  const [okMsg, setOkMsg] = useState<string | null>(null);

  async function cargar() {
    const [{ data: ins }, { data: movs }] = await Promise.all([
      supabase.from("insumos").select("*").order("nombre"),
      supabase.from("movimientos").select("*").eq("area", "almacen").order("fecha", { ascending: false }).order("hora", { ascending: false }).limit(12),
    ]);
    setInsumos((ins ?? []) as Insumo[]);
    setRecientes((movs ?? []) as Movimiento[]);
  }
  useEffect(() => { cargar(); }, []); // eslint-disable-line

  useEffect(() => { siguienteMovId(tipo).then(setIdSugerido); if (tipo === "IN") siguienteLote().then(setLote); }, [tipo]); // eslint-disable-line

  // Al elegir un insumo, autocompletamos con el proveedor habitual (si existe).
  useEffect(() => {
    if (insumo && tipo === "IN") proveedorHabitual(insumo.id).then((p) => { if (p) setProveedor(p); });
  }, [insumo, tipo]); // eslint-disable-line

  if (profile?.rol !== "almacen") {
    return <p className="text-brand-muted text-sm">Solo Almacén puede registrar movimientos generales.</p>;
  }

  const cantNum = parseFloat(cantidad) || 0;
  const stockInsuficiente = tipo === "OUT" && insumo && cantNum > insumo.stock_real;

  function limpiar() {
    setInsumo(null); setCantidad(""); setFecha(hoyISO()); setHora(horaAhora());
    setVencimiento(""); setProveedor(""); setTransportador(""); setPrecioTransporte("");
    setOrden(""); setNotas("");
  }

  async function registrar() {
    if (!insumo || cantNum <= 0) return;
    setGuardando(true);
    const id = await siguienteMovId(tipo);

    if (tipo === "IN" && proveedor.trim()) await asegurarExiste("proveedores", proveedor);
    if (tipo === "IN" && transportador.trim()) await asegurarExiste("transportadores", transportador);

    const { error } = await supabase.from("movimientos").insert({
      id, tipo, insumo_id: insumo.id, insumo_nombre: insumo.nombre,
      cantidad: cantNum, unidad: insumo.unidad, fecha, hora: `${hora}:00`,
      lote: tipo === "IN" ? lote : null,
      vencimiento: tipo === "IN" && vencimiento ? vencimiento : null,
      proveedor: tipo === "IN" ? proveedor : null,
      transportador: tipo === "IN" ? transportador : null,
      precio_transporte: tipo === "IN" && precioTransporte ? parseFloat(precioTransporte) : null,
      orden: tipo === "OUT" ? orden : null,
      area: "almacen", registrado_por: userId, notas,
    });

    if (!error) {
      const delta = tipo === "IN" ? cantNum : -Math.min(cantNum, insumo.stock_real);
      await supabase.from("insumos").update({
        stock_real: Math.max(0, insumo.stock_real + delta),
        stock_sistema: Math.max(0, insumo.stock_sistema + delta),
        ultimo_movimiento: fecha,
      }).eq("id", insumo.id);
    }

    setGuardando(false);
    if (error) { alert("No se pudo registrar: " + error.message); return; }
    setOkMsg(`Movimiento ${id} registrado correctamente.`);
    limpiar();
    cargar();
  }

  return (
    <div className="max-w-5xl grid md:grid-cols-[1.3fr_1fr] gap-5 items-start">
      <Card>
        <div className="flex items-center justify-between mb-3">
          <SectionTitle title="Registrar Movimiento" sub="Fecha, hora y folio se completan automáticamente" />
          <span className="font-mono text-[11px] text-brand-slate bg-brand-bg px-2.5 py-1 rounded-lg">{idSugerido}</span>
        </div>

        <div className="grid grid-cols-3 gap-2 mb-4">
          {[["IN", "Entrada"], ["OUT", "Salida"], ["TRF", "Transferencia"]].map(([k, l]) => (
            <button key={k} onClick={() => setTipo(k as any)} className={`py-2.5 rounded-xl border text-[12.5px] font-bold ${tipo === k ? "border-accent bg-accent-bg text-accent-dark" : "border-brand-border text-brand-muted"}`}>
              {l}
            </button>
          ))}
        </div>

        <div className="space-y-3.5">
          <Field label="Insumo"><InsumoSelect insumos={insumos} value={insumo} onChange={setInsumo} /></Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label={`Cantidad ${insumo ? `(${insumo.unidad})` : ""}`}><input type="number" className={inputCls} value={cantidad} onChange={(e) => setCantidad(e.target.value)} /></Field>
            <Field label="Stock disponible">
              <div className="bg-brand-bg border border-brand-border rounded-lg px-3 py-2.5 text-sm text-brand-muted">{insumo ? `${insumo.stock_real.toLocaleString()} ${insumo.unidad}` : "—"}</div>
            </Field>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Fecha (automática)"><input type="date" className={inputCls} value={fecha} onChange={(e) => setFecha(e.target.value)} /></Field>
            <Field label="Hora (automática)"><input type="time" className={inputCls} value={hora} onChange={(e) => setHora(e.target.value)} /></Field>
          </div>

          {tipo === "IN" && (
            <>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Proveedor" hint="Autocompleta con el habitual; si es nuevo, se guarda solo">
                  <ComboboxCreatable table="proveedores" value={proveedor} onChange={setProveedor} placeholder="Buscar o escribir proveedor…" />
                </Field>
                <Field label="N° de lote (sugerido)"><input className={`${inputCls} font-mono`} value={lote} onChange={(e) => setLote(e.target.value)} /></Field>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Fecha de vencimiento del lote"><input type="date" className={inputCls} value={vencimiento} onChange={(e) => setVencimiento(e.target.value)} /></Field>
                <Field label="Transportador" hint="Igual que proveedor: busca o crea uno nuevo">
                  <ComboboxCreatable table="transportadores" value={transportador} onChange={setTransportador} placeholder="Buscar o escribir transportador…" />
                </Field>
              </div>
              <Field label="Precio de transporte (Bs.)" hint="Dato libre, cualquier valor"><input type="number" className={inputCls} value={precioTransporte} onChange={(e) => setPrecioTransporte(e.target.value)} /></Field>
            </>
          )}

          {tipo === "OUT" && (
            <Field label="Orden / lote de producción"><input className={inputCls} value={orden} onChange={(e) => setOrden(e.target.value)} placeholder="Ej. OP-0457" /></Field>
          )}

          <Field label="Notas / referencia"><textarea className={inputCls} rows={2} value={notas} onChange={(e) => setNotas(e.target.value)} /></Field>

          {stockInsuficiente && (
            <div className="bg-bad-bg border border-bad/20 rounded-lg p-3 text-[12.5px] text-bad">
              Stock insuficiente: disponible {insumo!.stock_real.toLocaleString()} {insumo!.unidad}, solicitado {cantNum.toLocaleString()} {insumo!.unidad}.
            </div>
          )}
          {okMsg && <div className="bg-good-bg text-good text-[12.5px] font-semibold rounded-lg px-3 py-2">{okMsg}</div>}

          <div className="flex gap-2 pt-1">
            <GhostButton onClick={limpiar}>Limpiar</GhostButton>
            <PrimaryButton className="flex-1" onClick={registrar} disabled={!insumo || cantNum <= 0 || !!stockInsuficiente || guardando}>
              {guardando ? "Registrando…" : "Registrar Movimiento"}
            </PrimaryButton>
          </div>
        </div>
      </Card>

      <Card>
        <SectionTitle title="Actividad reciente" />
        <div className="divide-y divide-brand-border">
          {recientes.map((m) => (
            <div key={m.id} className="py-2.5 flex items-center gap-2.5">
              <span>{m.tipo === "IN" ? "🟢" : m.tipo === "OUT" ? "🔴" : "🔁"}</span>
              <div className="min-w-0 flex-1">
                <div className="text-[12.5px] font-bold truncate">{m.insumo_nombre}</div>
                <div className="text-[11px] text-brand-slate font-mono">{m.id} · {m.fecha} {m.hora?.slice(0, 5)}</div>
              </div>
              <span className="font-mono text-[12px] font-bold">{m.tipo === "IN" ? "+" : "−"} {m.cantidad.toLocaleString()} {m.unidad}</span>
            </div>
          ))}
          {recientes.length === 0 && <p className="text-brand-muted text-[12.5px] py-3">Sin movimientos todavía.</p>}
        </div>
      </Card>
    </div>
  );
}
