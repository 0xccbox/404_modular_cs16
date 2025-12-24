#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <reapi>

// CSStatsX SQL integration (optional)
native get_user_stats_sql(id, stats[8], bodyhits[8]);
native get_user_skill(id);

#define PLUGIN  "Apex Core"
#define VERSION "4.1.0"
#define AUTHOR  "Architect"

// Stats array indexes (CSStatsX SQL v0.7.4+2)
#define STATS_KILLS   0
#define STATS_DEATHS  1
#define STATS_HS      2
#define STATS_TK      3
#define STATS_SHOTS   4
#define STATS_HITS    5
#define STATS_DAMAGE  6
#define STATS_SKILL   7

// Skill Ranks (ELO-based)
#define RANK_M       0    // M:    0-899
#define RANK_M_PLUS  1    // M+:   900-999
#define RANK_GM      2    // GM:   1000-1099
#define RANK_GM_PLUS 3    // GM+:  1100-1199
#define RANK_S       4    // S:    1200-1349
#define RANK_S_PLUS  5    // S+:   1350-1499
#define RANK_P       6    // P:    1500-1699
#define RANK_P_PLUS  7    // P+:   1700+

new const g_szRankNames[][] = {
    "M", "M+", "GM", "GM+", "S", "S+", "P", "P+"
};

new const g_iRankThresholds[] = {
    0, 900, 1000, 1100, 1200, 1350, 1500, 1700
};

enum _:PlayerState {
    bool:IsLoaded,
    bool:IsLoading,
    DB_ID,
    AuthID[35],
    Name[32],
    NameSafe[64],
    Float:Bits,
    TimePlayed,
    Reputation,
    SessionStart,
    LikesGivenRound,
    LikesGivenMap,
    LastLikeTime,
    Float:BitsTransferredToday,
    LastTransferDay
}

enum _:ReqType {
    REQ_TIME_MINUTES = 0,
    REQ_KILLS,
    REQ_REAL_SKILL,
    REQ_REPUTATION,
    REQ_FLAG
}

enum _:ReqItem {
    R_Type,
    R_Value
}

// Player data
new g_Player[33][PlayerState];

// SQL
new Handle:g_hSqlTuple = Empty_Handle;
new bool:g_bSqlReady = false;
new g_szSqlTable[32];

// Permissions
new Trie:g_tPermissions;

// CVars - Database
new cvar_sql_host, cvar_sql_user, cvar_sql_pass, cvar_sql_db, cvar_sql_table;

// CVars - Bits Rewards
new cvar_bits_kill, cvar_bits_kill_hs, cvar_bits_kill_knife, cvar_bits_kill_grenade;
new cvar_bits_assist, cvar_bits_round_win, cvar_bits_round_mvp, cvar_bits_round_survive;
new cvar_bits_bomb_plant, cvar_bits_bomb_defuse, cvar_bits_bomb_explode;
new cvar_bits_hostage_rescue, cvar_bits_hostage_all;
new cvar_bits_time_enabled, cvar_bits_time_interval, cvar_bits_time_amount;
new cvar_bits_teamkill, cvar_bits_suicide;

// CVars - Bits Decay
new cvar_bits_decay_enabled, cvar_bits_decay_days, cvar_bits_decay_percent, cvar_bits_decay_minimum;

// CVars - Bits Transfer
new cvar_bits_transfer_enabled, cvar_bits_transfer_min, cvar_bits_transfer_fee, cvar_bits_transfer_daily;

// CVars - Reputation
new cvar_like_enabled, cvar_like_per_round, cvar_like_per_map, cvar_like_cooldown, cvar_like_self;

// CVars - Notifications
new cvar_notify_bits, cvar_notify_bits_min, cvar_notify_sound;

// Forwards
new g_iFwdDataLoaded;
new bool:g_bCsStatsLoaded = false;

// Round tracking
new g_iRoundKills[33];
new g_iLikeTarget[33];

// ============================================================================
// STOCKS
// ============================================================================

stock EscapeString(const src[], dest[], maxlen) {
    new j = 0;
    for(new i = 0; src[i] != EOS && j < maxlen - 2; i++) {
        if(src[i] == 39 || src[i] == 92) {
            dest[j++] = 92;
        }
        dest[j++] = src[i];
    }
    dest[j] = EOS;
}

stock GetRankIndex(skill) {
    for(new i = sizeof(g_iRankThresholds) - 1; i >= 0; i--) {
        if(skill >= g_iRankThresholds[i]) {
            return i;
        }
    }
    return RANK_M;
}

stock GetRankName(skill, output[], maxlen) {
    new idx = GetRankIndex(skill);
    copy(output, maxlen, g_szRankNames[idx]);
}

stock GetCurrentDay() {
    new year, month, day;
    date(year, month, day);
    return year * 10000 + month * 100 + day;
}

// ============================================================================
// NATIVES
// ============================================================================

public plugin_natives() {
    register_library("apex_core");
    
    register_native("apex_get_credits", "_native_get_bits");   // Backward compat
    register_native("apex_set_credits", "_native_set_bits");
    register_native("apex_get_bits", "_native_get_bits");
    register_native("apex_set_bits", "_native_set_bits");
    register_native("apex_add_bits", "_native_add_bits");
    register_native("apex_get_reputation", "_native_get_reputation");
    register_native("apex_set_reputation", "_native_set_reputation");
    register_native("apex_check_access", "_native_check_access");
    register_native("apex_reset_player", "_native_reset_player");
    register_native("apex_get_bits_float", "_native_get_bits_float");
    
    set_native_filter("native_filter");
}

