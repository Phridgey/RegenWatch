# RegenWatch

A World of Warcraft 1.12 addon that puts one number on screen: the health your
last regeneration tick actually gave you. It's built to see how much regen a
character gets from Spirit, the Troll racial and similar, measured rather than
calculated.

- **Green** while out of combat, **orange** in combat, **grey** when no tick has
  come for a few seconds (full health, or regeneration stopped).
- Heals, potions, bandages and food that appear in your combat log are taken
  off, so the number is your own regeneration only.
- Hover over the number to see your average per tick, and per second, out of
  combat and in combat.
- A tick that tops you off at full health is cut short, so it is left out of
  the averages.

## Install

Copy the `RegenWatch` folder into `Interface\AddOns`, then log out to the
character screen once so the game picks it up.

## Commands

- `/regen`: show or hide the number
- `/regen reset`: clear the averages
- **Shift-drag** the number to move it (a plain click or drag does nothing, so
  it can't be knocked out of place by accident).

## How it works

The game regenerates health every 2 seconds. Every rise in your health is
collected into a tick. Heals on you from the combat log (around the same
moment) are subtracted, and whatever is left counts as regeneration.

## Limits

Only heals that show up in your combat log can be subtracted. A heal cast from
very far away may not appear there, and would then count as regeneration.
