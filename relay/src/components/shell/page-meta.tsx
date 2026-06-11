"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

interface PageMetaState {
  actions: ReactNode | null;
  setActions: (n: ReactNode | null) => void;
}

const Ctx = createContext<PageMetaState | null>(null);

export function PageMetaProvider({ children }: { children: ReactNode }) {
  const [actions, setActions] = useState<ReactNode | null>(null);
  const value = useMemo<PageMetaState>(() => ({ actions, setActions }), [actions]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function usePageActions(): { actions: ReactNode | null } {
  const ctx = useContext(Ctx);
  return { actions: ctx?.actions ?? null };
}

/** Pages call this from a useEffect to register an actions slot in the AppBar. */
export function useSetPageActions(node: ReactNode | null, deps: unknown[] = []): void {
  const ctx = useContext(Ctx);
  useEffect(() => {
    if (!ctx) return;
    ctx.setActions(node);
    return () => ctx.setActions(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
}