public native_filter(const name[], index, trap) {
    if(equal(name, "get_user_stats_sql") || equal(name, "get_user_skill")) {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// ============================================================================
// PLUGIN INIT
// ============================================================================

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Database CVars
    cvar_sql_host = register_cvar("apex_sql_host", "127.0.0.1");
    cvar_sql_user = register_cvar("apex_sql_user", "root");
    cvar_sql_pass = register_cvar("apex_sql_pass", "");
    cvar_sql_db   = register_cvar("apex_sql_db", "server_data");
    cvar_sql_table = register_cvar("apex_sql_table", "apex_players");

    // Bits Rewards CVars
    cvar_bits_kill = register_cvar("apex_bits_kill", "0.1");
    cvar_bits_kill_hs = register_cvar("apex_bits_kill_hs", "0.2");
    cvar_bits_kill_knife = register_cvar("apex_bits_kill_knife", "0.5");
    cvar_bits_kill_grenade = register_cvar("apex_bits_kill_grenade", "0.3");
    cvar_bits_assist = register_cvar("apex_bits_assist", "0.05");
    cvar_bits_round_win = register_cvar("apex_bits_round_win", "0.3");
    cvar_bits_round_mvp = register_cvar("apex_bits_round_mvp", "0.5");
    cvar_bits_round_survive = register_cvar("apex_bits_round_survive", "0.1");
    cvar_bits_bomb_plant = register_cvar("apex_bits_bomb_plant", "0.3");
    cvar_bits_bomb_defuse = register_cvar("apex_bits_bomb_defuse", "0.5");
    cvar_bits_bomb_explode = register_cvar("apex_bits_bomb_explode", "0.2");
    cvar_bits_hostage_rescue = register_cvar("apex_bits_hostage_rescue", "0.3");
    cvar_bits_hostage_all = register_cvar("apex_bits_hostage_all", "1.0");
    cvar_bits_time_enabled = register_cvar("apex_bits_time_enabled", "1");
    cvar_bits_time_interval = register_cvar("apex_bits_time_interval", "600");
    cvar_bits_time_amount = register_cvar("apex_bits_time_amount", "0.1");
    cvar_bits_teamkill = register_cvar("apex_bits_teamkill", "-1.0");
    cvar_bits_suicide = register_cvar("apex_bits_suicide", "-0.5");

    // Bits Decay CVars
    cvar_bits_decay_enabled = register_cvar("apex_bits_decay_enabled", "0");
    cvar_bits_decay_days = register_cvar("apex_bits_decay_days", "30");
    cvar_bits_decay_percent = register_cvar("apex_bits_decay_percent", "10");
    cvar_bits_decay_minimum = register_cvar("apex_bits_decay_minimum", "10.0");

    // Bits Transfer CVars
    cvar_bits_transfer_enabled = register_cvar("apex_bits_transfer_enabled", "1");
    cvar_bits_transfer_min = register_cvar("apex_bits_transfer_min", "1.0");
    cvar_bits_transfer_fee = register_cvar("apex_bits_transfer_fee", "0");
    cvar_bits_transfer_daily = register_cvar("apex_bits_transfer_daily", "100.0");

    // Reputation CVars
    cvar_like_enabled = register_cvar("apex_like_enabled", "1");
    cvar_like_per_round = register_cvar("apex_like_per_round", "1");
    cvar_like_per_map = register_cvar("apex_like_per_map", "3");
    cvar_like_cooldown = register_cvar("apex_like_cooldown", "60");
    cvar_like_self = register_cvar("apex_like_self", "0");

    // Notification CVars
    cvar_notify_bits = register_cvar("apex_notify_bits", "1");
    cvar_notify_bits_min = register_cvar("apex_notify_bits_minimum", "0.1");
    cvar_notify_sound = register_cvar("apex_notify_sound", "1");

    // Load config
    new cfgDir[64];
    get_configsdir(cfgDir, charsmax(cfgDir));
    server_cmd("exec %s/apex.cfg", cfgDir);
    server_exec();

    // Permissions
    g_tPermissions = TrieCreate();
    LoadPermissionsFile();

    // ReAPI Hooks
    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled", true);
    RegisterHookChain(RG_RoundEnd, "OnRoundEnd", true);
    
    // Commands - Profile
    register_clcmd("say /my", "Cmd_Profile");
    register_clcmd("say_team /my", "Cmd_Profile");
    register_clcmd("say .my", "Cmd_Profile");
    register_clcmd("say_team .my", "Cmd_Profile");
    register_clcmd("say /ьн", "Cmd_Profile");
    register_clcmd("say_team /ьн", "Cmd_Profile");
    
    // Commands - Like
    register_clcmd("say /like", "Cmd_Like");
    register_clcmd("say_team /like", "Cmd_Like");
    register_clcmd("say .like", "Cmd_Like");
    register_clcmd("say_team .like", "Cmd_Like");
    register_clcmd("say /дшлу", "Cmd_Like");
    register_clcmd("say_team /дшлу", "Cmd_Like");
    
    // Commands - Transfer bits
    register_clcmd("say /give", "Cmd_Give");
    register_clcmd("say_team /give", "Cmd_Give");
    register_clcmd("say /send", "Cmd_Give");
    register_clcmd("say_team /send", "Cmd_Give");
    register_clcmd("say /пшму", "Cmd_Give");
    register_clcmd("say_team /пшму", "Cmd_Give");
    
    // Commands - Reset
    register_clcmd("say /reset", "Cmd_ResetConfirm");
    register_clcmd("say_team /reset", "Cmd_ResetConfirm");

    // Initialize SQL
    set_task(1.0, "SQL_Init");
    
    // Forward
    g_iFwdDataLoaded = CreateMultiForward("apex_on_data_loaded", ET_IGNORE, FP_CELL);
    
    // CSStatsX check
    g_bCsStatsLoaded = bool:LibraryExists("csstatsx_sql", LibType_Library);
    if(!g_bCsStatsLoaded) {
        g_bCsStatsLoaded = (is_plugin_loaded("csstatsx_sql.amxx") != -1);
    }
    log_amx("[Apex] CSStatsX SQL: %s", g_bCsStatsLoaded ? "Found" : "Not found");
}

public plugin_end() {
    if(g_hSqlTuple != Empty_Handle) SQL_FreeHandle(g_hSqlTuple);
    TrieDestroy(g_tPermissions);
}

// ============================================================================
// TIME BONUS TASK
// ============================================================================

public Task_TimeBonus(id) {
    id -= 100; // Task ID offset
    
    if(!is_user_connected(id) || is_user_bot(id)) return;
    if(!g_Player[id][IsLoaded]) return;
    if(!get_pcvar_num(cvar_bits_time_enabled)) return;
    
    new Float:amount = get_pcvar_float(cvar_bits_time_amount);
    if(amount > 0.0) {
        GiveBits(id, amount, "время онлайн");
    }
    
    // Reschedule
    new Float:interval = get_pcvar_float(cvar_bits_time_interval);
    set_task(interval, "Task_TimeBonus", id + 100);
}

// ============================================================================
// KILL EVENTS
// ============================================================================

public OnPlayerKilled(victim, killer, inflictor) {
    if(!is_user_connected(victim)) return;
    
    // Suicide
    if(killer == victim || killer == 0) {
        if(is_user_connected(victim) && g_Player[victim][IsLoaded]) {
            new Float:penalty = get_pcvar_float(cvar_bits_suicide);
            if(penalty != 0.0) {
                GiveBits(victim, penalty, "суицид");
            }
        }
        return;
    }
    
    if(!is_user_connected(killer)) return;
    if(!g_Player[killer][IsLoaded]) return;
    
    // Team kill check
    if(get_member(killer, m_iTeam) == get_member(victim, m_iTeam)) {
        new Float:penalty = get_pcvar_float(cvar_bits_teamkill);
        if(penalty != 0.0) {
            GiveBits(killer, penalty, "тимкилл");
        }
        return;
    }
    
    // Track kills for MVP
    g_iRoundKills[killer]++;
    
    // Determine kill type and reward
    new Float:reward = 0.0;
    new szReason[32];
    
    new weaponId = get_user_weapon(killer);
    new bool:isHeadshot = bool:(get_member(victim, m_LastHitGroup) == HIT_HEAD);
    
    if(weaponId == CSW_KNIFE) {
        reward = get_pcvar_float(cvar_bits_kill_knife);
        copy(szReason, charsmax(szReason), "убийство ножом");
    }
    else if(weaponId == CSW_HEGRENADE) {
        reward = get_pcvar_float(cvar_bits_kill_grenade);
        copy(szReason, charsmax(szReason), "убийство гранатой");
    }
    else if(isHeadshot) {
        reward = get_pcvar_float(cvar_bits_kill_hs);
        copy(szReason, charsmax(szReason), "хедшот");
    }
    else {
        reward = get_pcvar_float(cvar_bits_kill);
        copy(szReason, charsmax(szReason), "убийство");
    }
    
    if(reward > 0.0) {
        GiveBits(killer, reward, szReason);
    }
}

// ============================================================================
// ROUND END
// ============================================================================

public OnRoundEnd(WinStatus:status, ScenarioEventEndRound:event, Float:delay) {
    new players[32], num;
    get_players(players, num, "h");
    
    new TeamName:winTeam = TEAM_UNASSIGNED;
    
    if(status == WINSTATUS_TERRORISTS) {
        winTeam = TEAM_TERRORIST;
    }
    else if(status == WINSTATUS_CTS) {
        winTeam = TEAM_CT;
    }
    
    // Find MVP (most kills this round)
    new mvp = 0, maxKills = 0;
    for(new i = 0; i < num; i++) {
        new id = players[i];
        if(g_iRoundKills[id] > maxKills) {
            maxKills = g_iRoundKills[id];
            mvp = id;
        }
    }
    
    // Give rewards
    for(new i = 0; i < num; i++) {
        new id = players[i];
        if(is_user_bot(id) || !g_Player[id][IsLoaded]) continue;

        new TeamName:team = get_member(id, m_iTeam);
        
        // Win bonus
        if(team == winTeam && winTeam != TEAM_UNASSIGNED) {
            new Float:winBonus = get_pcvar_float(cvar_bits_round_win);
            if(winBonus > 0.0) {
                GiveBits(id, winBonus, "победа раунда");
            }
        }
        
        // MVP bonus
        if(id == mvp && maxKills > 0) {
            new Float:mvpBonus = get_pcvar_float(cvar_bits_round_mvp);
            if(mvpBonus > 0.0) {
                GiveBits(id, mvpBonus, "MVP раунда");
            }
        }
        
        // Survive bonus
        if(is_user_alive(id)) {
            new Float:surviveBonus = get_pcvar_float(cvar_bits_round_survive);
            if(surviveBonus > 0.0) {
                GiveBits(id, surviveBonus, "выживание");
            }
        }
        
        // Reset round data
        g_iRoundKills[id] = 0;
        g_Player[id][LikesGivenRound] = 0;
    }
}

// ============================================================================
// BOMB EVENTS (ReAPI)
// ============================================================================

public plugin_cfg() {
    // Register bomb events after config loaded
    RegisterHookChain(RG_CGrenade_DefuseBombEnd, "OnDefuseEnd", true);
    RegisterHookChain(RG_PlantBomb, "OnBombPlant", true);
    RegisterHookChain(RG_CGrenade_ExplodeBomb, "OnBombExplode", true);
}

public OnBombPlant(id, Float:vecStart[3], Float:vecVelocity[3]) {
    if(!is_user_connected(id) || is_user_bot(id)) return;
    if(!g_Player[id][IsLoaded]) return;
    
    new Float:reward = get_pcvar_float(cvar_bits_bomb_plant);
    if(reward > 0.0) {
        GiveBits(id, reward, "установка бомбы");
    }
}

public OnDefuseEnd(ent, id, bool:success) {
    if(!success) return;
    if(!is_user_connected(id) || is_user_bot(id)) return;
    if(!g_Player[id][IsLoaded]) return;
    
    new Float:reward = get_pcvar_float(cvar_bits_bomb_defuse);
    if(reward > 0.0) {
        GiveBits(id, reward, "разминирование");
    }
}

public OnBombExplode(ent, trace, bits) {
    // Give bonus to all terrorists
    new players[32], num;
    get_players(players, num, "eh", "TERRORIST");
    
    new Float:reward = get_pcvar_float(cvar_bits_bomb_explode);
    if(reward <= 0.0) return;
    
    for(new i = 0; i < num; i++) {
        new id = players[i];
        if(is_user_bot(id) || !g_Player[id][IsLoaded]) continue;
        GiveBits(id, reward, "взрыв бомбы");
            }
}

// ============================================================================
// GIVE BITS FUNCTION
// ============================================================================

GiveBits(id, Float:amount, const reason[] = "") {
    if(!is_user_connected(id) || !g_Player[id][IsLoaded]) return;
    
    g_Player[id][Bits] += amount;
    
    // Prevent negative
    if(g_Player[id][Bits] < 0.0) {
        g_Player[id][Bits] = 0.0;
    }
    
    // Notification
    if(get_pcvar_num(cvar_notify_bits)) {
        new Float:minNotify = get_pcvar_float(cvar_notify_bits_min);
        if(floatabs(amount) >= minNotify) {
            if(amount > 0.0) {
                client_print_color(id, print_team_default, "^4[Apex]^1 +^3%.1f^1 бит (%s) | Всего: ^4%.1f", amount, reason, g_Player[id][Bits]);
            } else {
                client_print_color(id, print_team_default, "^4[Apex]^1 ^3%.1f^1 бит (%s) | Всего: ^4%.1f", amount, reason, g_Player[id][Bits]);
            }
            
            if(get_pcvar_num(cvar_notify_sound) && amount > 0.0) {
                client_cmd(id, "spk buttons/lightswitch2");
            }
        }
    }
}

// ============================================================================
// TRANSFER COMMAND
// ============================================================================

public Cmd_Give(id) {
    if(!get_pcvar_num(cvar_bits_transfer_enabled)) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Передача битов отключена.");
        return PLUGIN_HANDLED;
            }
    
    if(!g_Player[id][IsLoaded]) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Подождите, данные загружаются...");
        return PLUGIN_HANDLED;
}

    new args[64];
    read_args(args, charsmax(args));
    remove_quotes(args);
    
    // Parse: /give <name> <amount>
    new szName[32], szAmount[16];
    new pos = contain(args, " ");
    
    if(pos == -1) {
        // No args - show menu
        ShowGiveMenu(id);
        return PLUGIN_HANDLED;
    }
    
    // Parse command
    copy(szName, pos, args);
    copy(szAmount, charsmax(szAmount), args[pos + 1]);
    trim(szName);
    trim(szAmount);
    
    new Float:amount = str_to_float(szAmount);
    new Float:minAmount = get_pcvar_float(cvar_bits_transfer_min);
    
    if(amount < minAmount) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Минимальная сумма: ^3%.1f^1 бит", minAmount);
        return PLUGIN_HANDLED;
    }
    
    if(g_Player[id][Bits] < amount) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Недостаточно битов. У вас: ^3%.1f", g_Player[id][Bits]);
        return PLUGIN_HANDLED;
    }

    // Daily limit check
    new Float:dailyLimit = get_pcvar_float(cvar_bits_transfer_daily);
    if(dailyLimit > 0.0) {
        new today = GetCurrentDay();
        if(g_Player[id][LastTransferDay] != today) {
            g_Player[id][BitsTransferredToday] = 0.0;
            g_Player[id][LastTransferDay] = today;
        }
        
        if(g_Player[id][BitsTransferredToday] + amount > dailyLimit) {
            client_print_color(id, print_team_default, "^4[Apex]^1 Превышен дневной лимит (^3%.1f^1). Осталось: ^3%.1f", 
                dailyLimit, dailyLimit - g_Player[id][BitsTransferredToday]);
            return PLUGIN_HANDLED;
        }
    }
    
    // Find target
    new target = cmd_target(id, szName, CMDTARGET_NO_BOTS);
    if(!target) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Игрок не найден.");
        return PLUGIN_HANDLED;
    }
    
    if(target == id) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Нельзя передать биты себе.");
        return PLUGIN_HANDLED;
    }
    
    if(!g_Player[target][IsLoaded]) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Данные получателя ещё не загружены.");
        return PLUGIN_HANDLED;
    }
    
    // Transfer
    g_Player[id][Bits] -= amount;
    g_Player[target][Bits] += amount;
    g_Player[id][BitsTransferredToday] += amount;
    
    new targetName[32];
    get_user_name(target, targetName, charsmax(targetName));
    
    client_print_color(id, print_team_default, "^4[Apex]^1 Вы передали ^3%.1f^1 бит игроку ^4%s", amount, targetName);
    client_print_color(target, print_team_default, "^4[Apex]^1 Игрок ^3%s^1 передал вам ^4%.1f^1 бит!", g_Player[id][Name], amount);
    
    // Sound
    client_cmd(target, "spk buttons/bell1");
    
    // Save both
    SavePlayer(id);
    SavePlayer(target);
    
    return PLUGIN_HANDLED;
}

