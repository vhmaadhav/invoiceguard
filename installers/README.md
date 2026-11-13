# Oracle installers (not in git)

Everything in this folder except the README and `.dockerignore` is gitignored. You download the
files yourself: Oracle requires an account and licence acceptance, which this project never does.

## Required files

| File | Size (approx.) | Where to get it |
|---|---|---|
| `fmw_14.1.2.0.0_fr_linux64.bin` | 1.4 GB | Forms and Reports 14.1.2.0.0 for Linux x86-64, eDelivery zip `V1045121-01.zip`: <https://www.oracle.com/middleware/technologies/forms/downloads.html> |
| `fmw_14.1.2.0.0_infrastructure.jar` | 2.1 GB | Fusion Middleware Infrastructure 14.1.2.0.0, eDelivery zip `V1045135-01.zip`. Also listed on the WebLogic Server installers page as "Fusion Middleware Infrastructure Installer" under 14.1.2.0. |
| `jdk-21.0.8_linux-x64_bin.tar.gz` | 0.2 GB | Oracle JDK 21.0.8, no login: <https://download.oracle.com/java/21/archive/jdk-21.0.8_linux-x64_bin.tar.gz> |

The Infrastructure and Forms installers reject OpenJDK, so the image uses Oracle's JDK 21.0.8.

## Zips or extracted files

`scripts/forms_up.sh` accepts either form:

* The eDelivery zips `V1045135-01.zip` and `V1045121-01.zip` as downloaded. The script extracts the
  `.jar` and `.bin` once into this folder, next to the zips, and keeps the zips.
* The extracted `fmw_14.1.2.0.0_infrastructure.jar` and `fmw_14.1.2.0.0_fr_linux64.bin` directly.

The JDK tarball is always used as downloaded. Names must match exactly; the Dockerfile and
`scripts/forms_up.sh` depend on them.

## Checking

`scripts/forms_up.sh` lists missing files and exits with code 2. It does not check checksums.

See `docker/forms/README.md` for the build and the fixes that depend on these installers.
