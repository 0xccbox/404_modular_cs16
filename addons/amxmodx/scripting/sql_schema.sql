-- ============================================================================
-- APEX CORE DATABASE SCHEMA
-- Version: 3.7.0
-- ============================================================================
-- This schema creates the required table for the Apex Core plugin.
-- Apex Core stores: Time Played, Credits (Economy), Reputation (Social)
-- Kills/Skill data comes from CSStatsX SQL (separate database)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS `server_data` 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE `server_data`;

-- Main player data table
CREATE TABLE IF NOT EXISTS `apex_players` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `authid` VARCHAR(32) NOT NULL UNIQUE COMMENT 'Steam ID (STEAM_X:X:XXXXXXXX)',
    `name` VARCHAR(32) NOT NULL DEFAULT '' COMMENT 'Last known player name',
    `credits` INT NOT NULL DEFAULT 0 COMMENT 'Custom economy credits',
    `time_played` INT NOT NULL DEFAULT 0 COMMENT 'Total time played in SECONDS',
    `reputation` INT NOT NULL DEFAULT 0 COMMENT 'Social reputation (likes from other players)',
    `last_seen` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Auto-updated timestamp',
    
    INDEX `idx_authid` (`authid`),
    INDEX `idx_time_played` (`time_played`),
    INDEX `idx_reputation` (`reputation`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- NOTES:
-- 1. time_played is stored in SECONDS (divide by 60 for minutes, 3600 for hours)
-- 2. Credits can be used for shop systems, VIP features, etc.
-- 3. Reputation increments when players use /like or /thx commands
-- 4. Kills and Skill data are NOT stored here - they come from CSStatsX SQL
-- ============================================================================



