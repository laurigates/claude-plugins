// TEST FILE: Contains promises without proper error handling
// Should trigger async pattern detection

// Promise.then without .catch
function fetchUserData(userId) {
  fetch(`/api/users/${userId}`)
    .then(response => response.json())
    .then(data => {
      displayUser(data);
    });
  // Missing .catch() - unhandled rejection if fetch fails
}

// Promise chain without error handling
function loadConfiguration() {
  return fetch("/api/config")
    .then(r => r.json())
    .then(config => validateConfig(config))
    .then(config => applyConfig(config));
  // Long chain without any .catch()
}

// Promise.all without catch
async function loadAllData() {
  const results = Promise.all([
    fetch("/api/users"),
    fetch("/api/posts"),
    fetch("/api/comments"),
  ]);
  // If any fails, unhandled rejection

  return results;
}

// Async function without try-catch, caller doesn't handle
async function riskyOperation() {
  const response = await fetch("/api/dangerous");
  if (!response.ok) {
    throw new Error("Operation failed");
  }
  return response.json();
}

function callRiskyOperation() {
  const result = riskyOperation(); // No await, no .catch
  console.log("Called risky operation");
}

// Swallowed error - catches but doesn't handle meaningfully
async function swallowedError() {
  try {
    await fetch("/api/data");
  } catch (e) {
    // Swallowed - no rethrow, no logging, no handling
  }
  return "success"; // Returns success even on error!
}

// Mock functions
function displayUser(data) { console.log(data); }
function validateConfig(config) { return config; }
function applyConfig(config) { return config; }

module.exports = {
  fetchUserData,
  loadConfiguration,
  loadAllData,
  riskyOperation,
  callRiskyOperation,
  swallowedError,
};
