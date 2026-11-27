# R652 — offline rollback acceptance test

Status: 13/13 PASS on a disposable Linux filesystem, Python 3.13.5.
Scope: a mock configuration with synthetic contents, temporary files,
SHA256 comparison, atomic replacement and fsync. No LG interaction.
This is a test of the rollback model, not an LG installer.

| Test | Result |
| --- | --- |
| Round-trip restoration | PASS |
| Backup bytes unchanged | PASS |
| File mode retained | PASS |
| Repeated rollback | PASS |
| Missing backup rejected | PASS |
| Duplicate backup rejected | PASS |
| Damaged backup before switch rejected | PASS |
| Damaged backup after switch rejected | PASS |
| Unexpected active contents before switch preserved | PASS |
| Unexpected active contents after switch preserved | PASS |
| Symlink backup rejected | PASS |
| Simulated interruption before replacement during switch | PASS |
| Simulated interruption before replacement during rollback; retry restores baseline | PASS |

Actual test runner output: Ran 13 tests in 0.034s; OK.

Limitations: interruption was simulated by exceptions, not power loss.
No live webOS service, real configuration, actual installed generation,
ownership/ACL/xattrs, concurrent writers, real reboot, hardware audio,
or on-device rollback tested. No production installation authorized.
The R650 Linux-lab package manager remains separate from the mock model.
Do not use the inherited R278/R352 installer as a R650 updater.
TV_INSTALL_ALLOWED=NO.
