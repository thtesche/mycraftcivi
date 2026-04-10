# myCraftCivi

A Voxel-Based Survival & Civilization Builder powered by the **Luanti** engine.

## Overview

myCraftCivi is a game that focuses on the evolution from a primitive survival experience to a sophisticated civilization. It leverages the robust and extensible Luanti (formerly Minetest) engine to provide a rich voxel world.

## Key Features

- **Civilization Growth**: Progress from basic crafting to advanced infrastructure.
- **Dynamic Physics**: Blocks like Asphalt provide speed boosts to simulate roads.
- **Advanced Movement**: Includes double-tap sprinting, sneaking, and multiple camera perspectives (1st/3rd person).
- **Rich Resources**: Mine for Coal, Iron, Copper, and Gold to fuel your progress.
- **Standalone Experience**: Built as a custom Luanti game without external dependencies on `minetest_game`.

## Technical Stack

- **Engine**: [Luanti](https://www.luanti.org/)
- **Logic**: Lua
- **Rendering**: Irrlicht/Mt-Engine
- **Persistence**: SQLite/LevelDB

## Getting Started

1. Ensure you have the [Luanti](https://www.luanti.org/downloads/) engine installed.
2. Clone this repository into your Luanti `games` folder.
3. Select `myCraftCivi` in the game selection menu and create a new world.

## Documentation

For a detailed vision of the game, check out [idea.md](idea.md).
Check our current progress in [walkthrough.md](.gemini/antigravity/brain/ad74221a-1857-4b90-8435-bf7581b40bf2/walkthrough.md).

## License & Attribution

- **Code**: Licensed under LGPLv2.1.
- **Media (Textures & Sounds)**: Licensed under CC BY-SA 3.0.

Many assets (sounds and textures) are derived from the [Minetest Game](https://github.com/minetest/minetest_game) project. We gratefully acknowledge the contributions of the Minetest development community. Detailed attribution for each component can be found in the `license.txt` files within individual mod directories (e.g., `mods/civi_core/license.txt`).
