#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <reapi>

// CSStatsX SQL integration
native get_user_stats_sql(id, stats[8], bodyhits[8]);
native get_user_skill(id); // Returns integer skill points

#define PLUGIN  "Apex Core"
#define VERSION "4.0.0"
#define AUTHOR  "Architect"

// Stats array indexes (CSStatsX SQL v0.7.4+2)
// stats[0] = kills, stats[1] = deaths, stats[2] = hs, stats[3] = tks
// stats[4] = shots, stats[5] = hits, stats[6] = damage, stats[7] = skill (ELO)
#define STATS_KILLS   0
#define STATS_DEATHS  1
#define STATS_HS      2
#define STATS_TK      3
#define STATS_SHOTS   4
#define STATS_HITS    5
#define STATS_DAMAGE  6
#define STATS_SKILL   7

// Skill Ranks (ELO-based, CSStatsX SQL starts at 1000)
// ELO System: Win vs higher = big gain, Lose vs lower = big loss
// Most players stay around 900-1100
#define RANK_M       0    // M:    0-899      (beginner/losing streak)
#define RANK_M_PLUS  1    // M+:   900-999    (below average)
#define RANK_GM      2    // GM:   1000-1099  (average, starting point)
#define RANK_GM_PLUS 3    // GM+:  1100-1199  (above average)
#define RANK_S       4    // S:    1200-1349  (skilled)
#define RANK_S_PLUS  5    // S+:   1350-1499  (very skilled)
#define RANK_P       6    // P:    1500-1699  (pro level)
#define RANK_P_PLUS  7    // P+:   1700+      (elite)

new const g_szRankNames[][] = {
    "M", "M+", "GM", "GM+", "S", "S+", "P", "P+"
};

// ELO thresholds (CSStatsX SQL default start = 1000)
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
    Bits,           // Changed from Credits to Bits
    TimePlayed,
    Reputation,
    SessionStart,
    bool:HasLiked
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

new g_Player[33][PlayerState];
new Handle:g_hSqlTuple = Empty_Handle;
new bool:g_bSqlReady = false;
new g_szSqlTable[32];
new Trie:g_tPermissions;
new cvar_sql_host, cvar_sql_user, cvar_sql_pass, cvar_sql_db, cvar_sql_table;
new g_iFwdDataLoaded;
new bool:g_bCsStatsLoaded = false;

// Menu for /like
new g_iLikeTarget[33]; // Store who player wants to like

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

// Get rank index from skill points
stock GetRankIndex(skill) {
    for(new i = sizeof(g_iRankThresholds) - 1; i >= 0; i--) {
        if(skill >= g_iRankThresholds[i]) {
            return i;
        }
    }
    return RANK_M;
}

// Get rank name from skill points
stock GetRankName(skill, output[], maxlen) {
    new idx = GetRankIndex(skill);
    copy(output, maxlen, g_szRankNames[idx]);
}

public plugin_natives() {
    register_library("apex_core");
    register_native("apex_get_credits", "_native_get_bits");   // Backward compat
    register_native("apex_set_credits", "_native_set_bits");
    register_native("apex_get_bits", "_native_get_bits");      // New name
    register_native("apex_set_bits", "_native_set_bits");
    register_native("apex_get_reputation", "_native_get_reputation");
    register_native("apex_set_reputation", "_native_set_reputation");
    register_native("apex_check_access", "_native_check_access");
    register_native("apex_reset_player", "_native_reset_player");
    
    set_native_filter("native_filter");
}

