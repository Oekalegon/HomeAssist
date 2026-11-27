# HomeAssist app design

Status: **proposal**, agreed in outline with the owner. Update this doc in the same PR as any change
to what a screen shows or how it behaves.

## Goals

- Daily use is fast: switch a light or check the temperature in one tap.
- Most-used devices are **lights, climate and sensors**; their controls come first.
- iPhone first. Works in light and dark mode, with Dynamic Type and VoiceOver.

## Navigation

A bottom **tab bar** with two tabs. A gear button in each tab's toolbar opens **Settings** as a sheet
(server, connection status, disconnect).

```
┌──────────────────────────┐
│ Favourites          ⚙ ⚡ │
│                          │
│  CLIMATE                 │
│  ┌────────────────────┐  │
│  │ Living room   21.5°│  │
│  │ Heating → 22.0°    │  │
│  └────────────────────┘  │
│  LIGHTS                  │
│  ┌───────┐ ┌───────┐     │
│  │ 💡 Desk│ │ 💡 Lamp│    │
│  │ On 80% │ │ Off    │    │
│  └───────┘ └───────┘     │
│  SENSORS                 │
│  ┌──────┐ ┌──────┐       │
│  │ 19.8°│ │ 54 % │       │
│  └──────┘ └──────┘       │
├──────────────────────────┤
│   ★ Favourites   ▦ Rooms │
└──────────────────────────┘
```

## Favourites tab

- Entities the user pinned, shown in sections in this order: **Climate**, **Lights**, **Sensors**,
  then **Other** (switches, covers, …). Empty sections are hidden.
- Order within a section is the user's own; **Edit** mode reorders and removes.
- Empty state: "No favourites yet. Press and hold any device and choose Add to Favourites."
- Storage: a local ordered list of entity IDs (`UserDefaults`). An ID whose entity no longer exists
  is hidden, not deleted, in case the entity comes back.

## Rooms tab

- A grid of **room cards** built from Home Assistant **areas**. Each card shows the room name, an
  icon, and a one-line summary: lights on, current temperature ("2 lights on · 21.5°").
- Rooms are sorted by name. Entities without an area go in a final **Unassigned** room.
- Tapping a room pushes the **room detail**: the same section layout as Favourites (Climate, Lights,
  Sensors, Other) for that room's entities. A search field filters by name.

### Where rooms come from

The REST states list has no room information. The app asks the WebSocket API for three registries
after connecting: `config/area_registry/list`, `config/device_registry/list` and
`config/entity_registry/list`. An entity's room is its own `area_id`, else its device's `area_id`.
Entities that are `hidden_by` or `disabled_by` something are not shown.

Open risk: the `config/*` commands may require an **admin** user. If the call fails, rooms fall back
to a single **Unassigned** room and the list stays usable. To be checked against the real server.

## Tiles and interaction

**Tap toggles, press-and-hold opens details** for anything that can be switched. Climate and sensors
have nothing to toggle, so a tap opens their details.

| Entity | Tile shows | Tap | Press and hold |
|---|---|---|---|
| Light | icon tinted with the light's colour, name, "On 80%" / "Off" | toggle | detail sheet |
| Switch / fan / input_boolean | icon, name, on/off | toggle | detail sheet |
| Climate | current temperature, target, mode | detail sheet | detail sheet |
| Sensor | value with unit, name | detail sheet | detail sheet |
| Cover, lock, media player | icon, name, state | detail sheet | detail sheet |

- A tile never shows a state the server has not confirmed: after a tap it stays as it was until the
  live `state_changed` event arrives (a small spinner shows meanwhile). Failures show an inline message.
- Unavailable entities are dimmed and not tappable.

## Detail sheet

A medium/large sheet opened from any tile.

- **Light:** on/off, brightness slider, colour temperature slider, colour picker when supported.
- **Climate:** large current temperature, target with − / + buttons, mode picker (heat, cool, off, …).
- **Sensor:** current value and a 24-hour history chart (Swift Charts, from `/api/history/period`).
- **Everything:** **Add to / Remove from Favourites**, the room, and a collapsible attributes list.

Controls call domain services (`light.turn_on`, `climate.set_temperature`, …) and wait for the live
state, like tiles do.

## Visual style

- Native SwiftUI: system materials, SF Symbols (chosen from domain and `device_class`), rounded
  tiles, the system accent colour. Light tiles use the light's own colour when on.
- State is never conveyed by colour alone: tiles also say "On"/"Off" in text.
- Every tile is one VoiceOver element: "Desk lamp, light, on, 80 percent", with the toggle as its
  default action and the detail sheet as a custom action.

## Data and architecture

- `AppModel` keeps the entity list and live connection (as today).
- New: `RegistryStore` (areas, devices, entity→area map), `FavouritesStore` (ordered IDs), and pure,
  tested view-model helpers that group entities by section and by room. Views stay thin.
- New: typed wrappers for the entities we render (`LightState`, `ClimateState`, `SensorState`) decoded
  from `HAEntity` attributes, so views don't poke at raw attribute dictionaries.

## Build order (one PR each, into `develop`)

1. Tab bar shell, tile components, **Favourites** tab with pin/unpin and edit mode.
2. Registries over WebSocket and the **Rooms** tab and room detail.
3. **Detail sheets** for lights and climate.
4. Sensor history chart.
5. Settings sheet; polish (empty states, error states, accessibility pass).

## Open questions

- Should Settings be a third tab instead of a toolbar sheet?
- iPad: a sidebar layout later, or just scale up the iPhone layout?
- Should favourites be stored on the server (so they follow the user to other devices) rather than
  only on the phone?
