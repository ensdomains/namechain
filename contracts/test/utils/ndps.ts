type Rounding = "nearest" | "floor" | "ceil";

const SECONDS_PER_YEAR_BI = 31_557_600n; // exact (365.25 * 86400)
const ND_PER_DOLLAR_BI = 1_000_000_000n; // nanodollars per dollar

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
export function dollarsPerYearToNdpsExact(
  dollarsPerYear: string,
  rounding: Rounding = "nearest",
): bigint {
  const s = dollarsPerYear.trim();
  if (!/^\d+(\.\d{0,9})?$/.test(s)) {
    throw new Error("use dollars with up to 9 decimal places");
  }
  const [dollars, fracRaw = ""] = s.split(".");
  const frac = (fracRaw + "000000000").slice(0, 9); // pad to 9 places
  const ndPerYear = BigInt(dollars) * ND_PER_DOLLAR_BI + BigInt(frac); // already nanodollars

  return divRound(ndPerYear, SECONDS_PER_YEAR_BI, rounding);
}

const POW10N: readonly bigint[] = [
  1n,
  10n,
  100n,
  1_000n,
  10_000n,
  100_000n,
  1_000_000n,
  10_000_000n,
  100_000_000n,
  1_000_000_000n,
];

function formatFixed(n: bigint, decimals: number): string {
  if (decimals === 0) return n.toString();
  const base = POW10N[decimals];
  const i = n / base;
  const f = (n % base).toString().padStart(decimals, "0");
  return `${i}.${f}`;
}

/**
 * exact: nd/s (bigint) -> $/yr as a decimal string with `decimals` places (0..9)
 * default 9 decimals gives the exact dollar value since inputs are in nanodollars.
 */
export function ndpsToDollarsPerYearStringExact(
  ndps: bigint,
  decimals: number = 9,
  rounding: Rounding = "nearest",
): string {
  if (decimals < 0 || decimals > 9) throw new Error("decimals must be 0..9");
  const ndPerYear = ndps * SECONDS_PER_YEAR_BI; // nanodollars/year (exact)
  const scaleDown = 9 - decimals; // convert nd -> dollars with N decimals
  const divisor = POW10N[scaleDown];
  const scaled = divRound(ndPerYear, divisor, rounding); // integer of dollars * 10^decimals
  return formatFixed(scaled, decimals);
}
