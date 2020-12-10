#if defined _mapstages_included
#endinput
#endif
#define _mapstages_included

/**
 * Called when a player enters a stage.
 *
 * @param client					Client index.
 * @param oldstage						Old stage index.
 * @param newstage						New stage index.
 * @noreturn
 */
forward void MS_OnStageChanged(int client, int oldstage, int newstage);

/**
 * Gets the current stage for a player.
 *
 * @param client					Client index.
 * @return							Stage index. 
 */
native int MS_GetClientStage(int client);

/**
 * Gets the amount of stages for the current map.
 *
 * @return							Amount of stages.
 */
native int MS_GetStageCount();

/**
 * Checks if stages for the current map is set, and stages are enabled.
 *
 * @return							True if stages are set and enabled, false otherwise.
 */
native bool MS_IsStagesEnabled();



public SharedPlugin __pl_server_redirect = 
{
	name = "mapstages",
	file = "mapstages.smx",
	#if defined REQUIRE_PLUGIN
		required = 1,
	#else
		required = 0,
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_mapstages_SetNTVOptional()
{
	MarkNativeAsOptional("MS_OnStageChanged");
	MarkNativeAsOptional("MS_GetClientStage");
	MarkNativeAsOptional("MS_IsStagesEnabled");
}
#endif