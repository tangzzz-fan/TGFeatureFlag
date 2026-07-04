---
kind: frontend_style
name: SwiftUI Native Styling with System Assets
category: frontend_style
scope:
    - '**'
source_files:
    - Example/TGFeatureFlagDemo/TGFeatureFlagDemo/ContentView.swift
    - Example/TGFeatureFlagDemo/TGFeatureFlagDemo/Assets.xcassets/AccentColor.colorset/Contents.json
---

This repository is a Swift Package focused on feature-flag logic and contains no CSS, SCSS, Tailwind, or external UI framework. Visual styling is entirely SwiftUI-based and follows Apple's native conventions:

- **Styling approach**: Pure SwiftUI declarative views using built-in modifiers (`.font()`, `.foregroundStyle()`, `.background()`, `.cornerRadius()`, `.padding()`, `.frame()`) rather than custom style sheets or design systems.
- **Theming**: Relies on system colors (`Color.blue`, `Color.gray`, `Color.orange`, `Color(uiColor: .systemBackground)`, `.yellow`, `.secondary`) and SF Symbols for icons; no custom color palette or theme tokens are defined in code.
- **Assets**: The only asset catalog lives at `Example/TGFeatureFlagDemo/TGFeatureFlagDemo/Assets.xcassets` and contains the app icon and an `AccentColor.colorset`; no additional themed images or design tokens are present.
- **Responsive strategy**: Views use SwiftUI's adaptive layout primitives (`ScrollView`, `VStack`, `HStack`, `Spacer`, `List`, `NavigationStack`) and avoid fixed pixel sizes except where illustrative (e.g., product image height), letting iOS handle device adaptation automatically.
- **Consistency pattern**: Demo views reuse common modifier chains (rounded corners + subtle background opacity) to give a cohesive look across scenarios, but there is no shared style helper or design token layer — each view composes its own appearance inline.

In short, the repo has no cross-cutting frontend style system beyond standard SwiftUI + system assets.