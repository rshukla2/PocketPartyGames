# React-to-Flutter parity

The previous untracked AI Studio React/Vite application was replaced, not embedded. Flutter now owns every screen and all Android, iOS, and web output.

Preserved:

- Eight game families and their local modes, scoring, timers, pass-the-phone reveals, setup choices, summaries, and results.
- All migrated prompt text, including Bold Truth or Dare content.
- Roster constraints (0–20 stored players, unique 1–16-character names, eight colors) and sound/haptic preferences. Individual multiplayer modes enforce their own minimums.
- Full-bleed game palettes, party presentation, safe-area layout, and large controls.

Corrected:

- Solo Timer persists consistent `attempts`, `bestErrorMs`, `nearPerfectCount`, and a 50-entry history.
- Routes are unique and onboarding covers all eight games.
- Marketing uses measured data counts: 1,300 / 200 / 194 / 420 / 316 / 231.
- Nearby claims are shown only where a native implementation exists; web is explicitly single-device.
- Truth or Dare now tracks two swaps, one free skip, and active/quit state independently for every player.
- Buzzer Battle now uses sequential private attempts and first-to-points scoring; Timer Imposter now supports multiple imposters, False Target/No Target secrets, hidden attempts, and voting.

The former source had 194 drawing prompts and 420 acting prompts, despite older copy claiming 203 and 431. The repository preserves the actual source corpus rather than fabricating missing items.
