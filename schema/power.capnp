@0xa1b2c3d4e5f6000e;

using T = import "types.capnp";

# ── Power State ────────────────────────────────────────────────────────
# High-level power state for the system.
enum PowerState {
    on @0;
    suspend @1;
    hibernate @2;
    shutdown @3;
    reboot @4;
    custom @5;
}

# ═══════════════════════════════════════════════════════════════════════
# Power - battery state, power profiles, suspend/hibernate/shutdown.
#
# Improvements beyond the original schema:
#   - T.Duration for timeToEmpty and timeToFull (was raw Int64).
#   - Typed physical quantities: TemperatureKelvin, Voltage, Current.
#   - PowerProfileId typed ID replaces bare Text.
#   - Subscription cancel method added.
#   - Custom variant on BatteryHealth.
# ═══════════════════════════════════════════════════════════════════════

interface Power {
    getBattery @0 () -> (state :BatteryState);
    getProfiles @1 (pagination :T.Pagination) -> (profiles :List(PowerProfile));
    setProfile @2 (profileId :T.PowerProfileId) -> T.VoidResult;

    subscribeBattery @3 () -> (subscription :BatterySubscription);

    suspend @4 () -> T.VoidResult;
    hibernate @5 () -> T.VoidResult;
    reboot @6 () -> T.VoidResult;
    shutdown @7 () -> T.VoidResult;

    # Audit-7: power telemetry streaming.
    subscribePowerTelemetry @8 (config :TelemetryConfig) -> (subscription :PowerTelemetrySubscription);

    # Audit-7: per-subsystem power budget.
    getPowerBudget @9 () -> (budget :PowerBudget);
    setPowerBudget @10 (budget :PowerBudget) -> T.VoidResult;

    # Audit-7: charging intelligence.
    getChargingInfo @11 () -> (info :ChargingInfo);

    # Audit-9: USB Power Delivery negotiation.
    negotiateUsbPd @12 (requestedVoltage :T.Voltage, requestedCurrent :T.Current) -> (contract :UsbPdContract);

    # Audit-9: get USB-PD contract details.
    getUsbPdContract @13 () -> (contract :UsbPdContract);

    # Audit-9: wireless charging negotiation.
    negotiateWirelessCharging @14 (requestedPowerClass :Float32) -> (config :WirelessChargingConfig);

    # Audit-9: get grid energy info (for battery/UPS systems with grid export).
    getGridEnergy @15 () -> (info :GridEnergyInfo);

    # Audit-9: get carbon intensity for carbon-aware scheduling.
    getCarbonIntensity @16 (region :Text) -> (intensity :CarbonIntensity);

    # Audit-9: get PoE (Power over Ethernet) info.
    getPoEInfo @17 () -> (info :PoEInfo);

    # Audit-10: Configure battery cell balancing.
    configureCellBalancing @18 (config :CellBalancingConfig) -> T.VoidResult;

    # Audit-10: Get cell balancing status.
    getCellBalancingStatus @19 () -> (status :CellBalancingStatus);

    # Audit-10: Get fuel gauge estimate.
    getFuelGauge @20 () -> (estimate :FuelGaugeEstimate);

    # Audit-10: Predict thermal runaway risk.
    predictThermalRunaway @21 () -> (prediction :ThermalRunawayPrediction);
}

interface BatterySubscription {
    pull @0 () -> (state :BatteryState);
    cancel @1 () -> T.VoidResult;
}

struct BatteryState {
    present @0 :Bool;
    # Charge percentage 0-100.
    percentage @1 :UInt32;
    charging @2 :Bool;
    plugged @3 :Bool;
    # Estimated time until fully discharged. Zero if unknown or fully charged.
    timeToEmpty @4 :T.Duration;
    # Estimated time until fully charged. Zero if unknown or fully discharged.
    timeToFull @5 :T.Duration;
    health @6 :BatteryHealth;
    # Battery temperature in Kelvin (273.15 = 0C, 310.15 = 37C).
    temperature @7 :T.TemperatureKelvin;
    # Battery voltage in Volts (e.g., 3.7, 4.2).
    voltage @8 :T.Voltage;
    # Battery current in Amperes (positive = charging, negative = discharging).
    current @9 :T.Current;

