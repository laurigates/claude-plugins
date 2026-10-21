import unittest

from inventory.api import items as api
from inventory.api.routes import dispatch
from tests.helpers import make_store


class ItemApiTest(unittest.TestCase):
    def setUp(self):
        self.store = make_store()

    def create(self, **body):
        body.setdefault("category", "tools")
        return dispatch(self.store, "POST", "/items", {"body": body})

    def test_create_and_get(self):
        status, body = self.create(sku="ab-1", name="Hammer", quantity="3", price_cents=1250)
        self.assertEqual(status, 201)
        self.assertEqual(body["sku"], "AB-1")
        self.assertEqual(body["price"], "12.50")
        status, got = api.get_item(self.store, {"params": {"id": str(body["id"])}})
        self.assertEqual((status, got), (200, body))

    def test_duplicate_sku_conflict(self):
        self.create(sku="X", name="One")
        status, body = self.create(sku="x", name="Two")
        self.assertEqual(status, 409)
        self.assertEqual(body["error"]["code"], "conflict")

    def test_validation_envelope(self):
        status, body = self.create(sku="Y", name="Bad", quantity="-1")
        self.assertEqual(status, 400)
        self.assertEqual(
            body["error"],
            {"code": "validation_error", "message": "quantity must be >= 0", "field": "quantity"},
        )

    def test_list_hides_archived(self):
        _, a = self.create(sku="A", name="A")
        self.create(sku="B", name="B")
        api.archive_item(self.store, {"params": {"id": str(a["id"])}})
        status, body = api.list_items(self.store, {})
        self.assertEqual(status, 200)
        self.assertEqual([i["sku"] for i in body["items"]], ["B"])

    def test_not_found(self):
        status, body = api.get_item(self.store, {"params": {"id": "99"}})
        self.assertEqual(status, 404)


if __name__ == "__main__":
    unittest.main()
