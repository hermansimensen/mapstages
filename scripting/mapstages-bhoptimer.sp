
#define DEBUG

#define PLUGIN_NAME           "MapStages-bhop"
#define PLUGIN_AUTHOR         "carnifex"
#define PLUGIN_DESCRIPTION    "bhoptimer module for mapstages."
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            ""

#define TIME_SPENT 0
#define TIME_TOTAL 1

#include <sourcemod>
#include <sdktools>
#include <shavit>
#include <mapstages>

#pragma semicolon 1

float g_fWRTimes[50][2];
int g_iMenuStyle[MAXPLAYERS + 1];

int g_iFurthestStage[MAXPLAYERS + 1];
float g_fLastTime[MAXPLAYERS + 1];
float g_fTime[MAXPLAYERS + 1][50][2]; //setting 128 as a max stage limit for now. No one needs more than that... right?
float g_fStageWR[STYLE_LIMIT][50];
char g_sWRHolder[STYLE_LIMIT][50][32];
Database g_hDatabase;
char g_sMap[PLATFORM_MAX_PATH];
bool g_bEnabled;

ArrayList g_aStages[MAXPLAYERS + 1];
ArrayList g_aCheckpoints[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

enum struct stage_t
{
	int iStage;
	float fLastTime;
	float fSpentTime;
	float fTotalTime;
	int iFurthestStage;
}

public void OnPluginStart()
{
	LoadSQL();
	CreateDefaultTables();
	
	RegAdminCmd("sm_enablerecords", Command_Enable, ADMFLAG_RCON);
	RegAdminCmd("sm_disablerecords", Command_Disable, ADMFLAG_RCON);
	
	RegConsoleCmd("sm_stagewr", Command_WR, "List stage WR's for map");
}

public Action Command_WR(int client, int args)
{
	OpenStyleMenu(client);
	
	return Plugin_Handled;
}

public void OpenStyleMenu(int client)
{
	Menu menu = new Menu(MenuHandler_StyleMenu);
	menu.SetTitle("Select a style.");
	
	for(int i = 0; i < Shavit_GetStyleCount(); i++)
	{
		char name[32];
		Shavit_GetStyleStrings(i, sStyleName, name, sizeof(name));
		char index[16];
		IntToString(i, index, 16);
		
		menu.AddItem(index, name);
	}
	
	menu.Display(client, 60);
}

public int MenuHandler_StyleMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		
		g_iMenuStyle[param1] = StringToInt(info);
		
		OpenStageMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenStageMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Stages);
	menu.SetTitle("Select a stage.");
	
	for(int i = 1; i < MS_GetStageCount(); i++)
	{
		char index[32];
		IntToString(i, index, sizeof(index));
		
		char fmt[48];
		Format(fmt, sizeof(fmt), "Stage %s", index);
		
		menu.AddItem(index, fmt);
	}
	
	menu.Display(client, 60);
}

