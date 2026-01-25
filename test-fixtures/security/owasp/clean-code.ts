// TEST FILE: Clean code with secure patterns
// Should NOT trigger OWASP vulnerability detection

import { Pool } from "pg";
import { escape } from "html-escaper";

const pool = new Pool();

// SECURE: Parameterized query
async function getUserById(userId: number): Promise<User | null> {
  const result = await pool.query("SELECT * FROM users WHERE id = $1", [
    userId,
  ]);
  return result.rows[0] || null;
}

// SECURE: Prepared statement
async function searchUsers(searchTerm: string): Promise<User[]> {
  const result = await pool.query(
    "SELECT * FROM users WHERE name ILIKE $1",
    [`%${searchTerm}%`]
  );
  return result.rows;
}

// SECURE: Input validation
function validateUserId(input: unknown): number {
  const id = Number(input);
  if (!Number.isInteger(id) || id < 1) {
    throw new Error("Invalid user ID");
  }
  return id;
}

// SECURE: HTML escaping
function renderUserContent(content: string): string {
  return escape(content);
}

// SECURE: Allowlist for user actions
const ALLOWED_ACTIONS = ["view", "edit", "delete"] as const;
type Action = typeof ALLOWED_ACTIONS[number];

function validateAction(action: string): Action {
  if (!ALLOWED_ACTIONS.includes(action as Action)) {
    throw new Error("Invalid action");
  }
  return action as Action;
}

// SECURE: URL validation
function isValidUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return ["http:", "https:"].includes(parsed.protocol);
  } catch {
    return false;
  }
}

interface User {
  id: number;
  name: string;
  email: string;
}

export {
  getUserById,
  searchUsers,
  validateUserId,
  renderUserContent,
  validateAction,
  isValidUrl,
};
