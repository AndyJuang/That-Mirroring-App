#!/usr/bin/env python3
"""Fail unless en and zh-Hant use the same keys, placeholders, and source strings."""
import pathlib, plistlib, re, subprocess, sys

root = pathlib.Path(__file__).resolve().parent.parent
tables = ("Localizable.strings", "InfoPlist.strings")
ui_calls = (
    "localizedText", "Text", "Button", "Toggle", "Label", "CommandMenu", "WindowGroup",
)
simplified = set(
    "这国说们对时会来过还发经现开关门问长从动电话网软设备连视频率应复后显认请无线"
    "蓝触扫识语体号码据库优邮图标夹馈计机项质检户盘载页节点击个与为着"
)


def load_strings(path):
    try:
        xml = subprocess.check_output(["plutil", "-convert", "xml1", "-o", "-", str(path)], stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.output.decode() or f"invalid strings file: {path}")
    data = plistlib.loads(xml)
    if not isinstance(data, dict) or not data:
        raise SystemExit(f"{path} has no string entries")
    cleaned = {}
    for key, value in data.items():
        if not isinstance(key, str) or not isinstance(value, str) or value == "":
            raise SystemExit(f"{path} has an empty or non-string entry")
        cleaned[key] = value
    return cleaned


def unescape(text):
    output = []
    index = 0
    while index < len(text):
        if text[index] == "\\" and index + 1 < len(text):
            output.append({"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\"}.get(text[index + 1], text[index + 1]))
            index += 2
        else:
            output.append(text[index])
            index += 1
    return "".join(output)


def placeholders(value):
    return re.findall(r"%(?:\d+\$)?@", value)


def source_keys():
    keys = []
    pattern = re.compile(r"\b(?:" + "|".join(ui_calls) + r")\(\s*\"((?:\\.|[^\"\\])*)\"")
    for name in ("MirrorApp.swift", "MirrorLogic.swift", "AndroidManager.swift"):
        text = (root / name).read_text(encoding="utf-8")
        keys.extend(unescape(item) for item in pattern.findall(text))
        if name == "MirrorApp.swift":
            keys.extend(re.findall(r'case \w+ = "((?:\\.|[^"\\])*)"', text))
        if name == "MirrorLogic.swift":
            match = re.search(r'let androidConnectionSteps = """\n(.*)\n"""', text, re.S)
            if not match:
                raise SystemExit("android connection steps are missing")
            keys.append(match.group(1))
    return keys


def main():
    loaded = {}
    for name in tables:
        en = load_strings(root / "en.lproj" / name)
        zh = load_strings(root / "zh-Hant.lproj" / name)
        if set(en) != set(zh):
            raise SystemExit(
                f"{name} keys differ\n"
                f"missing in zh-Hant: {sorted(set(en) - set(zh))}\n"
                f"extra in zh-Hant: {sorted(set(zh) - set(en))}"
            )
        for key, value in en.items():
            if placeholders(value) != placeholders(zh[key]):
                raise SystemExit(f"{name} placeholders differ for {key!r}")
        loaded[name] = (en, zh)

    en, zh = loaded["Localizable.strings"]
    if en.get("That Mirroring") != "That Mirroring" or zh.get("That Mirroring") != "That Mirroring":
        raise SystemExit("The That Mirroring window title must stay the same in both languages")
    missing = sorted({key for key in source_keys() if key not in en})
    if missing:
        raise SystemExit("source strings missing from Localizable.strings:\n" + "\n".join(missing))

    logic = (root / "MirrorLogic.swift").read_text(encoding="utf-8")
    manager = (root / "AndroidManager.swift").read_text(encoding="utf-8")
    if "--window-title=That Mirroring — Android ·" not in logic:
        raise SystemExit("Android window title must stay stable")
    if 'window.title == "That Mirroring"' not in manager:
        raise SystemExit("main window title match must stay stable")

    plist = plistlib.loads((root / "Info.plist").read_bytes())
    if plist.get("CFBundleDevelopmentRegion") != "en":
        raise SystemExit("CFBundleDevelopmentRegion must be en")
    if plist.get("CFBundleLocalizations") != ["en", "zh-Hant"]:
        raise SystemExit("CFBundleLocalizations must be en, zh-Hant")
    info_en = loaded["InfoPlist.strings"][0]
    for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription"):
        if plist.get(key) != info_en.get(key):
            raise SystemExit(f"Info.plist {key} does not match en InfoPlist.strings")

    chinese = "\n".join((root / "zh-Hant.lproj" / name).read_text(encoding="utf-8") for name in tables)
    found = sorted({char for char in chinese if char in simplified})
    if found:
        raise SystemExit("zh-Hant contains simplified characters: " + "".join(found))
    print("STRINGS ALIGNED")


if __name__ == "__main__":
    sys.exit(main() or 0)
