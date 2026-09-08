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

    def test_preserves_simctl_identifier_case(self):
        identifier = "FE32D002-7973-4F0F-B63B-59901A0312D3"
        self.assertEqual(module.select({
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"name": "iPhone SE", "isAvailable": True, "udid": identifier}],
        }, "18.5"), identifier)

    def test_ignores_runtimes_newer_than_selected_xcode_sdk(self):
        compatible = "FE32D002-7973-4F0F-B63B-59901A0312D3"
        newer = "CCA19FC8-1066-4F9D-9383-7D95EFBFEBF7"
        self.assertEqual(module.select({
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"name": "iPhone SE", "isAvailable": True, "udid": compatible}],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                {"name": "iPhone SE", "isAvailable": True, "udid": newer}],
        }, "18.5"), compatible)

    def test_fails_when_no_runtime_fits_the_selected_sdk(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
            {"name": "iPhone SE", "isAvailable": True,
             "udid": "CCA19FC8-1066-4F9D-9383-7D95EFBFEBF7"}]}
        with self.assertRaisesRegex(ValueError, "No available"):
            module.select(devices, "18.5")
        with self.assertRaisesRegex(ValueError, "Invalid"):
            module.select(devices, "not-a-version")
