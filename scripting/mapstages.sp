
#define DEBUG

#define PLUGIN_NAME           "Map Stages"
#define PLUGIN_AUTHOR         "carnifex"
#define PLUGIN_DESCRIPTION    "Advanced map stages for bhop."
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            ""

#include <sourcemod>
#include <sdktools>
#include <mapstages>

#pragma semicolon 1

#pragma newdecls required

Address IVEngineServer;
Handle g_hGetCluster;
Handle g_hGetArea;

bool g_bTracking[MAXPLAYERS + 1];
bool g_bStagesEnabled;
bool g_bAutoSave;
int g_iTrackingStage[MAXPLAYERS + 1];
int g_iStageCount;
int g_iClientTicks[MAXPLAYERS + 1];
int g_iClientStage[MAXPLAYERS + 1];
Handle g_hSyncText;
Handle g_hOnStageChange;

StringMap g_smClusterMap;
ConVar g_cvPath;
char g_sPath[PLATFORM_MAX_PATH];
bool g_bIsSMPath;

#include "mapstages/mapstages-commands.sp"

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	if(GetEngineVersion() != Engine_CSGO && GetEngineVersion() != Engine_CSS)
		SetFailState("This plugin is for the game CSGO/CSS only.");
	
	LoadHooks();
	
	if(g_smClusterMap == null)
	{
		g_smClusterMap = CreateTrie();
	} else
	{
		g_smClusterMap.Clear();
	}
	
	g_cvPath = CreateConVar("stages_file_path", "{SM}/data/stages/", "The path to the folder where stage files should be stored.", FCVAR_PROTECTED);
	AutoExecConfig();
	
	RegAdminCmd("sm_trackstage", Command_TrackStage, ADMFLAG_RCON, "Starts tracking a specified stage.");
	RegAdminCmd("sm_stoptracking", Command_StopTracking, ADMFLAG_RCON, "Stops the stage tracking mode.");
	RegAdminCmd("sm_setleafstage", Command_SetCurrent, ADMFLAG_RCON, "Sets the stage for the current leaf.");
	RegAdminCmd("sm_setareastage", Command_SetCurrentArea, ADMFLAG_RCON, "Sets the stage for the current area.");
	RegAdminCmd("sm_savestages", Command_SaveStages, ADMFLAG_RCON, "Saves stages to file.");
	RegAdminCmd("sm_replicatecheats", Command_Replicate, ADMFLAG_RCON, "Replicates cheat to client to allow mat_leafvis.");
	RegAdminCmd("sm_areainfo", Command_AreaInfo, ADMFLAG_RCON, "Finds the area index of your current position.");
	RegAdminCmd("sm_deletestage", Command_DeleteStage, ADMFLAG_RCON, "Deletes entries of a specified stage.");
	RegAdminCmd("sm_deletestages", Command_DeleteStages, ADMFLAG_RCON, "Deletes all stage data.");
	RegAdminCmd("sm_autosave", Command_AutoSave, ADMFLAG_RCON, "Toggles autosave.");
	
	g_hOnStageChange = CreateGlobalForward("MS_OnStageChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_hSyncText = CreateHudSynchronizer();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("MS_GetClientStage", Native_GetClientStage);
	CreateNative("MS_IsStagesEnabled", Native_StagesEnabled);
	CreateNative("MS_GetStageCount", Native_StageCount);

	RegPluginLibrary("mapstages");

	return APLRes_Success;
}

public int Native_GetClientStage(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	return g_iClientStage[client];
}

public int Native_StagesEnabled(Handle handler, int numParams)
{
	return g_bStagesEnabled;
}

public int Native_StageCount(Handle handler, int numParams)
{
	return g_iStageCount;
}

public void OnMapStart()
{
	LoadPath();
	
	g_iStageCount = 0;
	g_bStagesEnabled = false;
	g_smClusterMap.Clear();
	LoadStages();
}

public void LoadPath()
{
	g_cvPath.GetString(g_sPath, sizeof(g_sPath));
	if(StrContains(g_sPath, "{SM}", false) != -1)
	{
		g_bIsSMPath = true;
		ReplaceString(g_sPath, sizeof(g_sPath), "{sm}", "", false);
	} else
	{
		g_bIsSMPath = false;
	}
}

public void OnClientDisconnect(int client)
{
	g_bTracking[client] = false;
}

public void OnClientPutInServer(int client)
{
	g_bTracking[client] = false;
}

public void LoadStages()
{
	char path[PLATFORM_MAX_PATH];
	GetCurrentMap(path, sizeof(path));
	
	if(g_bIsSMPath)
	{
		Format(path, sizeof(path), "%s/%s.stages", g_sPath, path);
		BuildPath(Path_SM, path, sizeof(path), "%s", path);
	} else
	{
		Format(path, sizeof(path), "file://%s%s.stages", g_sPath, path);
	}
	
	if(!FileExists(path))
	{
		g_bStagesEnabled = false;
		return;
	} else
	{
		g_bStagesEnabled = true;
	}
	
	File file = OpenFile(path, "rb");
	
	char buffer[PLATFORM_MAX_PATH];
	file.ReadLine(buffer, sizeof(buffer));
	
	char exploded[2][32];
	ExplodeString(buffer, ":", exploded, 2, 32);
	
	int size = StringToInt(exploded[1]);
	
	for(int i = 0; i < size; i++)
	{
		file.ReadLine(buffer, sizeof(buffer));
		ExplodeString(buffer, ":", exploded, 2, 32);
		
		int stage = StringToInt(exploded[1]);
		
		g_smClusterMap.SetValue(exploded[0], stage, true);
		
		if(stage > g_iStageCount) g_iStageCount = stage;
	}
	
	//for loading in spawn points, coming later...
	char spawns[4][32];
	while(file.ReadLine(buffer, sizeof(buffer)))
	{
		ExplodeString(buffer, ":", spawns, 4, 32);
	}
	delete file;
}

