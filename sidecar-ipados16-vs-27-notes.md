# Sidecar iPadOS 16 vs 27 Static Comparison

Compared local IPSWs:

- `iPad_Spring_2022_16.1.1_20B101_Restore.ipsw`
- `iPad_Spring_2022_27.0_24A5370h_Restore.ipsw`

Both target iPad Air 5 / M1 (`iPad13,16` / `iPad13,17`).

## High-signal findings

- `Applications/Sidecar.app/PlugIns/ContinuityDisplay.appex/ContinuityDisplay` is the main iPad-side display/input target in both versions.
- iPadOS 16 already has `TouchController`, `SidecarHID`, `MultitouchReport`, `TouchReport`, `PencilReport`, `TouchTracker`, and `allowFingerTouches`.
- iPadOS 27 adds/expands the HID path rather than adding touch support from nothing.
- New iPadOS 27 strings/fields include:
  - `supportsNativeTouches`
  - `supportsMacOSCompatibleTouchReports`
  - `peerSupportsHIDReportExtensions`
  - `SqueezeGestureReport`
- iPadOS 27 adds `peerSupportsHIDReportExtensions` fields to:
  - `ContinuityDisplay.SidecarDisplaySession`
  - `ContinuityDisplay.HIDEventObserver`
- iPadOS 27 expands `SidecarHID.TouchReport.Contact` with:
  - `identity`
  - `swipePending`
  - `swipeLocked`
  - `swipeUp`
  - `swipeDown`
  - `swipeLeft`
  - `swipeRight`
  - `cancel`
- iPadOS 27 adds a new hidden app, `Applications/ScreenContinuityShell.app`, with bundle id `com.apple.ScreenContinuityShell`. It has private `RemoteDisplay`, HID event-dispatch/admin, SessionKit, and ScreenContinuity service entitlements. It looks related to the newer Screen Continuity system, but the direct Sidecar display/touch code still appears to live in `ContinuityDisplay.appex`.

## Packet constants from disassembly

From `work/27-disass-touchreport-init.txt` and related snippets:

- `SidecarHID.TouchReport.reportID` returns `0x05`.
- `SidecarHID.TouchReport.version1ByteCount` returns `0x17`.
- `SidecarHID.TouchReport.version2ByteCount` returns `0x19`.
- `SidecarHID.TouchReport.version3ByteCount` returns `0x1b`.
- `SidecarHID.TouchReport.init()` initializes a `0x1b`-byte report with report ID `0x05`.
- `SidecarHID.PencilReport.version1ByteCount` returns `0x13`.
- `SidecarHID.PencilReport.version2ByteCount` returns `0x15`.
- `SidecarHID.SqueezeGestureReport.reportID` returns `0x07`.

## Interpretation

The most plausible backport target is not a new pairing/auth handshake. It is the iPadOS 27 `ContinuityDisplay` HID-report extension path.

The likely feature gate is a capability/config value that sets `peerSupportsHIDReportExtensions` and/or maps host capabilities into `supportsNativeTouches` / `supportsMacOSCompatibleTouchReports`. Once enabled, the iPadOS 27 client can emit a newer `TouchReport` format over the existing `com.apple.sidecar.hid` stream.

For an iOS 16 tweak, the first useful experiment should be:

1. Hook `ContinuityDisplay.appex`.
2. Trace `ContinuityDisplay.TouchController` and `ContinuityDisplay.HIDEventObserver`.
3. Trace writes on `ContinuityDisplay.DisplayHIDDevice`.
4. Force/log `allowFingerTouches`.
5. Try emitting v1 `TouchReport` report ID `0x05` from finger touches.
6. If macOS 27 ignores v1, recreate the iPadOS 27 v3 `0x1b` touch report layout.

Useful generated artifacts:

- `work/16-continuitydisplay.strings`
- `work/27-continuitydisplay.strings`
- `work/27-continuitydisplay-swift-dump.txt`
- `work/27-disass-touchreport-init.txt`
- `work/16-disass-touchreport-init.txt`
- `work/27-disass-peer-hid-report-extensions-getter.txt`
- `work/27-disass-touch-version1-bytecount.txt`
- `work/27-disass-touch-version2-bytecount.txt`
- `work/27-disass-touch-version3-bytecount.txt`

