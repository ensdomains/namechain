type Rounding = "nearest" | "floor" | "ceil";

export const PRICE_DECIMALS = 12; // see: IETHRegistrar.sol
const SECONDS_PER_YEAR = 31_557_600n; // exact (365.25 * 86400)

function divRound(n: bigint, d: bigint, mode: Rounding): bigint {
  if (mode === "floor") return n / d;
  if (mode === "ceil") return (n + d - 1n) / d;
  // nearest, half-up (inputs assumed non-negative)
  return (n + d / 2n) / d;
}

/**
 * exact: dollars/year (string, up to 9 decimal places) -> nd/s (bigint)
 * examples of valid inputs: "12", "12.3", "12.345678901"
 */
export function rateFromAnnualPrice(
  pricePerYear: string,
  rounding: Rounding = "ceil",
) {
  if (!/^\d+(\.\d+)?$/.test(pricePerYear)) throw new Error("expected price");
  const [dollars, fracRaw = ""] = pricePerYear.split(".");
  if (fracRaw.length > PRICE_DECIMALS) throw new Error("too many decimals");
  const frac = fracRaw.slice(0, PRICE_DECIMALS).padStart(PRICE_DECIMALS, "0");
  const ndPerYear = BigInt(dollars) * 10n ** BigInt(PRICE_DECIMALS) + BigInt(frac);
  return divRound(ndPerYear, SECONDS_PER_YEAR, rounding);
}

function formatFixed(n: bigint, decimals: number): string {
  if (decimals === 0) return n.toString();
  const base = 10n ** BigInt(decimals);
  const i = n / base;
  const f = (n % base).toString().padStart(decimals, "0");
  return `${i}.${f}`;
}

export function formatRateAsAnnualPrice(
  rate: bigint,
  decimals = PRICE_DECIMALS,
  rounding: Rounding = "nearest",
): string {
  if (decimals < 0 || decimals > PRICE_DECIMALS) {
    throw new Error(`decimals must be 0..${PRICE_DECIMALS}`);
  }
  const perYear = rate * SECONDS_PER_YEAR;
  const divisor = 10n ** BigInt(PRICE_DECIMALS - decimals);
  const scaled = divRound(perYear, divisor, rounding);
  return formatFixed(scaled, decimals);
}
