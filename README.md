# Half Sword Save Recovery

Move selected progress from an old or bloated Half Sword save into a fresh save. This Windows batch script works directly with `.sav` files using built-in PowerShell. No UeSaveConverter or JSON export is needed.

## Quick start

1. Back up your old save. Start a fresh game, play a quick battle, then quit Half Sword.
2. Put `Restore Half Sword Save.bat` and copies of both saves in the same folder. Use different filenames for the saves.
3. Run the batch file. Enter the old save under **Restore FROM**, the fresh save under **Restore TO**, and the total gold you want. The defaults are `gsc.sav`, `GameProgress.sav`, and `12,000` gold.
4. After verification, the script updates the destination and keeps a timestamped copy of its previous contents. With Half Sword closed, copy the restored file to `%LOCALAPPDATA%\HalfSwordUE5\Saved\SaveGames\GameProgress.sav`.

## What gets restored

- Height, weight, and fat
- Day count and Baron defeats
- Player tier, permanent tier, and rank reputation
- Insured weapons and armor

The source insurance list replaces the destination’s list. The destination keeps its character name, equipped gear, and regular inventory. Reclaim restored insured gear at the trader.

If you need to roll back, use the timestamped backup. Keep your personal `.sav` files and backups out of the repository.


## Compatibility

Tested on Windows with Half Sword progression saves using Unreal's GVAS v3 layout. The exact Half Sword game version was not recorded. Migrating to a fresh save resolved menu lag in the original test. Results may vary with the save and game version.

## Download

Get the latest version from the [Releases page](../../releases/latest) and extract the ZIP before running the batch file.

## License

[MIT](LICENSE)
