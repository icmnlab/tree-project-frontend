---
name: Forest Intelligence
colors:
  surface: '#f8f9ff'
  surface-dim: '#d9dadf'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f9'
  surface-container: '#ededf3'
  surface-container-high: '#e7e8ee'
  surface-container-highest: '#e1e2e8'
  on-surface: '#191c20'
  on-surface-variant: '#424750'
  inverse-surface: '#2e3035'
  inverse-on-surface: '#f0f0f6'
  outline: '#727781'
  outline-variant: '#c2c7d1'
  surface-tint: '#24609e'
  primary: '#003765'
  on-primary: '#ffffff'
  primary-container: '#004e8b'
  on-primary-container: '#91c0ff'
  inverse-primary: '#a2c9ff'
  secondary: '#1b6d24'
  on-secondary: '#ffffff'
  secondary-container: '#a0f499'
  on-secondary-container: '#207128'
  tertiary: '#5a007c'
  on-tertiary: '#ffffff'
  tertiary-container: '#781b9f'
  on-tertiary-container: '#e7a5ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d3e4ff'
  primary-fixed-dim: '#a2c9ff'
  on-primary-fixed: '#001c38'
  on-primary-fixed-variant: '#004881'
  secondary-fixed: '#a3f69c'
  secondary-fixed-dim: '#87d982'
  on-secondary-fixed: '#002204'
  on-secondary-fixed-variant: '#005312'
  tertiary-fixed: '#f8d8ff'
  tertiary-fixed-dim: '#ebb2ff'
  on-tertiary-fixed: '#320047'
  on-tertiary-fixed-variant: '#721199'
  background: '#f8f9ff'
  on-background: '#191c20'
  surface-variant: '#e1e2e8'
typography:
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 28px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
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
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  screen-margin: 20px
  gutter: 16px
  touch-target-min: 48px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 24px
---

## Brand & Style
The design system for this product is built on the philosophy of **Industrial Minimalism**. It is designed specifically for foresters and carbon auditors working in demanding outdoor environments. The aesthetic balances the rigorous structure of Material 3 with the clarity required for high-glare visibility.

The personality is **authoritative, reliable, and functional**. It avoids unnecessary ornamentation, focusing instead on information density that remains legible under sunlight. The interface evokes a sense of "digital precision in a natural world," blending deep industrial blues with organic greens to bridge the gap between technology and the field.

## Colors
This design system utilizes a high-contrast palette optimized for legibility. The **Primary Ocean Blue** serves as the anchor for core actions and navigation, while **Forest Green** is reserved for environmental data and success states. **Deep Purple** is a functional accent used specifically for AI-driven features like species identification. 

Neutral surfaces use a cool off-white to reduce eye strain, while text is set in a deep navy rather than pure black to maintain a sophisticated, industrial feel. High-visibility overrides (Deep Cyan) are used for statistical data to distinguish it from interactive primary elements.

## Typography
The typography is centered around **Plus Jakarta Sans**, chosen for its modern, geometric clarity and excellent legibility in Traditional Chinese (zh-TW) contexts. 

- **Headlines:** Always bold (`700`) to create a strong visual hierarchy.
- **Body Text:** Standardized at `18px` for the primary reading level to ensure readability during field movement.
- **Labels:** Use a slightly tighter tracking and heavier weight (`600`) to differentiate meta-data from body content.
- **Language:** All UI strings must use Traditional Chinese (zh-TW) glyphs, ensuring character balance is maintained across dense data tables.

## Layout & Spacing
This design system follows a strict grid-based layout to ensure consistency across various mobile devices.

- **Margins:** A generous `20px` screen margin prevents content from being obscured by rugged phone cases or thumbs.
- **Touch Targets:** A minimum height/width of `48px` is mandatory for all interactive elements to accommodate gloved hands or shaky field conditions.
- **Rhythm:** An 8px base unit drives all spacing. The layout is fluid within the 20px margins, utilizing a 4-column structure for mobile displays.
- **Status Chip:** A persistent chip sits at the top of the interface to show connectivity status (e.g., "離線" or "已連線").

## Elevation & Depth
Depth is used functionally to separate persistent navigation from transient data surfaces.

- **Base Layer:** The background is `#FCF8FF`.
- **Surface Layer (Cards):** White cards use a soft `12%` shadow with an `8px` blur. This provides enough contrast to lift data points without creating visual "noise."
- **Overlay Layer (Modals & Nav):** Floating components, including the signature bottom navigation, use a more pronounced `18%` shadow with a `16px` blur to signal their priority in the hierarchy.
- **Focus States:** Focused inputs use a `2px` solid border in the Primary color rather than a shadow, maintaining the "Industrial" look.

## Shapes
The shape language is tiered based on the component's role:

- **Interactive Elements:** Buttons, input fields, and small chips use an `8px` radius for a crisp, professional look.
- **Information Containers:** Data cards and list items use a `16px` radius to soften the layout and group related information clearly.
- **System Level Elements:** The floating bottom navigation bar and Floating Action Buttons (FAB) use a `24px` "Pill" radius to emphasize their distinct, "floating island" nature.

## Components
- **Buttons:**
  - *Primary:* Solid `#0066B3` with white text. High-contrast and bold.
  - *Secondary:* Outlined in Forest Green (`#1B6D24`) for additive or non-destructive actions.
- **Navigation (Floating Island):** A pill-shaped nav bar inset `12px` from the screen edges. Active states are indicated by a primary-colored pill background behind the icon.
- **Input Fields:** Outlined style with `#717782`. Labels are always visible (never hidden as placeholders) to ensure context is never lost during data entry.
- **Chips:** `16px` roundedness. Used for filtering species or audit status.
- **Status Chip:** Positioned at the top of the screen; "離線" (Offline) in Navy/Light-Grey; "已連線/同步中" (Online/Syncing) in Forest Green.
- **Lists:** High-density list items with a `16px` radius container, featuring a clear `16px` gutter between items for easy tapping.