# Control4 HomeKit Controller
## NOTE
## The pairing process can be slow on large project and overloaded EA OR Core controllers. CA10 Does not have this issue.
Hopefully i will have a fix to inprove it.
 
A native HomeKit controller for Control4. It pairs directly with "Works with HomeKit" accessories over the local network and bridges them into Control4 as standard device proxies. No Home Assistant, no external bridge software, and no cloud connection are required — the Control4 talks to each accessory directly using the HomeKit Accessory Protocol (HAP).
The suite is made up of one hub driver and a set of per-accessory child drivers. The hub owns discovery, pairing, and the encrypted connection to the accessory. Each child driver presents one paired accessory to Control4 as the appropriate native proxy.
##

![Version](https://img.shields.io/badge/version-1.0-blue)
  <img src="https://img.shields.io/badge/Control4-OS%203.4.3-red" alt="Control4 OS 3.4.3">
  <img src="https://img.shields.io/badge/Control4-OS%204.x-blue" alt="Control4 OS 4.x">
  <a href="https://www.buymeacoffee.com/ckunakdot" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>


## How it fits together

- The **hub** (`homekit-controller`) pairs with a HomeKit accessory, holds the encrypted session, and reads the accessory's database of services and characteristics.
- A HomeKit device can expose one accessory (a single lock, a thermostat) or many (a bridge such as Bond, Lutron, or Homebridge). Each accessory has its own accessory ID, or `aid`.
- A **child driver** binds to the hub and is pointed at a single `aid`. It translates that accessory's HomeKit characteristics to and from a native Control4 proxy, so it behaves like any other Control4 device in Navigator and in Composer programming.

One hub instance can bridge every accessory on a paired device. You add one child per accessory you want to control.

## Hub driver: homekit-controller

### What it does

- **Discovers accessories** on the network using mDNS/Bonjour (`_hap._tcp`), listing each device's name, IP address, port, model, and whether it is currently pairable or already paired.
- **Pairs** with an accessory using its HomeKit setup code. The full HAP handshake.
- **Removes pairing** cleanly, telling the accessory to delete the controller so it is genuinely unpaired rather than only forgotten locally.
- **Lists paired accessories** with their `aid`, name, service type, and the child driver to use for each.
- **Bridges** each accessory to its child driver, keeping state synchronised in both directions.
- **Identifies** an accessory, triggering its physical identify routine to confirm which unit you are talking to.

### Actions

| Action | Description |
| --- | --- |
| Discover Devices | Scans the network and fills the Discovered Device list with every HomeKit accessory found. |
| Pair | Pairs with the accessory at the configured IP and port using the Setup Code. |
| Remove Pairing | Unpairs from the accessory on both ends. |
| Refresh | Re-reads the accessory database and current state. |
| Show Accessories | Lists every paired accessory with its `aid` and the recommended child driver. |
| Identify | Asks the accessory to identify itself. |

### Properties

| Property | Description |
| --- | --- |
| Accessory IP | The accessory's IP address. Filled automatically when you pick a discovered device. |
| Accessory Port | The accessory's HomeKit port. Filled automatically when you pick a discovered device. |
| Discovered Device | Dropdown of discovered accessories; selecting one fills in the IP and port. |
| Setup Code | The HomeKit setup code from the accessory, in the form 123-45-678. |
| Pairing Status | Read-only status such as Unpaired, Pairing, or Connected. |
| Connected Device | Read-only. Names the paired accessory, read from the accessory itself after connecting: name, manufacturer, model and firmware. A bridge also shows how many accessories it exposes. |
| Poll Interval | Seconds between state polls, so changes made at the device itself are picked up. 0 disables polling. |
| Compact Pairing | Optional. Shrinks the pairing request for accessories whose HAP implementations reject the standard one. Leave off unless a device fails to pair. |
| Debug Mode | Enables verbose logging to the Lua output window. |

## Child drivers

Every child driver binds to the hub, is assigned one accessory by its `aid`, and exposes it through a native Control4 proxy. Each reports live state back to Control4 and translates Control4 commands into HomeKit characteristic writes.

### homekit-shade

Bridges a HomeKit Window Covering to a Control4 blind proxy.

- Open, close, and set position to any level.
- Reports current position and movement state.
- Supports Stop on accessories that expose a hold-position capability.

### homekit-thermostat

Bridges a HomeKit climate accessory to a Control4 thermostatV2 proxy. It supports both HomeKit climate services and detects which one the accessory uses:

- **Thermostat**, used by whole-home thermostats such as ecobee and Nest.
- **Heater/Cooler**, used by mini-splits, window air conditioners, and virtual thermostats. These have no single target temperature, so the heat and cool thresholds act as the setpoints and Off is expressed by making the unit inactive.

Features:

- Reports current temperature and the active heating or cooling state.
- Sets heat and cool setpoints, and a single setpoint where the accessory uses one.
- Selects HVAC mode: Off, Heat, Cool, or Auto.
- Reports relative humidity when the accessory measures it.
- Fan control (Auto or On) when the accessory exposes a fan.
- Reports connection status to Control4.
- Handles Fahrenheit and Celsius. The selected scale is remembered, temperatures are reported in that scale, and the accessory's own display units are kept in sync. HomeKit works in Celsius internally; the driver converts at the boundary.
- Respects the accessory's declared limits. Every accessory publishes a minimum, maximum and step size for each value it accepts, and rejects anything that breaks them. The driver reads those limits and fits each setpoint to them, so a value the thermostat cannot accept is adjusted to the nearest one it can rather than being silently refused.
- Routes each setpoint to the right place for the current mode. Control4 keeps heat and cool as a pair and sends both whenever either changes, while a thermostat in Heat or Cool mode has only one target temperature. The driver writes the setpoint that matches the active mode to the target, and stores the other on its own threshold, so neither is lost and neither overwrites the other. Setpoints set while the thermostat is Off are stored as well.

### homekit-lock

Bridges a HomeKit Lock Mechanism to a Control4 lock proxy.

- Lock, unlock, and toggle.
- Reports lock state: locked, unlocked, or unknown.
- Reports battery status for locks that expose a battery service.

### homekit-light

Bridges a HomeKit Lightbulb to a Control4 light_v2 proxy.

- On and off.
- Brightness for bulbs that support dimming.
- Full colour for bulbs with hue and saturation, converting between Control4's CIE xy colour model and HomeKit's hue and saturation.
- Colour temperature for bulbs that support it, converting between Kelvin and mireds.
- Advertises the bulb's real capabilities so Navigator shows only the controls it actually has, and writes colour as a single atomic update so changes take effect immediately.
- Also works with HomeKit Switch and Outlet accessories, presenting them as on/off lights.

### homekit-fan-3speed / 4speed / 5speed / 6speed

Bridges a HomeKit fan to a Control4 fan proxy. Pick the variant matching the number of speeds your fan has, since Control4 defines discrete speed counts per driver.

- On, off, and toggle.
- Set speed directly, or cycle speed up and down.
- Reports on/off state and current speed.
- Works with both HomeKit fan services, the classic Fan and the newer Fanv2.
- HomeKit fans use a 0-100 percent rotation speed; the driver converts to and from Control4's discrete speeds, and sends power and speed together so the fan applies them as one change.
- Respects the speed steps the fan declares, so fans that only accept certain speed values are driven to the nearest one they allow.

### homekit-contact

Bridges any HomeKit binary sensor to a Control4 contact sensor.

- Supports Contact, Motion, Occupancy, Smoke, and Leak sensors.
- Reports OPENED when the sensor is active or detecting, CLOSED when it is not.
- A Sensor Type property selects which sensor to follow. One accessory can expose several at once, such as an ecobee that publishes both motion and occupancy, so add one instance per sensor and point them all at the same Accessory AID. Left on Auto, the driver uses the first sensor it finds, which suits accessories with only one.
- Handles accessories that publish the same kind of sensor as several separate zones, such as the Aqara FP2's presence zones. A Zone property selects a named zone, using the name set in the accessory's own app. Add one instance per zone and point them all at the same Accessory AID; each is addressed by its own characteristic, so zones do not overwrite one another. Left on Auto, it follows the first matching sensor.
- An Invert property swaps the reported state for cases where the opposite convention is wanted.
- The output is a standard Control4 contact sensor, so it can be bound to a Motion Sensor or similar proxy to present properly in Navigator with the matching events and history.

### homekit-sensor

Bridges HomeKit environmental sensors to Control4 temperature, humidity, and light-level values.

- Reports temperature in both Celsius and Fahrenheit, so Control4 can display either.
- Reports relative humidity.
- Reports ambient light level (lux) as a variable, and makes it programmable. Configurable Dark Threshold and Bright Threshold properties set a hysteresis band; a LIGHT_IS_DARK variable tracks the current side of that band; and Became Dark and Became Bright programming events fire on a real transition. The dead-band between the two thresholds keeps light hovering at dusk from flapping the events, so an ambient-light reading can drive lighting scenes directly without extra programming.

### homekit-garage

Bridges a HomeKit Garage Door Opener to Control4, using the same relay and contact-sensor bindings as a conventional Control4 garage door setup.

- Open, close, and toggle.
- Reports door position through separate OPEN and CLOSED contact sensors.
- Handles the in-transit states, reporting neither sensor as triggered while the door is opening or closing.
- Logs obstruction detection when the accessory reports it.

### homekit-alarm

Bridges a HomeKit Security System to Control4 security panel and partition proxies.

- Arm Home, Away, or Night, and disarm.
- Reports armed state and type, disarmed, and alarm-triggered.
- Derives an exit-delay state, which HomeKit does not report directly, by detecting when the accessory is still disarmed while an arm mode is pending.
- An optional User Code property makes Control4 prompt for a code, which the driver checks before arming or disarming. HomeKit does not carry a user code over the protocol, so this is a Control4-side check rather than one enforced by the accessory. Left blank, no code is requested.

### timer-sprinkler (HomeKit irrigation)

A countdown-timer front-end that controls a HomeKit Valve or Irrigation System, such as a Rachio. Unlike the proxy child drivers, this presents in Navigator as a timer button rather than a device proxy: pick a run time and the zone waters for that long, then shuts off.

- One timer per zone, addressed by its Accessory AID. On systems that publish each zone as its own accessory (Rachio), you add one timer per zone.
- Writes the run duration and the start command together so the accessory's own timer matches the countdown.
- Wakes the parent Irrigation System accessory automatically when a zone starts, for controllers that gate zones behind a system-active state.
- A Control Method property (Relay, Light Switch, or HomeKit) lets the same driver drive a physical relay, a bound Control4 light, or a HomeKit valve, so it can be reused outside HomeKit too.

### timer-relay (HomeKit switch / relay)

A countdown-timer and relay front-end that controls a HomeKit Switch, Outlet, or Valve on a timer or as a plain on/off.

- Timed runs or permanent on/off.
- Sends the correct value type for the target automatically, since a switch's On characteristic and a valve's Active characteristic are different types in HomeKit.
- The same Control Method property as timer-sprinkler, so it works with a physical relay, a bound light, or a HomeKit accessory.

## Supported accessory types

| HomeKit service | Child driver | Control4 proxy |
| --- | --- | --- |
| Window Covering | homekit-shade | blind |
| Thermostat | homekit-thermostat | thermostatV2 |
| Heater/Cooler | homekit-thermostat | thermostatV2 |
| Lock Mechanism | homekit-lock | lock |
| Lightbulb | homekit-light | light_v2 |
| Switch, Outlet | homekit-light | light_v2 (on/off) |
| Fan, Fanv2 | homekit-fan-Nspeed | fan |
| Contact, Motion, Occupancy, Smoke, Leak | homekit-contact | contact sensor |
| Temperature, Humidity, Light sensors | homekit-sensor | temperature, humidity, and light-level values |
| Garage Door Opener | homekit-garage | relay and contact sensors |
| Security System | homekit-alarm | securitypanel and security |
| Valve, Irrigation System | timer-sprinkler | countdown timer |
| Switch, Outlet, Valve (timed) | timer-relay | countdown timer / relay |

## Tested Controllers

| Model | Operating System | Works |
| --- | --- | --- |
|CA-10 | 4.2.1| Y |
| Core lite | 4.2.0 | Y |
| Core 3 |  4.2.0 | Y |
| EA5 | 4.2.0 | Y |
| EA3 | 3.4.3 | Y |
| EA1 | 4.2.0 | Y |
| HC800 | 3.3.0 | N |

## Tested devices

These have been paired and exercised against the drivers. Anything that speaks HAP should work; this is simply what has been confirmed.

| Device | Exposes over HomeKit | Child drivers used |
| --- | --- | --- |
| Ecobee Smart Thermostat Premium | Thermostat, plus motion and occupancy sensors, all on a single accessory | homekit-thermostat, and homekit-contact twice (Sensor Type set to Motion and to Occupancy, both on the same Accessory AID) |
| Lutron RadioRA 3 | Each shared load as its own accessory | homekit-light |
| Lutron Caseta | Each shared load as its own accessory | homekit-light |
| Bond Bridge Pro | One accessory per device it controls, such as shades and fans | homekit-shade, homekit-fan-Nspeed |
| Bond Bridge (original) | One accessory per device it controls, such as shades and fans | homekit-shade, homekit-fan-Nspeed |
| Rachio Smart Sprinkler Controller | An Irrigation System accessory, plus one Valve accessory per zone | timer-sprinkler set to HomeKit, one instance per zone |
| Aqara Presence Sensor FP2 | Occupancy per detection zone, plus ambient light, all on one accessory | homekit-contact per zone (Zone property), and homekit-sensor for the light level |
| TP-Link Kasa EP25 (smart plug) | Outlet | homekit-light (on/off), or timer-relay for timed runs |
| Honeywell T9 | Thermostat | homekit-thermostat|
| Homebridge | One accessory per plugin-provided device | Whichever child matches each accessory |

Notes from testing these:

- The ecobee publishes its thermostat, motion sensor and occupancy sensor on one accessory, so all three child drivers share the same Accessory AID and are told apart by Sensor Type.
- Lutron processors only publish the loads that have been shared to HomeKit. If a load is missing from Show Accessories, share it in the Lutron app first. (RA3 Only Caseta shows all)
- Lutron accessory IDs are very large numbers rather than the small ones most accessories use. This is handled, and is worth knowing only because the `aid` you copy from Show Accessories will be long.
- The original Bond Bridge behaves like the Bond Bridge Pro: one accessory per device it controls, matched to homekit-shade or homekit-fan-Nspeed.
- Rachio exposes each zone as its own Valve accessory, with a separate Irrigation System accessory for the controller itself. Add one timer-sprinkler per zone and set its Accessory AID to that zone; the system accessory is woken automatically when a zone runs. A HomeKit valve reports and accepts its on/off state as a number rather than a true/false, which the driver handles — worth knowing only if you write to one yourself.
- The Aqara FP2 publishes each presence zone you draw in the Aqara app as its own occupancy service, carrying that zone's name. Add one homekit-contact per zone and pick the zone in its Zone property; use homekit-sensor for the FP2's ambient-light reading, including its Dark/Bright threshold events. Keep polling high or it will loose connection.
- The TP-Link Kasa EP25 presents as an Outlet. Control it on/off through homekit-light, or through timer-relay when you want a timed run.
- Homebridge is useful for testing. Its plugins can present almost any accessory type, and its pairing can be reset from the Homebridge UI without touching real hardware, which makes it a safe way to try a child driver before pointing it at something real.
- A Homebridge virtual thermostat is a Heater/Cooler rather than a Thermostat. Both are supported, but they behave differently: see the homekit-thermostat section.

## Using the drivers

1. Add the `homekit-controller` driver to your project.
2. Press **Discover Devices**, then choose your accessory from the **Discovered Device** list. The IP and port fill in automatically.
3. Enter the accessory's **Setup Code** and press **Pair**. Pairing Status moves to Connected.
4. Press **Show Accessories**. Each accessory is listed with its `aid` and the child driver to use.
5. Add the matching child driver for each accessory, bind it to the hub, and set its **Accessory AID** to the value from step 4.

The accessory then appears in Navigator as a native device and can be used in Composer programming like any other.

## Screenshots

**System View**

<img width="248" height="419" alt="image" src="https://github.com/user-attachments/assets/6006b839-7f1a-4185-b76d-3bbdf40f15f6" />

**Driver View**

<img width="809" height="333" alt="Driver View" src="https://github.com/user-attachments/assets/d4f9f867-df08-42cc-909b-09ded10a28b0" />

**Discovery List**

<img width="813" height="362" alt="Discovery List" src="https://github.com/user-attachments/assets/36669be1-f52e-49fe-885e-2c156e263909" />

**Show Accessories output**

<img width="884" height="281" alt="Show Accessories output" src="https://github.com/user-attachments/assets/ddef788a-1c73-41bc-b795-c7dbac0d021d" />

## Notes
- My setup has all equipment configured with either static IP addresses or DHCP reservations.

## Basic Troubleshooting

- If pairing appears to be stuck, reboot your controller and try pairing again.
- If you have iTunes installed on a PC or Mac, you can use `dns-sd` to discover HomeKit devices on the network.

Command to list all HomeKit accessories:
`dns-sd -B _hap._tcp`
Command to show a device host, port, and TXT records, including `sf`, `md`, and `id`:
`dns-sd -L "My Device" _hap._tcp`

## Pairing Notes
A HomeKit setup code pairs an accessory to the first controller that claims it. If an accessory is already paired to another controller or app, remove it there first, or reset its HomeKit pairing before pairing it here.
Use **Remove Pairing** before deleting or replacing a hub driver. This releases the pairing on the accessory. Otherwise, the accessory may keep a pairing that no longer exists and refuse to pair again until it is reset.
Pairings are stored per driver instance on a specific controller. To move to a newer driver version, use **Update Driver** in place so the existing pairings carry over.
Everything runs locally on the Control4 Director. There is no cloud dependency and no bridge software required.