## Post-testing runtime findings

These findings are from live testing after adding logging to the jailbreak tweak in
`sidecar-touch-tweak/`.

Test logs:

- `sidecar-touch-tweak/sidecar-logs/out.txt`
- `sidecar-touch-tweak/sidecar-logs/27-logs.txt`
- `sidecar-touch-tweak/sidecar-logs/27-session-setup.txt`
- `sidecar-touch-tweak/sidecar-logs/0.0.1-6.txt`
- `sidecar-touch-tweak/sidecar-logs/0.0.1-8.txt`
- `sidecar-touch-tweak/sidecar-logs/0.0.1-16.txt`
- `sidecar-touch-tweak/sidecar-logs/macos-sidecar-touch.txt`
- `sidecar-touch-tweak/sidecar-logs/0.0.1-18.txt`
- `sidecar-touch-tweak/sidecar-logs/macos-sidecar-touch-18.txt`

Runtime observations:

- Finger touches reach `ContinuityDisplay.appex` on iPadOS 16.
- `UIApplication sendEvent:` sees `UITouchTypeDirect` touches (`touchType=0`).
- `ContinuityDisplay.TouchController` accepts those touches; `gestureRecognizer:shouldReceiveTouch:` returns `1`.
- iPadOS 16 already emits Sidecar HID relay traffic for direct touches:
  - report `0x05`, length `23` (`0x17`)
  - report `0x06`, length `23`
- macOS 27 did not make direct touch work when paired with the iPadOS 16 client.
- Under macOS 27, the iPadOS 16 client still emits the old report shape:
  - `0x05` reports stay length `23`
  - `0x06` reports stay length `23`
  - no `0x1b` / 27-byte v3 `TouchReport` packets were seen
- iPadOS 16 sends one HID descriptor packet on `SidecarStream<HIDRelay>`:
  - OPACK key `0`
  - report ID `0x09`
  - length `471`
- iPadOS 16 `ContinuityDisplay.SidecarDisplaySession` has no runtime
  `peerSupportsHIDReportExtensions` ivar or method.
- The macOS 27 `init` item observed by iPadOS 16 included:
  - `applesilicon = 1`
  - `serverCapabilities = 1`
  - `vers = "400.37"`

Reconstructed runtime artifacts:

- `work/log-extracted/hid-descriptor-16-from-log.bin`
- `work/log-extracted/hid-descriptor-16-from-log.bin.hex`
- `work/log-extracted/init-item-macos27.bin`
- `work/log-extracted/init-item-macos27.bin.hex`

The logged iPadOS 16 HID descriptor's report `0x05` section is 166 bytes long.
iPadOS 27 contains a longer report `0x05` descriptor fragment with the same prefix
and an inserted vendor-usage block. The insertion starts immediately after:

```text
06 1a ff 09 11 15 00 26 ff 00 75 08 95 3f 81 22
```

iPadOS 27 inserts this block:

```text
a1 02 06 1a ff 0a f4 e0 95 02 75 08 81 02 c0
a1 02 06 1a ff 0a 62 e0 75 01 95 02 81 02
0a 63 e0 75 01 95 02 81 02
0a 64 e0 75 01 95 02 81 02
0a 65 e0 75 01 95 02 81 02
0a 66 e0 75 01 95 02 81 02
0a 67 e0 75 01 95 02 81 02
0a 68 e0 75 01 95 02 81 02
95 02 75 01 81 01 c0
```

This matches the static iPadOS 27 `TouchReport.Contact` expansion:

- `identity`
- `swipePending`
- `swipeLocked`
- `swipeUp`
- `swipeDown`
- `swipeLeft`
- `swipeRight`
- `cancel`

Current working hypothesis after testing:

1. iPadOS 16 already sees direct finger touches and sends old-format touch HID
   reports.
2. macOS 27 does not treat those old 23-byte touch reports as direct-touch input.
3. iPadOS 27 likely makes direct touch work by advertising an extended report
   descriptor and emitting v3 `TouchReport` packets.
4. The next tweak experiment should patch the outgoing HID descriptor packet
   (OPACK key `0`, report `0x09`) to include the iPadOS 27 report `0x05`
   extension block, then expand outgoing report `0x05` packets from 23 bytes to
   27 bytes.