ShowGiveMenu(id) {
    new menu = menu_create("\yПередать биты \w- Выберите игрока", "Handler_GiveMenu");
    
    new players[32], num;
    get_players(players, num, "ch");
    
    new name[32], info[8];
    new count = 0;

    for(new i = 0; i < num; i++) {
        new pid = players[i];
        if(pid == id || is_user_bot(pid)) continue;
        
        get_user_name(pid, name, charsmax(name));
        num_to_str(pid, info, charsmax(info));
        menu_additem(menu, name, info, 0);
        count++;
    }
    
    if(count == 0) {
        menu_destroy(menu);
        client_print_color(id, print_team_default, "^4[Apex]^1 Нет доступных игроков.");
        return;
    }
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu);
}

public Handler_GiveMenu(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new info[8], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), "", 0, callback);
    
    new target = str_to_num(info);
    menu_destroy(menu);
    
    if(!is_user_connected(target)) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Игрок вышел с сервера.");
        return PLUGIN_HANDLED;
    }
    
    // Store target and ask for amount
    g_iLikeTarget[id] = target;
    
    new targetName[32];
    get_user_name(target, targetName, charsmax(targetName));
    
    client_print_color(id, print_team_default, "^4[Apex]^1 Введите в чат сумму для ^3%s^1 (или /cancel)", targetName);
    client_cmd(id, "messagemode apex_give_amount");
    
    return PLUGIN_HANDLED;
}

