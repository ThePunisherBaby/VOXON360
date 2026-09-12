// Los planes vienen de shared/plans.json, que también lee la app.
// El script `prebuild` copia ese archivo aquí antes de compilar.
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
  name: string;
  priceMode: "tax_included" | "tax_excluded";
  legalTip: boolean;
}

interface Plans {
  currency: string;
  trialDays: number;
  features: Record<string, string>;
  tiers: Record<Tier, TierConfig>;
  modes: Record<string, ModeConfig>;
}

export const plans = plansJson as unknown as Plans;

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

/** En los topes, 0 significa "sin tope". */
export function withinLimit(used: number, limit: number): boolean {
  return limit === 0 || used <= limit;
}

export function modeConfig(mode: string): ModeConfig | undefined {
  return plans.modes[mode];
}
