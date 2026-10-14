"""Edits the converter's build settings for the spike: menu-bar-only app, macOS 26, fixed bundle
IDs, unsandboxed app (Developer ID plan), sandboxed extension, and the spike's entitlements files.
Each buildSettings block is identified by the Info.plist it points at."""
import re
import sys

path = sys.argv[1]
text = open(path).read()
APP = "FocusPilotSpikeS1"


def patch_block(block):
    is_ext = "Extension/Info.plist" in block
    is_app = f"INFOPLIST_FILE = {APP}/Info.plist;" in block
    if not (is_ext or is_app):
        return block
    block = re.sub(r"MACOSX_DEPLOYMENT_TARGET = [^;]+;", "MACOSX_DEPLOYMENT_TARGET = 26.0;", block)
    block = re.sub(r"\n\s*INFOPLIST_KEY_NSMainStoryboardFile = [^;]+;", "", block)
    extra = {
        "CODE_SIGN_IDENTITY": '"-"',
        "CODE_SIGN_STYLE": "Manual",
        "DEVELOPMENT_TEAM": '""',
        "SWIFT_VERSION": "5.0",
    }
    if is_app:
        block = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;", "PRODUCT_BUNDLE_IDENTIFIER = com.focuspilot.spike.s1;", block)
        extra |= {
            "ENABLE_APP_SANDBOX": "NO",
            "INFOPLIST_KEY_LSUIElement": "YES",
            "CODE_SIGN_ENTITLEMENTS": f"{APP}/{APP}.entitlements",
        }
    else:
        block = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;", "PRODUCT_BUNDLE_IDENTIFIER = com.focuspilot.spike.s1.Extension;", block)
        extra |= {
            "ENABLE_APP_SANDBOX": "YES",
            "CODE_SIGN_ENTITLEMENTS": f'"{APP} Extension/{APP} Extension.entitlements"',
        }
    for key, value in extra.items():
        block = re.sub(rf"\n\s*{key} = [^;]+;", "", block)
        block = block.replace("buildSettings = {", f"buildSettings = {{\n\t\t\t\t{key} = {value};", 1)
    return block


text = re.sub(r"buildSettings = \{.*?\n\t\t\t\};", lambda m: patch_block(m.group(0)), text, flags=re.S)
open(path, "w").write(text)