    # Audit-7: extended battery health data.
    # Charge cycle count (critical for state-of-health assessment).
    cycleCount @10 :UInt32;
    # Battery state-of-health percentage (0-100, 100 = new).
    soh @11 :UInt32;
    # Structured charging phase (replaces bare charging Bool).
    chargingPhase @12 :ChargingPhase;
    # Typed power source (replaces bare plugged Bool).
    powerSource @13 :PowerSource;
    # Thermal state of the battery.
    thermalState @14 :ThermalState;
    # Per-cell data for multi-cell batteries.
    cells @15 :List(BatteryCell);
}

enum BatteryHealth {
    good @0;
    overheat @1;
    dead @2;
    overVoltage @3;
    cold @4;
    unknown @5;
    custom @6;
}

struct PowerProfile {
    id @0 :T.PowerProfileId;
    name @1 :Text;
    description @2 :Text;
    active @3 :Bool;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended power management
#
# Power telemetry, battery health, charging intelligence, thermal
# management, and power budgets. These extend the basic battery
# snapshot model to support mobile, wearable, automotive, and
# AR/VR power management needs.
# ═══════════════════════════════════════════════════════════════════════

# ── Charging Phase ────────────────────────────────────────────

enum ChargingPhase {
    idle @0;            # Not charging
    cc @1;              # Constant current phase
    cv @2;              # Constant voltage phase
    trickle @3;         # Trickle charge (very low current)
    done @4;            # Charging complete
    custom @5;
}

# ── Power Source ──────────────────────────────────────────────

enum PowerSource {
    ac @0;              # AC adapter (wall outlet)
    battery @1;         # Running on battery
    wireless @2;        # Wireless charging (Qi)
    usb @3;             # USB power delivery
    poe @4;             # Power over Ethernet
    generator @5;       # Generator
    ups @6;             # Uninterruptible power supply
    solar @7;           # Solar panel
    custom @8;
}

# ── Thermal State ─────────────────────────────────────────────

enum ThermalState {
    normal @0;
    warm @1;
    hot @2;
    critical @3;        # Thermal throttling active
    custom @4;
}

# ── Battery Cell (multi-cell batteries) ───────────────────────

struct BatteryCell {
    # Cell index (0-based).
    index @0 :UInt32;
    # Cell voltage in Volts.
    voltage @1 :T.Voltage;
    # Cell temperature in Kelvin.
    temperature @2 :T.TemperatureKelvin;
    # Cell impedance in milliohms (for health assessment).
    impedance @3 :UInt32;
}

# ── Power Sample (telemetry) ──────────────────────────────────

struct PowerSample {
    timestamp @0 :T.Timestamp;
    # Instantaneous power draw in Watts.
    powerWatts @1 :Float32;
    # Cumulative energy consumption in Watt-hours.
    energyWh @2 :Float32;
    # Power source for this sample.
    source @3 :PowerSource;
}

# ── Telemetry Configuration ───────────────────────────────────

struct TelemetryConfig {
    # Sampling interval for power telemetry.
    interval @0 :T.Duration;
    # Whether to include per-subsystem breakdown.
    perSubsystem @1 :Bool;
    # Subsystems to track (empty = all).
    subsystems @2 :List(Text);
}

interface PowerTelemetrySubscription {
    pull @0 () -> (samples :List(PowerSample));
    cancel @1 () -> T.VoidResult;
}

# ── Power Budget ──────────────────────────────────────────────

struct PowerBudget {
    # Maximum total power draw in Watts.
    maxPowerWatts @0 :Float32;
    # Thermal limit in Watts (throttling kicks in above this).
    thermalLimitWatts @1 :Float32;
    # Current total draw in Watts.
    currentDrawWatts @2 :Float32;
    # Available headroom in Watts.
    headroomWatts @3 :Float32;
    # Per-subsystem budget allocations.
    subsystems @4 :List(SubsystemBudget);
}

struct SubsystemBudget {
    name @0 :Text;
    # Maximum power allocation in Watts.
    maxWatts @1 :Float32;
    # Current draw in Watts.
    currentWatts @2 :Float32;
}

# ── Charging Intelligence ─────────────────────────────────────

struct ChargingInfo {
    phase @0 :ChargingPhase;
    source @1 :PowerSource;
    # USB-PD contract voltage (if applicable).
    usbPdVoltage @2 :T.Voltage;
    # USB-PD contract current (if applicable).
    usbPdCurrent @3 :T.Current;
    # Wireless charging power class in Watts.
    wirelessPowerClass @4 :Float32;
    # Whether fast charging is enabled.
    fastCharging @5 :Bool;
    # Charging temperature limit in Kelvin.
    tempLimit @6 :T.TemperatureKelvin;
}

# ── Ignition State (automotive) ───────────────────────────────

enum IgnitionState {
    off @0;
    accessory @1;       # Radio only, limited systems
    on @2;              # All systems powered
    start @3;           # Cranking engine
    custom @4;
}

# ── Sleep/Wake Power States ───────────────────────────────────

enum SleepState {
    active @0;
    idle @1;
    lightSleep @2;
    deepSleep @3;
    hibernate @4;
    custom @5;
}

# ── USB Power Delivery (audit-9) ─────────────────────────────

enum UsbPdPowerRole {
    source @0;
    sink @1;
    dual @2;
    custom @3;
}

struct UsbPdContract {
    voltage @0 :T.Voltage;
    current @1 :T.Current;
    maxVoltage @2 :T.Voltage;
    maxCurrent @3 :T.Current;
    powerRole @4 :UsbPdPowerRole;
    # Whether PPS (Programmable Power Supply) is active.
    ppsActive @5 :Bool;
    # Whether AVS (Adjustable Voltage Supply) is active.
    avsActive @6 :Bool;
}

# ── Wireless Charging (audit-9) ──────────────────────────────

struct WirelessChargingConfig {
    # Qi/EPP power class in Watts.
    powerClass @0 :Float32;
    # Whether foreign object detection is clear.
    fodClear @1 :Bool;
    # Coil alignment quality (0.0-1.0).
    coilAlignment @2 :Float32;
    # Charging efficiency percentage.
    efficiency @3 :Float32;
}

# ── Grid Energy (audit-9) ─────────────────────────────────────

enum GridConnectionState {
    connected @0;
    disconnected @1;
    backup @2;
    custom @3;
}

struct GridEnergyInfo {
    # Current grid connection state.
    connectionState @0 :GridConnectionState;
    # Grid import power in Watts.
    importPower @1 :Float32;
    # Grid export power in Watts.
    exportPower @2 :Float32;
    # Battery charge level (0-100).
    batteryLevel @3 :UInt32;
    # Estimated backup duration at current draw.
    backupDuration @4 :T.Duration;
    # Solar production in Watts (if applicable).
    solarProduction @5 :Float32;
}

struct SolarInfo {
    # Current solar production in Watts.
    currentWatts @0 :Float32;
    # Daily energy produced in Wh.
    dailyEnergyWh @1 :Float32;
    # Panel efficiency percentage.
    efficiency @2 :Float32;
    # Whether panels are clean (no debris/snow).
    panelsClean @3 :Bool;
}

# ── Carbon Intensity (audit-9) ───────────────────────────────

enum CarbonIntensityUnit {
    gramsPerKwh @0;
    custom @1;
}

struct CarbonIntensity {
    # Carbon intensity in grams CO2 per kWh.
    gramsPerKwh @0 :Float32;
    # Grid region.
    region @1 :Text;
    # Timestamp of this reading.
    timestamp @2 :T.Timestamp;
    # Forecast for next hour (low/medium/high).
    forecast @3 :CarbonForecast;
    # Whether this is a real-time or forecast value.
    isRealTime @4 :Bool;
}

enum CarbonForecast {
    low @0;
    medium @1;
    high @2;
    custom @3;
}

# ── Power over Ethernet (audit-9) ────────────────────────────

enum PoEClass {
    poeClass0 @0;   # 15.4W (IEEE 802.3af)
    poeClass1 @1;   # 4W
    poeClass2 @2;   # 7W
    poeClass3 @3;   # 15.4W
    poeClass4 @4;   # 30W (802.3at)
    poeClass5 @5;   # 45W (802.3bt type 2)
    poeClass6 @6;   # 60W (802.3bt type 3)
    poeClass7 @7;   # 75W (802.3bt type 4)
    poeClass8 @8;   # 90W (802.3bt type 4)
    custom @9;
}

struct PoEInfo {
    # PoE class of the connected device.
    poeClass @0 :PoEClass;
    # Power allocated in Watts.
    allocatedWatts @1 :Float32;
    # Power consumed in Watts.
    consumedWatts @2 :Float32;
    # LLDP-MED policy applied.
    lldpMedPolicy @3 :Text;
    # Whether PoE is enabled on this port.
    enabled @4 :Bool;
}

# ─── Battery Cell Balancing (audit-10) ─────────────────────

enum BalancingMethod {
    passive @0;
    active @1;
    none @2;
    custom @3;
}

struct CellBalancingConfig {
    method @0 :BalancingMethod;
    # Voltage threshold for triggering balance (Volts).
    thresholdVoltage @1 :T.Voltage;
    # Maximum balancing current (Amperes).
    maxCurrent @2 :T.Current;
    # Whether balancing is enabled.
    enabled @3 :Bool;
}

struct CellBalancingStatus {
    active @0 :Bool;
    method @1 :BalancingMethod;
    # Cells currently being balanced.
    balancingCells @2 :List(UInt32);
    # Maximum voltage difference across cells.
    maxVoltageDiff @3 :T.Voltage;
    # Time since balancing started.
    duration @4 :T.Duration;
}

# ─── Fuel Gauge (audit-10) ─────────────────────────────────

struct FuelGaugeEstimate {
    # State of charge percentage (0-100).
    stateOfCharge @0 :UInt32;
    # State of health percentage (0-100).
    stateOfHealth @1 :UInt32;
    # Full charge capacity in mAh.
    fullChargeCapacity @2 :UInt32;
    # Remaining capacity in mAh.
    remainingCapacity @3 :UInt32;
    # Cycle count.
    cycleCount @4 :UInt32;
    # Time to empty at current load.
    timeToEmpty @5 :T.Duration;
    # Time to full at current charge rate.
    timeToFull @6 :T.Duration;
    # Remaining energy in Wh.
    remainingEnergyWh @7 :Float32;
    # Instantaneous power draw in Watts.
    powerDrawWatts @8 :Float32;
    # Timestamp of estimate.
    timestamp @9 :T.Timestamp;
}

# ─── Thermal Runaway Prediction (audit-10) ─────────────────

enum ThermalRiskLevel {
    low @0;
    moderate @1;
    elevated @2;
    high @3;
    critical @4;
    custom @5;
}

struct ThermalRunawayPrediction {
    riskLevel @0 :ThermalRiskLevel;
    # Probability of thermal event in next hour (0.0-1.0).
    probability @1 :Float32;
    # Predicted time to critical temperature.
    timeToCritical @2 :T.Duration;
    # Current battery temperature.
    currentTemperature @3 :T.TemperatureKelvin;
    # Temperature trend (degrees per minute).
    temperatureTrend @4 :Float32;
    # Contributing factors.
    factors @5 :List(Text);
    # Recommended action.
    recommendedAction @6 :Text;
    # Prediction confidence (0.0-1.0).
    confidence @7 :Float32;
    # Timestamp of prediction.
    timestamp @8 :T.Timestamp;
}
