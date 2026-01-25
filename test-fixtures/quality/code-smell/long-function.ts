// TEST FILE: Contains a deliberately long function (60+ lines)
// Should trigger "Long Function" code smell detection

interface User {
  id: number;
  name: string;
  email: string;
  role: string;
  permissions: string[];
  createdAt: Date;
  updatedAt: Date;
}

interface ProcessResult {
  success: boolean;
  message: string;
  data?: unknown;
}

// This function is intentionally too long and does too many things
export function processUserData(users: User[], options: {
  validate: boolean;
  transform: boolean;
  filter: boolean;
  sort: boolean;
  paginate: boolean;
  page: number;
  limit: number;
}): ProcessResult {
  // Step 1: Validation
  if (options.validate) {
    for (const user of users) {
      if (!user.id) {
        return { success: false, message: "User ID is required" };
      }
      if (!user.name) {
        return { success: false, message: "User name is required" };
      }
      if (!user.email) {
        return { success: false, message: "User email is required" };
      }
      if (!user.email.includes("@")) {
        return { success: false, message: "Invalid email format" };
      }
      if (!user.role) {
        return { success: false, message: "User role is required" };
      }
      if (!Array.isArray(user.permissions)) {
        return { success: false, message: "Permissions must be an array" };
      }
    }
  }

  // Step 2: Transform
  let processedUsers = users;
  if (options.transform) {
    processedUsers = users.map(user => ({
      ...user,
      name: user.name.trim(),
      email: user.email.toLowerCase(),
      role: user.role.toUpperCase(),
      permissions: user.permissions.map(p => p.toLowerCase()),
    }));
  }

  // Step 3: Filter
  if (options.filter) {
    processedUsers = processedUsers.filter(user => {
      if (user.role === "INACTIVE") {
        return false;
      }
      if (user.permissions.length === 0) {
        return false;
      }
      return true;
    });
  }

  // Step 4: Sort
  if (options.sort) {
    processedUsers = processedUsers.sort((a, b) => {
      if (a.name < b.name) return -1;
      if (a.name > b.name) return 1;
      return 0;
    });
  }

  // Step 5: Paginate
  if (options.paginate) {
    const start = (options.page - 1) * options.limit;
    const end = start + options.limit;
    processedUsers = processedUsers.slice(start, end);
  }

  return {
    success: true,
    message: "Processing complete",
    data: processedUsers,
  };
}
