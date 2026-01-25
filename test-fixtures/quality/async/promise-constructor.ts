// TEST FILE: Contains Promise constructor anti-patterns
// Should trigger async pattern detection

// Anti-pattern: async executor in Promise constructor
function fetchWithTimeout(url: string, timeout: number): Promise<Response> {
  return new Promise(async (resolve, reject) => {
    // BAD: async inside Promise constructor
    try {
      const response = await fetch(url);
      resolve(response);
    } catch (error) {
      reject(error);
    }
  });
}

// Anti-pattern: Wrapping already-async function in Promise
async function getData(): Promise<string> {
  return "data";
}

function wrappedGetData(): Promise<string> {
  return new Promise(async (resolve, reject) => {
    try {
      const data = await getData();
      resolve(data);
    } catch (e) {
      reject(e);
    }
  });
}

// Anti-pattern: Unnecessary Promise wrapper
function unnecessaryWrapper(value: number): Promise<number> {
  return new Promise((resolve) => {
    resolve(value * 2); // Could just return Promise.resolve(value * 2)
  });
}

// Sequential awaits that could be parallel
async function loadUserProfile(userId: string): Promise<{
  user: unknown;
  posts: unknown;
  followers: unknown;
}> {
  // BAD: Sequential when they could be parallel
  const user = await fetchUser(userId);
  const posts = await fetchPosts(userId);
  const followers = await fetchFollowers(userId);

  return { user, posts, followers };
}

// Unnecessary async (doesn't await anything)
async function calculateSum(a: number, b: number): Promise<number> {
  // This function doesn't need to be async
  return a + b;
}

// Missing error propagation
async function processWithBadErrorHandling(): Promise<string> {
  try {
    return await riskyOperation();
  } catch (error) {
    console.log("Error occurred");
    // BAD: Doesn't rethrow or return error state
    return "default";
  }
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
async function riskyOperation(): Promise<string> {
  return "result";
}

export {
  fetchWithTimeout,
  wrappedGetData,
  unnecessaryWrapper,
  loadUserProfile,
  calculateSum,
  processWithBadErrorHandling,
};
