// TEST FILE: Contains floating promises and unhandled rejections
// Should trigger async pattern detection

// Floating promise - not awaited, not stored, not chained
async function fetchData(url: string): Promise<Response> {
  return fetch(url);
}

function processRequest() {
  fetchData("/api/data"); // FLOATING: Promise is ignored
  return "done";
}

// Fire and forget without void
async function logAnalytics(event: string): Promise<void> {
  await fetch("/api/analytics", {
    method: "POST",
    body: JSON.stringify({ event }),
  });
}

function trackClick() {
  logAnalytics("click"); // FLOATING: Should use void if intentional
  updateUI();
}

// Multiple floating promises
async function syncData(): Promise<void> {
  await fetchData("/sync");
}

function initializeApp() {
  syncData(); // Floating
  fetchData("/config"); // Floating
  loadUser(); // Floating
  console.log("App started"); // Runs before async completes
}

// Promise in loop without await
async function processItems(items: string[]): Promise<void> {
  for (const item of items) {
    processItem(item); // Each promise floats
  }
}

// Conditional floating promise
function maybeSync(shouldSync: boolean) {
  if (shouldSync) {
    syncData(); // Floating in conditional
  }
}

// Async functions (mock implementations)
async function loadUser(): Promise<{ id: number }> {
  return { id: 1 };
}

async function processItem(item: string): Promise<void> {
  console.log(item);
}

function updateUI(): void {
  // UI update
}

export {
  processRequest,
  trackClick,
  initializeApp,
  processItems,
  maybeSync,
};
