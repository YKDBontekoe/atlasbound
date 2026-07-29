import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "ci_test_matrix.py"
SPEC = importlib.util.spec_from_file_location("ci_test_matrix", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CITestMatrixTests(unittest.TestCase):
    def test_discovers_classes_and_methods(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "ExampleTests.swift"
            source.write_text(
                """
import XCTest
final class ExampleTests: XCTestCase {
    func testFirst() {}
    func testSecond() throws {}
}
""",
                encoding="utf-8",
            )

            classes = MODULE.discover_test_classes(Path(directory))

        self.assertEqual(classes[0].name, "ExampleTests")
        self.assertEqual(classes[0].methods, ("testFirst", "testSecond"))

    def test_class_shards_balance_by_method_count(self):
        classes = [
            MODULE.TestClass("LargeTests", ("testA", "testB", "testC")),
            MODULE.TestClass("SmallTests", ("testA",)),
            MODULE.TestClass("MediumTests", ("testA", "testB")),
        ]
        items = MODULE.test_items("AtlasboundTests", classes, "class")

        matrix = MODULE.balanced_matrix(items, 2, "unit")

        filters = [entry["only_testing"] for entry in matrix["include"]]
        self.assertEqual(len(filters), 2)
        self.assertIn("AtlasboundTests/LargeTests", filters)
        self.assertIn("AtlasboundTests/MediumTests", " ".join(filters))
        self.assertIn("AtlasboundTests/SmallTests", " ".join(filters))

    def test_fails_when_a_test_method_would_be_omitted(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "ExtensionTests.swift"
            source.write_text(
                """
extension ExampleTests {
    func testInExtension() {}
}
""",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "outside"):
                MODULE.discover_test_classes(Path(directory))

    def test_method_shards_cover_each_test_once(self):
        classes = [
            MODULE.TestClass("SmokeTests", ("testA", "testB", "testC")),
        ]
        items = MODULE.test_items("AtlasboundUITests", classes, "method")

        matrix = MODULE.balanced_matrix(items, 5, "ui")
        identifiers = [
            identifier
            for entry in matrix["include"]
            for identifier in entry["only_testing"].split()
        ]

        self.assertEqual(len(matrix["include"]), 3)
        self.assertEqual(
            sorted(identifiers),
            [
                "AtlasboundUITests/SmokeTests/testA",
                "AtlasboundUITests/SmokeTests/testB",
                "AtlasboundUITests/SmokeTests/testC",
            ],
        )


if __name__ == "__main__":
    unittest.main()
