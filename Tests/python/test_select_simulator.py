import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "select_simulator", Path(__file__).resolve().parents[2] / "Scripts/select_simulator.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_newest_supported_available_iphone(self):
        valid = "11111111-1111-1111-1111-111111111111"
        newer = "22222222-2222-2222-2222-222222222222"
        self.assertEqual(module.select({
            "com.apple.CoreSimulator.SimRuntime.iOS-17-4": [
                {"name": "iPhone 15", "isAvailable": True, "udid": valid}],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"name": "iPhone 16", "isAvailable": True, "udid": newer},
                {"name": "iPhone 16 Pro", "isAvailable": False, "udid": valid},
                {"name": "iPad Pro", "isAvailable": True, "udid": valid}],
        }), newer)

    def test_rejects_old_other_platform_and_invalid_identifier(self):
        device = {"name": "iPhone 15", "isAvailable": True,
                  "udid": "11111111-1111-1111-1111-111111111111"}
        with self.assertRaisesRegex(ValueError, "No available"):
            module.select({
                "com.apple.CoreSimulator.SimRuntime.iOS-17-3": [device],
                "com.apple.CoreSimulator.SimRuntime.tvOS-18-5": [device],
                "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [dict(device, udid="bad")],
            })

    def test_reports_missing_simulators(self):
        with self.assertRaisesRegex(ValueError, "No available"):
            module.select({})
