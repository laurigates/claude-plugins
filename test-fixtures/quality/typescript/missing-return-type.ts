// TEST FILE: Contains functions with missing return types
// Should trigger TypeScript strictness detection

// Exported function without return type
export function calculateTotal(items: number[]) {
  return items.reduce((sum, item) => sum + item, 0);
}

// Public class method without return type
export class UserService {
  private users: Map<number, { name: string }> = new Map();

  // Missing return type on public method
  getUser(id: number) {
    return this.users.get(id);
  }

  // Missing return type on async method
  async fetchUser(id: number) {
    const response = await fetch(`/api/users/${id}`);
    return response.json();
  }

  // Callback without parameter types
  processUsers(callback) {
    return Array.from(this.users.values()).map(callback);
  }
}

// Arrow function without type annotation
export const multiply = (a: number, b: number) => a * b;

// Higher order function with untyped callback
export function mapItems(items: string[], transform) {
  return items.map(transform);
}

// Event handler without parameter type
export function setupHandler(element: HTMLElement) {
  element.addEventListener("click", (e) => {
    console.log(e.target);
  });
}

// Generic function with implicit return
export function first<T>(items: T[]) {
  return items[0];
}

// Function expression without type
export const formatDate = function (date: Date) {
  return date.toISOString();
};
