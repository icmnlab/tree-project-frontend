---
name: Forest Intelligence
colors:
  surface: '#fcf8ff'
  surface-dim: '#dad7f3'
  surface-bright: '#fcf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f5f2ff'
  surface-container: '#efecff'
  surface-container-high: '#e8e5ff'
  surface-container-highest: '#e2e0fc'
  on-surface: '#1a1a2e'
  on-surface-variant: '#414751'
  inverse-surface: '#2f2e43'
  inverse-on-surface: '#f2efff'
  outline: '#717782'
  outline-variant: '#c1c7d3'
  surface-tint: '#0060a9'
  primary: '#004e8b'
  on-primary: '#ffffff'
  primary-container: '#0066b3'
  on-primary-container: '#d2e3ff'
  inverse-primary: '#a2c9ff'
  secondary: '#1b6d24'
  on-secondary: '#ffffff'
  secondary-container: '#a0f399'
  on-secondary-container: '#217128'
  tertiary: '#781b9f'
  on-tertiary: '#ffffff'
  tertiary-container: '#933ab9'
  on-tertiary-container: '#f7d7ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d3e4ff'
  primary-fixed-dim: '#a2c9ff'
  on-primary-fixed: '#001c38'
  on-primary-fixed-variant: '#004881'
  secondary-fixed: '#a3f69c'
  secondary-fixed-dim: '#88d982'
  on-secondary-fixed: '#002204'
  on-secondary-fixed-variant: '#005312'
  tertiary-fixed: '#f8d8ff'
  tertiary-fixed-dim: '#ebb2ff'
  on-tertiary-fixed: '#320047'
  on-tertiary-fixed-variant: '#721199'
  background: '#fcf8ff'
  on-background: '#1a1a2e'
  surface-variant: '#e2e0fc'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  display-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 26px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.05em
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  display-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
  display-md-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 22px
    fontWeight: '700'
    lineHeight: 30px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  touch-target-min: 48px
  margin-screen: 20px
  gutter-grid: 16px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 24px
---

## Brand & Style
The design system is engineered for professional foresters and carbon auditors operating in diverse outdoor environments. It balances high-utility "Industrial Minimalism" with a "Modern Corporate" polish inspired by Material 3. 

The brand personality is authoritative yet approachable—evoking a sense of precision, environmental stewardship, and technological sophistication. To ensure usability in high-glare outdoor settings, the UI prioritizes clarity, spaciousness, and high-contrast elements. The aesthetic leverages soft, layered depth and generous rounded corners to reduce cognitive load during complex data entry tasks.

## Colors
This design system utilizes a specialized palette optimized for environmental survey workflows:

- **Primary (Ocean Blue):** Used for core navigation, primary actions, and branding elements.
- **Sustainability (Forest Green):** Reserved for carbon-specific data, growth metrics, and "success" states in the survey process.
- **AI/Experimental (Deep Purple):** Denotes automated tree identification, LIDAR processing, and intelligent analysis features.
- **Stats (Deep Cyan):** Used for data visualization, dashboard summaries, and inventory metrics.
- **Alert (Link Red):** High-visibility red specifically for Bluetooth connectivity issues, hardware sensor errors, and critical data sync warnings.

The light mode background is a cool, desaturated off-white to reduce eye strain, while the text utilizes a deep navy for superior legibility compared to pure black.

## Typography
The system uses **Plus Jakarta Sans** for its exceptional legibility and modern, open letterforms. 

To accommodate outdoor usage, body text is slightly oversized (18px for primary content) to ensure readability at arm's length or while the device is in a mounting bracket. Headlines use a bold weight to establish clear information hierarchy. All labels related to data entry utilize increased letter spacing and medium/bold weights to remain distinct even on lower-quality mobile displays in direct sunlight.

## Layout & Spacing
The layout follows a **Fluid Grid** model with high-density vertical rhythm.

- **Touch Targets:** A strict minimum of 48x48dp is enforced for all interactive elements to facilitate use with field gloves.
- **Margins:** 20px side margins provide a generous safety buffer for thumb navigation and protection against accidental edge-touches.
- **Navigation:** A signature **Floating Bottom Navigation Bar** is used. It should be inset from the screen edges by 12px, creating a distinct "island" that floats above the content.
- **Breakpoints:** The system scales fluidly across Android handsets, with tablet optimizations that introduce a secondary side-rail for data entry when in landscape mode.

## Elevation & Depth
This design system uses a **Tonal Layering** approach combined with **Ambient Shadows** to define hierarchy:

- **Level 0 (Base):** The surface background (`#F5F5FA`).
- **Level 1 (Cards):** Pure white surfaces with a soft, 12% opacity shadow (8px blur, 4px Y-offset) to indicate interactivity.
- **Level 2 (Floating Nav/Modals):** Pure white with a more pronounced 18% opacity shadow (16px blur) and 24px corner radius.
- **Depth Cues:** Gradient overlays are used exclusively on Dashboard cards to signify "Active" or "Critical" metrics, using subtle top-to-bottom linear transitions from primary/secondary colors to white.

## Shapes
The design language is defined by large, friendly, yet professional radii. 

- **Standard Components:** Buttons, input fields, and small chips use a **0.5rem (8px)** radius.
- **Container Elements:** Dashboard cards and list items use a **1rem (16px)** radius.
- **Signature Elements:** The Floating Bottom Navigation Bar and primary Action Buttons (FABs) use a **1.5rem (24px)** radius to create a distinct, modern silhouette that stands out from standard system apps.

## Components
- **Floating Bottom Nav:** A pill-shaped container with active states indicated by a primary-colored pill background behind the icon. 24px corner radius.
- **Dashboard Gradient Cards:** Use a subtle 10% opacity color tint matching the category (Blue for Primary, Green for Stats). Icons inside these cards should sit on a high-contrast circular background.
- **Status Indicators:** "Offline" mode is indicated by a persistent top-bar chip in Neutral Navy. "Syncing" or "Online" uses Sustainability Green.
- **Input Fields:** Large, outlined text fields with a 2px border on focus. Labels must always remain visible (no floating labels that disappear) to assist field workers.
- **Buttons:** Primary buttons use a solid `#0066B3` fill with white text. Secondary buttons use an outlined style with `#2E7D32` to differentiate survey-related actions.
- **Chips:** Used for tree species tagging and quick-filtering. These are rounded (16px) with high-contrast text.
- **AI Camera Interface:** When using the Purple (AI) mode, a dedicated "scanning" frame with a soft purple glow and translucent overlays should be used to signal the experimental nature of the tool.