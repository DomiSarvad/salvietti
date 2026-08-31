"use client";
import { estadoDe } from "@/lib/types";

export function Card({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <div className={`bg-brand-card border border-brand-border rounded-xl2 p-5 ${className}`}>{children}</div>;
}

export function SectionTitle({ title, sub }: { title: string; sub?: string }) {
  return (
    <div className="mb-3">
      <div className="font-extrabold text-[14.5px]">{title}</div>
      {sub && <div className="text-[12px] text-brand-muted mt-0.5">{sub}</div>}
    </div>
  );
}

export function StatCard({ icon, label, value, sub, color }: { icon: string; label: string; value: string | number; sub?: string; color: string }) {
  return (
    <div className="bg-brand-card border border-brand-border rounded-xl2 p-4">
      <div className="flex items-center justify-between">
        <span className="text-[11px] font-bold text-brand-muted uppercase tracking-wide">{label}</span>
        <span className="w-7 h-7 rounded-lg flex items-center justify-center text-sm" style={{ background: color + "22" }}>{icon}</span>
      </div>
      <div className="text-2xl font-extrabold mt-2">{value}</div>
      {sub && <div className="text-[11.5px] text-brand-muted mt-1">{sub}</div>}
    </div>
  );
}

export function EstadoBadge({ dias, critico, bajo }: { dias: number | null; critico: number; bajo: number }) {
  const e = estadoDe(dias, critico, bajo);
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11.5px] font-bold ${e.bg} ${e.color}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${e.dot}`} />
      {e.label}
    </span>
  );
}

export function GaugeBar({ dias, critico, bajo, cap = 30 }: { dias: number | null; critico: number; bajo: number; cap?: number }) {
  if (dias === null) return <span className="font-mono text-brand-slate text-[13px]">—</span>;
  const pct = Math.max(4, Math.min(100, (dias / cap) * 100));
  const e = estadoDe(dias, critico, bajo);
  const barColor = e.label === "Crítico" ? "bg-bad" : e.label === "Bajo" ? "bg-warn" : "bg-good";
  return (
    <div className="flex items-center gap-2 min-w-[110px]">
      <div className="flex-1 h-1.5 bg-[#EDEEF3] rounded-full overflow-hidden">
        <div className={`h-full ${barColor} rounded-full`} style={{ width: `${pct}%` }} />
      </div>
      <span className={`font-mono text-[12px] font-semibold w-10 text-right ${e.color}`}>{dias}d</span>
    </div>
  );
}

export function Chip({ children, active, onClick, danger }: { children: React.ReactNode; active: boolean; onClick: () => void; danger?: boolean }) {
  return (
    <button
      onClick={onClick}
      className={`px-3.5 py-1.5 rounded-full text-[12.3px] font-bold border whitespace-nowrap transition
        ${active ? (danger ? "bg-bad-bg text-bad border-bad" : "bg-navy text-white border-navy") : "bg-white text-brand-muted border-brand-border"}`}
    >
      {children}
    </button>
  );
}

export function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="text-[12.5px] font-bold text-brand-text">{label}</span>
      <div className="mt-1.5">{children}</div>
      {hint && <span className="text-[11px] text-brand-slate mt-1 block">{hint}</span>}
    </label>
  );
}

export const inputCls =
  "w-full border border-brand-border rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent-bg focus:border-accent bg-white";

export function PrimaryButton(props: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  const { className = "", ...rest } = props;
  return (
    <button
      {...rest}
      className={`bg-accent hover:bg-accent-dark disabled:opacity-40 text-white font-bold text-[13px] px-4 py-2.5 rounded-lg transition ${className}`}
    />
  );
}
export function GhostButton(props: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  const { className = "", ...rest } = props;
  return (
    <button
      {...rest}
      className={`border border-brand-border bg-white hover:bg-brand-bg text-brand-text font-semibold text-[13px] px-4 py-2.5 rounded-lg transition ${className}`}
    />
  );
}