void LoadHooks()
{
	Handle gamedataConf = LoadGameConfigFile("mapstages.games");

	if(gamedataConf == null)
	{
		SetFailState("Couldn't load gamedata for mapstages.");
	}

	StartPrepSDKCall(SDKCall_Static);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Signature, "CreateInterface"))
	{
		SetFailState("Failed to get CreateInterface");
	}
	
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle CreateInterface = EndPrepSDKCall();

	if(CreateInterface == null)
	{
		SetFailState("Unable to prepare SDKCall for CreateInterface");
	}

	char interfaceName[64];
	if(!GameConfGetKeyValue(gamedataConf, "IVEngineServer", interfaceName, sizeof(interfaceName)))
	{
		SetFailState("Failed to get IVEngineServer interface name");
	}

	IVEngineServer = SDKCall(CreateInterface, interfaceName, 0);

	if(!IVEngineServer)
	{
		SetFailState("Failed to get IVEngineServer pointer");
	}
	
	StartPrepSDKCall(SDKCall_Raw);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Virtual, "GetClusterForOrigin"))
	{
		SetFailState("Couldn't find GetClusterForOrigin offset");
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hGetCluster = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Raw);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Virtual, "GetArea"))
	{
		SetFailState("Couldn't find GetArea offset");
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hGetArea = EndPrepSDKCall();
	
	
	delete CreateInterface;
	delete gamedataConf;
}

public int GetClusterForPlayer(int client)
{
	if(IsFakeClient(client) || !IsClientInGame(client))
	{
		return -1;
	}
	float pos[3];
	GetClientEyePosition(client, pos);
	return SDKCall(g_hGetCluster, IVEngineServer, pos);
}

public int GetAreaForPlayer(int client)
{
	if(IsFakeClient(client) || !IsClientInGame(client))
	{
		return -1;
	}
	float pos[3];
	GetClientEyePosition(client, pos);
	return SDKCall(g_hGetArea, IVEngineServer, pos);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsClientInGame(client) || IsClientConnected(client) || !IsFakeClient(client))
	{
		g_iClientTicks[client]++;
		
		char cluster[32];
		IntToString(GetClusterForPlayer(client), cluster, sizeof(cluster));
		
		if(g_bTracking[client])
		{
			//autosaving not enabled for tracking cause performance goes brrr down the drain. 
			g_smClusterMap.SetValue(cluster, g_iTrackingStage[client], true);
		}
		
		if(g_bStagesEnabled)
		{
			int stage;
			g_smClusterMap.GetValue(cluster, stage);
			
			if(stage == 0)
			{
				int area = GetAreaForPlayer(client);
				char areaStage[32];
				IntToString(area, areaStage, sizeof(areaStage));
				Format(areaStage, sizeof(areaStage), "a%s", areaStage);
				g_smClusterMap.GetValue(areaStage, stage);
			}
			
			//player has entered new stage
			if(g_iClientStage[client] != stage)
			{
				Call_StartForward(g_hOnStageChange);
				Call_PushCell(client);
				Call_PushCell(g_iClientStage[client]);
				Call_PushCell(stage);
				Call_Finish();
			}
			
			g_iClientStage[client] = stage;
			
			//dont update text every single tick
			if(g_iClientTicks[client] >= 60)
			{
				SetHudTextParams(0.45, 1.0, 5.0, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(client, g_hSyncText, "Stage: %i/%i", stage, g_iStageCount);
				g_iClientTicks[client] = 0;
			}
		} else
		{
			g_iClientStage[client] = 0;
		}
	}
	
	return Plugin_Continue;
}

public void SaveStageFile()
{
	char path[PLATFORM_MAX_PATH];
	GetCurrentMap(path, sizeof(path));
	
	if(g_bIsSMPath)
	{
		Format(path, sizeof(path), "%s/%s.stages", g_sPath, path);
		BuildPath(Path_SM, path, sizeof(path), "%s", path);
	} else
	{
		Format(path, sizeof(path), "file://%s%s.stages", g_sPath, path);
	}
	
	if(FileExists(path))
	{
		DeleteFile(path);
	}
	
	File file = OpenFile(path, "wb");
	
	if(file != null)
	{
		StringMapSnapshot snap = g_smClusterMap.Snapshot();
	
		int size = g_smClusterMap.Size;
		
		file.WriteLine("clusters:%i",size);
		
		for(int i = 0; i < g_smClusterMap.Size; i++)
		{
			char key[64];
			snap.GetKey(i, key, sizeof(key));
			int stage;
			g_smClusterMap.GetValue(key, stage);
			file.WriteLine("%s:%i", key, stage);
		}
	}
	
	delete file;
}