// ============================================================================
// PROFILE COMMAND
// ============================================================================

public Cmd_Profile(id) {
    ShowProfile(id);
    return PLUGIN_HANDLED;
}

ShowProfile(id) {
    new kills, deaths, skill_val;
    GetStats(id, kills, deaths, skill_val);

    new Float:kd = (deaths > 0) ? float(kills) / float(deaths) : float(kills);
    new current_session = get_systime() - g_Player[id][SessionStart];
    new total_secs = g_Player[id][TimePlayed] + current_session;
    new mins = total_secs / 60;
    new h = mins / 60;
    new m = mins % 60;

    new rankName[8];
    GetRankName(skill_val, rankName, charsmax(rankName));

    new title[64];
    formatex(title, charsmax(title), "\y%s \w- Профиль", g_Player[id][Name]);
    new menu = menu_create(title, "Handler_Profile");

    new buf[128];
    
    formatex(buf, charsmax(buf), "\wВремя: \y%dч %dм", h, m);
    menu_additem(menu, buf, "", 0);
    
    formatex(buf, charsmax(buf), "\wУбийства: \y%d \d(KD: %.2f)", kills, kd);
    menu_additem(menu, buf, "", 0);
    
    formatex(buf, charsmax(buf), "\wРанг: \r%s \d(%d ELO)", rankName, skill_val);
    menu_additem(menu, buf, "", 0);
    
    formatex(buf, charsmax(buf), "\wРепутация: \y%d", g_Player[id][Reputation]);
    menu_additem(menu, buf, "", 0);
    
    formatex(buf, charsmax(buf), "\wБиты: \g%.1f", g_Player[id][Bits]);
    menu_additem(menu, buf, "", 0);
    
    menu_additem(menu, "\d--- Действия ---", "", 0);
    menu_additem(menu, "\rСбросить данные", "reset", 0);

    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu);
}

