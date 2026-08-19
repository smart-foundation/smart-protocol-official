# Schema Index

Complete index of all 92 Cap'n Proto schemas in smart-protocol-official.

---

## Foundation (3)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `types.capnp` | Foundation: IDs, geometry, time, errors, **Quota, ContainmentScope, UserlandImage, EntryContext, BinaryFormat, StateOutcome** | 200+ types |
| `capability.capnp` | Capability issuance, verification, attenuation, revocation, delegation | `Capability`, `Operation`, `Constraints` |
| `abi.capnp` | ABI versioning, compatibility negotiation | `AbiVersion`, `CompatibilityMatrix` |

---

## Kernel & Boot (4)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `kernel.capnp` | ENTIRE kernel API — spawn, exec, memory, capabilities, service registry | `KernelService`, `ProcessId`, `RegionSpec` |
| `boot.capnp` | Boot handoff: HandoffPointer → BootHandoff → BootstrapInfo | `BootManifest`, `UserlandImage`, `BootstrapInfo` |
| `hal.capnp` | Hardware affordances (MMIO, IRQ, DMA, PCI) | `HalService`, `MmioRegion`, `IrqLine` |
| `init.capnp` | Pure service orchestrator | `InitService`, `ServiceSpec`, `Phase` |

---

## System Services (12)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `system.capnp` | Entry point, capability discovery, handshake | `System`, `Capabilities` |
| `service.capnp` | Service lifecycle, health, resources, TierClass | `Service`, `ServiceKind`, `TierClass` |
| `process.capnp` | Processes, Quota, ContainmentScope, universal states | `Process`, `ProcessState`, `Quota` |
| `session.capnp` | Login, lock, idle, user identity | `Session`, `SessionService` |
| `discovery.capnp` | Service registry, heartbeat, changeFeed, scopeBoundary | `DiscoveryService`, `ServiceDescriptor` |
| `logging.capnp` | Structured logs, opaque formats, UInt64 subscriptions | `Logging`, `LogEntry`, `LogLevel` |
| `diagnostics.capnp` | Metrics, health, tracing, GPU, resource forecasting | `DiagnosticsService`, `Metric` |
| `klog.capnp` | Kernel log access, retention, encryption, alerting | `KLogService`, `KLogEntry` |
| `time.capnp` | Clocks, timers, alarms, world clocks | `TimeService`, `Timestamp`, `Duration` |
| `queue.capnp` | Inter-app messaging | `QueueService`, `QueueMessage` |
| `signal.capnp` | Typed signal/event system | `SignalService`, `SignalKind` |
| `task_scheduler.capnp` | Scheduling policies, priorities | `TaskScheduler`, `SchedulingPolicy` |

---

## Hardware & Devices (10)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `device.capnp` | Backend-decided device tree, opaque IDs | `DeviceService`, `DeviceId` |
| `display.capnp` | Monitors, brightness, HDR, color, wireless | `DisplayService`, `DisplayMode` |
| `audio.capnp` | Devices, streams, timeless OS audio features | `AudioService`, `AudioStream` |
| `input.capnp` | Keyboard, mouse, touch, gamepad, force feedback | `InputService`, `InputDevice` |
| `camera.capnp` | Photo, video, preview, AI analysis | `CameraService`, `CameraDevice` |
| `usb.capnp` | USB device enumeration, PD, Thunderbolt | `UsbService`, `UsbDevice` |
| `bluetooth.capnp` | Bluetooth devices, audio, mesh | `BluetoothService`, `BluetoothDevice` |
| `nfc.capnp` | NFC tags, card emulation, peer-to-peer | `NfcService`, `NfcTag` |
| `sensor.capnp` | Sensors, telemetry | `SensorService`, `SensorReading` |
| `framebuffer.capnp` | Raw framebuffer access | `FramebufferService`, `FramebufferInfo` |

---

## UI & Compositing (6)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `compositor.capnp` | **Session interface only** — layers, cursor, DnD, input routing | `CompositorSession`, `Layer` |
| `windowmanager.capnp` | **Session interface only** — windows, workspaces, tiling, snapping | `WindowManagerSession`, `Window` |
| `ime.capnp` | **Canonical text input** — Session, preedit, commit, virtual keyboard | `ImeSession`, `InputMethod` |
| `clipboard.capnp` | Canonical clipboard service | `ClipboardService`, `ClipboardContent` |
| `notification.capnp` | Canonical notification service | `NotificationService`, `Notification` |
| `settings.capnp` | Canonical settings service | `SettingsService`, `SettingValue` |

---

