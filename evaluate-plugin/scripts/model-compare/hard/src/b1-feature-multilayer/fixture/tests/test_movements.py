import unittest

from inventory.api.routes import dispatch
from tests.helpers import make_store


class MovementApiTest(unittest.TestCase):
    def setUp(self):
        self.store = make_store()
        _, self.item = dispatch(
            self.store, "POST", "/items", {"body": {"sku": "S1", "name": "Saw", "category": "tools"}}
        )

    def move(self, kind, delta):
        return dispatch(
            self.store, "POST", "/movements",
            {"body": {"item_id": self.item["id"], "kind": kind, "delta": delta}},
        )

    def test_in_then_out(self):
        self.assertEqual(self.move("in", 5)[0], 201)
        status, body = self.move("out", 2)
        self.assertEqual((status, body["delta"]), (201, -2))
        status, item = dispatch(self.store, "GET", "/items/{id}", {"params": {"id": str(self.item["id"])}})
        self.assertEqual(item["quantity"], 3)

    def test_insufficient_stock(self):
        status, body = self.move("out", 1)
        self.assertEqual(status, 409)

    def test_bad_kind(self):
        status, body = self.move("teleport", 1)
        self.assertEqual(status, 400)
        self.assertEqual(body["error"]["field"], "kind")

    def test_list(self):
        self.move("in", 1)
        self.move("in", 2)
        status, body = dispatch(self.store, "GET", "/movements", {})
        self.assertEqual(len(body["items"]), 2)


if __name__ == "__main__":
    unittest.main()