public Handler_Profile(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new info[16], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), "", 0, callback);
    
    if(equal(info, "reset")) {
        menu_destroy(menu);
        Cmd_ResetConfirm(id);
        return PLUGIN_HANDLED;
    }
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ============================================================================
// LIKE COMMAND
// ============================================================================

public Cmd_Like(id) {
    if(!get_pcvar_num(cvar_like_enabled)) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Система лайков отключена.");
        return PLUGIN_HANDLED;
    }
    
    new maxRound = get_pcvar_num(cvar_like_per_round);
    new maxMap = get_pcvar_num(cvar_like_per_map);
    
    if(g_Player[id][LikesGivenRound] >= maxRound) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Вы уже использовали лайк в этом раунде.");
        return PLUGIN_HANDLED;
    }
    
    if(g_Player[id][LikesGivenMap] >= maxMap) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Вы использовали все лайки на этой карте (%d/%d).", maxMap, maxMap);
        return PLUGIN_HANDLED;
    }
    
    new cooldown = get_pcvar_num(cvar_like_cooldown);
    new timePassed = get_systime() - g_Player[id][LastLikeTime];
    if(timePassed < cooldown) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Подождите ^3%d^1 секунд.", cooldown - timePassed);
        return PLUGIN_HANDLED;
    }
    
    ShowLikeMenu(id);
    return PLUGIN_HANDLED;
}

