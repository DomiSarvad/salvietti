"use client";
import { useEffect, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

/**
 * Campo de "proveedor" o "transportador": busca coincidencias en la
 * tabla indicada mientras se escribe; si el usuario elige uno existente
 * lo usa tal cual, y si escribe uno que no está, lo guarda en la base
 * (sin pedir ningún dato extra) apenas se confirma el formulario, para
 * que la próxima vez ya aparezca en el autocompletado.
 */
export default function ComboboxCreatable({
  table, // 'proveedores' | 'transportadores'
  value,
  onChange,
  placeholder,
}: {
  table: "proveedores" | "transportadores";
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  const supabase = supabaseBrowser();
  const [open, setOpen] = useState(false);
  const [opciones, setOpciones] = useState<string[]>([]);
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClickOutside(e: MouseEvent) {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, []);

  useEffect(() => {
    let activo = true;
    supabase
      .from(table)
      .select("nombre")
      .ilike("nombre", `%${value ?? ""}%`)
      .order("nombre")
      .limit(20)
      .then(({ data }) => {
        if (activo) setOpciones((data ?? []).map((d: any) => d.nombre));
      });
    return () => {
      activo = false;
    };
  }, [value, table]); // eslint-disable-line

  const yaExiste = opciones.some((o) => o.toLowerCase() === (value ?? "").trim().toLowerCase());

  return (
    <div className="relative" ref={boxRef}>
      <input
        className="w-full border border-brand-border rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent-bg focus:border-accent"
        value={value}
        placeholder={placeholder}
        onFocus={() => setOpen(true)}
        onChange={(e) => {
          onChange(e.target.value);
          setOpen(true);
        }}
      />
      {open && (opciones.length > 0 || value.trim()) && (
        <div className="absolute z-20 mt-1 w-full bg-white border border-brand-border rounded-lg shadow-lg max-h-56 overflow-y-auto">
          {opciones.map((o) => (
            <button
              type="button"
              key={o}
              onClick={() => {
                onChange(o);
                setOpen(false);
              }}
              className="w-full text-left px-3 py-2 text-sm hover:bg-brand-bg"
            >
              {o}
            </button>
          ))}
          {value.trim() && !yaExiste && (
            <div className="px-3 py-2 text-[12px] text-accent-dark bg-accent-bg border-t border-brand-border">
              + Se guardará "{value.trim()}" como nuevo registro al confirmar
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** Inserta el valor en la tabla de lookup si todavía no existe (idempotente). */
export async function asegurarExiste(table: "proveedores" | "transportadores", nombre: string) {
  const n = nombre.trim();
  if (!n) return;
  const supabase = supabaseBrowser();
  await supabase.from(table).upsert({ nombre: n }, { onConflict: "nombre" });
}
