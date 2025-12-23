#if defined _apex_core_included
    #endinput
#endif
#define _apex_core_included

/**
 * ============================================================================
 * APEX CORE API - v4.0
 * ============================================================================
 * Include this file in your plugins to access Apex Core natives.
 * ============================================================================
 */

/**
 * Check if player has access to a feature.
 * 
 * @param id            Player index
 * @param permission    Permission key from apex_permissions.ini
 * @return              true if access granted, false otherwise
 */
native bool:apex_check_access(id, const permission[]);

/**
 * Get player's Bits (currency).
 * 
 * @param id    Player index
 * @return      Number of bits
 */
native apex_get_bits(id);

/**
 * Set player's Bits (currency).
 * 
 * @param id    Player index
 * @param bits  New bits value
 * @return      1 on success, 0 if player not connected
 */
native apex_set_bits(id, bits);

/**
 * Get player's Reputation (social score).
 * 
 * @param id    Player index
 * @return      Reputation value
 */
native apex_get_reputation(id);

/**
 * Set player's Reputation.
 * 
 * @param id            Player index
 * @param reputation    New reputation value
 * @return              1 on success, 0 if player not connected
 */
native apex_set_reputation(id, reputation);

/**
 * Reset all player data (time, bits, reputation).
 * 
 * @param id    Player index
 * @return      1 on success, 0 if player not connected
 */
native apex_reset_player(id);

// ============================================================================
// BACKWARD COMPATIBILITY (deprecated, use apex_get_bits/apex_set_bits)
// ============================================================================
native apex_get_credits(id);
native apex_set_credits(id, credits);

// ============================================================================
// FORWARDS
// ============================================================================

/**
 * Called when player data is loaded from database.
 * 
 * @param id    Player index
 */
forward apex_on_data_loaded(id);
