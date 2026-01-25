// TEST FILE: Contains deeply nested code (5+ levels)
// Should trigger "Deep Nesting" code smell detection

function processOrder(order, user, inventory, discounts) {
  if (order) {
    if (order.items && order.items.length > 0) {
      for (const item of order.items) {
        if (item.productId) {
          const product = inventory.find(p => p.id === item.productId);
          if (product) {
            if (product.inStock) {
              if (item.quantity <= product.stockCount) {
                // Level 6 - too deep!
                if (user.isPremium) {
                  for (const discount of discounts) {
                    if (discount.appliesTo === product.category) {
                      if (discount.minQuantity <= item.quantity) {
                        // Level 9 - way too deep!
                        item.discount = discount.percentage;
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  return order;
}

// Another example with deeply nested callbacks
function fetchUserData(userId, callback) {
  fetchUser(userId, (err, user) => {
    if (!err) {
      fetchOrders(user.id, (err, orders) => {
        if (!err) {
          fetchPayments(user.id, (err, payments) => {
            if (!err) {
              fetchPreferences(user.id, (err, prefs) => {
                if (!err) {
                  // Level 5+ nesting
                  callback(null, { user, orders, payments, prefs });
                } else {
                  callback(err);
                }
              });
            } else {
              callback(err);
            }
          });
        } else {
          callback(err);
        }
      });
    } else {
      callback(err);
    }
  });
}

// Mock functions
function fetchUser(id, cb) { cb(null, { id }); }
function fetchOrders(id, cb) { cb(null, []); }
function fetchPayments(id, cb) { cb(null, []); }
function fetchPreferences(id, cb) { cb(null, {}); }

module.exports = { processOrder, fetchUserData };
