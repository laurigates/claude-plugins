// TEST FILE: Contains non-null assertions without guards
// Should trigger TypeScript strictness detection

interface User {
  id: number;
  name: string;
  email?: string;
  profile?: {
    bio?: string;
    avatar?: string;
  };
}

// Non-null assertion on optional property
function getUserEmail(user: User): string {
  return user.email!; // Dangerous: email might be undefined
}

// Non-null assertion on nested optional
function getUserBio(user: User): string {
  return user.profile!.bio!; // Double dangerous
}

// Non-null assertion on array access
function getFirstItem<T>(items: T[]): T {
  return items[0]!; // Dangerous: array might be empty
}

// Non-null assertion on DOM query
function getElement(): HTMLElement {
  return document.getElementById("app")!; // Might not exist
}

// Multiple assertions in chain
function processConfig(config: { data?: { items?: string[] } }) {
  const firstItem = config.data!.items![0]!;
  return firstItem.toUpperCase();
}

// Type assertions that could be type guards
function isString(value: unknown): value is string {
  return typeof value === "string";
}

function processValue(value: unknown) {
  // Using assertion instead of type guard
  const str = value as string;
  return str.toUpperCase();
}

// Better: Using type guard (for comparison)
function processValueSafe(value: unknown) {
  if (typeof value === "string") {
    return value.toUpperCase();
  }
  throw new Error("Expected string");
}

export {
  getUserEmail,
  getUserBio,
  getFirstItem,
  getElement,
  processConfig,
  processValue,
  processValueSafe,
};
