# hid-nintendo fix for Switch Pro Controller clones (Trekpleister GAM 25004)

Two cheap Bluetooth controllers sold as Nintendo Switch pads identify as a
Pro Controller (`0005:057E:2009`, name "Pro Controller", a byte-for-byte copy
of the real HID report descriptor). The mainline `hid-nintendo` driver binds
them and then fails:

    nintendo 0005:057E:2009.0001: Failed to get joycon info; ret=-110
    nintendo 0005:057E:2009.0001: probe - fail = -110

With the module blacklisted they work as plain `hid-generic` gamepads, without
the driver's full report mode, calibration, LEDs, IMU and rumble.

## Root cause

The clone firmware validates every output report and silently drops any that
fails. The driver's probe-time subcommands fail on two counts:

1. **Length.** `joycon_hid_send_sync()` sends the minimal frame (11 bytes for
   subcommand 0x02) while the descriptor declares a 48-byte payload. The
   console always sends full-size reports, which is why the pads work on a
   Switch.
2. **Rumble bytes.** Every subcommand carries 8 rumble bytes taken from
   `ctlr->rumble_data`, which is zero-allocated and only filled by the first
   `joycon_set_rumble()` after init (never with `CONFIG_NINTENDO_FF=n`). An
   all-zero rumble field is not a valid encoding and the clone rejects the
   frame.

Either defect alone keeps the pad silent. Once one full-size report with valid
rumble bytes has been accepted, the pad also accepts short frames and zero
rumble, which made earlier "works after wake-up" observations confusing.

Established by replaying the driver's exact traffic from userspace over
`/dev/hidrawN` on freshly connected pads: the kernel-exact request got no
answer twice; the same request padded to 49 bytes with the neutral rumble
pattern `00 01 40 40 00 01 40 40` was answered within 55 ms; padded with zero
rumble bytes it was ignored.

## Fix

`patches/pad-and-neutral-rumble.patch` (two hunks against
`kernel-src/hid-nintendo-6.18.c`, also applies to mainline):

- `__joycon_hid_send()`: zero-pad every output report to `hid_report_len()` of
  the matching output report (49 bytes over Bluetooth, 64 over USB).
- `nintendo_hid_probe()`: preload the rumble queue with the neutral pattern,
  which is what `joycon_encode_rumble()` produces for 160/320 Hz at
  amplitude 0.

Genuine controllers already receive full-size reports from the console and
accept both forms. With the fix a cold clone probes in ~350 ms: device info,
calibration reads, IMU enable, report mode 0x30, player LEDs; gamepad and IMU
input devices appear; rumble works through the evdev force-feedback interface.

`patches/superseded/` keeps two earlier iterations (padding only; padding plus
a long retry loop) for reference. Do not apply them.

## Building

Manual out-of-tree build against the running kernel:

    cd module && make

DKMS, rebuilt automatically on kernel updates:

    sudo ./dkms/install-dkms.sh

The DKMS tree (`dkms/hid-nintendo-clonefix-<version>/`) installs to
`/lib/modules/<ver>/updates/dkms/`, which depmod prefers over the in-kernel
module. `Kbuild` adds `-DCONFIG_NINTENDO_FF=1` so rumble is available even on
kernels built without it (needs `ff-memless`, which most distro kernels ship).

### Compiler mismatch (Armbian, arm64)

The target kernel was built with gcc 14 while the distro's default gcc is 13,
which lacks `-fmin-function-alignment`. Dropping that flag to make gcc 13
compile is **not** safe on arm64: with `DYNAMIC_FTRACE_WITH_CALL_OPS` the
kernel requires strictly aligned function entries and BUGs at module load
("Misaligned patch-site", `arch/arm64/kernel/patching.c`). `dkms-build.sh`
therefore reads the kernel's real compiler from `include/config/auto.conf`
(the shipped `.config` may have been rewritten with the host gcc) and uses the
matching `gcc-<major>` when installed; otherwise it builds with
`CONFIG_CC_HAS_MIN_FUNCTION_ALIGNMENT=` **and** `NO_FTRACE=1`, which removes
`$(CC_FLAGS_FTRACE)` so the module has no patch sites at all. Installing the
matching gcc is the better option.

## Known quirks of these pads (not fixed)

- The "SPI flash" is a lookup table: only a few block addresses return data.
  The driver's user-calibration reads at 0x8012/0x801D return zeros, the
  plausibility check fails and default stick calibration is used (a few
  percent off-centre, full deflection reached early). The IMU calibration
  block is fine.
- The pad stops streaming 0x30 reports when idle and resumes on input. The
  driver's strict subcommand rate limiter then logs "timeout waiting for input
  report" until it falls back to its legacy throttle.
- Report cadence is bursty (~200 Hz), so "compensating for N dropped IMU
  reports" debug lines are normal.

## Layout

    kernel-src/   pristine reference sources (v6.18 base, mainline snapshot, hidp)
    patches/      the fix as a diff, plus superseded iterations
    module/       patched v6.18 source with a Makefile for manual builds
    dkms/         DKMS tree, compiler-aware build wrapper, install script