ShowLikeMenu(id) {
    new menu = menu_create("\yДать репутацию \w- Выберите игрока", "Handler_Like");
    
    new players[32], num;
    get_players(players, num, "ch");
    
    new bool:allowSelf = bool:get_pcvar_num(cvar_like_self);
    new name[32], info[8];
    new count = 0;
    
    for(new i = 0; i < num; i++) {
        new pid = players[i];
        if(pid == id && !allowSelf) continue;
        if(is_user_bot(pid)) continue;
        
        get_user_name(pid, name, charsmax(name));
        num_to_str(pid, info, charsmax(info));
        menu_additem(menu, name, info, 0);
        count++;
    }
    
    if(count == 0) {
        menu_destroy(menu);
        client_print_color(id, print_team_default, "^4[Apex]^1 Нет доступных игроков.");
        return;
    }
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu);
}

public Handler_Like(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    // Re-check limits
    new maxRound = get_pcvar_num(cvar_like_per_round);
    new maxMap = get_pcvar_num(cvar_like_per_map);
    
    if(g_Player[id][LikesGivenRound] >= maxRound || g_Player[id][LikesGivenMap] >= maxMap) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Лимит лайков исчерпан!");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new info[8], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), "", 0, callback);
    
    new target = str_to_num(info);
    menu_destroy(menu);
    
    if(!is_user_connected(target) || is_user_bot(target)) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Игрок недоступен.");
        return PLUGIN_HANDLED;
    }
    
    // Give like
    g_Player[target][Reputation]++;
    g_Player[id][LikesGivenRound]++;
    g_Player[id][LikesGivenMap]++;
    g_Player[id][LastLikeTime] = get_systime();
    
    new targetName[32];
    get_user_name(target, targetName, charsmax(targetName));
    
    client_print_color(id, print_team_default, "^4[Apex]^1 Вы дали репутацию игроку ^3%s^1!", targetName);
    client_print_color(target, print_team_default, "^4[Apex]^3 %s^1 дал вам репутацию! ^4(+1 Rep)", g_Player[id][Name]);
    
    client_cmd(target, "spk buttons/bell1");
    
    SavePlayer(target);
    
    return PLUGIN_HANDLED;
}

// ============================================================================
// RESET COMMAND
// ============================================================================

public Cmd_ResetConfirm(id) {
    new menu = menu_create("\rСбросить все данные?\n\w\nБудет удалено:\n- Время\n- Репутация\n- Биты\n\n\yВы уверены?", "Handler_Reset");
    
    menu_additem(menu, "\rДА - Сбросить всё", "yes", 0);
    menu_additem(menu, "\wНЕТ - Отмена", "no", 0);
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu);
    return PLUGIN_HANDLED;
}

public Handler_Reset(id, menu, item) {
    if(item == MENU_EXIT || item < 0) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new info[8], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), "", 0, callback);
    
    if(equal(info, "yes")) {
        ResetPlayerData(id);
        client_print_color(id, print_team_default, "^4[Apex]^1 Ваши данные ^3сброшены^1. Начните заново!");
    } else {
        client_print_color(id, print_team_default, "^4[Apex]^1 Сброс отменён.");
    }
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

ResetPlayerData(id) {
    g_Player[id][Bits] = 0.0;
    g_Player[id][TimePlayed] = 0;
    g_Player[id][Reputation] = 0;
    g_Player[id][SessionStart] = get_systime();
    
    if(g_bSqlReady && g_Player[id][IsLoaded]) {
        new q[256];
        formatex(q, charsmax(q), "UPDATE `%s` SET `bits`=0, `time_played`=0, `reputation`=0 WHERE `authid`='%s'", 
            g_szSqlTable, g_Player[id][AuthID]);
        SQL_ThreadQuery(g_hSqlTuple, "IgnoreHandle", q);
    }
}

public _native_reset_player(plugin, params) {
    new id = get_param(1);
    if(is_user_connected(id)) {
        ResetPlayerData(id);
        return 1;
    }
    return 0;
}

// ============================================================================
// STATS HELPER
// ============================================================================

GetStats(id, &kills, &deaths, &skill_points) {
    kills = 0;
    deaths = 0;
    skill_points = 1000;
    
    if(!is_user_connected(id)) return;
    
    new stats[8], bodyhits[8];
    
    if(get_user_stats_sql(id, stats, bodyhits)) {
        kills = stats[STATS_KILLS];
        deaths = stats[STATS_DEATHS];
        skill_points = stats[STATS_SKILL];
    }
}

// ============================================================================
// PERMISSIONS
// ============================================================================

