'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';

/** Envuelve cualquier página que requiera sesión iniciada. */
export default function Protected({ children }: { children: React.ReactNode }) {
  const { loading, userId } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !userId) router.replace('/login');
  }, [loading, userId, router]);

  if (loading || !userId) {
    return (
      <div className="h-screen flex items-center justify-center bg-brand-bg">
        <div className="text-brand-muted text-sm">Cargando...</div>
      </div>
    );
  }
  return <>{children}</>;
}
