// TEST FILE: Clean file with no secrets
// Should NOT trigger any secrets detection

// Using environment variables (correct approach)
const apiKey = process.env.API_KEY;
const databaseUrl = process.env.DATABASE_URL;
const secretKey = process.env.SECRET_KEY;

// Placeholder values (not real secrets)
const exampleConfig = {
  apiKey: "<your-api-key-here>",
  secret: "${SECRET_FROM_ENV}",
  token: "XXXX-XXXX-XXXX-XXXX",
};

// Type definitions (not secrets)
interface Credentials {
  username: string;
  password: string;
  apiKey: string;
}

// Function that accepts credentials (no hardcoded values)
export function authenticate(creds: Credentials): boolean {
  if (!creds.apiKey || !creds.password) {
    throw new Error("Missing credentials");
  }
  return true;
}

// Config loader from environment
export function loadConfig() {
  return {
    database: {
      host: process.env.DB_HOST || "localhost",
      port: parseInt(process.env.DB_PORT || "5432"),
      // Password comes from environment, not hardcoded
    },
    api: {
      baseUrl: process.env.API_BASE_URL,
      // Key comes from secrets manager
    },
  };
}