public bool:_native_check_access(plugin, params) {
    new id = get_param(1);
    if(!is_user_connected(id) || !g_Player[id][IsLoaded]) return false;

    new key[32];
    get_string(2, key, charsmax(key));

    if(!TrieKeyExists(g_tPermissions, key)) return true;

    new Array:reqs;
    TrieGetCell(g_tPermissions, key, reqs);
    new size = ArraySize(reqs);

    new kills, deaths, skill_points;
    new bool:stats_fetched = false;

    new data[ReqItem];
    for(new i = 0; i < size; i++) {
        ArrayGetArray(reqs, i, data);
        switch(data[R_Type]) {
            case REQ_TIME_MINUTES: {
                new minutes = (g_Player[id][TimePlayed] + (get_systime() - g_Player[id][SessionStart])) / 60;
                if(minutes >= data[R_Value]) return true;
            }
            case REQ_KILLS: {
                if(!stats_fetched) { GetStats(id, kills, deaths, skill_points); stats_fetched = true; }
                if(kills >= data[R_Value]) return true;
            }
            case REQ_REAL_SKILL: {
                if(!stats_fetched) { GetStats(id, kills, deaths, skill_points); stats_fetched = true; }
                if(skill_points >= data[R_Value]) return true;
            }
            case REQ_REPUTATION: {
                if(g_Player[id][Reputation] >= data[R_Value]) return true;
            }
            case REQ_FLAG: {
                if(get_user_flags(id) & data[R_Value]) return true;
            }
        }
    }
    return false;
}

LoadPermissionsFile() {
    new path[128];
    get_configsdir(path, charsmax(path));
    add(path, charsmax(path), "/apex_permissions.ini");

    if(!file_exists(path)) {
        log_amx("[Apex] Permissions file missing: %s", path);
        return;
    }

    new f = fopen(path, "rt");
    new line[128], key[32], req_str[96];
    new tokens[5][32];

    while(!feof(f)) {
        fgets(f, line, charsmax(line));
        trim(line);
        if(line[0] == ';' || line[0] == '[' || line[0] == EOS) continue;

        strtok(line, key, charsmax(key), req_str, charsmax(req_str), '=');
        trim(key); trim(req_str);
        if(!key[0]) continue;

        new Array:req_list = ArrayCreate(ReqItem);
        new count = explode_string(req_str, "|", tokens, 5, 31);

        for(new i = 0; i < count; i++) {
            trim(tokens[i]);
            new type[16], val[16];
            strtok(tokens[i], type, 15, val, 15, ':');

            new reqdata[ReqItem];
            reqdata[R_Value] = str_to_num(val);

            if(equali(type, "time")) reqdata[R_Type] = REQ_TIME_MINUTES;
            else if(equali(type, "kills")) reqdata[R_Type] = REQ_KILLS;
            else if(equali(type, "skill")) reqdata[R_Type] = REQ_REAL_SKILL;
            else if(equali(type, "social")) reqdata[R_Type] = REQ_REPUTATION;
            else if(equali(type, "flag")) {
                reqdata[R_Type] = REQ_FLAG;
                reqdata[R_Value] = read_flags(val);
            }
            ArrayPushArray(req_list, reqdata);
        }
        TrieSetCell(g_tPermissions, key, req_list);
    }
    fclose(f);
}

// ============================================================================
// SQL
// ============================================================================

public SQL_Init() {
    new host[64], user[32], pass[32], db[32];
    get_pcvar_string(cvar_sql_host, host, 63);
    get_pcvar_string(cvar_sql_user, user, 31);
    get_pcvar_string(cvar_sql_pass, pass, 31);
    get_pcvar_string(cvar_sql_db, db, 31);
    get_pcvar_string(cvar_sql_table, g_szSqlTable, 31);

    g_hSqlTuple = SQL_MakeDbTuple(host, user, pass, db);

    // Updated table with FLOAT for bits
    new query[512];
    formatex(query, charsmax(query), 
        "CREATE TABLE IF NOT EXISTS `%s` (\
        `id` INT AUTO_INCREMENT PRIMARY KEY, \
        `authid` VARCHAR(32) UNIQUE, \
        `name` VARCHAR(32), \
        `bits` FLOAT DEFAULT 0, \
        `time_played` INT DEFAULT 0, \
        `reputation` INT DEFAULT 0, \
        `last_seen` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP\
        )", g_szSqlTable);

    SQL_ThreadQuery(g_hSqlTuple, "Handler_TableCreated", query);
}

public Handler_TableCreated(FailState, Handle:Q, Error[], Errcode, Data[], DataSize) {
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[Apex] SQL FAILED: %s", Error);
        g_bSqlReady = false;
        return;
    }

    // Add bits column if missing (migration from old table)
    new migrationQuery[256];
    formatex(migrationQuery, charsmax(migrationQuery), 
        "ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `bits` FLOAT DEFAULT 0", g_szSqlTable);
    SQL_ThreadQuery(g_hSqlTuple, "IgnoreHandle", migrationQuery);

    log_amx("[Apex] SQL Ready. Table: %s", g_szSqlTable);
    g_bSqlReady = true;

    new players[32], num;
    get_players(players, num);
    for(new i = 0; i < num; i++) {
        new id = players[i];
        if(!is_user_bot(id) && !g_Player[id][IsLoaded] && !g_Player[id][IsLoading]) {
            LoadPlayer(id);
        }
    }
}

public client_putinserver(id) {
    ResetData(id);
    if(is_user_bot(id)) return;

    get_user_authid(id, g_Player[id][AuthID], 34);
    get_user_name(id, g_Player[id][Name], 31);
    EscapeString(g_Player[id][Name], g_Player[id][NameSafe], 63);
    g_Player[id][SessionStart] = get_systime();

    if(g_bSqlReady) {
        LoadPlayer(id);
    }
}

