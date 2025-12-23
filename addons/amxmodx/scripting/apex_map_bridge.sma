#include <amxmodx>
#include <amxmisc>
#include <apex_core>

#define PLUGIN  "Apex Map Bridge"
#define VERSION "1.1.0"
#define AUTHOR  "System Architect"

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    // Register generic say hooks to catch everything before Mistrick
    // Must be placed ABOVE Map Manager in plugins.ini
    register_clcmd("say", "Cmd_Say");
    register_clcmd("say_team", "Cmd_Say");
}

public Cmd_Say(id) {
    if(!is_user_connected(id)) return PLUGIN_CONTINUE;

    new args[64];
    read_args(args, charsmax(args));
    remove_quotes(args);
    trim(args);
    
    // Check RTV
    if(equali(args, "rtv") || equali(args, "/rtv")) {
        if(!apex_check_access(id, "map_rtv")) {
            client_print_color(id, print_team_red, "^4[Apex]^1 Access Denied! ^3RTV requires more experience.^1 Check ^4/profile^1.");
            return PLUGIN_HANDLED; // Block command
        }
    }
    
    // Check Nomination
    else if(equali(args, "maps") || equali(args, "/maps") || equali(args, "nominate") || equali(args, "/nominate")) {
        if(!apex_check_access(id, "map_nominate")) {
            client_print_color(id, print_team_red, "^4[Apex]^1 Access Denied! ^3Nomination requires higher status.^1 Check ^4/profile^1.");
            return PLUGIN_HANDLED; // Block command
        }
    }

    return PLUGIN_CONTINUE; // Allow other plugins (Map Manager) to handle it
}




