import { expect } from "vitest";

// expectVar({ x }) <==> expect(x, 'x')
export function expectVar<T>(obj: Record<string, T>) {
  const [[k, v]] = Object.entries(obj);
  return expect(v, k);
}
