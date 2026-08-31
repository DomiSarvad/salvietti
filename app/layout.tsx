import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AuthProvider } from "@/lib/auth-context";

export const metadata: Metadata = {
  title: "Sistema Salvietti",
  description: "Control de inventario, producción y jarabes — Salvietti",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body className="text-brand-text antialiased">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
