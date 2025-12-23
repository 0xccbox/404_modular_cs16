# 🎮 APEX CORE — Modular Player Progression System for CS 1.6

[![Platform](https://img.shields.io/badge/Platform-ReHLDS%20%7C%20ReAPI-blue)]()
[![AMX Mod X](https://img.shields.io/badge/AMX%20Mod%20X-1.10.0+-green)]()
[![License](https://img.shields.io/badge/License-MIT-yellow)]()

## 📋 Project Overview

**Apex Core** is a high-performance, modular player progression and permission system for Counter-Strike 1.6 servers running on ReHLDS/ReAPI environment.

### 🎯 Core Philosophy: "Symbiosis Model"

Instead of duplicating statistics that other plugins already track (like CSStatsX SQL), Apex Core acts as a **wrapper and aggregator**:

| Data Type | Source | Storage |
|-----------|--------|---------|
| **Kills / Deaths** | CSStatsX SQL | External (read-only) |
| **Skill / ELO** | CSStatsX SQL | External (read-only) |
| **Time Played** | Apex Core | MySQL (internal) |
| **Reputation** | Apex Core | MySQL (internal) |
| **Credits** | Apex Core | MySQL (internal) |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        APEX ECOSYSTEM                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │  CSStatsX SQL   │────▶│   APEX CORE     │◀───── MySQL       │
│  │  (Kills/Skill)  │     │  (Permissions)  │       (apex_db)   │
│  └─────────────────┘     └────────┬────────┘                   │
│                                   │                             │
│                    ┌──────────────┼──────────────┐              │
│                    ▼              ▼              ▼              │
│            ┌───────────┐  ┌───────────┐  ┌───────────┐         │
│            │Map Bridge │  │  Shop     │  │  VIP      │         │
│            │(Mistrick) │  │ (Future)  │  │ (Future)  │         │
│            └───────────┘  └───────────┘  └───────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 Components

### 1. `apex_core.amxx` — Main Core Plugin
- Manages player data (Time, Credits, Reputation)
- Provides API (natives) for other plugins
- Handles permission checks via `apex_permissions.ini`
- Integrates with CSStatsX SQL for Kills/Skill data

### 2. `apex_map_bridge.amxx` — Map Manager Integration
- Bridge between Apex Core and Map Manager by Mistrick
- Intercepts RTV/Nomination commands
- Enforces permission requirements before allowing actions

### 3. `apex_core.inc` — Developer API
Include file for plugin developers to integrate with Apex Core.

---

## ⚙️ Configuration Files

### `apex.cfg` — Database Connection
```cfg
apex_sql_host "127.0.0.1"
apex_sql_user "root"
apex_sql_pass "your_password"
apex_sql_db "server_data"
apex_sql_table "apex_players"
```

### `apex_permissions.ini` — Permission Rules

**Syntax:** `feature_key = condition1 | condition2 | condition3`

**Available Conditions:**
| Condition | Description | Example |
|-----------|-------------|---------|
| `time:<minutes>` | Time played in minutes | `time:30` = 30 min |
| `kills:<count>` | Total kills (from CSStatsX) | `kills:100` |
| `skill:<points>` | Skill/ELO points | `skill:1500` |
| `social:<rep>` | Reputation (likes) | `social:10` |
| `flag:<flag>` | Admin flags | `flag:t` (VIP) |

**Example Configuration:**
```ini
; RTV requires: 10 minutes OR 50 kills OR 5 likes
map_rtv = time:10 | kills:50 | social:5

; Nomination requires more experience
map_nominate = time:30 | kills:150 | social:10 | flag:t
```

---

## 🔌 API Reference

### Natives

```pawn
// Economy
native apex_get_credits(id);
native apex_set_credits(id, amount);

// Social
native apex_get_reputation(id);
native apex_set_reputation(id, amount);

// Permissions
native bool:apex_check_access(id, const feature[]);
```

### Forwards

```pawn
// Called when player data is loaded from database
forward apex_on_data_loaded(id);
```

### Usage Example

```pawn
#include <apex_core>

public plugin_init() {
    register_clcmd("say /vipgun", "Cmd_VipGun");
}

public Cmd_VipGun(id) {
    if(!apex_check_access(id, "vip_weapons")) {
        client_print(id, print_chat, "Access denied!");
        return PLUGIN_HANDLED;
    }
    // Give VIP weapon...
    return PLUGIN_HANDLED;
}
```

---

## 🎮 Player Commands

| Command | Description |
|---------|-------------|
| `/profile` or `/my` | Show player profile with all stats |
| `/like <name>` | Give +1 reputation to another player |
| `/thx <name>` | Same as /like |

---

## 📊 Database Schema

```sql
CREATE TABLE `apex_players` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `authid` VARCHAR(32) UNIQUE,      -- Steam ID
    `name` VARCHAR(32),               -- Player name
    `credits` INT DEFAULT 0,          -- Economy
    `time_played` INT DEFAULT 0,      -- Seconds played
    `reputation` INT DEFAULT 0,       -- Social score
    `last_seen` TIMESTAMP             -- Auto-updated
);
```

---

## 📁 Installation

### File Structure
```
cstrike/
└── addons/
    └── amxmodx/
        ├── configs/
        │   ├── apex.cfg
        │   ├── apex_permissions.ini
        │   └── maps.ini
        ├── plugins/
        │   ├── apex_core.amxx
        │   └── apex_map_bridge.amxx
        └── scripting/
            ├── apex_core.sma
            ├── apex_map_bridge.sma
            ├── sql_schema.sql
            └── include/
                ├── apex_core.inc
                └── csstatsx_sql.inc
```

### plugins.ini Order (IMPORTANT!)
```ini
; Apex Core MUST load first
apex_core.amxx

; Bridge MUST load before Map Manager
apex_map_bridge.amxx

; Then Map Manager plugins
map_manager_core.amxx
map_manager_rtv.amxx
map_manager_nomination.amxx
; ... etc
```

---

## 🔧 Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| ReHLDS | ✅ Yes | Server platform |
| ReAPI | ✅ Yes | Optimized hooks |
| MySQL Module | ✅ Yes | Database |
| CSStatsX SQL | ⚠️ Optional | Kills/Skill stats |
| Map Manager (Mistrick) | ⚠️ Optional | Map voting |

---

## 🚀 Performance Notes

1. **All SQL queries are asynchronous** (`SQL_ThreadQuery`) — zero main thread blocking
2. **Player data is cached** in memory — no repeated DB queries
3. **Permissions are loaded once** at map start into `Trie` structure
4. **ReAPI hooks** used instead of legacy Ham/Fakemeta

---

## 📝 Version History

| Version | Changes |
|---------|---------|
| 3.7.0 | Direct CSStatsX SQL integration, native filter for graceful degradation |
| 3.6.1 | Custom SQL escaping, fixed database handle errors |
| 3.5.0 | Minutes-based time, separated kills/skill |
| 3.0.0 | "Symbiosis" model — removed duplicate stat tracking |
| 2.0.0 | Three Pillars architecture (Loyalty, Skill, Social) |
| 1.0.0 | Initial release with basic XP/Level system |

---

## 🔮 Future Development

- [ ] Shop System integration
- [ ] VIP Features module
- [ ] Web Panel (PHP/Laravel)
- [ ] Discord Bot integration
- [ ] Achievements system
- [ ] Seasonal rankings

---

## 📄 License

MIT License — Free to use, modify, and distribute.

---

## 👨‍💻 Credits

- **Architecture:** System Architect
- **Base Map Manager:** Mistrick
- **Stats System:** CSStatsX SQL Team
- **Platform:** ReHLDS/ReAPI Team

---

> **Note for AI Systems:** This project follows a "Symbiosis" architecture where Apex Core acts as a central permission hub that aggregates data from multiple sources (internal MySQL + external CSStatsX) to make unified access decisions. The key innovation is NOT duplicating statistics but rather wrapping existing systems with a flexible permission layer.