## Data & Storage (8)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `files.capnp` | File I/O + mount/unmount + trash | `Files`, `FileHandle`, `FileInfo` |
| `storage.capnp` | Block devices, pools, volumes, snapshots | `StorageService`, `Volume`, `Snapshot` |
| `database.capnp` | Key-value, graph, vector, CRDT | `DatabaseService`, `KeyValue` |
| `backup.capnp` | Backup/restore | `BackupService`, `BackupJob` |
| `archive.capnp` | Compression, encryption, content-addressed | `ArchiveService`, `ArchiveFormat` |
| `mount.capnp` | Mount orchestration, overlay, auto-mount | `MountService`, `MountInfo` |
| `ramfs.capnp` | Filesystem capability domain | `RamFsProvider`, `RamFs` |
| `filesystem.capnp` | **DEPRECATED** — merged into files.capnp | — |

---

## Network & Communication (7)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `network.capnp` | WiFi, ethernet, cellular, DNS, DHCP, VPN, firewall | `Network`, `NetworkInterface` |
| `dns.capnp` | DNS resolution, DNSSEC, zone management | `DnsService`, `DnsRecord` |
| `web.capnp` | HTTP, WebSocket, URL resolution | `WebService`, `HttpRequest` |
| `socket.capnp` | Connection API — TCP/UDP/Unix, proxy, TLS | `SocketService`, `Socket` |
| `tunnel.capnp` | Universal channels, transport-agnostic | `TunnelService`, `Tunnel` |
| `endpoint.capnp` | Service endpoints, generic EndpointAddress | `EndpointService`, `EndpointAddress` |
| `telephony.capnp` | Calls, SMS, modem | `TelephonyService`, `Call` |

---

## Security & Identity (8)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `auth.capnp` | Authentication, privilege escalation | `AuthService`, `AuthToken` |
| `access.capnp` | Access control, recovery | `AccessService`, `Credential` |
| `biometric.capnp` | Biometric enrollment, verification | `BiometricService`, `Template` |
| `secret.capnp` | Keyring, secrets, SecretRef | `SecretService`, `Secret` |
| `crypto.capnp` | Hashing, HMAC, KDF, AEAD, signatures, PQC | `CryptoService`, `KeyPair` |
| `key_management.capnp` | Key lifecycle, generation, rotation, revocation | `KeyManagementService`, `KeyId` |
| `signature.capnp` | Signing, verification, policies | `SignatureService`, `Signature` |
| `vcard.capnp` | Contact cards, parsing, export | `VCardService`, `VCard` |

---

## Apps & Intelligence (11)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `app.capnp` | App lifecycle, intents, data sharing | `AppService`, `AppInfo` |
| `appindex.capnp` | App discovery, launch, pinning | `AppIndexService`, `AppEntry` |
| `package.capnp` | Package management, repos, updates | `PackageService`, `Package` |
| `extension.capnp` | Extension registration, capabilities, sandboxing | `ExtensionService`, `Extension` |
| `ai.capnp` | **AI/ML inference, model management, agent coordination** | `InferenceService`, `AgentService`, `ModelId` |
| `speech.capnp` | STT, TTS | `SpeechService`, `Voice` |
| `translation.capnp` | Text translation | `TranslationService`, `Language` |
| `contacts.capnp` | Address book | `ContactsService`, `Contact` |
| `calendar.capnp` | Events, reminders, recurrence | `CalendarService`, `Event` |
| `content.capnp` | Encrypted content envelopes, key rotation | `ContentService`, `ContentEnvelope` |
| `system_search.capnp` | Global search, provider registration | `SearchService`, `SearchProvider` |

---

## Time & System (5)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `timezone.capnp` | Timezone query, conversion, DST | `TimezoneService`, `TimezoneInfo` |
| `update.capnp` | System updates, staged rollout, verification | `UpdateService`, `UpdateInfo` |
| `power.capnp` | Battery, profiles, suspend, charging | `PowerService`, `BatteryInfo` |
| `print.capnp` | Printer discovery, print jobs | `PrintService`, `Printer` |
| `cli.capnp` | Command execution, shell access, custom commands | `CliService`, `Command` |

---

## Accessibility & Media (4)

| Schema | Purpose | Key Types |
|--------|---------|-----------|
| `accessibility.capnp` | Accessibility tree, roles, states | `AccessibilityService`, `AccessibilityNode` |
| `media.capnp` | Playback control (MPRIS-style) | `MediaService`, `MediaPlayer` |
| `capture.capnp` | Screenshots, screen recording | `CaptureService`, `CaptureSession` |
| `theme.capnp` | Semantic tokens, dark/light, accent | `ThemeService`, `ThemeTokens` |

---

## Deprecated (3)

| Schema | Status | Replacement |
|--------|--------|-------------|
| `textinput.capnp` | **DEPRECATED** | `ime.capnp` |
| `surface.capnp` | **DEPRECATED** | `compositor.capnp` (Session) |
| `filesystem.capnp` | **DEPRECATED** | `files.capnp` (mount/unmount/trash merged) |

---

## Total: 92 schemas (89 active + 3 deprecated)