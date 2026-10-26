// Cambodian phone numbers (+855). Accepts what people type: "012 345 678",
// "12345678", "+855 12 345 678", "855-12-345-678". Returns E.164 or null.
export function normalizeKhPhone(input: string): string | null {
  let digits = input.replace(/[\s\-().]/g, "");
  if (digits.startsWith("+")) digits = digits.slice(1);
  if (!/^\d+$/.test(digits)) return null;
  if (digits.startsWith("855")) digits = digits.slice(3);
  if (digits.startsWith("0")) digits = digits.slice(1);
  // Mobile numbers are 8 or 9 digits after the country code, never 0-led.
  if (!/^[1-9]\d{7,8}$/.test(digits)) return null;
  return `+855${digits}`;
}

export function normalizeEmail(input: string): string | null {
  const email = input.trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}
