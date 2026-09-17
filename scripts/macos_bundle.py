#!/usr/bin/env python3
"""Stamp and inspect macOS bundles using the binaries that will be shipped."""

from __future__ import annotations

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def run(*command: str) -> str:
    return subprocess.check_output(command, text=True).strip()


def version(value: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(?:\.\d+)*", value):
        raise ValueError(f"Invalid version: {value!r}")
    return tuple(map(int, value.split("."))) + (0,) * (3 - len(value.split(".")))


def build_versions(output: str) -> tuple[str, str]:
    minimums = re.findall(r"^\s*minos\s+(\d+(?:\.\d+)*)\s*$", output, re.MULTILINE)
    sdks = re.findall(r"^\s*sdk\s+(\d+(?:\.\d+)*)\s*$", output, re.MULTILINE)
    if not minimums or len(minimums) != len(sdks):
        raise ValueError("Missing macOS build-version load commands")
    return max(minimums, key=version), min(sdks, key=version)


def inspect(app: Path) -> tuple[dict, str, str, set[str]]:
    contents = app / "Contents"
    with (contents / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    executable = contents / "MacOS" / info["CFBundleExecutable"]
    helper = contents / "Helpers/SaveMeMediaMuxer"
    sparkle = contents / "Frameworks/Sparkle.framework/Sparkle"
    resources = contents / "Resources/SaveMe_SaveMe.bundle"
    if (resources / "Contents/Resources").is_dir():
        resources = resources / "Contents/Resources"
    required = [
        executable,
        helper,
        contents / "Resources/SaveMe.icns",
        resources / "bootstrap_worker.sh",
        resources / "update_config.json",
        resources / "google_drive_copy_link.applescript",
        resources / "worker/bridge.py",
        sparkle,
        contents / "SharedSupport/node_worker/package.json",
        contents / "SharedSupport/node_worker/package-lock.json",
        contents / "SharedSupport/node_worker/bridge.mjs",
    ]
    missing = [str(path.relative_to(app)) for path in required if not path.is_file()]
    if missing:
        raise ValueError("Incomplete app bundle: " + ", ".join(missing))

    builds = [build_versions(run("xcrun", "vtool", "-show-build", str(binary)))
              for binary in (executable, helper)]
    architectures = [set(run("lipo", "-archs", str(binary)).split())
                     for binary in (executable, helper, sparkle)]
    if not architectures[0].issubset(architectures[1] & architectures[2]):
        raise ValueError("The media helper or Sparkle is missing an app architecture")
    return (info, max((entry[0] for entry in builds), key=version),
            min((entry[1] for entry in builds), key=version), architectures[0])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "stamp", "verify"))
    parser.add_argument("--app", type=Path)
    parser.add_argument("--require-sdk", default="14.0")
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--distribution", action="store_true",
                        help="also require Developer ID, hardened runtime, and a stapled notarization ticket")
    args = parser.parse_args()
    required_sdk = version(args.require_sdk)

    if args.command == "preflight":
        sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-version")
        print(run("xcodebuild", "-version"))
        print(f"Selected macOS SDK: {sdk}")
        if version(sdk) < required_sdk:
            raise ValueError(f"macOS SDK {args.require_sdk} or newer is required; select a matching Xcode with DEVELOPER_DIR")
        if version(sdk) < version("27"):
            print("macOS 27 SDK validation is pending; this build uses the SDK shown above.")
        return 0

    if args.app is None:
        parser.error("--app is required for stamp and verify")
    info, minimum, sdk, architectures = inspect(args.app)
    if version(sdk) < required_sdk:
        raise ValueError(f"The app/helper were built with SDK {sdk}; SDK {args.require_sdk} or newer is required")
    if required_sdk >= version("27") and "arm64" not in architectures:
        raise ValueError("macOS 27 readiness requires a native Apple silicon (arm64) app")

    if args.command == "stamp":
        info.update(LSMinimumSystemVersion=minimum, DTPlatformName="macosx",
                    DTPlatformVersion=sdk, DTSDKName=f"macosx{sdk}",
                    CFBundleSupportedPlatforms=["MacOSX"])
        if not (args.app / "Contents/Resources/Assets.car").is_file():
            info.pop("CFBundleIconName", None)
        if args.preview:
            info.update(CFBundleDisplayName="SaveMe Preview", CFBundleName="SaveMe Preview",
                        SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
            info.pop("SUFeedURL", None)
            info.pop("SUPublicEDKey", None)
        with (args.app / "Contents/Info.plist").open("wb") as destination:
            plistlib.dump(info, destination, sort_keys=False)
    else:
        if version(info.get("LSMinimumSystemVersion", "0")) != version(minimum):
            raise ValueError("LSMinimumSystemVersion does not match the packaged binaries")
        if info.get("DTSDKName") != f"macosx{sdk}":
            raise ValueError("DTSDKName does not match the packaged binaries")
        run("codesign", "--verify", "--deep", "--strict", str(args.app))
        if args.distribution:
            signature = subprocess.run(
                ["codesign", "--display", "--verbose=4", str(args.app)],
                capture_output=True, text=True, check=True,
            ).stderr
            if "Authority=Developer ID Application:" not in signature or "(runtime)" not in signature:
                raise ValueError("Distribution requires Developer ID Application signing and hardened runtime")
            run("xcrun", "stapler", "validate", str(args.app))

    print(f"{args.app.name}: macOS {minimum}+, SDK {sdk}, architectures {', '.join(sorted(architectures))}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"macOS packaging check failed: {error}", file=sys.stderr)
        sys.exit(1)
