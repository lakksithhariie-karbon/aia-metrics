/** Shared Bill Extraction money formatter. USD is a display convention requested
 * by the product owner; source currency verification is a separate dependency.
 * Never apply FX conversion or invent missing numeric values. */
export function formatRecordedCost(value: number | null, currency: "unverified" | "USD", digits = 2): string {
  if (value === null || !Number.isFinite(value)) return "Unknown";
  if (currency === "USD") {
    return new Intl.NumberFormat("en-US",{
      style:"currency",currency:"USD",minimumFractionDigits:digits,maximumFractionDigits:digits,
    }).format(value);
  }
  return new Intl.NumberFormat("en-US",{
    minimumFractionDigits:digits,maximumFractionDigits:digits,
  }).format(value) + " units";
}