public client_disconnected(id) {
    if(g_Player[id][IsLoaded] && g_bSqlReady) {
        SavePlayer(id);
    }
    
    // Remove time bonus task
    remove_task(id + 100);
    
    ResetData(id);
}

ResetData(id) {
    g_Player[id][IsLoaded] = false;
    g_Player[id][IsLoading] = false;
    g_Player[id][Bits] = 0.0;
    g_Player[id][TimePlayed] = 0;
    g_Player[id][Reputation] = 0;
    g_Player[id][LikesGivenRound] = 0;
    g_Player[id][LikesGivenMap] = 0;
    g_Player[id][LastLikeTime] = 0;
    g_Player[id][BitsTransferredToday] = 0.0;
    g_Player[id][LastTransferDay] = 0;
    g_Player[id][NameSafe][0] = EOS;
    g_Player[id][Name][0] = EOS;
    g_Player[id][AuthID][0] = EOS;
    g_iLikeTarget[id] = 0;
    g_iRoundKills[id] = 0;
}

LoadPlayer(id) {
    if(!g_bSqlReady || g_Player[id][IsLoading]) return;

    g_Player[id][IsLoading] = true;

    new query[256], data[2];
    data[0] = id;
    data[1] = get_user_userid(id);

    formatex(query, charsmax(query), 
        "SELECT `id`, `bits`, `time_played`, `reputation` FROM `%s` WHERE `authid` = '%s'", 
        g_szSqlTable, g_Player[id][AuthID]);

    SQL_ThreadQuery(g_hSqlTuple, "Handler_Load", query, data, 2);
}

public Handler_Load(FailState, Handle:Q, Error[], Errcode, Data[], DataSize) {
    new id = Data[0];
    new userid = Data[1];

    if(!is_user_connected(id) || get_user_userid(id) != userid) {
        return;
    }

    g_Player[id][IsLoading] = false;

    if(FailState != TQUERY_SUCCESS) {
        log_amx("[Apex] Load Error: %s", Error);
        return;
    }

    if(SQL_NumResults(Q)) {
        g_Player[id][DB_ID] = SQL_ReadResult(Q, 0);
        SQL_ReadResult(Q, 1, g_Player[id][Bits]);
        g_Player[id][TimePlayed] = SQL_ReadResult(Q, 2);
        g_Player[id][Reputation] = SQL_ReadResult(Q, 3);
    } else {
        new q[256];
        formatex(q, charsmax(q), "INSERT INTO `%s` (`authid`, `name`) VALUES ('%s', '%s')", 
            g_szSqlTable, g_Player[id][AuthID], g_Player[id][NameSafe]);
        SQL_ThreadQuery(g_hSqlTuple, "IgnoreHandle", q);
    }

    g_Player[id][IsLoaded] = true;

    // Start time bonus task
    if(get_pcvar_num(cvar_bits_time_enabled)) {
        new Float:interval = get_pcvar_float(cvar_bits_time_interval);
        set_task(interval, "Task_TimeBonus", id + 100);
    }

    new ret;
    ExecuteForward(g_iFwdDataLoaded, ret, id);
}

SavePlayer(id) {
    if(!g_bSqlReady || !g_Player[id][IsLoaded]) return;

    new session_time = get_systime() - g_Player[id][SessionStart];
    g_Player[id][TimePlayed] += session_time;
    g_Player[id][SessionStart] = get_systime();

    get_user_name(id, g_Player[id][Name], 31);
    EscapeString(g_Player[id][Name], g_Player[id][NameSafe], 63);

    new q[512];
    formatex(q, charsmax(q), 
        "UPDATE `%s` SET `bits`=%.1f, `time_played`=%d, `reputation`=%d, `name`='%s' WHERE `authid`='%s'", 
        g_szSqlTable, g_Player[id][Bits], g_Player[id][TimePlayed], g_Player[id][Reputation], 
        g_Player[id][NameSafe], g_Player[id][AuthID]);

    SQL_ThreadQuery(g_hSqlTuple, "IgnoreHandle", q);
}

public IgnoreHandle(FailState, Handle:Q, Error[], Errcode, Data[], DataSize) {
    if(FailState != TQUERY_SUCCESS) log_amx("[Apex] SQL Error: %s", Error);
}

// ============================================================================
// NATIVES IMPLEMENTATION
// ============================================================================

public _native_get_bits(plugin, params) {
    new id = get_param(1);
    return is_user_connected(id) ? floatround(g_Player[id][Bits]) : 0;
}

public Float:_native_get_bits_float(plugin, params) {
    new id = get_param(1);
    return is_user_connected(id) ? g_Player[id][Bits] : 0.0;
}

public _native_set_bits(plugin, params) {
    new id = get_param(1);
    if(is_user_connected(id)) {
        g_Player[id][Bits] = float(get_param(2));
    }
    return 1;
}

public _native_add_bits(plugin, params) {
    new id = get_param(1);
    if(is_user_connected(id)) {
        new Float:amount = get_param_f(2);
        g_Player[id][Bits] += amount;
        if(g_Player[id][Bits] < 0.0) g_Player[id][Bits] = 0.0;
    }
    return 1;
}

public _native_get_reputation(plugin, params) {
    new id = get_param(1);
    return is_user_connected(id) ? g_Player[id][Reputation] : 0;
}

public _native_set_reputation(plugin, params) {
    new id = get_param(1);
    if(is_user_connected(id)) g_Player[id][Reputation] = get_param(2);
    return 1;
}
