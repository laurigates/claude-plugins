// TEST FILE: Properly typed TypeScript code
// Should NOT trigger TypeScript strictness detection

interface User {
  id: number;
  name: string;
  email?: string;
  profile?: UserProfile;
}

interface UserProfile {
  bio?: string;
  avatar?: string;
}

// Proper optional chaining instead of non-null assertion
function getUserEmail(user: User): string | undefined {
  return user.email;
}

// Type guard for safe access
function getUserBio(user: User): string {
  if (user.profile?.bio) {
    return user.profile.bio;
  }
  return "No bio available";
}

// Safe array access with bounds check
function getFirstItem<T>(items: T[]): T | undefined {
  return items.length > 0 ? items[0] : undefined;
}

// Null check for DOM element
function getElement(): HTMLElement | null {
  return document.getElementById("app");
}

// Proper type guard
function isString(value: unknown): value is string {
  return typeof value === "string";
}

// Using type guard properly
function processValue(value: unknown): string {
  if (isString(value)) {
    return value.toUpperCase();
  }
  throw new Error("Expected string");
}

// Explicit return types on exports
export function calculateTotal(items: number[]): number {
  return items.reduce((sum, item) => sum + item, 0);
}

// Typed callback parameters
export function mapItems<T, U>(
  items: T[],
  transform: (item: T, index: number) => U
): U[] {
  return items.map(transform);
}

// Properly typed class
export class UserService {
  private users: Map<number, User> = new Map();

  public getUser(id: number): User | undefined {
    return this.users.get(id);
  }

  public async fetchUser(id: number): Promise<User> {
    const response = await fetch(`/api/users/${id}`);
    if (!response.ok) {
      throw new Error(`Failed to fetch user: ${response.statusText}`);
    }
    return response.json() as Promise<User>;
  }
}

export {
  getUserEmail,
  getUserBio,
  getFirstItem,
  getElement,
  isString,
  processValue,
};
