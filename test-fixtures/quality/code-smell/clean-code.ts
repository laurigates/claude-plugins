// TEST FILE: Well-structured clean code
// Should NOT trigger code smell detection

// Constants instead of magic numbers
const SHIPPING_WEIGHT_THRESHOLD_HEAVY = 50;
const SHIPPING_WEIGHT_THRESHOLD_MEDIUM = 20;
const SHIPPING_COST_HEAVY = 25.99;
const SHIPPING_COST_MEDIUM = 12.50;
const SHIPPING_COST_LIGHT = 5.99;
const FREE_SHIPPING_THRESHOLD = 100;

interface ShippingItem {
  weight: number;
}

// Single responsibility: only calculates shipping for one item
function calculateItemShipping(weight: number): number {
  if (weight > SHIPPING_WEIGHT_THRESHOLD_HEAVY) {
    return SHIPPING_COST_HEAVY;
  }
  if (weight > SHIPPING_WEIGHT_THRESHOLD_MEDIUM) {
    return SHIPPING_COST_MEDIUM;
  }
  return SHIPPING_COST_LIGHT;
}

// Composes smaller functions
export function calculateTotalShipping(items: ShippingItem[]): number {
  const total = items.reduce(
    (sum, item) => sum + calculateItemShipping(item.weight),
    0
  );

  return total > FREE_SHIPPING_THRESHOLD ? 0 : total;
}

// Proper error handling
export async function fetchData<T>(url: string): Promise<T> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }

  return response.json() as Promise<T>;
}

// Early returns instead of deep nesting
export function validateUser(user: {
  id?: number;
  email?: string;
  role?: string;
}): { valid: boolean; error?: string } {
  if (!user.id) {
    return { valid: false, error: "User ID is required" };
  }

  if (!user.email?.includes("@")) {
    return { valid: false, error: "Valid email is required" };
  }

  if (!user.role) {
    return { valid: false, error: "Role is required" };
  }

  return { valid: true };
}
