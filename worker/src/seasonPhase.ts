// Per-league season-lifecycle flag (close season vs rollover prep vs live),
// distinct from the deploy-outage "maintenance mode" concept — see
// docs/season-phase.md. Stored as a single KV string per league Worker, so no
// cross-league coordination is needed (each league has its own KV namespace).

export type SeasonPhase = "live" | "closed" | "rollover";

const PHASE_KEY = "season:phase";

/** Defaults to "live" (today's behaviour) when unset — ships inert. */
export async function getSeasonPhase(kv: KVNamespace): Promise<SeasonPhase> {
  const v = await kv.get(PHASE_KEY);
  return v === "closed" || v === "rollover" ? v : "live";
}

export async function setSeasonPhase(kv: KVNamespace, phase: SeasonPhase): Promise<void> {
  await kv.put(PHASE_KEY, phase);
}
