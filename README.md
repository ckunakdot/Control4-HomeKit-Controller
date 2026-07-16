# Control4 HomeKit Controller

A native HomeKit controller for Control4. It pairs directly with "Works with HomeKit" accessories over the local network and bridges them into Control4 as standard device proxies. No Home Assistant, no external bridge software, and no cloud connection are required — the Control4 Director talks to each accessory directly using the HomeKit Accessory Protocol (HAP).

The suite is made up of one hub driver and a set of per-accessory child drivers. The hub owns discovery, pairing, and the encrypted connection to the accessory. Each child driver presents one paired accessory to Control4 as the appropriate native proxy.

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
- An Invert property swaps the reported state for cases where the opposite convention is wanted.
- The output is a standard Control4 contact sensor, so it can be bound to a Motion Sensor or similar proxy to present properly in Navigator with the matching events and history.

### homekit-sensor

Bridges HomeKit environmental sensors to Control4 temperature and humidity values.

- Reports temperature in both Celsius and Fahrenheit, so Control4 can display either.
- Reports relative humidity.
- Reads ambient light level into a variable when the accessory provides it.

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
| Temperature, Humidity, Light sensors | homekit-sensor | temperature and humidity values |
| Garage Door Opener | homekit-garage | relay and contact sensors |
| Security System | homekit-alarm | securitypanel and security |

## Using the drivers

1. Add the `homekit-controller` driver to your project.
2. Press **Discover Devices**, then choose your accessory from the **Discovered Device** list. The IP and port fill in automatically.
3. Enter the accessory's **Setup Code** and press **Pair**. Pairing Status moves to Connected.
4. Press **Show Accessories**. Each accessory is listed with its `aid` and the child driver to use.
5. Add the matching child driver for each accessory, bind it to the hub, and set its **Accessory AID** to the value from step 4.

The accessory then appears in Navigator as a native device and can be used in Composer programming like any other.

## Notes

- A HomeKit setup code pairs an accessory to the first controller that claims it. If an accessory is already paired to another controller or app, remove it there first, or reset its HomeKit pairing, before pairing it here.
- Use **Remove Pairing** before deleting or replacing a hub driver. That releases the pairing on the accessory as well; otherwise the accessory keeps a pairing that no longer exists and will refuse to pair again until it is reset.
- Pairings are stored per driver instance on a specific controller. To move to a newer version of a driver, use Update Driver in place so the existing pairings carry over.
- Everything runs locally on the Control4 Director. There is no cloud dependency and no bridge software required.
- Some low-cost accessories ship with limited HAP implementations and may not pair reliably. The Compact Pairing option on the hub resolves this for some of them.

## Screenshots
<img width="179" height="146" alt="image" src="https://github.com/user-attachments/assets/52183493-79c0-4047-9cc8-dff2988a895b" />
<img width="584" height="250" alt="image" src="https://github.com/user-attachments/assets/46c39f08-2c7e-4f9b-b550-5488ba1c898c" />
<img width="591" height="281" alt="image" src="https://github.com/user-attachments/assets/bb39ba71-a7a1-4503-a503-0abd57e8028d" />
<img width="598" height="306" alt="image" src="https://github.com/user-attachments/assets/1723d7fc-febb-4fb1-8905-70d297e61c30" />


## Notes

- A HomeKit setup code pairs an accessory to the first controller that claims it. If an accessory is already paired to another controller or app, remove it there first, or reset its HomeKit pairing, before pairing it here.
- Use **Remove Pairing** before deleting or replacing a hub driver. That releases the pairing on the accessory as well; otherwise the accessory keeps a pairing that no longer exists and will refuse to pair again until it is reset.
- Pairings are stored per driver instance on a specific controller. To move to a newer version of a driver, use Update Driver in place so the existing pairings carry over.
- Everything runs locally on the Control4 Director. There is no cloud dependency and no bridge software required.
- Some low-cost accessories ship with limited HAP implementations and may not pair reliably. The Compact Pairing option on the hub resolves this for some of them.
