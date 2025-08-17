type Rounding = "nearest" | "floor" | "ceil";

export const PRICE_DECIMALS = 12; // see: IETHRegistrar.sol
export const SEC_PER_YEAR = 31_557_600n; // exact (365.25 * 86400)

function divRound(n: bigint, d: bigint, mode: Rounding): bigint {
  if (mode === "floor") return n / d;
  if (mode === "ceil") return (n + d - 1n) / d;
  // nearest, half-up (inputs assumed non-negative)
  return (n + d / 2n) / d;
}

// examples of valid inputs: "12", "12.3", "12.345678901"
export function rateFromAnnualPrice(
  pricePerYear: string,
  rounding: Rounding = "ceil",
) {
  if (!/^\d+(\.\d+)?$/.test(pricePerYear)) throw new Error("expected price");
  const [i, f = ""] = pricePerYear.split(".");
  const decimals = f.slice(0, PRICE_DECIMALS).padStart(PRICE_DECIMALS, "0");
  const perYear = BigInt(i) * 10n ** BigInt(PRICE_DECIMALS) + BigInt(decimals);
  return divRound(perYear, SEC_PER_YEAR, rounding);
}

function formatFixed(n: bigint, decimals: number): string {
  if (decimals === 0) return n.toString();
  const base = 10n ** BigInt(decimals);
  const i = n / base;
  const f = (n % base).toString().padStart(decimals, "0");
  return `${i}.${f}`;
}

export function formatAnnualPriceFromRate(
  rate: bigint,
  decimals = PRICE_DECIMALS,
  rounding: Rounding = "nearest",
): string {
  if (decimals < 0 || !Number.isInteger(decimals)) {
    throw new Error(`invalid decimals: ${decimals}`);
  }
  const perYear = rate * SEC_PER_YEAR;
  const diff = BigInt(PRICE_DECIMALS - decimals);
  const scaled =
    diff > 0
      ? divRound(perYear, 10n ** diff, rounding)
      : perYear * 10n ** -diff;
  return formatFixed(scaled, decimals);
}
