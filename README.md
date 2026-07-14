# Control4 HomeKit Controller

A native HomeKit controller for Control4, implemented entirely in DriverWorks Lua. It pairs directly with "Works with HomeKit" accessories over the local network and bridges them into Control4 as standard device proxies. No Home Assistant, no external hub, and no cloud connection are required — the Control4 Director talks to each accessory directly using the HomeKit Accessory Protocol (HAP).

The suite is made up of one hub driver and a set of per-accessory child drivers. The hub owns discovery, pairing, and the encrypted connection to the accessory. Each child driver presents one paired accessory to Control4 as the appropriate native proxy (shade, thermostat, lock, or light).

## How it fits together

- The **hub** (`homekit-controller`) pairs with a HomeKit accessory, holds the encrypted session, and reads the accessory's database of services and characteristics.
- A HomeKit device (for example a bridge like Bond, or a standalone accessory like an ecobee) can expose one or more **accessories**, each identified by an accessory ID (`aid`).
- A **child driver** binds to the hub and is pointed at a single `aid`. It translates that accessory's HomeKit characteristics to and from a native Control4 proxy so it behaves like any other Control4 device in Navigator and Composer programming.

One hub instance can bridge multiple accessories; you add one child per accessory you want to control.

## Hub driver: homekit-controller

The hub does everything related to finding, pairing with, and talking to HomeKit accessories.

### What it does

- **Discovers accessories** on the network using mDNS/Bonjour (`_hap._tcp`). It lists each device's name, IP address, port, model, and whether it is currently pairable or already paired.
- **Pairs** with an accessory using the standard HomeKit setup code. The full HAP handshake — SRP-6a pair-setup, pair-verify, and the ChaCha20-Poly1305 encrypted session — is implemented in pure Lua.
- **Removes pairing** cleanly, telling the accessory to delete the controller so it is genuinely unpaired (not just forgotten locally).
- **Reads the accessory database** and lists every accessory with its `aid`, name, service type, and the child driver to use for it.
- **Bridges** each accessory to a child driver and keeps state synchronized in both directions.
- **Identifies** an accessory (triggers its physical identify routine) to confirm you are talking to the right unit.

### Actions

| Action | Description |
| --- | --- |
| Discover Devices | Scans the network and populates the Discovered Device list with every HomeKit accessory found. |
| Pair | Pairs with the accessory at the configured IP and port using the Setup Code. |
| Remove Pairing | Unpairs from the accessory on both ends. |
| Refresh | Re-reads the accessory database and current state. |
| Show Accessories | Prints a summary of every paired accessory with its `aid` and the recommended child driver. |
| Identify | Asks the accessory to identify itself. |

### Properties

| Property | Description |
| --- | --- |
| Accessory IP | The accessory's IP address. Filled automatically when you pick a discovered device. |
| Accessory Port | The accessory's HomeKit port. Filled automatically when you pick a discovered device. |
| Discovered Device | A dropdown of discovered accessories; selecting one fills in the IP and port. |
| Setup Code | The HomeKit setup code from the accessory, in the form 123-45-678. |
| Pairing Status | Read-only status (Unpaired, Pairing, Connected, and so on). |
| Compact Pairing | Optional. Shrinks the pairing request for accessories with strict or naive HAP implementations that otherwise refuse to pair. |
| Debug Mode | Enables verbose logging to the Lua output window. |

## Child drivers

Every child driver binds to the hub, is assigned a single accessory by its `aid`, and exposes that accessory through a native Control4 proxy. Each one reports live state back to Control4 and translates Control4 commands into HomeKit characteristic writes.

### homekit-shade

Bridges a HomeKit Window Covering to a Control4 blind proxy.

- Open, close, and set position to any level.
- Reports current position and movement state to Control4.
- Supports Stop on accessories that expose a hold-position capability.

### homekit-thermostat

Bridges a HomeKit Thermostat to a Control4 thermostatV2 proxy.

- Reports current temperature and the active heating/cooling state.
- Sets the single setpoint as well as separate heat and cool setpoints in Auto mode.
- Selects HVAC mode: Off, Heat, Cool, or Auto.
- Handles Fahrenheit and Celsius. The selected scale is remembered, temperatures are reported in that scale, and the accessory's own display units are kept in sync. HomeKit works in Celsius internally; the driver converts at the boundary.

### homekit-lock

Bridges a HomeKit Lock Mechanism to a Control4 lock proxy.

- Lock, unlock, and toggle.
- Reports lock state (locked, unlocked, unknown) to Control4.
- Reports battery status (normal, warning, critical) for locks that expose a battery service.

### homekit-light

Bridges a HomeKit Lightbulb to a Control4 light_v2 proxy.

- On and off.
- Brightness / dimming for bulbs that support it.
- Full color for bulbs with hue and saturation, converting between Control4's CIE xy color model and HomeKit's hue/saturation.
- Color temperature (warm-to-cool white) for bulbs that support it, converting between Kelvin and mireds.
- Advertises the bulb's real capabilities so Navigator shows only the controls the bulb actually supports, and writes color as a single atomic update so changes take effect immediately.

## Supported accessory types

| HomeKit service | Child driver | Control4 proxy |
| --- | --- | --- |
| Window Covering | homekit-shade | blind |
| Thermostat | homekit-thermostat | thermostatV2 |
| Lock Mechanism | homekit-lock | lock |
| Lightbulb | homekit-light | light_v2 |

## Screenshots

<img width="584" height="250" alt="image" src="https://github.com/user-attachments/assets/46c39f08-2c7e-4f9b-b550-5488ba1c898c" />
<img width="591" height="281" alt="image" src="https://github.com/user-attachments/assets/bb39ba71-a7a1-4503-a503-0abd57e8028d" />
<img width="598" height="306" alt="image" src="https://github.com/user-attachments/assets/1723d7fc-febb-4fb1-8905-70d297e61c30" />


## Using the drivers

1. Add the `homekit-controller` driver to your project.
2. Press **Discover Devices**, then choose your accessory from the **Discovered Device** list. The IP and port fill in automatically.
3. Enter the accessory's **Setup Code** and press **Pair**. The Pairing Status will move to Connected.
4. Press **Show Accessories** to list every accessory the device exposes, each with its `aid`.
5. Add the matching child driver for each accessory, bind it to the hub, and set its **Accessory AID** to the value from step 4.

The accessory then appears in Navigator as a native shade, thermostat, lock, or light and can be used in Composer programming like any other device.

## Notes

- A HomeKit setup code pairs the accessory to the first controller that claims it. If an accessory is already paired to another controller or app (for example Home Assistant or Apple Home), remove it there first, or factory-reset its HomeKit pairing, before pairing it here.
- Everything runs locally on the Control4 Director. There is no cloud dependency and no bridge software required.
- Some very low-cost accessories ship with limited HAP implementations and may not pair reliably. The Compact Pairing option resolves this for many of them.
