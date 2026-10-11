# Honor OEMINFO

It's a storage (partition `/dev/block/by-name/oeminfo`) where Honor stores additional data.

## Security status SAFE/RISK

When you running `hwnff get_security_status` you can see the next picture:
```
$ adb -s AWRT026122000810 exec-out 'hwnff get_security_status'
status        : SAFE
version       : v2.4.1
current status: SAFE
old status    : SAFE
change time   : Wed Oct  7 00:09:28 2026
details:
item: verifyboot, status: SAFE, old status: SAFE, category: integrity, credible: N, risk time: NA
item: verity-enable, status: SAFE, old status: SAFE, category: integrity, credible: Y, risk time: NA
item: key-files, status: SAFE, old status: SAFE, category: integrity, credible: Y, risk time: NA
item: verified-state, status: SAFE, old status: SAFE, category: integrity, credible: Y, risk time: NA
item: fblock, status: SAFE, old status: SAFE, category: integrity, credible: Y, risk time: NA
item: userlock, status: SAFE, old status: SAFE, category: integrity, credible: Y, risk time: NA
item: check-su, status: SAFE, old status: SAFE, category: integrity, credible: Y, risk time: NA
item: eima, status: SAFE, old status: SAFE, category: integrity, credible: N, risk time: NA
item: kcode, status: SAFE, old status: SAFE, category: integrity, credible: N, risk time: NA
item: kcode-syscall, status: SAFE, old status: SAFE, category: integrity, credible: Y, risk time: NA
item: se-hook, status: SAFE, old status: SAFE, category: integrity, credible: N, risk time: NA
item: mrcinfo, status: SAFE, old status: SAFE, category: integrity, credible: N, risk time: NA
item: root-prop, status: SAFE, old status: SAFE, category: root, credible: Y, risk time: NA
item: sysrw, status: SAFE, old status: SAFE, category: root, credible: Y, risk time: NA
item: setids, status: SAFE, old status: SAFE, category: root, credible: Y, risk time: NA
item: se-enforcing, status: SAFE, old status: SAFE, category: root, credible: Y, risk time: NA
item: root-procs, status: RISK, old status: SAFE, category: root, credible: N, risk time: Wed Oct  7 00:09:28 2026
```

But once you starting ghostlock root - it will quickly change to:
```
status        : RISK
version       : v2.4.1
current status: RISK
old status    : RISK
...
item: kcode-syscall, status: RISK, old status: SAFE, category: integrity, credible: Y, risk time: Sat Sep  5 18:11:04 2026
```

And even after reboot back to stock it will haunt you. To restore - you usually can do factory
reset, but this will clean up your data. So instead you can just replace the oeminfo data:
```
-| 12 | 7 | DEBUG_LOCK_POLICY | RAW | True | 3584 | '\x00\x00\x00\x00\x01\x00\x00\x00 \x1a\xc9j\x00\x00\x00\x00\x12\x00\x00\x00\x00\x00\x00\x00\x00\x0...' |
+| 12 | 7 | DEBUG_LOCK_POLICY | RAW | True | 3584 | '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x12\x00\x00\x00\x00\x00\x00\x00\...' |
```

For simplicity - you can dump the oeminfo partition while it's in SAFE state and reapply it once
it become RISK, or use the `oeminfo_*` tools from https://github.com/rabits/honor-tools to change
the value of the current RISKy oeminfo back to SAFE.
