"use client";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useAuth } from "@/lib/auth-context";
import type { Insumo } from "@/lib/types";
import { Card, SectionTitle, Field, inputCls, PrimaryButton, GhostButton } from "@/components/ui";
import InsumoSelect from "@/components/InsumoSelect";

function hoyISO() { return new Date().toISOString().slice(0, 10); }
function horaAhora() { return new Date().toTimeString().slice(0, 5); }

interface SaldoRow { insumo: Insumo; saldo: number; }

export default function JarabesPage() {
  const supabase = supabaseBrowser();
  const { profile, userId } = useAuth();
  const esAlmacen = profile?.rol === "almacen";
  const esJarabes = profile?.rol === "jarabes";

  const [insumos, setInsumos] = useState<Insumo[]>([]);
  const [saldos, setSaldos] = useState<SaldoRow[]>([]);
  const [movs, setMovs] = useState<any[]>([]);

  // Formulario de ASIGNACIÓN (solo Almacén)
  const [asigInsumo, setAsigInsumo] = useState<Insumo | null>(null);
  const [asigCantidad, setAsigCantidad] = useState("");

  // Formulario de CONSUMO (solo Jarabes)
  const [consInsumo, setConsInsumo] = useState<Insumo | null>(null);
  const [consCantidad, setConsCantidad] = useState("");
  const [sabor, setSabor] = useState("");
  const [litros, setLitros] = useState("");
  const [obs, setObs] = useState("");

  const [guardando, setGuardando] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function cargar() {
    const [{ data: ins }, { data: sal }, { data: mv }] = await Promise.all([
      supabase.from("insumos").select("*").order("nombre"),
      supabase.from("jarabes_saldos").select("*"),
      supabase.from("jarabes_movimientos").select("*").order("fecha", { ascending: false }).order("hora", { ascending: false }).limit(15),
    ]);
    const insumosData = (ins ?? []) as Insumo[];
    setInsumos(insumosData);
    const rows: SaldoRow[] = (sal ?? [])
      .map((s: any) => ({ insumo: insumosData.find((i) => i.id === s.insumo_id)!, saldo: s.saldo }))
      .filter((r: SaldoRow) => r.insumo && r.saldo > 0);
    setSaldos(rows);
    setMovs(mv ?? []);
  }
  useEffect(() => { cargar(); }, []); // eslint-disable-line

  async function asignar() {
    if (!asigInsumo || !asigCantidad) return;
    setGuardando(true);
    const { error } = await supabase.from("jarabes_asignaciones").insert({
      insumo_id: asigInsumo.id, cantidad: parseFloat(asigCantidad), fecha: hoyISO(), entregado_por: userId,
    });
    setGuardando(false);
    if (error) { alert(error.message); return; }
    setMsg(`Se entregaron ${asigCantidad} ${asigInsumo.unidad} de ${asigInsumo.nombre} a Jarabes.`);
    setAsigInsumo(null); setAsigCantidad("");
    cargar();
  }

  async function registrarConsumo() {
    if (!consInsumo || !consCantidad) return;
    setGuardando(true);
    const { error } = await supabase.from("jarabes_movimientos").insert({
      insumo_id: consInsumo.id, cantidad_usada: parseFloat(consCantidad),
      sabor_producido: sabor || null, litros_producidos: litros ? parseFloat(litros) : null,
      fecha: hoyISO(), hora: `${horaAhora()}:00`, observaciones: obs || null, registrado_por: userId,
    });
    setGuardando(false);
    if (error) { alert(error.message); return; }
    setMsg("Consumo registrado y descontado de tu saldo.");
    setConsInsumo(null); setConsCantidad(""); setSabor(""); setLitros(""); setObs("");
    cargar();
  }

  return (
    <div className="max-w-4xl space-y-5">
      <div>
        <h1 className="text-lg font-extrabold">Jarabes</h1>
        <p className="text-[12.5px] text-brand-muted mt-0.5">
          Almacén entrega concentrado y azúcar como saldo; Jarabes descuenta de ese saldo
          cada vez que prepara un lote — igual que el cuaderno de papel, pero conectado al sistema.
        </p>
      </div>

      {msg && <div className="bg-good-bg text-good text-[12.5px] font-semibold rounded-lg px-4 py-2.5">{msg}</div>}

      <Card>
        <SectionTitle title="Saldo actual en Jarabes" sub="Lo que Almacén ya entregó y todavía no se ha usado" />
        <div className="divide-y divide-brand-border">
          {saldos.map((s) => (
            <div key={s.insumo.id} className="flex items-center justify-between py-2.5">
              <span className="text-[13px] font-semibold">{s.insumo.nombre}</span>
              <span className="font-mono text-[13px] font-bold text-accent">{s.saldo.toLocaleString()} {s.insumo.unidad}</span>
            </div>
          ))}
          {saldos.length === 0 && <p className="text-brand-muted text-[12.5px] py-3">Sin saldo entregado todavía.</p>}
        </div>
      </Card>

      {esAlmacen && (
        <Card>
          <SectionTitle title="Entregar insumo a Jarabes" />
          <div className="grid md:grid-cols-[1fr_160px_auto] gap-3 items-end">
            <Field label="Insumo"><InsumoSelect insumos={insumos} value={asigInsumo} onChange={setAsigInsumo} /></Field>
            <Field label={`Cantidad ${asigInsumo ? `(${asigInsumo.unidad})` : ""}`}><input type="number" className={inputCls} value={asigCantidad} onChange={(e) => setAsigCantidad(e.target.value)} /></Field>
            <PrimaryButton onClick={asignar} disabled={!asigInsumo || !asigCantidad || guardando}>Entregar</PrimaryButton>
          </div>
        </Card>
      )}

      {esJarabes && (
        <Card>
          <SectionTitle title="Registrar mi consumo" sub="Fecha y hora se completan automáticamente" />
          <div className="space-y-3">
            <Field label="Insumo usado"><InsumoSelect insumos={insumos.filter((i) => saldos.some((s) => s.insumo.id === i.id))} value={consInsumo} onChange={setConsInsumo} /></Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label={`Cantidad usada ${consInsumo ? `(${consInsumo.unidad})` : ""}`}><input type="number" className={inputCls} value={consCantidad} onChange={(e) => setConsCantidad(e.target.value)} /></Field>
              <Field label="Sabor producido"><input className={inputCls} value={sabor} onChange={(e) => setSabor(e.target.value)} placeholder="Ej. Lima Limón" /></Field>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Litros producidos"><input type="number" className={inputCls} value={litros} onChange={(e) => setLitros(e.target.value)} /></Field>
              <Field label="Observaciones"><input className={inputCls} value={obs} onChange={(e) => setObs(e.target.value)} /></Field>
            </div>
            <PrimaryButton className="w-full" onClick={registrarConsumo} disabled={!consInsumo || !consCantidad || guardando}>
              {guardando ? "Guardando…" : "Registrar consumo"}
            </PrimaryButton>
          </div>
        </Card>
      )}

      <Card>
        <SectionTitle title="Historial reciente de Jarabes" />
        <div className="divide-y divide-brand-border">
          {movs.map((m) => {
            const i = insumos.find((x) => x.id === m.insumo_id);
            return (
              <div key={m.id} className="py-2.5 text-[12.5px] flex items-center justify-between gap-2">
                <div>
                  <div className="font-semibold">{i?.nombre ?? "—"} {m.sabor_producido ? `· ${m.sabor_producido}` : ""}</div>
                  <div className="text-brand-slate text-[11px] font-mono">{m.fecha} {m.hora?.slice(0, 5)}</div>
                </div>
                <span className="font-mono font-bold text-bad">− {m.cantidad_usada.toLocaleString()} {i?.unidad}</span>
              </div>
            );
          })}
          {movs.length === 0 && <p className="text-brand-muted text-[12.5px] py-3">Sin registros todavía.</p>}
        </div>
      </Card>
    </div>
  );
}
