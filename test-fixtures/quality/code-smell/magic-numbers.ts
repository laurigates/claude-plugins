// TEST FILE: Contains magic numbers and magic strings
// Should trigger "Magic Numbers" code smell detection

interface Item {
  price: number;
  quantity: number;
  weight: number;
  category: string;
}

// Magic numbers in conditionals and calculations
export function calculateShipping(items: Item[]): number {
  let total = 0;

  for (const item of items) {
    // Magic number: 50 (weight threshold)
    if (item.weight > 50) {
      total += 25.99; // Magic number: shipping cost
    } else if (item.weight > 20) {
      total += 12.50; // Another magic number
    } else {
      total += 5.99; // Yet another magic number
    }
  }

  // Magic number: 100 (free shipping threshold)
  if (total > 100) {
    return 0;
  }

  return total;
}

// Magic numbers in discount logic
export function applyDiscount(price: number, quantity: number): number {
  // Magic numbers: discount thresholds
  if (quantity >= 100) {
    return price * 0.75; // 25% discount
  } else if (quantity >= 50) {
    return price * 0.85; // 15% discount
  } else if (quantity >= 10) {
    return price * 0.90; // 10% discount
  }
  return price;
}

// Magic strings in category checks
export function getCategoryTax(category: string): number {
  if (category === "electronics") {
    return 0.08;
  } else if (category === "food") {
    return 0.02;
  } else if (category === "luxury") {
    return 0.15;
  }
  return 0.05;
}

// Repeated magic numbers
export function validateOrder(items: Item[]): boolean {
  // 1000 repeated multiple times
  const maxItems = items.length <= 1000;
  const maxWeight = items.reduce((sum, i) => sum + i.weight, 0) <= 1000;
  const maxPrice = items.reduce((sum, i) => sum + i.price, 0) <= 1000;

  return maxItems && maxWeight && maxPrice;
}
