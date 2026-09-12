// Planes y modos vienen de shared/plans.json y shared/modes.json, que también leen las apps.
// El script `prebuild` copia esos archivos aquí antes de compilar.
import modesJson from "./modes.json";
import plansJson from "./plans.json";

export type Tier = "v45" | "v90" | "v180" | "v360";

export interface Limits {
  instances: number;
  users: number;
  products: number;
  devices: number;
}

export interface TierConfig {
  name: string;
  tagline: string;
  priceMonthly: number;
  limits: Limits;
  features: string[];
}

export interface ModeConfig {
  id: string;
  order: number;
  /** priority y ready se pueden elegir; planned todavía no. */
  status: "priority" | "ready" | "planned";
  name: string;
  description: string;
  icon: string;
  color: string;
  priceMode: "tax_included" | "tax_excluded";
  legalTip: boolean;
  modules: string[];
  categories: string[];
  stations?: string[];
}

interface Plans {
  currency: string;
  trialDays: number;
  trialTier: Tier;
  features: Record<string, string>;
  tiers: Record<Tier, TierConfig>;
}

export const plans = plansJson as unknown as Plans;

const modes = (modesJson as unknown as { modes: ModeConfig[] }).modes;

export const tiers = Object.keys(plans.tiers) as Tier[];

export function isTier(value: unknown): value is Tier {
  return typeof value === "string" && (tiers as string[]).includes(value);
}

export function limitsFor(tier: Tier): Limits {
  return plans.tiers[tier].limits;
}

export function featuresFor(tier: Tier): string[] {
  return plans.tiers[tier].features;
}

export function hasFeature(tier: Tier, feature: string): boolean {
  return plans.tiers[tier].features.includes(feature);
}

/** En los topes, 0 significa "sin tope". */
export function withinLimit(used: number, limit: number): boolean {
  return limit === 0 || used <= limit;
}

export function modeConfig(mode: string): ModeConfig | undefined {
  return modes.find((candidate) => candidate.id === mode);
}
