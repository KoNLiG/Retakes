/*
 * • Responsible for selecting a random player as a planter.
 *
 * • Includes all the planter features: moving around in freeze time, 
 * 	 instant plant, etc...
 *
 * • Setups barriers around the site area.
 */

#assert defined COMPILING_FROM_MAIN

float g_PlantOrigin[3];

void PlantLogic_RoundPreStart()
{
	int planter = SelectPlanter();
	
	// Failed to select a random planter
	// meaning that there are 0 player in the defender team, abort.
	if (planter == -1)
	{
		return;
	}
	
	g_Players[planter].spawn_role = SpawnRole_Planter;
	
	// This is too early to setup the planter.
	// The player is gurranted to spawn in the next frame.
	RequestFrame(SetupPlanter, GetClientUserId(planter));
	
	LockupBombsite(g_TargetSite, true);
}

void PlantLogic_RoundFreezeEnd()
{
	int planted_c4 = FindEntityByClassname(-1, "planted_c4");
	if (planted_c4 == -1)
	{
		CreateNaturalPlantedC4();
	}
	
	LockupBombsite(g_TargetSite, false);
}

void PlantLogic_OnBombPlanted(int planter, int bombsite_index, int planted_c4)
{
	#pragma unused planter, bombsite_index, planted_c4
	
	SetFreezePeriod(false);
}

void PlantLogic_OnClientDisconnect(int client)
{
	if (GetPlanter() != client || !GetFreezePeriod())
	{
		return;
	}
	
	CreateNaturalPlantedC4();
}

void SetupPlanter(int userid)
{
	int planter = GetClientOfUserId(userid);
	if (!planter)
	{
		return;
	}
	
	GetClientAbsOrigin(planter, g_PlantOrigin);
	
	DisarmClient(planter);
	
	int c4_entity = GivePlayerItem(planter, "weapon_c4");
	if (c4_entity == -1)
	{
		return;
	}
	
	EquipPlayerWeapon(planter, c4_entity);
	
	UnfreezePlanter(planter);
}

// Generatse a random player index from the defender team to act as a planter.
int SelectPlanter()
{
	int clients_count;
	int[] clients = new int[MaxClients];
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_Players[current_client].spawn_role == SpawnRole_Defender)
		{
			clients[clients_count++] = current_client;
		}
	}
	
	return clients_count ? clients[GetRandomInt(0, clients_count - 1)] : -1;
}

// Retrieves the current planter player index, or -1 if unavailable.
int GetPlanter()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_Players[current_client].spawn_role == SpawnRole_Planter)
		{
			return current_client;
		}
	}
	
	return -1;
}

void UnfreezePlanter(int client)
{
	SetEntProp(client, Prop_Send, "m_bCanMoveDuringFreezePeriod", true, 1);
}

void LockupBombsite(int bombsite, bool value)
{
	char ent_name[16], lookup_name[16];
	Format(lookup_name, sizeof(lookup_name), "retake.%csite", bombsite == Bombsite_A ? 'a' : 'b');
	
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "func_brush")) != -1)
	{
		GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
		if (!StrEqual(ent_name, lookup_name))
		{
			continue;
		}
		
		AcceptEntityInput(ent, value ? "Enable" : "Disable");
	}
}

void CreateNaturalPlantedC4()
{
	int planted_c4 = CreateEntityByName("planted_c4");
	if (planted_c4 == -1 || !DispatchSpawn(planted_c4))
	{
		return;
	}
	
	// Make the to spawn the c4 on the ground.
	TR_TraceRay(g_PlantOrigin, { 90.0, 0.0, 0.0 }, MASK_ALL, RayType_Infinite);
	TR_GetEndPosition(g_PlantOrigin);
	
	TeleportEntity(planted_c4, g_PlantOrigin);
	
	SetEntProp(planted_c4, Prop_Send, "m_bBombTicking", true, 1);
	
	int planter = GetPlanter();
	if (planter == -1)
	{
		PlantLogic_OnBombPlanted(0, g_TargetSite, planted_c4);
		
		return;
	}
	
	// Teleport the planter to the original to avoid exploits.
	float mins[3], maxs[3];
	GetClientMins(planter, mins);
	GetClientMaxs(planter, maxs);
	
	if (ValidateSpawn(planter, g_PlantOrigin, mins, maxs))
	{
		TeleportEntity(planter, g_PlantOrigin);
	}
	
	// Remove the old c4 if exists.
	int weapon_c4 = GetPlayerWeaponSlot(planter, CS_SLOT_C4);
	if (weapon_c4 != -1)
	{
		RemovePlayerItem(planter, weapon_c4);
		RemoveEntity(weapon_c4);
	}
	
	NotifyBombPlanted(planter, g_TargetSite);
}

void NotifyRoundFreezeEnd()
{
	Event event = CreateEvent("round_freeze_end")
	if (event != null)
	{
		event.Fire();
	}
}

void NotifyBombPlanted(int client, int bombsite_index)
{
	Event event = CreateEvent("bomb_planted");
	if (event != null)
	{
		event.SetInt("userid", GetClientUserId(client));
		event.SetInt("site", bombsite_index);
		event.Fire();
	}
}

bool GetFreezePeriod()
{
	return view_as<bool>(GameRules_GetProp("m_bFreezePeriod", 1));
}

void SetFreezePeriod(bool value)
{
	if (GetFreezePeriod() == value)
	{
		return;
	}
	
	GameRules_SetProp("m_bFreezePeriod", value, 1);
	
	if (!value)
	{
		NotifyRoundFreezeEnd();
	}
} 