# Service repairs

The service window now opens a component repair selection before the existing setup/tire garage. Initial rally setup skips repairs. Only damaged components are listed; selected entries are fully repaired. Tires and rims remain exclusively in the tire inventory.

Default allowance: 30 minutes. Every started minute beyond the allowance adds 10 seconds to the following stage's official player penalty. Window fields `repair_minutes` and `repair_penalty_seconds_per_minute` override these defaults. Component full-damage labor times are in `RallyServicePanel.PARTS`; actual labor rounds damage-proportional minutes upward (minimum one minute). Each brake and alignment component is listed separately. Brake repair restores both collision damage and natural wear. Body, hood, trunk, windshield and headlights are separately repairable.

Confirmation applies selected repairs and persists the updated vehicle, penalty and service-window key before opening setup. This prevents applying the same service again on resume. Unselected damage is retained. Penalties are stored by stage in the event save and incorporated into the official stage result, rather than the stopwatch or resettable stage simulation.

Reference inspection: D:/open-cmr2-rust/OpenCMR2/game, including GameMenus.cpp, FrontendMenus.cpp and RallyTiming.cpp. This source tree does not expose a repair-selection implementation found by repair/service searches. The above labor times and penalty tariff are project defaults, not verified CMR2 constants.

No tests or gameplay validation were executed, as requested by the user.
