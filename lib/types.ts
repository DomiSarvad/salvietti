export type Rol = "gerente" | "almacen" | "jarabes" | "ingeniero";

export interface Profile {
  id: string;
  nombre: string;
  rol: Rol;
  avatar_url: string | null;
  tema: "claro" | "oscuro";
  activo: boolean;
}

export interface Insumo {
  id: string;
  codigo: string;
  nombre: string;
  categoria: "azucar" | "esencia" | "aditivo" | "envase" | "tapa";
  unidad: string;
  stock_real: number;
  stock_sistema: number;
  consumo_dia: number;
  proveedor: string | null;
  stock_min: number;
  ultimo_movimiento: string | null;
  dias_existencia: number | null;
}

export interface Movimiento {
  id: string;
  tipo: "IN" | "OUT" | "TRF";
  insumo_id: string | null;
  insumo_nombre: string;
  cantidad: number;
  unidad: string;
  fecha: string;
  hora: string;
  lote: string | null;
  vencimiento: string | null;
  proveedor: string | null;
  transportador: string | null;
  precio_transporte: number | null;
  orden: string | null;
  destino: string | null;
  notas: string | null;
  area: "almacen" | "jarabes";
  registrado_por: string | null;
}

export interface ProduccionDiaria {
  id: string;
  fecha: string;
  sabor: string;
  litros_planificados: number;
  estado: "pendiente" | "completado";
  creado_por: string | null;
  completado_por: string | null;
  completado_en: string | null;
}

export interface JarabesSaldo {
  insumo_id: string;
  saldo: number;
}

export const CATEGORIAS = [
  { key: "azucar", label: "Azúcares", prefix: "AZ", color: "#8A5A2B" },
  { key: "esencia", label: "Esencias y Concentrados", prefix: "CN", color: "#2F8F5B" },
  { key: "aditivo", label: "Ácidos y Aditivos", prefix: "AD", color: "#3D6FD8" },
  { key: "envase", label: "Preformas y Envases", prefix: "PT", color: "#8A4FD8" },
  { key: "tapa", label: "Tapas y Cápsulas", prefix: "CP", color: "#C4880C" },
] as const;

export function categoriaInfo(key: string) {
  return CATEGORIAS.find((c) => c.key === key) ?? CATEGORIAS[1];
}

export function diasExistencia(stock: number, consumo: number): number | null {
  if (!consumo || consumo <= 0) return null;
  return Math.round((stock / consumo) * 10) / 10;
}

export function estadoDe(dias: number | null, critico: number, bajo: number) {
  if (dias === null) return { label: "Óptimo", color: "text-good", bg: "bg-good-bg", dot: "bg-good" };
  if (dias < critico) return { label: "Crítico", color: "text-bad", bg: "bg-bad-bg", dot: "bg-bad" };
  if (dias < bajo) return { label: "Bajo", color: "text-warn", bg: "bg-warn-bg", dot: "bg-warn" };
  return { label: "Óptimo", color: "text-good", bg: "bg-good-bg", dot: "bg-good" };
}

/** Etiquetas de permisos por rol — referencia única usada en toda la app. */
export const PERMISOS: Record<Rol, { editarAlmacen: boolean; editarJarabes: boolean; verTodo: boolean; administrarUsuarios: boolean; crearProduccion: boolean }> = {
  gerente:   { editarAlmacen: false, editarJarabes: false, verTodo: true,  administrarUsuarios: true,  crearProduccion: false },
  almacen:   { editarAlmacen: true,  editarJarabes: true,  verTodo: true,  administrarUsuarios: false, crearProduccion: true  },
  jarabes:   { editarAlmacen: false, editarJarabes: true,  verTodo: false, administrarUsuarios: false, crearProduccion: false },
  ingeniero: { editarAlmacen: false, editarJarabes: false, verTodo: true,  administrarUsuarios: false, crearProduccion: true  },
};
