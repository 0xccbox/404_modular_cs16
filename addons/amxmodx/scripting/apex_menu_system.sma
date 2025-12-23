/**
 * ============================================================================
 * APEX MENU SYSTEM - Universal Menu Manager v2.0
 * ============================================================================
 * Version: 2.0.0
 * Author: System Architect
 * 
 * Commands:
 * - /menu, .menu      - Open main menu
 * - /vty, .vty        - Russian keyboard layout support
 * - Nightvision key   - Opens menu (bind friendly)
 * ============================================================================
 */

#include <amxmodx>
#include <amxmisc>
#include <apex_core>

#define PLUGIN  "Apex Menu System"
#define VERSION "2.0.0"
#define AUTHOR  "Architect"

// ============================================================================
// CONFIGURATION
// ============================================================================

#define MAX_MENUS           32
#define MAX_MENU_ITEMS      15
#define MAX_LABEL_LEN       64
#define MAX_CMD_LEN         64
#define MAX_PERM_LEN        32
#define MAX_MENUNAME_LEN    32
#define MAX_HISTORY         8

// ============================================================================
// DATA STRUCTURES
// ============================================================================

enum _:MenuItemData {
    MI_Label[MAX_LABEL_LEN],
    MI_Command[MAX_CMD_LEN],
    MI_Permission[MAX_PERM_LEN],
    MI_SubMenu[MAX_MENUNAME_LEN]
}

enum _:MenuData {
    MD_Title[MAX_LABEL_LEN],
    Array:MD_Items
}

// ============================================================================
// GLOBAL VARIABLES
// ============================================================================

new Trie:g_tMenus;
new g_szPlayerCurrentMenu[33][MAX_MENUNAME_LEN];
new g_szPlayerHistory[33][MAX_HISTORY][MAX_MENUNAME_LEN];
new g_iPlayerHistoryIdx[33];
new g_szConfigPath[128];

// CVars
new g_pCvarHideNoAccess;
new g_pCvarMainMenu;
new g_pCvarNightvision;

