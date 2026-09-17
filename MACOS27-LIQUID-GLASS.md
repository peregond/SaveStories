# Liquid Glass — SDK 27 preview

Updated September 18, 2026. Prepared for release 0.6.82.

- System glass / prominent glass button styles throughout the main screens, settings and sheets.
- Tinted interactive glass for download and secondary actions, with disabled-state treatment.
- Shared GlassEffectContainer for download/stop controls; motion respects Reduce Motion.
- Extended gradient behind navigation, 20-point content corners, retained SF Rounded and readable content surfaces.
- Opaque control fallbacks for Reduce Transparency / Increase Contrast and macOS versions before 26; minimum deployment remains macOS 14.

Validation: 46 Swift tests with Xcode 27; 7 packaging tests; light/dark visual inspection. Preview app and media helper report SDK 27.0, minimum OS 14.0, arm64; strict ad-hoc signature check passed. Real Instagram downloads were not part of visual validation.

Xcode 27 switches SwiftPM to swiftbuild, which creates structured resource bundles. Resource lookup and package validation now support both layouts. On this installation its linked binaries reported SDK 14.0 despite selecting SDK 27. Packaging explicitly uses the native SwiftPM backend and selected SDK; actual Mach-O metadata remains checked. Revisit this compatibility setting when updating the toolchain.

Sources: https://developer.apple.com/videos/play/wwdc2026/269/ and https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

Build: `SAVEME_REQUIRE_SDK=27 SAVEME_REQUIRE_COMPOSED_ICON=1 ./scripts/build_beta_app.sh`
