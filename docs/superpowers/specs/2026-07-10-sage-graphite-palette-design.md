# Sage Graphite Palette Design

## Goal

Replace the cool blue default theme with the approved "Sage Graphite" palette while preserving the existing compact layout, display modes, animations, task navigation, and refresh behavior.

## Visual Direction

The floating window should feel neutral, mature, and quiet enough to remain visible throughout the workday. A solid graphite-tinted background replaces the translucent blue-white surface so desktop content cannot bleed through. Muted sage is used for normal quota capacity and controls, while ochre and brick red remain reserved for warning states.

The palette must avoid a one-color appearance. Neutral graphite defines the structure, sage communicates healthy capacity, ochre communicates attention, and brick red communicates urgency.

## Color Tokens

| Role | Hex | Calibrated RGB | Usage |
| --- | --- | --- | --- |
| Window background | `#F2F3EF` | `0.949, 0.953, 0.937` | Expanded and capsule window surfaces |
| Card surface | `#FAFBF8` | `0.980, 0.984, 0.973` | Meter cards and activity capsule tint base |
| Card border | `#D9DCD5` | `0.851, 0.863, 0.835` | Low-contrast component boundaries |
| Progress track | `#E4E7E1` | `0.894, 0.906, 0.882` | Inactive bar and gauge tracks |
| Primary text | `#292D2A` | `0.161, 0.176, 0.165` | Title, percentages, capsule quota values |
| Secondary text | `#646E65` | `0.392, 0.431, 0.396` | Meter names and activity labels |
| Tertiary text | `#818880` | `0.506, 0.533, 0.502` | Reset timestamps |
| Control tint | `#68796A` | `0.408, 0.475, 0.416` | Header icon buttons |
| Healthy quota | `#758B74` | `0.459, 0.545, 0.455` | Remaining quota at 50% or above |
| Warning quota | `#C7953D` | `0.780, 0.584, 0.239` | Remaining quota from 20% through 49% and working status |
| Critical quota | `#C8605C` | `0.784, 0.376, 0.361` | Remaining quota below 20% and waiting status |
| Completed status | `#4F9870` | `0.310, 0.596, 0.439` | Completed activity state |
| Idle status | `#868D86` | `0.525, 0.553, 0.525` | Idle and unknown activity states |

## Component Application

- Rename the default visual style from `creamBlue` to `sageGraphite` so the code reflects the visible design.
- Apply the palette to both compact bars and circular gauges.
- Apply the same window background and text hierarchy to the collapsed capsule so expanding and collapsing feels visually continuous.
- Keep the existing minimalist gray theme available through the palette button.
- Keep quota thresholds unchanged: healthy at 50% or above, warning from 20% through 49%, and critical below 20%.
- Keep activity status backgrounds derived from each semantic status color at the existing low alpha values.

## Interaction And Data

No interaction or data-flow behavior changes. Auto refresh remains once per minute, manual refresh remains available, activity polling remains once per second, and clicking the activity capsule continues to open the active task menu.

## Testing

- Update source-level style tests to assert the new calibrated RGB values and the renamed visual style.
- Run the complete Node test suite and Swift model tests.
- Build and ad-hoc sign the native macOS application.
- Launch one app instance and visually inspect both expanded display modes plus the collapsed capsule for hierarchy, contrast, consistency, and clipping.

## Success Criteria

- No blue accent remains in the default theme.
- Healthy, warning, and critical quota levels are immediately distinguishable without making the window visually loud.
- Text remains readable against all default-theme surfaces.
- Desktop content does not remain legible through the window or meter cards.
- Layout, window dimensions, controls, animations, and refresh behavior remain unchanged.