// Forward for nightvision
public client_impulse(id, impulse) {
    if(impulse == 100 && get_pcvar_num(g_pCvarNightvision)) {
        Cmd_OpenMainMenu(id);
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// Callback ID
new g_iCallbackId;

// ============================================================================
// PLUGIN LIFECYCLE
// ============================================================================

public plugin_natives() {
    register_library("apex_menu");
    register_native("apex_menu_open", "_native_menu_open");
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
    
    // CVars
    g_pCvarHideNoAccess = register_cvar("apex_menu_hide_noaccess", "1");
    g_pCvarMainMenu = register_cvar("apex_menu_main", "Main");
    g_pCvarNightvision = register_cvar("apex_menu_nightvision", "1"); // 1 = use nightvision key
    
    // Main menu command - /menu only
    register_clcmd("say /menu", "Cmd_OpenMainMenu");
    register_clcmd("say_team /menu", "Cmd_OpenMainMenu");
    register_clcmd("say .menu", "Cmd_OpenMainMenu");
    register_clcmd("say_team .menu", "Cmd_OpenMainMenu");
    
    // Russian keyboard layout: /menu = /vty (when typing on Russian layout)
    register_clcmd("say /vty", "Cmd_OpenMainMenu");
    register_clcmd("say_team /vty", "Cmd_OpenMainMenu");
    register_clcmd("say .vty", "Cmd_OpenMainMenu");
    register_clcmd("say_team .vty", "Cmd_OpenMainMenu");
    
    // Full Russian: /ме|ню -> /ьутг
    register_clcmd("say /ьутг", "Cmd_OpenMainMenu");
    register_clcmd("say_team /ьутг", "Cmd_OpenMainMenu");
    register_clcmd("say .ьутг", "Cmd_OpenMainMenu");
    register_clcmd("say_team .ьутг", "Cmd_OpenMainMenu");
    
    // Initialize data structures
    g_tMenus = TrieCreate();
    
    // Build config path
    get_configsdir(g_szConfigPath, charsmax(g_szConfigPath));
    add(g_szConfigPath, charsmax(g_szConfigPath), "/apex_menu.ini");
    
    // Load menus from config
    LoadMenuConfig();
    
    // Create callback for permission checking
    g_iCallbackId = menu_makecallback("MenuItemCallback");
}

public plugin_end() {
    new TrieIter:iter = TrieIterCreate(g_tMenus);
    new key[MAX_MENUNAME_LEN];
    new menuData[MenuData];
    
    while(!TrieIterEnded(iter)) {
        TrieIterGetKey(iter, key, charsmax(key));
        if(TrieGetArray(g_tMenus, key, menuData, sizeof(menuData))) {
            if(menuData[MD_Items] != Invalid_Array) {
                ArrayDestroy(menuData[MD_Items]);
            }
        }
        TrieIterNext(iter);
    }
    TrieIterDestroy(iter);
    TrieDestroy(g_tMenus);
}

// ============================================================================
// CONFIG PARSER
// ============================================================================

LoadMenuConfig() {
    if(!file_exists(g_szConfigPath)) {
        log_amx("[Apex Menu] Config not found: %s", g_szConfigPath);
        log_amx("[Apex Menu] Creating default config...");
        CreateDefaultConfig();
        return;
    }
    
    new file = fopen(g_szConfigPath, "rt");
    if(!file) {
        log_amx("[Apex Menu] Failed to open config: %s", g_szConfigPath);
        return;
    }
    
    new line[256];
    new currentMenu[MAX_MENUNAME_LEN];
    new menuData[MenuData];
    new bool:inMenu = false;
    new menuCount = 0, itemCount = 0;
    
    while(!feof(file)) {
        fgets(file, line, charsmax(line));
        trim(line);
        
        if(line[0] == EOS || line[0] == ';' || line[0] == '#') {
            continue;
        }
        
        // Check for section header [MenuName]
        if(line[0] == '[') {
            // Save previous menu if exists
            if(inMenu && currentMenu[0]) {
                TrieSetArray(g_tMenus, currentMenu, menuData, sizeof(menuData));
                menuCount++;
            }
            
            // Parse new section name
            new endBracket = contain(line, "]");
            if(endBracket > 1) {
                copy(currentMenu, min(endBracket - 1, MAX_MENUNAME_LEN - 1), line[1]);
                trim(currentMenu);
                
                // Initialize new menu
                menuData[MD_Title][0] = EOS;
                menuData[MD_Items] = ArrayCreate(MenuItemData);
                inMenu = true;
            }
            continue;
        }
        
        if(!inMenu) continue;
        
        // Parse key = value
        new key[32], value[224];
        strtok(line, key, charsmax(key), value, charsmax(value), '=');
        trim(key); trim(value);
        
        if(equali(key, "Title")) {
            ProcessColorCodes(value, menuData[MD_Title], charsmax(menuData[MD_Title]));
        }
        else if(equali(key, "Item")) {
            new itemData[MenuItemData];
            ParseMenuItem(value, itemData);
            ArrayPushArray(menuData[MD_Items], itemData);
            itemCount++;
        }
    }
    
    // Save last menu
    if(inMenu && currentMenu[0]) {
        TrieSetArray(g_tMenus, currentMenu, menuData, sizeof(menuData));
        menuCount++;
    }
    
    fclose(file);
    log_amx("[Apex Menu] Loaded %d menus with %d total items", menuCount, itemCount);
}

ParseMenuItem(const input[], itemData[MenuItemData]) {
    new parts[4][128];
    new partCount = 0;
    new len = strlen(input);
    new partStart = 0;
    
    for(new i = 0; i <= len && partCount < 4; i++) {
        if(input[i] == '|' || input[i] == EOS) {
            new partLen = i - partStart;
            if(partLen > 0 && partLen < 128) {
                copy(parts[partCount], partLen, input[partStart]);
                trim(parts[partCount]);
            }
            partCount++;
            partStart = i + 1;
        }
    }
    
    ProcessColorCodes(parts[0], itemData[MI_Label], MAX_LABEL_LEN - 1);
    copy(itemData[MI_Command], MAX_CMD_LEN - 1, parts[1]);
    copy(itemData[MI_Permission], MAX_PERM_LEN - 1, parts[2]);
    copy(itemData[MI_SubMenu], MAX_MENUNAME_LEN - 1, parts[3]);
    
    trim(itemData[MI_Command]);
    trim(itemData[MI_Permission]);
    trim(itemData[MI_SubMenu]);
}

ProcessColorCodes(const input[], output[], maxlen) {
    new j = 0;
    new len = strlen(input);
    
    for(new i = 0; i < len && j < maxlen - 1; i++) {
        if(input[i] == 92 && i + 1 < len) { // 92 = '\'
            new nextChar = input[i + 1];
            switch(nextChar) {
                case 'y', 'Y': { output[j++] = 0x01; i++; continue; }
                case 'r', 'R': { output[j++] = 0x02; i++; continue; }
                case 'w', 'W': { output[j++] = 0x03; i++; continue; }
                case 'd', 'D': { output[j++] = 0x04; i++; continue; }
            }
        }
        output[j++] = input[i];
    }
    output[j] = EOS;
}

CreateDefaultConfig() {
    new file = fopen(g_szConfigPath, "wt");
    if(!file) return;
    
    fprintf(file, "; APEX MENU SYSTEM CONFIG^n");
    fprintf(file, "; Format: Item = Label | Command | Permission | SubMenu^n^n");
    fprintf(file, "[Main]^n");
    fprintf(file, "Title = \\yApex \\rServer Menu^n");
    fprintf(file, "Item = \\wMy Profile | say /my | |^n");
    fprintf(file, "Item = \\wTop Players | say /top15 | |^n");
    fprintf(file, "Item = \\rAdmin Panel | | menu_admin | Admin^n^n");
    fprintf(file, "[Admin]^n");
    fprintf(file, "Title = \\rAdmin Panel^n");
    fprintf(file, "Item = Kick Player | amx_kickmenu | flag:d |^n");
    fprintf(file, "Item = \\dBack | | | Main^n");
    
    fclose(file);
    log_amx("[Apex Menu] Default config created");
    LoadMenuConfig();
}

// ============================================================================
// MENU DISPLAY
// ============================================================================

public Cmd_OpenMainMenu(id) {
    new mainMenu[MAX_MENUNAME_LEN];
    get_pcvar_string(g_pCvarMainMenu, mainMenu, charsmax(mainMenu));
    
    // Reset navigation history
    g_iPlayerHistoryIdx[id] = 0;
    
    OpenMenu(id, mainMenu);
    return PLUGIN_HANDLED;
}

OpenMenu(id, const menuName[]) {
    if(!is_user_connected(id)) return;
    
    new menuData[MenuData];
    if(!TrieGetArray(g_tMenus, menuName, menuData, sizeof(menuData))) {
        client_print_color(id, print_team_red, "^4[Apex]^1 Menu ^3%s^1 not found!", menuName);
        return;
    }
    
    // Store current menu
    copy(g_szPlayerCurrentMenu[id], MAX_MENUNAME_LEN - 1, menuName);
    
    // Create menu
    new menu = menu_create(menuData[MD_Title], "MenuHandler");
    
    // Add items
    new itemCount = ArraySize(menuData[MD_Items]);
    new itemData[MenuItemData];
    new bool:hideNoAccess = (get_pcvar_num(g_pCvarHideNoAccess) == 1);
    
    for(new i = 0; i < itemCount; i++) {
        ArrayGetArray(menuData[MD_Items], i, itemData);
        
        // Check permission
        new bool:hasAccess = true;
        if(itemData[MI_Permission][0]) {
            hasAccess = bool:apex_check_access(id, itemData[MI_Permission]);
        }
        
        if(!hasAccess && hideNoAccess) {
            continue;
        }
        
        // Prepare item info (store index)
        new info[8];
        num_to_str(i, info, charsmax(info));
        
        if(hasAccess) {
            menu_additem(menu, itemData[MI_Label], info, 0, g_iCallbackId);
        } else {
            // Gray out item
            new grayLabel[MAX_LABEL_LEN];
            grayLabel[0] = 0x04;
            copy(grayLabel[1], MAX_LABEL_LEN - 2, itemData[MI_Label]);
            menu_additem(menu, grayLabel, info, 0, g_iCallbackId);
        }
    }
    
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
}

public MenuItemCallback(id, menu, item) {
    if(item < 0) return ITEM_IGNORE;
    
    new info[8], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback);
    
    new itemIndex = str_to_num(info);
    new menuData[MenuData];
    
    if(!TrieGetArray(g_tMenus, g_szPlayerCurrentMenu[id], menuData, sizeof(menuData))) {
        return ITEM_IGNORE;
    }
    
    if(itemIndex >= ArraySize(menuData[MD_Items])) {
        return ITEM_IGNORE;
    }
    
    new itemData[MenuItemData];
    ArrayGetArray(menuData[MD_Items], itemIndex, itemData);
    
    if(itemData[MI_Permission][0]) {
        if(!apex_check_access(id, itemData[MI_Permission])) {
            return ITEM_DISABLED;
        }
    }
    
    return ITEM_ENABLED;
}

public MenuHandler(id, menu, item) {
    if(item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new info[8], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback);
    
    new itemIndex = str_to_num(info);
    new menuData[MenuData];
    
    if(!TrieGetArray(g_tMenus, g_szPlayerCurrentMenu[id], menuData, sizeof(menuData))) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    if(itemIndex >= ArraySize(menuData[MD_Items])) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    
    new itemData[MenuItemData];
    ArrayGetArray(menuData[MD_Items], itemIndex, itemData);
    
    menu_destroy(menu);
    
    // Check for sub-menu
    if(itemData[MI_SubMenu][0]) {
        if(g_iPlayerHistoryIdx[id] < MAX_HISTORY - 1) {
            copy(g_szPlayerHistory[id][g_iPlayerHistoryIdx[id]], MAX_MENUNAME_LEN - 1, g_szPlayerCurrentMenu[id]);
            g_iPlayerHistoryIdx[id]++;
        }
        
        OpenMenu(id, itemData[MI_SubMenu]);
        return PLUGIN_HANDLED;
    }
    
    // Execute command
    if(itemData[MI_Command][0]) {
        client_cmd(id, itemData[MI_Command]);
    }
    
    return PLUGIN_HANDLED;
}

// ============================================================================
// NATIVES
// ============================================================================

public _native_menu_open(plugin, params) {
    new id = get_param(1);
    
    if(!is_user_connected(id)) {
        return 0;
    }
    
    new menuName[MAX_MENUNAME_LEN];
    get_string(2, menuName, charsmax(menuName));
    
    if(!TrieKeyExists(g_tMenus, menuName)) {
        return 0;
    }
    
    g_iPlayerHistoryIdx[id] = 0;
    OpenMenu(id, menuName);
    return 1;
}

// ============================================================================
// UTILITY
// ============================================================================

public client_disconnected(id) {
    g_iPlayerHistoryIdx[id] = 0;
    g_szPlayerCurrentMenu[id][0] = EOS;
}