public native_filter(const name[], index, trap) {
    if(equal(name, "get_user_stats_sql") || equal(name, "get_user_skill")) {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    cvar_sql_host = register_cvar("apex_sql_host", "127.0.0.1");
    cvar_sql_user = register_cvar("apex_sql_user", "root");
    cvar_sql_pass = register_cvar("apex_sql_pass", "");
    cvar_sql_db   = register_cvar("apex_sql_db", "server_data");
    cvar_sql_table = register_cvar("apex_sql_table", "apex_players");

    new cfgDir[64];
    get_configsdir(cfgDir, charsmax(cfgDir));
    server_cmd("exec %s/apex.cfg", cfgDir);
    server_exec();

    g_tPermissions = TrieCreate();
    LoadPermissionsFile();

    RegisterHookChain(RG_RoundEnd, "OnRoundEnd", 1);
    
    // Profile command - only /my and alternatives
    register_clcmd("say /my", "Cmd_Profile");
    register_clcmd("say_team /my", "Cmd_Profile");
    register_clcmd("say .my", "Cmd_Profile");
    register_clcmd("say_team .my", "Cmd_Profile");
    // Russian keyboard layout /ьн
    register_clcmd("say /ьн", "Cmd_Profile");
    register_clcmd("say_team /ьн", "Cmd_Profile");
    register_clcmd("say .ьн", "Cmd_Profile");
    register_clcmd("say_team .ьн", "Cmd_Profile");
    
    // Like command - opens menu
    register_clcmd("say /like", "Cmd_Like");
    register_clcmd("say_team /like", "Cmd_Like");
    register_clcmd("say .like", "Cmd_Like");
    register_clcmd("say_team .like", "Cmd_Like");
    // Russian layout /дшлу
    register_clcmd("say /дшлу", "Cmd_Like");
    register_clcmd("say_team /дшлу", "Cmd_Like");
    
    // Reset data command
    register_clcmd("say /reset", "Cmd_ResetConfirm");
    register_clcmd("say_team /reset", "Cmd_ResetConfirm");

    set_task(1.0, "SQL_Init");
    g_iFwdDataLoaded = CreateMultiForward("apex_on_data_loaded", ET_IGNORE, FP_CELL);
    
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

// Get stats from CSStatsX SQL
// Get stats from CSStatsX SQL v0.7.4+2
// NOTE: get_user_skill() returns RANK POSITION (#1, #2...), NOT ELO points!
// ELO points are stored in stats[7] (STATS_SKILL)
GetStats(id, &kills, &deaths, &skill_points) {
    kills = 0;
    deaths = 0;
    skill_points = 1000; // Default ELO (CSStatsX SQL default)
    
    if(!is_user_connected(id)) return;
    
    new stats[8], bodyhits[8];
    
    // get_user_stats_sql returns rank position, stats[] contains actual data
    if(get_user_stats_sql(id, stats, bodyhits)) {
        kills = stats[STATS_KILLS];
        deaths = stats[STATS_DEATHS];
        skill_points = stats[STATS_SKILL]; // ELO points from stats array
    }
}

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

    // Get rank name
    new rankName[8];
    GetRankName(skill_val, rankName, charsmax(rankName));

    new title[64];
    formatex(title, charsmax(title), "\y%s \w- Profile", g_Player[id][Name]);
    new menu = menu_create(title, "Handler_Profile");

    new buf[128];
    
    // Time
    formatex(buf, charsmax(buf), "\wTime: \y%dh %dm", h, m);
    menu_additem(menu, buf, "", 0);
    
    // Kills with KD
    formatex(buf, charsmax(buf), "\wKills: \y%d \d(KD: %.2f)", kills, kd);
    menu_additem(menu, buf, "", 0);
    
    // Skill as Rank (M, M+, GM, etc)
    formatex(buf, charsmax(buf), "\wRank: \r%s \d(%d pts)", rankName, skill_val);
    menu_additem(menu, buf, "", 0);
    
    // Reputation
    formatex(buf, charsmax(buf), "\wReputation: \y%d", g_Player[id][Reputation]);
    menu_additem(menu, buf, "", 0);
    
    // Bits (was Credits)
    formatex(buf, charsmax(buf), "\wBits: \g%d", g_Player[id][Bits]);
    menu_additem(menu, buf, "", 0);
    
    // Reset option
    menu_additem(menu, "\d--- Actions ---", "", 0);
    menu_additem(menu, "\rReset All Data", "reset", 0);

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
// LIKE COMMAND (Menu with players)
// ============================================================================

public Cmd_Like(id) {
    if(g_Player[id][HasLiked]) {
        client_print_color(id, print_team_default, "^4[Apex]^1 You already gave respect this round. Wait for next round.");
        return PLUGIN_HANDLED;
    }
    
    ShowLikeMenu(id);
    return PLUGIN_HANDLED;
}

ShowLikeMenu(id) {
    new menu = menu_create("\yGive Respect \w- Select Player", "Handler_Like");
    
    new players[32], num;
    get_players(players, num, "ch"); // Skip bots and HLTV
    
    new name[32], info[8];
    new count = 0;
    
    for(new i = 0; i < num; i++) {
        new pid = players[i];
        
        // Skip self
        if(pid == id) continue;
        
        // Skip bots (double check)
        if(is_user_bot(pid)) continue;
        
        get_user_name(pid, name, charsmax(name));
        num_to_str(pid, info, charsmax(info));
        
        menu_additem(menu, name, info, 0);
        count++;
    }
    
    if(count == 0) {
        menu_destroy(menu);
        client_print_color(id, print_team_default, "^4[Apex]^1 No players available to give respect.");
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
    
    if(g_Player[id][HasLiked]) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Already used this round!");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new info[8], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), "", 0, callback);
    
    new target = str_to_num(info);
    
    if(!is_user_connected(target) || is_user_bot(target)) {
        client_print_color(id, print_team_default, "^4[Apex]^1 Player no longer available.");
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    // Give respect
    g_Player[target][Reputation]++;
    g_Player[id][HasLiked] = true;
    
    new targetName[32];
    get_user_name(target, targetName, charsmax(targetName));
    
    client_print_color(id, print_team_default, "^4[Apex]^1 Respect sent to ^3%s^1!", targetName);
    client_print_color(target, print_team_default, "^4[Apex]^3 %s^1 gave you respect! ^4(+1 Rep)^1", g_Player[id][Name]);
    
    // Play sound for target
    client_cmd(target, "spk buttons/bell1");
    
    SavePlayer(target);
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ============================================================================
// RESET DATA COMMAND
// ============================================================================

public Cmd_ResetConfirm(id) {
    new menu = menu_create("\rReset All Data?\n\w\nThis will delete:\n- Time played\n- Reputation\n- Bits\n\n\yAre you sure?", "Handler_Reset");
    
    menu_additem(menu, "\rYES - Reset Everything", "yes", 0);
    menu_additem(menu, "\wNO - Cancel", "no", 0);
    
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
        client_print_color(id, print_team_default, "^4[Apex]^1 Your data has been ^3reset^1. Fresh start!");
    } else {
        client_print_color(id, print_team_default, "^4[Apex]^1 Reset cancelled.");
    }
    
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

ResetPlayerData(id) {
    // Reset in-memory data
    g_Player[id][Bits] = 0;
    g_Player[id][TimePlayed] = 0;
    g_Player[id][Reputation] = 0;
    g_Player[id][SessionStart] = get_systime();
    
    // Reset in database
    if(g_bSqlReady && g_Player[id][IsLoaded]) {
        new q[256];
        formatex(q, charsmax(q), "UPDATE `%s` SET `credits`=0, `time_played`=0, `reputation`=0 WHERE `authid`='%s'", 
            g_szSqlTable, g_Player[id][AuthID]);
        SQL_ThreadQuery(g_hSqlTuple, "IgnoreHandle", q);
    }
}

// Native to reset player (for other plugins)
public _native_reset_player(plugin, params) {
    new id = get_param(1);
    if(is_user_connected(id)) {
        ResetPlayerData(id);
        return 1;
    }
    return 0;
}

// ============================================================================
// ROUND END - Reset like ability
// ============================================================================

public OnRoundEnd() {
    for(new i = 1; i <= MaxClients; i++) {
        g_Player[i][HasLiked] = false;
    }
}

// ============================================================================
// SQL FUNCTIONS
// ============================================================================

public SQL_Init() {
    new host[64], user[32], pass[32], db[32];
    get_pcvar_string(cvar_sql_host, host, 63);
    get_pcvar_string(cvar_sql_user, user, 31);
    get_pcvar_string(cvar_sql_pass, pass, 31);
    get_pcvar_string(cvar_sql_db, db, 31);
    get_pcvar_string(cvar_sql_table, g_szSqlTable, 31);

    g_hSqlTuple = SQL_MakeDbTuple(host, user, pass, db);

    // Note: 'credits' column kept for backward compatibility (stores Bits)
    new query[512];
    formatex(query, charsmax(query), "CREATE TABLE IF NOT EXISTS `%s` (`id` INT AUTO_INCREMENT PRIMARY KEY, `authid` VARCHAR(32) UNIQUE, `name` VARCHAR(32), `credits` INT DEFAULT 0, `time_played` INT DEFAULT 0, `reputation` INT DEFAULT 0, `last_seen` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)", g_szSqlTable);

    SQL_ThreadQuery(g_hSqlTuple, "Handler_TableCreated", query);
}

public Handler_TableCreated(FailState, Handle:Q, Error[], Errcode, Data[], DataSize) {
    if(FailState != TQUERY_SUCCESS) {
        log_amx("[Apex] SQL FAILED: %s", Error);
        g_bSqlReady = false;
        return;
    }

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
    ResetData(id);
}

ResetData(id) {
    g_Player[id][IsLoaded] = false;
    g_Player[id][IsLoading] = false;
    g_Player[id][Bits] = 0;
    g_Player[id][TimePlayed] = 0;
    g_Player[id][Reputation] = 0;
    g_Player[id][HasLiked] = false;
    g_Player[id][NameSafe][0] = EOS;
    g_Player[id][Name][0] = EOS;
    g_Player[id][AuthID][0] = EOS;
    g_iLikeTarget[id] = 0;
}

LoadPlayer(id) {
    if(!g_bSqlReady || g_Player[id][IsLoading]) return;

    g_Player[id][IsLoading] = true;

    new query[256], data[2];
    data[0] = id;
    data[1] = get_user_userid(id);

    formatex(query, charsmax(query), "SELECT `id`, `credits`, `time_played`, `reputation` FROM `%s` WHERE `authid` = '%s'", g_szSqlTable, g_Player[id][AuthID]);

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
        g_Player[id][Bits] = SQL_ReadResult(Q, 1);  // 'credits' column = Bits
        g_Player[id][TimePlayed] = SQL_ReadResult(Q, 2);
        g_Player[id][Reputation] = SQL_ReadResult(Q, 3);
    } else {
        new q[256];
        formatex(q, charsmax(q), "INSERT INTO `%s` (`authid`, `name`) VALUES ('%s', '%s')", g_szSqlTable, g_Player[id][AuthID], g_Player[id][NameSafe]);
        SQL_ThreadQuery(g_hSqlTuple, "IgnoreHandle", q);
    }

    g_Player[id][IsLoaded] = true;

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
    formatex(q, charsmax(q), "UPDATE `%s` SET `credits`=%d, `time_played`=%d, `reputation`=%d, `name`='%s' WHERE `authid`='%s'", 
        g_szSqlTable, g_Player[id][Bits], g_Player[id][TimePlayed], g_Player[id][Reputation], g_Player[id][NameSafe], g_Player[id][AuthID]);

    SQL_ThreadQuery(g_hSqlTuple, "IgnoreHandle", q);
}

public IgnoreHandle(FailState, Handle:Q, Error[], Errcode, Data[], DataSize) {
    if(FailState != TQUERY_SUCCESS) log_amx("[Apex] SQL Error: %s", Error);
}

// ============================================================================
// NATIVES
// ============================================================================

public _native_get_bits(plugin, params) {
    new id = get_param(1);
    return is_user_connected(id) ? g_Player[id][Bits] : 0;
}

public _native_set_bits(plugin, params) {
    new id = get_param(1);
    if(is_user_connected(id)) g_Player[id][Bits] = get_param(2);
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
