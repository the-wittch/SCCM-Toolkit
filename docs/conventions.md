# How we keep this from turning into a junk drawer

## One package, one folder

Don't mix three products in one directory. Future You is tired.

```
drivers/Realtek-USB-NIC-8153/
  detection/Detect-DriverStore.ps1
  install/Install-Driver.ps1
  uninstall/Uninstall-Driver.ps1
  source/README.md
```

Vendor driver packs do **not** go in git. Put a note in `source/README.md` pointing at the content library path. Disk is cheap. Git history filled with `.cab` files is not.

## Script headers — tell the next person what they're looking at

At the top of anything that runs on a client, leave:

1. What it does (detect / install / uninstall — pick one job)
2. Who it runs as (SYSTEM vs user)
3. Exit codes
4. The knobs they need to turn (HWIDs, versions, paths) up near the top

If someone has to read 200 lines to find the one variable that matters, failed.

## Shared code

Copy/paste is fine twice. Third time, extract it to `shared/functions/` and stop lying to yourself that "this one's different." If it gets bigger than a couple helpers, make a module under `shared/modules/`.
