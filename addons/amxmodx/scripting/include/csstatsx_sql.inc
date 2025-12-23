/**
 * ============================================================================
 * CSStatsX SQL v0.7.4+2 (serfreeman1337) - Native Declarations
 * ============================================================================
 * Include file for integration with csstatsx_sql plugin
 * 
 * IMPORTANT: 
 * - ELO starts at 1000 by default
 * - get_user_skill() returns RANK POSITION (#1, #2...), NOT ELO points!
 * - Use stats[7] from get_user_stats_sql() to get actual ELO/Skill points
 * ============================================================================
 */

#if defined _csstatsx_sql_included
    #endinput
#endif
#define _csstatsx_sql_included

/**
 * Stats array indexes for get_user_stats_sql():
 * [0] = kills       - Total kills
 * [1] = deaths      - Total deaths  
 * [2] = headshots   - Headshot kills
 * [3] = teamkills   - Team kills
 * [4] = shots       - Shots fired
 * [5] = hits        - Shots hit
 * [6] = damage      - Total damage dealt
 * [7] = skill       - ELO/Skill points (starts at 1000)
 */

#define STATS_KILLS     0
#define STATS_DEATHS    1
#define STATS_HS        2
#define STATS_TK        3
#define STATS_SHOTS     4
#define STATS_HITS      5
#define STATS_DAMAGE    6
#define STATS_SKILL     7   // ELO points (default 1000)

/**
 * Get player stats from SQL database
 * 
 * @param id        Player index
 * @param stats     Array[8] to store stats (see STATS_* constants above)
 * @param bodyhits  Array[8] to store bodyhit counts per zone
 * @return          Player RANK POSITION (1 = top player), 0 if not ranked
 * 
 * @note stats[7] contains ELO/Skill points, NOT the return value!
 */
native get_user_stats_sql(id, stats[8], bodyhits[8]);

/**
 * Get player rank position (NOT skill points!)
 * 
 * @param id    Player index
 * @return      Rank position (#1 = best player, #2, #3...)
 * 
 * @note This returns RANK POSITION, not ELO! Use stats[7] for ELO.
 */
native get_user_skill(id);

/**
 * Get stats by rank position
 * 
 * @param index     Rank position (1 = top player)
 * @param stats     Array[8] to store stats
 * @param bodyhits  Array[8] to store bodyhit counts
 * @param name      Buffer for player name
 * @param len       Buffer length
 * @return          Next rank index, 0 if no more
 */
native get_stats_sql(index, stats[8], bodyhits[8], name[], len);

/**
 * Get total number of ranked players in database
 * 
 * @return  Total players count
 */
native get_stats_num();
