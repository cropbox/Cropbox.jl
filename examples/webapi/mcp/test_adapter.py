"""Offline checks for HTTP forwarding. Run with python -m unittest discover."""

import io
import json
import unittest
import urllib.error
from unittest.mock import patch

from adapter import route_json, service_url


class AdapterTests(unittest.TestCase):
    def test_url_validation(self):
        self.assertEqual(service_url("http://127.0.0.1:8000/"), "http://127.0.0.1:8000")
        for url in ("file:///tmp/model", "http://name:secret@example.com", "https://host/?key=secret", ""):
            with self.subTest(url=url), self.assertRaises(ValueError):
                service_url(url)

    def test_forward_units_without_rounding(self):
        payload = {"config_entries": [{"path": "Example.a", "value": {"value": 1.23456789, "unit": "m"}}]}
        result = {"rows": [[1.23456789]], "columns": [{"name": "a", "unit": "m"}]}
        with patch("urllib.request.urlopen", return_value=io.BytesIO(json.dumps(result).encode())) as open_url:
            self.assertEqual(route_json("http://localhost:8000", "POST", "/api/simulate", payload), result)
        sent = open_url.call_args.args[0]
        self.assertEqual(sent.full_url, "http://localhost:8000/api/simulate")
        self.assertEqual(json.loads(sent.data), payload)

    def test_http_error_retains_detail(self):
        error = urllib.error.HTTPError("http://localhost", 400, "Bad Request", {}, io.BytesIO(b'{"error":"unit"}'))
        with patch("urllib.request.urlopen", side_effect=error), self.assertRaisesRegex(ValueError, 'HTTP 400.*unit'):
            route_json("http://localhost", "POST", "/api/simulate", {})

    def test_non_object_response_rejected(self):
        with patch("urllib.request.urlopen", return_value=io.BytesIO(b"[]")), self.assertRaises(ValueError):
            route_json("http://localhost", "GET", "/api/model")


if __name__ == "__main__":
    unittest.main()