public int MenuHandler_Stages(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		
		int index = StringToInt(info);
		
		LoadWRsForStyle(param1, index);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenWRMenu(int client)
{

}

public int MenuHandler_Listing(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{

	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OnMapStart()
{
	GetCurrentMap(g_sMap, sizeof(g_sMap));
	g_bEnabled = false;
	CheckMapEnabled();
	
	LoadMapWRs();
}

public void OnClientPutInServer(int client)
{
	for(int y = 0; y < MS_GetStageCount(); y++)
	{
		g_fTime[client][y][TIME_SPENT] = 0.0;
		g_fTime[client][y][TIME_TOTAL] = 0.0;
	}
	
	CheckPlayerEntry(client);
	
	UpdatePlayerData(client, Shavit_GetBhopStyle(client));
	
	if(g_aStages[client] == null)
	{
		g_aStages[client] = new ArrayList(sizeof(stage_t));
	} else
	{
		g_aStages[client].Clear();
	}
	
	if(g_aCheckpoints[client] == null)
	{
		g_aCheckpoints[client] = new ArrayList(sizeof(stage_t));
	} else
	{
		g_aCheckpoints[client].Clear();
	}
}

public void OnClientDisconnect(int client)
{
	for(int i = 0; i < g_aCheckpoints[client].Length; i++)
	{
		ArrayList list = g_aCheckpoints[client].Get(i);
		delete list;
	}
	
	g_aStages[client].Clear();
	delete g_aCheckpoints[client];
}

public Action Command_Enable(int client, int args)
{
	EnableMap();
	PrintToChat(client, "[Stages] Enabled stage WRs on this map.");
}

public Action Command_Disable(int client, int args)
{
	DisableMap();
	PrintToChat(client, "[Stages] Disabled stage WRs on this map.");
}

/*
 * SQL STUFF
 */

public void LoadSQL()
{
	char errorMsg[255];
	if(SQL_CheckConfig("mapstages"))
	{
		if((g_hDatabase = SQL_Connect("mapstages", true, errorMsg, sizeof(errorMsg))) == null)
		{
			SetFailState("[Stages] Could not connect to database. Error: %s", errorMsg);
		}
	}
}

public void LoadMapWRs()
{
	for(int i = 0; i < Shavit_GetStyleCount(); i++)
	{
		for(int y = 1; y < MS_GetStageCount(); y++)
		{
			char query[1024];
			FormatEx(query, sizeof(query), "SELECT stagetimes.stage, stagetimes.style, stagetimes.timespent, stageusers.name FROM stagetimes INNER JOIN stageusers ON stagetimes.steamauth = stageusers.steamauth WHERE style = '%i' and map = '%s' and stage = '%i' ORDER BY stagetimes.timespent ASC LIMIT 1;", i, g_sMap, y);
			g_hDatabase.Query(Callback_WRLoad, query);
		}
	}
}

public void Callback_WRLoad(Database db, DBResultSet results, const char[] error, any data)
{
	while(results.FetchRow())
	{
		int stage = results.FetchInt(0);
		int style = results.FetchInt(1);
		g_fStageWR[style][stage] = results.FetchFloat(2);
		results.FetchString(3, g_sWRHolder[style][stage], 160);
	}
}

public void CheckPlayerEntry(int client)
{
	char query[1024];
	FormatEx(query, sizeof(query), "SELECT name FROM stageusers WHERE steamauth = '%i';", GetSteamAccountID(client));
	g_hDatabase.Query(Callback_PlayerEntry, query, GetClientSerial(client));
}

public void LoadWRsForStyle(int client, int stage)
{
	char query[1024];
	FormatEx(query, sizeof(query), "SELECT stagetimes.timespent, stagetimes.currenttime, stagetimes.stage, stagetimes.steamauth, stageusers.name FROM stagetimes INNER JOIN stageusers ON stagetimes.steamauth = stageusers.steamauth WHERE stagetimes.map = '%s' and stagetimes.style = %i and stagetimes.stage = %i ORDER BY stagetimes.timespent ASC LIMIT 50", g_sMap, g_iMenuStyle[client], stage);
	g_hDatabase.Query(Callback_LoadWRs, query, GetClientSerial(client));
}

public void Callback_LoadWRs(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	Menu menu = new Menu(MenuHandler_Listing);

	menu.SetTitle("Stage WR list");
	
	int i = 0;
	while(results.FetchRow())
	{
		g_fWRTimes[i][TIME_SPENT] = results.FetchFloat(0);
		g_fWRTimes[i][TIME_TOTAL] = results.FetchFloat(1);
		char name[32];
		results.FetchString(4, name, 32);
		
		char stagetime[16];
		FormatSeconds(g_fWRTimes[i][TIME_SPENT], stagetime, sizeof(stagetime));
		char timertime[16];
		FormatSeconds(g_fWRTimes[i][TIME_TOTAL], timertime, sizeof(timertime));
		char display[64];
		Format(display, sizeof(display), "%s - Stage: %s - Timer: %s", name, stagetime, timertime);
		
		menu.AddItem("", display, ITEMDRAW_DISABLED);
	}
	menu.Display(client, 60);
}

public void Callback_PlayerEntry(Database db, DBResultSet results, const char[] error, any data)
{
	char playerName[160];
	int client = GetClientFromSerial(data);
	GetClientName(client, playerName, sizeof(playerName));
	
	if(client == 0)
		return;
	
	if(results.RowCount == 0)
	{
		char query[1024];
		FormatEx(query, sizeof(query), "INSERT INTO `stageusers` (`name`, `steamauth`) VALUES ('%s', '%i');", playerName, GetSteamAccountID(client));
		g_hDatabase.Query(Callback_InsertMap, query);
	} else
	{
		char query[1024];
		FormatEx(query, sizeof(query), "DELETE FROM stageusers WHERE steamauth = '%i';", GetSteamAccountID(client));
		g_hDatabase.Query(Callback_InsertMap, query);
		FormatEx(query, sizeof(query), "INSERT INTO `stageusers` (`name`, `steamauth`) VALUES ('%s', '%i');", playerName, GetSteamAccountID(client));
		g_hDatabase.Query(Callback_InsertMap, query);
	}
}

public void UpdatePlayerData(int client, int style)
{
	for(int y = 0; y < MS_GetStageCount(); y++)
	{
		g_fTime[client][y][TIME_SPENT] = 0.0;
		g_fTime[client][y][TIME_TOTAL] = 0.0;
	}
	
	char query[1024];
	FormatEx(query, sizeof(query), "SELECT currenttime, timespent, stage FROM stagetimes WHERE steamauth = %i and map = '%s' and style = %i;", GetSteamAccountID(client), g_sMap, style);
	g_hDatabase.Query(Callback_UpdatePlayerData, query, GetClientSerial(client));
}

public void CreateDefaultTables()
{
	char query[1024];
	FormatEx(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `stagetimes` (`index` INT(11) NOT NULL AUTO_INCREMENT, `steamauth` INT(11) NOT NULL, `map` CHAR(160) NOT NULL, `currenttime` FLOAT(23,8) NOT NULL, `timespent` FLOAT(23,8) NOT NULL, `style` TINYINT(4) NOT NULL, `stage` INT(11) NOT NULL, PRIMARY KEY (`index`)) ENGINE=INNODB;");
	g_hDatabase.Query(Callback_TableCreation, query);
  	FormatEx(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `stagemaps` ( `map` CHAR(160) NOT NULL, `enabled` TINYINT(4) NULL, PRIMARY KEY (`map`)) ENGINE=INNODB;");
	g_hDatabase.Query(Callback_TableCreation, query);
	FormatEx(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `stageusers` ( `name` CHAR(160) NOT NULL, `steamauth` INT(11) NOT NULL, PRIMARY KEY (`steamauth`)) ENGINE=INNODB;");
	g_hDatabase.Query(Callback_TableCreation, query);
}

public void CheckMapEnabled()
{
	char query[1024];
	FormatEx(query, sizeof(query), "SELECT enabled FROM stagemaps WHERE map = '%s';", g_sMap);
	g_hDatabase.Query(Callback_MapEnabled, query);
}

public void DisableMap()
{
	g_bEnabled = false;
	UpdateEnabled();
}

public void EnableMap()
{
	g_bEnabled = true;
	UpdateEnabled();
}

public void UpdateEnabled()
{
	char query[1024];
	FormatEx(query, sizeof(query), "UPDATE `stagemaps` SET `enabled` = '%i' WHERE (`map` = '%s');", g_bEnabled, g_sMap);
	g_hDatabase.Query(Callback_InsertMap, query);
}

public void UpdatePB(int client, float time, float timerTime, int stage, int style)
{
	char query[2048];
	FormatEx(query, sizeof(query), "DELETE FROM stagetimes WHERE map = '%s' and style = '%i' and steamauth = '%i' and stage = '%i';", g_sMap, style, GetSteamAccountID(client), stage);
	g_hDatabase.Query(Callback_UpdatePB, query);
	FormatEx(query, sizeof(query), "INSERT INTO `stagetimes` (`steamauth`, `map`, `currenttime`, `timespent`, `style`, `stage`) VALUES ('%i', '%s', '%f', '%f', '%i', '%i');", GetSteamAccountID(client), g_sMap, timerTime, time, style, stage);
	g_hDatabase.Query(Callback_UpdatePB, query, GetClientSerial(client));
}

public void Callback_UpdatePB(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		SetFailState("[Stages] Failed to update PB. %s", error);
	}
	
	int client = GetClientFromSerial(data);
	
	if(client > 0)
		UpdatePlayerData(client, Shavit_GetBhopStyle(client));
}

public void Callback_MapEnabled(Database db, DBResultSet results, const char[] error, any data)
{
	if(results.RowCount != 0)
	{
		while(results.FetchRow())
		{
			int enabled = results.FetchInt(0);
			if(enabled)
				g_bEnabled = true;
		}
	} else
	{
		char query[1024];
		FormatEx(query, sizeof(query), "INSERT INTO `stagemaps` (`map`, `enabled`) VALUES ('%s', '0');", g_sMap);
		g_hDatabase.Query(Callback_InsertMap, query);
	}
}

public void Callback_InsertMap(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		SetFailState("[Stages] Failed to create entry for map. %s", error);
	}
}

public void Callback_TableCreation(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		SetFailState("[Stages] Failed to create tables. %s", error);
	}
}

public void Callback_UpdatePlayerData(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		LogError("[Stages] Failed to update playerdata. %s", error);
	} else {
		
		int client = GetClientFromSerial(data);
		
		if(client == 0)
		{
			return;
		}
		
		while(results.FetchRow())
		{
			float currentTime = results.FetchFloat(0);
			float spentTime = results.FetchFloat(1);
			int stage = results.FetchInt(2);
			
			g_fTime[client][stage][TIME_SPENT] = spentTime;
			g_fTime[client][stage][TIME_TOTAL] = currentTime;
		}
	}
}

/*
 * SQL STUFF END
 */


public Action Shavit_OnStart(int client, int track)
{
	if(track == Track_Main)
	{
		g_iFurthestStage[client] = MS_GetClientStage(client);
		g_fLastTime[client] = 0.0;
		g_aStages[client].Clear();
	}
}

public Action Shavit_OnTeleport(int client, int index)
{	
	delete g_aStages[client];
	ArrayList checkPoint = g_aCheckpoints[client].Get(index);
	g_aStages[client] = checkPoint.Clone();
	
	for(int i = 0; i < checkPoint.Length; i++)
	{
		stage_t stage;
		g_aStages[client].GetArray(i, stage);
		g_fTime[client][stage.iStage][TIME_SPENT] = stage.fSpentTime;
		g_fTime[client][stage.iStage][TIME_TOTAL] = stage.fTotalTime;
		g_fLastTime[client] = stage.fLastTime;
		g_iFurthestStage[client] = stage.iFurthestStage;
	}
	
	
}

public Action Shavit_OnSave(int client, int index, bool overflow)
{
	timer_snapshot_t snap;
	Shavit_SaveSnapshot(client, snap, sizeof(snap));
	
	if(g_aStages[client].Length == 0)
	{
		stage_t stage;
		stage.iFurthestStage = 1;
		stage.fLastTime = 0.0;
		stage.fSpentTime = g_fTime[client][1][TIME_SPENT];
		stage.fTotalTime = snap.fCurrentTime;
		stage.iStage = 1;
		
		g_aStages[client].PushArray(stage);
	}
	
	ArrayList newArray = g_aStages[client].Clone();

	if(index == g_aCheckpoints[client].Length)
	{
		g_aCheckpoints[client].Push(newArray);
	}
	
	
	else if(index > g_aCheckpoints[client].Length)
	{
		int oldSize = g_aCheckpoints[client].Length;
		g_aCheckpoints[client].Resize(index + 1);

		for(int i = oldSize; i < g_aCheckpoints[client].Length; ++i)
		{
			g_aCheckpoints[client].Set(i, 0);
		}

		g_aCheckpoints[client].Set(index, g_aStages[client].Clone());
	}

	else
	{
		g_aCheckpoints[client].Set(index, g_aStages[client].Clone());
	}


	if(overflow)
	{
		g_aCheckpoints[client].Erase(0);
	}

	return Plugin_Continue;
}

public Action Shavit_OnDelete(int client, int index)
{
	ArrayList list = g_aCheckpoints[client].Get(index);
	g_aCheckpoints[client].Erase(index);
	delete list;
}

public void MS_OnStageChanged(int client, int oldstage, int newstage)
{
	if(!g_bEnabled)
		return; 
		
	if(Shavit_GetTimerStatus(client) != Timer_Running || newstage == 1 || Shavit_IsPracticeMode(client))
		return;
	
	if(newstage > g_iFurthestStage[client])
	{
		g_iFurthestStage[client] = newstage;
		
		timer_snapshot_t snap;
		Shavit_SaveSnapshot(client, snap, sizeof(timer_snapshot_t));
		
		float time = snap.fCurrentTime - g_fLastTime[client];
		
		char timeString[64];
		FormatSeconds(time, timeString, sizeof(timeString));
		
		char timeDiff[64];
		FormatSeconds(g_fTime[client][oldstage][TIME_SPENT] - time, timeDiff, sizeof(timeDiff));
	
		if(g_fTime[client][oldstage][TIME_SPENT] != 0.0)
		{
			if((time < g_fTime[client][oldstage][TIME_SPENT])) 
			{
				
				PrintToChat(client, "[Stages] New PB for stage %i. Time: %s (-%s)", oldstage, timeString, timeDiff);
				UpdatePB(client, time, snap.fCurrentTime, oldstage, snap.bsStyle);
				UpdatePBInCPs(client, time, snap.fCurrentTime, oldstage);
				if(time < g_fStageWR[snap.bsStyle][oldstage])
				{
					LoadMapWRs();
				}
			}
		} else
		{
			PrintToChat(client, "[Stages] New PB for stage %i. Time: %s (-%fs)", oldstage, timeString, timeDiff);
			UpdatePB(client, time, snap.fCurrentTime, oldstage, snap.bsStyle);
			UpdatePBInCPs(client, time, snap.fCurrentTime, oldstage);
			LoadMapWRs();
		}
		
		g_fLastTime[client] = time;
		
		stage_t stage;
		stage.fLastTime = g_fLastTime[client];
		stage.fSpentTime = time;
		stage.fTotalTime = g_fTime[client][oldstage][TIME_TOTAL];
		stage.iFurthestStage = g_iFurthestStage[client];
		stage.iStage = oldstage;
		
		g_aStages[client].PushArray(stage);
	}
}

public void UpdatePBInCPs(int client, float spentTime, float totalTime, int stage)
{
	for(int i = 0; i < g_aCheckpoints[client].Length; i++)
	{
		ArrayList stages = g_aCheckpoints[client].Get(i);
		for(int y = 0; y < stages.Length; y++)
		{
			stage_t staget;
			stages.GetArray(y, staget);
			
			if(staget.iStage == stage)
			{
				staget.fTotalTime = totalTime;
				staget.fSpentTime = spentTime;
				
				stages.SetArray(y, staget);
			}
		}
	}
}

public Action Shavit_OnTopLeftHUD(int client, int target, char[] topleft, int topleftlength)
{
	if(!g_bEnabled)
		return Plugin_Continue;
	
	char timeString[64];
	if(g_fTime[client][MS_GetClientStage(client)][TIME_SPENT] != 0.0)
	{
		FormatSeconds(g_fTime[client][MS_GetClientStage(client)][TIME_SPENT], timeString, sizeof(timeString));
	} else
	{
		Format(timeString, sizeof(timeString), "N/A");
	}
	
	char wrString[64];
	if(g_fStageWR[Shavit_GetBhopStyle(client)][MS_GetClientStage(client)] != 0.0)
	{
		FormatSeconds(g_fStageWR[Shavit_GetBhopStyle(client)][MS_GetClientStage(client)], wrString, sizeof(wrString));
		Format(wrString, sizeof(wrString), "%s (%s)", wrString, g_sWRHolder[Shavit_GetBhopStyle(client)][MS_GetClientStage(client)]);
	} else
	{
		Format(wrString, sizeof(wrString), "N/A");
	}
	
	Format(topleft, topleftlength, "%s \nStage WR: %s\nStage PB: %s", topleft, wrString, timeString);
	return Plugin_Changed;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	UpdatePlayerData(client, newstyle);
}