5. The first v3 report test can conservatively zero the added identity/flag
   fields, then iterate if macOS 27 still ignores the stream.

Additional version 16 test:

- The tweak successfully patched the outgoing iPadOS 16 HID descriptor:
  - original descriptor length `471`
  - patched descriptor length `561`
  - report `0x05` start offset `183`
  - extension insert offset `348`
  - HID report-descriptor length updated to `552` (`0x0228`)
- The tweak successfully expanded outgoing report `0x05` touch packets from
  `23` bytes to `27` bytes.
- The added four bytes were `01 06 00 00`, matching the likely iPadOS 27 default
  contact identities for the first two contact slots plus zeroed swipe/cancel
  flags.
- macOS 27 still did not produce working native direct touch with this patch.
- Immediately after macOS received the iPad `config` item, `SidecarDisplayAgent`
  logged:

```text
Display doesn't support MacOSCompatibleTouchReports
```

- The macOS log shows the patched HID stream is not being dropped at transport
  level:
  - `SidecarDisplayAgent` receives repeated `HIDRelay` events.
  - `SidecarDisplayAgent` logs `com.apple.sidecar:gesture` scale/scroll tracking.
  - `SidecarDisplayAgent` logs `com.apple.sidecar:multitouch` gesture state
    transitions.
- The key macOS-side clue from this run is WindowServer:

```text
failed to find a main display to map suspected sidecar2 hid service to, using generic BKIOHIDService
```

- Around that failure, `SidecarDisplayAgent` queried the Sidecar virtual HID
  service properties and got missing values:
  - `displayUUID -> nil`
  - `Product -> nil`
  - `Authenticated -> nil`
  - `Built-In -> nil`
  - `DeviceTypeHint -> nil`
- It did report:
  - `PrimaryUsagePage -> 1`
  - `PrimaryUsage -> 2`
  - `Transport -> Virtual`
  - `SupportsGestureScrolling -> 1`

Updated hypothesis after the version 16 test:

1. The iPad-side descriptor/report-byte patch is accepted well enough for macOS
   Sidecar to consume the stream as legacy gesture/multitouch input.
2. Native direct touch is gated by the iPad `DisplayCapabilities` value; macOS
   currently decodes the iPadOS 16 display as not supporting
   `supportsMacOSCompatibleTouchReports`.
3. Even if that capability is patched, native direct touch likely also requires
   the macOS virtual HID service to be associated with the Sidecar display. The
   missing `displayUUID`/identity properties remain a second suspect.
4. The next tweak/debugging step should inspect how iPadOS 27 causes the macOS
   Sidecar virtual service to expose display identity and native-touch capability
   properties, then either patch the iPadOS 16 session items that drive those
   properties or add targeted logging around the Sidecar item/capability exchange.

Additional version 18 test:

- The config item is dictionary-backed on iPadOS 16 and can be patched before
  it is serialized.
- The tweak changed the outgoing config from `<config (485 bytes)>` to
  `<config (506 bytes)>` by adding `displayCapabilities = 1`.
- macOS 27 received and decoded the patched config:

```text
Received display capabilities rawValue: 1
```

- macOS still immediately logged:

```text
Display doesn't support MacOSCompatibleTouchReports
```

- This proves the key name and OPACK/dictionary serialization path are correct,
  but raw value `1` is not the bit that satisfies
  `supportsMacOSCompatibleTouchReports`.
- iPadOS 27 `ContinuityDisplay.SidecarDisplaySession.copyConfig()` builds a
  seven-field config, while the iPadOS 16 config lacks `displayCapabilities`.
- The iPadOS 27 binary defines `DisplayCapabilities` as an `Int` raw-value
  wrapper. Nearby capability helper code initializes a byte to `2` and masks it
  down before returning, making raw value `2` the next candidate for
  `supportsMacOSCompatibleTouchReports`.

Next tweak experiment after version 18:

1. Force `displayCapabilities = 2` in the outgoing config.
2. Confirm macOS logs `Received display capabilities rawValue: 2`.
3. Check whether the `Display doesn't support MacOSCompatibleTouchReports` line
   disappears. If it disappears but touch still fails, continue with HID service
   display identity (`displayUUID`) and report-shape debugging.
