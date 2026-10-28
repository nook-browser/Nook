#!/usr/bin/env python3
"""Run window lifecycle checks against a built Debug app, with isolated application data."""
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

root = pathlib.Path(__file__).resolve().parents[2]
derived = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else root / "build-prototype").resolve()
products = derived / "Build/Products/Debug"
bundle_id = "com.nook.window-check." + uuid.uuid4().hex


def cleanup_application(identifier):
    shutil.rmtree(pathlib.Path.home() / "Library/Application Support" / identifier, ignore_errors=True)
    shutil.rmtree(pathlib.Path.home() / "Library/Saved Application State" / (identifier + ".savedState"), ignore_errors=True)
    subprocess.run(["defaults", "delete", identifier], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


with tempfile.TemporaryDirectory(prefix="nook-window-check-") as temporary:
    folder = pathlib.Path(temporary)
    contents = folder / "WindowCheck.app/Contents"
    binaries = contents / "MacOS"
    binaries.mkdir(parents=True)
    (contents / "Resources").symlink_to(products / "Nook.app/Contents/Resources")
    (contents / "Frameworks").symlink_to(products / "Nook.app/Contents/Frameworks")
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleIdentifier": bundle_id, "CFBundleExecutable": "WindowCheck",
                      "CFBundlePackageType": "APPL", "CFBundleName": "Nook Window Check"}, stream)
    library = binaries / "Nook.debug.dylib"
    shutil.copy2(products / "Nook.app/Contents/MacOS/Nook.debug.dylib", library)
    command = [
        "swiftc", "-parse-as-library", "-I", str(products), "-I", str(products / "include"),
        "-I", str(derived / "SourcePackages/checkouts/swift-atomics/Sources/_AtomicsShims/include"),
        "-Xcc", "-fmodule-map-file=" + str(derived / "Build/Intermediates.noindex/GeneratedModuleMaps/MuteableWKWebView.modulemap"),
        "-F", str(products), "-F", str(contents / "Frameworks"),
        str(root / "scripts/tests/BrowserWindowOpeningCheck.swift"), str(library),
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        "-o", str(binaries / "WindowCheck"),
    ]
    try:
        subprocess.run(command, check=True)
        for executable in (library, binaries / "WindowCheck"):
            subprocess.run(["codesign", "--force", "--sign", "-", str(executable)], check=True)
        subprocess.run([str(binaries / "WindowCheck"), "-NookStateDir", str(folder / "state")], check=True, timeout=60)

        # Use the real SwiftUI App entry point and macOS URL delivery for cold launches.
        command[command.index(str(root / "scripts/tests/BrowserWindowOpeningCheck.swift"))] = str(root / "scripts/tests/BrowserColdLaunchCheck.swift")
        subprocess.run(command, check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(binaries / "WindowCheck")], check=True)
        with (products / "Nook.app/Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        info.update(CFBundleIdentifier=bundle_id, CFBundleExecutable="WindowCheck", CFBundleName="Nook Window Check")
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)

        for scenario in ("routed", "tabs", "no-windows", "restored"):
            # AppKit/SwiftUI restoration is keyed by bundle identity, not NookStateDir.
            scenario_id = bundle_id + "." + scenario
            scenario_app = folder / (scenario + ".app")
            shutil.copytree(contents.parent, scenario_app, symlinks=True)
            info["CFBundleIdentifier"] = scenario_id
            with (scenario_app / "Contents/Info.plist").open("wb") as stream:
                plistlib.dump(info, stream)
            report = folder / (scenario + ".json")
            try:
                subprocess.run([
                    "open", "-W", "-n", "-a", str(scenario_app),
                    "--stdout", str(folder / (scenario + ".log")), "--stderr", str(folder / (scenario + ".log")),
                    "https://window-check.invalid/" + scenario, "--args",
                    "-NookStateDir", str(folder / scenario),
                    "-NookColdCheckCase", scenario, "-NookColdCheckReport", str(report),
                ], check=True, timeout=45)
                result = json.loads(report.read_text())
                print("Cold launch:", json.dumps(result, sort_keys=True), flush=True)
                if not result["passed"]:
                    print((folder / (scenario + ".log")).read_text(), flush=True)
                assert result["passed"], result
            finally:
                # A timeout kills `open`, not the app it launched. Stop only this disposable app.
                executable_pattern = "^" + re.escape(str(scenario_app / "Contents/MacOS/WindowCheck")) + "( |$)"
                subprocess.run(["pkill", "-f", executable_pattern], check=False)
                cleanup_application(scenario_id)
    finally:
        cleanup_application(bundle_id)
