# UI++ binaries live on the share, not in git

Drop these next to your config XML in the ConfigMgr package (or prestart folder):

| File | Notes |
|------|--------|
| `UI++64.exe` / `UI++.exe` | Match WinPE / Windows arch |
| `FTWldap64.dll` / `FTWldap.dll` | Same folder as the EXE |
| `FTWCMLog64.dll` / `FTWCMLog.dll` | Same folder as the EXE |

Get UI++ from Jason Sandys / the official UI++ distribution. Don’t commit the binaries.

**Content library path (fill me in):**

```
\\fileserver\sources\OSD\UI++\
```
