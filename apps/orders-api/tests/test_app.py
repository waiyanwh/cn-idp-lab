import unittest

import app


class OrdersApiTest(unittest.TestCase):
    def test_payload_contains_service_and_order(self):
        result = app.payload("/orders")

        self.assertEqual(result["service"], "orders-api")
        self.assertEqual(result["orders"][0]["status"], "accepted")
        self.assertIn("secret_message", result)


if __name__ == "__main__":
    unittest.main()

