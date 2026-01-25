// TEST FILE: Contains SQL injection vulnerability patterns
// For workflow validation - DO NOT use these patterns in production

const mysql = require("mysql");

// VULNERABLE: String concatenation in SQL query
async function getUserById(userId) {
  const query = "SELECT * FROM users WHERE id = " + userId;
  return db.query(query);
}

// VULNERABLE: Template literal without parameterization
async function searchUsers(searchTerm) {
  const query = `SELECT * FROM users WHERE name LIKE '%${searchTerm}%'`;
  return db.query(query);
}

// VULNERABLE: Direct user input in query
function deleteUser(req, res) {
  const userId = req.params.id;
  const sql = "DELETE FROM users WHERE id = '" + userId + "'";
  connection.query(sql, (err, result) => {
    if (err) throw err;
    res.send("Deleted");
  });
}

// VULNERABLE: Building WHERE clause from user input
function buildDynamicQuery(filters) {
  let query = "SELECT * FROM products WHERE 1=1";
  if (filters.category) {
    query += " AND category = '" + filters.category + "'";
  }
  if (filters.price) {
    query += " AND price < " + filters.price;
  }
  return query;
}

module.exports = { getUserById, searchUsers, deleteUser, buildDynamicQuery };
