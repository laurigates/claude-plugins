// TEST FILE: Properly handled async patterns
// Should NOT trigger async pattern detection

// Proper error handling with try-catch
async function fetchData(url: string): Promise<Response> {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    return response;
  } catch (error) {
    console.error("Fetch failed:", error);
    throw error; // Re-throw for caller to handle
  }
}

// Proper Promise.all with error handling
async function loadAllData(): Promise<{
  users: unknown;
  posts: unknown;
}> {
  try {
    const [users, posts] = await Promise.all([
      fetch("/api/users").then((r) => r.json()),
      fetch("/api/posts").then((r) => r.json()),
    ]);
    return { users, posts };
  } catch (error) {
    console.error("Failed to load data:", error);
    throw new Error("Data loading failed", { cause: error });
  }
}

// Parallel fetches with Promise.all (not sequential)
async function loadUserProfile(userId: string): Promise<{
  user: unknown;
  posts: unknown[];
  followers: unknown[];
}> {
  const [user, posts, followers] = await Promise.all([
    fetchUser(userId),
    fetchPosts(userId),
    fetchFollowers(userId),
  ]);

  return { user, posts, followers };
}

// Intentional fire-and-forget with void operator
function trackAnalytics(event: string): void {
  void logEvent(event); // Explicit fire-and-forget
}

// Proper Promise chain with catch
function fetchUserDataChained(userId: string): Promise<void> {
  return fetch(`/api/users/${userId}`)
    .then((response) => response.json())
    .then((data) => displayUser(data))
    .catch((error) => {
      console.error("Failed to fetch user:", error);
      displayError(error);
    });
}

// Proper finally for cleanup
async function withCleanup(): Promise<void> {
  const resource = await acquireResource();
  try {
    await useResource(resource);
  } finally {
    await releaseResource(resource);
  }
}

// Type-safe error handling
class FetchError extends Error {
  constructor(
    message: string,
    public readonly status: number
  ) {
    super(message);
    this.name = "FetchError";
  }
}

async function safeFetch(url: string): Promise<unknown> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new FetchError(`Request failed`, response.status);
  }
  return response.json();
}

// Mock functions
async function fetchUser(id: string): Promise<unknown> {
  return { id };
}
async function fetchPosts(id: string): Promise<unknown[]> {
  return [];
}
async function fetchFollowers(id: string): Promise<unknown[]> {
  return [];
}
async function logEvent(event: string): Promise<void> {
  console.log(event);
}
function displayUser(data: unknown): void {
  console.log(data);
}
function displayError(error: unknown): void {
  console.error(error);
}
async function acquireResource(): Promise<unknown> {
  return {};
}
async function useResource(resource: unknown): Promise<void> {
  console.log(resource);
}
async function releaseResource(resource: unknown): Promise<void> {
  console.log(resource);
}

export {
  fetchData,
  loadAllData,
  loadUserProfile,
  trackAnalytics,
  fetchUserDataChained,
  withCleanup,
  safeFetch,
};
