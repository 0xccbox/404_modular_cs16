#if defined _apex_menu_included
    #endinput
#endif
#define _apex_menu_included

/**
 * Opens a specific menu section for a player.
 * 
 * @param id            Player index
 * @param menu_name     Menu section name (as defined in apex_menu.ini)
 * @return              1 on success, 0 if menu not found or player disconnected
 */
native apex_menu_open(id, const menu_name[]);



