"""Regression checks for widget signing and backend compatibility."""
import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
class WidgetProfilesTest(unittest.TestCase):
    def test_both_team_groups(self):
        s=(R/"Shared/WidgetSharedStore.swift").read_text()
        self.assertIn("group.dfbc88d056a46f1b.",s)
        self.assertIn("group.4d9963ba648cf299.",s)
        self.assertIn("containerURL(forSecurityApplicationGroupIdentifier: candidate)",s)
    def test_existing_server(self):
        s=(R/"App/VersionCompatibility.swift").read_text()
        import re
        server=re.search(r'^APP_VERSION = "([^"]+)"',(R/"Backend/rj_love_server.py").read_text(),re.M).group(1)
        # The app never requires a newer server than the one shipped in the same package.
        self.assertIn(f'minimumServer = "{server}"',s)
        self.assertIn("protocolVersion = 5",s)
        b=(R/"App/BackgroundDeliveryService.swift").read_text()
        self.assertIn("api.bootstrap()",b)
        self.assertIn("CommandDeliveryProcessor.shared.process",b)
    def test_widget_extension(self):
        s=(R/"WidgetExtension/RJLoveWidgets.swift").read_text()
        self.assertIn("WidgetSharedStore.loadSnapshot()",s)
if __name__=="__main__":
    unittest.main()
