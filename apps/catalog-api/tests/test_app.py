import unittest

import app


class CatalogApiTest(unittest.TestCase):
    def test_payload_contains_service_and_items(self):
        result = app.payload("/catalog")

        self.assertEqual(result["service"], "catalog-api")
        self.assertIn("secure-pipeline", result["items"])
        self.assertIn("secret_message", result)


if __name__ == "__main__":
    unittest.main()

