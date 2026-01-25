// TEST FILE: Contains empty catch blocks and swallowed errors
// Should trigger "Empty Catch" code smell detection

async function fetchData(url) {
  try {
    const response = await fetch(url);
    return await response.json();
  } catch (e) {
    // Empty catch block - swallows error silently
  }
}

function parseConfig(configString) {
  try {
    return JSON.parse(configString);
  } catch (error) {
    // Returns undefined on error - caller won't know parsing failed
    return undefined;
  }
}

function processFile(path) {
  try {
    const fs = require("fs");
    return fs.readFileSync(path, "utf-8");
  } catch (err) {
    // Logs but doesn't handle - still returns undefined implicitly
    console.log("File error");
  }
}

async function saveData(data) {
  try {
    await database.save(data);
  } catch (e) {
    // Empty catch with no handling or logging
  }
  return true; // Always returns true even if save failed!
}

function calculateTotal(items) {
  let total = 0;
  for (const item of items) {
    try {
      total += parseFloat(item.price);
    } catch {
      // Silently ignores invalid prices
    }
  }
  return total;
}

// Console statements in production code
function logUserActivity(user, action) {
  console.log("User activity:", user.id, action);
  console.error("Debug: checking user", user);
  console.debug("Action performed");
}

// Mock database
const database = {
  save: async () => {},
};

module.exports = {
  fetchData,
  parseConfig,
  processFile,
  saveData,
  calculateTotal,
  logUserActivity,
};
