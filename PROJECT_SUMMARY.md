# 📊 APEX CORE — ИТОГИ ПРОЕКТА

## ✅ Статус: ГОТОВО К ПРОДАКШЕНУ

**Дата:** 22 декабря 2025  
**Версия:** 3.7.0  
**Компилятор:** AMX Mod X 1.10.0.5474  
**Результат компиляции:** ✅ 0 Errors, 0 Warnings

---

## 🎯 Концепция проекта

**Apex Core** — это централизованная система прогрессии и прав доступа для серверов CS 1.6.

### Ключевая идея: "Симбиоз"

Вместо дублирования статистики, Apex Core **агрегирует данные** из разных источников:

```
┌─────────────────────┐
│   CSStatsX SQL      │ → Kills, Deaths, Skill/ELO (только чтение)
├─────────────────────┤
│   APEX CORE DB      │ → Time, Credits, Reputation (чтение/запись)
├─────────────────────┤
│   PERMISSIONS       │ → Гибкие правила доступа (INI файл)
└─────────────────────┘
```

---

## 📦 Компоненты системы

| Файл | Назначение | Размер |
|------|-----------|--------|
| `apex_core.amxx` | Главное ядро | 64 KB |
| `apex_map_bridge.amxx` | Мост для Map Manager | 19 KB |
| `apex_core.inc` | API для разработчиков | 1 KB |
| `csstatsx_sql.inc` | Интеграция с CSStatsX | 1 KB |
| `apex_permissions.ini` | Конфиг прав доступа | — |
| `apex.cfg` | Настройки БД | — |

---

## 🔧 Система прав доступа

### Доступные параметры:

| Параметр | Описание | Пример |
|----------|----------|--------|
| `time:X` | Время игры (минуты) | `time:30` = 30 мин |
| `kills:X` | Количество убийств | `kills:100` |
| `skill:X` | Очки скилла/ELO | `skill:1500` |
| `social:X` | Репутация (лайки) | `social:10` |
| `flag:X` | Админ-флаг | `flag:t` (VIP) |

### Логика "ИЛИ":
```ini
; Игрок получает доступ если выполнено ЛЮБОЕ условие
map_rtv = time:10 | kills:50 | social:5
```

---

## 🎮 Команды игрока

| Команда | Действие |
|---------|----------|
| `/profile` | Показать профиль |
| `/my` | Показать профиль |
| `/like <ник>` | Дать +1 репутацию |
| `/thx <ник>` | Дать +1 репутацию |

---

## 🔌 API для разработчиков

```pawn
#include <apex_core>

// Экономика
native apex_get_credits(id);
native apex_set_credits(id, amount);

// Социальная система
native apex_get_reputation(id);
native apex_set_reputation(id, amount);

// Проверка прав
native bool:apex_check_access(id, const feature[]);

// Forward при загрузке данных
forward apex_on_data_loaded(id);
```

---

## 📁 Структура файлов

```
cstrike/addons/amxmodx/
├── configs/
│   ├── apex.cfg              ← Настройки MySQL
│   ├── apex_permissions.ini  ← Правила доступа
│   └── maps.ini              ← Список карт
├── plugins/
│   ├── apex_core.amxx        ← ГЛАВНЫЙ ПЛАГИН
│   └── apex_map_bridge.amxx  ← Мост для Map Manager
└── scripting/
    ├── apex_core.sma
    ├── apex_map_bridge.sma
    ├── sql_schema.sql
    └── include/
        ├── apex_core.inc
        └── csstatsx_sql.inc
```

---

## ⚠️ Важный порядок в plugins.ini

```ini
; 1. СНАЧАЛА Apex Core
apex_core.amxx

; 2. ПОТОМ Bridge (перед Map Manager!)
apex_map_bridge.amxx

; 3. ПОТОМ Map Manager by Mistrick
map_manager_core.amxx
map_manager_rtv.amxx
map_manager_nomination.amxx
```

---

## 🐛 Известные особенности

1. **Боты YAPB** не засчитываются в статистику CSStatsX — это нормально
2. **Kills/Skill** = 0 при игре с ботами — нужны реальные игроки
3. **Time** сохраняется при отключении игрока в MySQL

---

## 🔮 Что можно добавить в будущем

- [ ] Система магазина (Shop)
- [ ] VIP-модуль с оружием
- [ ] Веб-панель статистики
- [ ] Discord интеграция
- [ ] Система достижений
- [ ] Сезонные рейтинги

---

## 📝 История версий

| Версия | Изменения |
|--------|-----------|
| **3.7.0** | Прямая интеграция CSStatsX SQL, native filter |
| 3.6.x | Исправления SQL, кастомный escaping |
| 3.5.x | Минуты вместо часов, разделение kills/skill |
| 3.0.0 | Модель "Симбиоз" |
| 2.0.0 | Три столпа: Loyalty, Skill, Social |
| 1.0.0 | Базовая XP/Level система |

---

## ✅ Чеклист готовности

- [x] Компиляция без ошибок
- [x] SQL схема готова
- [x] Конфиги созданы
- [x] API документирован
- [x] Интеграция с CSStatsX SQL
- [x] Интеграция с Map Manager
- [x] README создан

---

> **Для AI/Нейросетей:**  
> Проект "Apex Core" — это middleware-система для CS 1.6 серверов.  
> Ключевая архитектура: НЕ дублировать статистику, а агрегировать из разных источников (CSStatsX + собственная БД) для единой системы прав доступа.  
> Технологии: Pawn, ReAPI, MySQL, асинхронные SQL-запросы.



