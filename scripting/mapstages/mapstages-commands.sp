public Action Command_TrackStage(int client, int args)
{
	g_bStagesEnabled = true;
	char argument[64];
	GetCmdArg(1, argument, sizeof(argument));
	
	g_iTrackingStage[client] = StringToInt(argument);
	g_bTracking[client] = true;
	
	if(g_iTrackingStage[client] > g_iStageCount)
	{
		g_iStageCount = g_iTrackingStage[client];
	}
	
	PrintToChat(client, "[Stages] Started tracking for stage %s.", argument);
	return Plugin_Handled;
}

public Action Command_StopTracking(int client, int args)
{
	g_bTracking[client] = false;
	PrintToChat(client, "[Stages] Stopped tracking the stage.");
	return Plugin_Handled;
}

public Action Command_AreaInfo(int client, int args)
{
	int iArea = GetAreaForPlayer(client);
	PrintToChat(client, "[Stages] Current area for your position is: %i.", iArea);
	return Plugin_Handled;
}

public Action Command_AutoSave(int client, int args)
{
	if(!g_bAutoSave)
	{
		g_bAutoSave = true;
		PrintToChat(client, "[Stages] Auto-saving is now enabled.");
	} else
	{
		PrintToChat(client, "[Stages] Auto-saving is now disabled.");
		g_bAutoSave = false;
	}
	return Plugin_Handled;
}

public Action Command_DeleteStage(int client, int args)
{
	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	
	StringMapSnapshot snap = g_smClusterMap.Snapshot();
	
	for(int i = 0; i < g_smClusterMap.Size; i++)
	{
		char key[32];
		snap.GetKey(i, key, sizeof(key));
		
		int stage;
		g_smClusterMap.GetValue(key, stage);
		
		if(stage == StringToInt(arg))
		{
			g_smClusterMap.Remove(key);
		}
	}
	
	if(StringToInt(arg) == g_iStageCount)
	{
		if(g_iStageCount == 1)
		{
			g_iStageCount = 0;
			g_bStagesEnabled = false;
		} else
		{
			g_iStageCount--;
		}
	}
	
	PrintToChat(client, "[Stages] Deleted entries for stage: %s.", arg);
	
	if(g_bAutoSave) SaveStageFile();
	return Plugin_Handled;
}

public Action Command_DeleteStages(int client, int args)
{
	char path[PLATFORM_MAX_PATH];
	GetCurrentMap(path, sizeof(path));
	Format(path, sizeof(path), "data/stages/%s.stages", path);
	
	BuildPath(Path_SM, path, sizeof(path), "%s", path);
	
	if(!FileExists(path))
	{
		PrintToChat(client, "[Stages] Could not find stage data file.");
		return Plugin_Handled;
	} else
	{
		g_bStagesEnabled = false;
		if(DeleteFile(path))
		{
			g_smClusterMap.Clear();
			g_iStageCount = 0;
			PrintToChat(client, "[Stages] Deleted all stage data.");
		} else
		{
			PrintToChat(client, "[Stages] Could not delete stage data file.");
		}
		return Plugin_Handled;
	}
}

public Action Command_Replicate(int client, int args)
{
	FindConVar("sv_cheats").ReplicateToClient(client, "1");
	return Plugin_Handled;
}

public Action Command_SetCurrent(int client, int args)
{
	char cluster[32];
	IntToString(GetClusterForPlayer(client), cluster, sizeof(cluster));
	
	if(args == 0)
	{
		g_smClusterMap.SetValue(cluster, g_iTrackingStage[client], true);
		PrintToChat(client, "[Stages] Set current cluster to stage %i.", g_iTrackingStage[client]);
	} else
	{
		char argument[64];
		GetCmdArg(1, argument, sizeof(argument));
		
		if(StringToInt(argument) > g_iStageCount) g_iStageCount = StringToInt(argument);
		
		g_smClusterMap.SetValue(cluster, StringToInt(argument), true);
		PrintToChat(client, "[Stages] Set current cluster to stage %s.", argument);
	}
	g_bStagesEnabled = true;
	if(g_bAutoSave) SaveStageFile();
	return Plugin_Handled;
}

public Action Command_SetCurrentArea(int client, int args)
{
	char area[32];
	IntToString(GetAreaForPlayer(client), area, sizeof(area));
	Format(area, sizeof(area), "a%s", area);
	
	if(args == 0)
	{
		g_smClusterMap.SetValue(area, g_iTrackingStage[client], true);
		PrintToChat(client, "[Stages] Set current area to stage %i.", g_iTrackingStage[client]);
	} else
	{
		char argument[64];
		GetCmdArg(1, argument, sizeof(argument));
		if(StringToInt(argument) > g_iStageCount) g_iStageCount = StringToInt(argument);
		g_smClusterMap.SetValue(area, StringToInt(argument), true);
		PrintToChat(client, "[Stages] Set current area to stage %s.", argument);
	}
	g_bStagesEnabled = true;
	if(g_bAutoSave) SaveStageFile();
	return Plugin_Handled;
}

public Action Command_SaveStages(int client, int args)
{
	PrintToChat(client, "Saving stages to disk.");
	SaveStageFile();
	return Plugin_Handled;
}