"use client";
import { createContext, useContext, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "./supabase/client";
import type { Profile } from "./types";

interface AuthCtx {
  loading: boolean;
  userId: string | null;
  profile: Profile | null;
  refreshProfile: () => Promise<void>;
  signOut: () => Promise<void>;
}

const Ctx = createContext<AuthCtx>({
  loading: true,
  userId: null,
  profile: null,
  refreshProfile: async () => {},
  signOut: async () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const supabase = supabaseBrowser();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [userId, setUserId] = useState<string | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);

  async function loadProfile(uid: string) {
    const { data } = await supabase.from("profiles").select("*").eq("id", uid).single();
    setProfile(data as Profile | null);
  }

  async function refreshProfile() {
    if (userId) await loadProfile(userId);
  }

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      const uid = data.session?.user.id ?? null;
      setUserId(uid);
      if (uid) await loadProfile(uid);
      setLoading(false);
    });

    const { data: sub } = supabase.auth.onAuthStateChange(async (_event, session) => {
      const uid = session?.user.id ?? null;
      setUserId(uid);
      if (uid) {
        await loadProfile(uid);
      } else {
        setProfile(null);
        router.push("/login");
      }
    });
    return () => sub.subscription.unsubscribe();
  }, []); // eslint-disable-line

  async function signOut() {
    await supabase.auth.signOut();
    router.push("/login");
  }

  return (
    <Ctx.Provider value={{ loading, userId, profile, refreshProfile, signOut }}>
      {children}
    </Ctx.Provider>
  );
}

export function useAuth() {
  return useContext(Ctx);
}
