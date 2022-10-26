/*
 * • Responsible for managing and generating random players spawns.
 */

#assert defined COMPILING_FROM_MAIN

#define max(%1,%2) (((%1) > (%2)) ? (%1) : (%2))

// This is the the error distance that the player can spawn from the plant area.
#define SPAWN_PLANT_ERROR 15.0

// 64.0 units as for the player model height.
// IIRC it's 48.0 units when crouching.
#define PLAYER_MODEL_HEIGHT 64.0

Bombsite g_Bombsites[Bombsite_Max];

ArrayList g_BombsiteSpawns[Bombsite_Max][NavMeshArea_Max];

// Initialize global vars.
void SpawnManager_OnPluginStart()
{
	for (int i; i < sizeof(g_BombsiteSpawns); i++)
	{
		for (int j; j < sizeof(g_BombsiteSpawns[]); j++)
		{
			g_BombsiteSpawns[i][j] = new ArrayList();
		}
	}
}

void SpawnManager_OnMapStart()
{
	for (int i; i < sizeof(g_Bombsites); i++)
	{
		g_Bombsites[i].Reset();
	}

	// InitializeBombsites();
}

// HACK: apparently initializing the bombsites on 'OnMapStart' is too early,
// 		 'OnConfigsExecuted' is a decent alternative since it's called
// 		 once per map and it's more delayed.
public void OnConfigsExecuted()
{
	InitializeBombsites();
}

void InitializeBombsites()
{
	int player_resource = GetPlayerResourceEntity();
	if (player_resource == -1)
	{
		SetFailState("Failed to get player resource entity.");
	}

	// Get the center position of bombsite A.
	float bombsite_centers[Bombsite_Max][3];
	GetEntPropVector(player_resource, Prop_Send, "m_bombsiteCenterA", bombsite_centers[Bombsite_A]);
	GetEntPropVector(player_resource, Prop_Send, "m_bombsiteCenterB", bombsite_centers[Bombsite_B]);

	// Find all bomb sites on the map.
	Bombsite new_site;
	int ent_index = -1;

	while ((ent_index = FindEntityByClassname(ent_index, "func_bomb_target")) != -1)
	{
		// Get the mins and maxs of the bomb site.
		GetEntPropVector(ent_index, Prop_Send, "m_vecMins", new_site.mins);
		GetEntPropVector(ent_index, Prop_Send, "m_vecMaxs", new_site.maxs);

		// Get the index of the bomb site.
		new_site.bombsite_index = IsVecBetween(
			bombsite_centers[Bombsite_A],
			new_site.mins,
			new_site.maxs
			) ? Bombsite_A : Bombsite_B;

		// Get the center of the bomb site.
		new_site.center = bombsite_centers[new_site.bombsite_index];

		// Save bombsite.
		g_Bombsites[new_site.bombsite_index] = new_site;
	}
}

void SpawnManager_OnPlayerSpawn(int client)
{
	#if defined DEBUG
	static Profiler profiler;
	if (!profiler)
	{
		profiler = new Profiler();
	}

	profiler.Start();
	#endif

	// DO NOT change controlled bots position.
	if (IsControllingBot(client))
	{
		return;
	}

	float origin[3];
	NavArea nav_area;
	if (!GetRandomSpawnLocation(client, origin, nav_area))
	{
		#if defined DEBUG
		profiler.Stop();
		PrintToServer("[SpawnManager_OnPlayerSpawn] VPROF: GetRandomSpawnLocation FAILED");
		#endif
		return;
	}

	float angles[3];
	if (nav_area)
	{
		ComputeRandomSpawnAngles(origin, nav_area, angles);
	}

	TeleportEntity(client, origin, angles);

	#if defined DEBUG
	profiler.Stop();
	PrintToServer("[SpawnManager_OnPlayerSpawn] VPROF: %fs, %fms", profiler.Time, profiler.Time * 1000.0);
	#endif
}

bool GetRandomSpawnLocation(int client, float origin[3], NavArea &nav_area)
{
	if (g_Players[client].spawn_role == SpawnRole_Planter)
	{
		if (!g_Bombsites[g_TargetSite].IsValid())
		{
			return false;
		}

		GenerateSpawnLocation(client, g_Bombsites[g_TargetSite].mins, g_Bombsites[g_TargetSite].maxs, origin);
		return true;
	}

	if ((nav_area = GetSuitableNavArea(client)) == NULL_NAV_AREA)
	{
		// Apparently there are no nav areas configurated.
		return false;
	}

	float mins[3], maxs[3];
	GetClientMins(client, mins);
	GetClientMaxs(client, maxs);

	// Generate a valid randomized spawn origin.
	bool player_collision;

	do
	{
		// Note: If 'nav_area' bounds is only enough to fit a single player entity.
		// 		 an infinite loop will occurre.
		//
		// 		 By checking if there's any player collision, we know if a new navigation area
		// 		 is necessary.
		if (player_collision)
		{
			NavArea new_nav_area = GetSuitableNavArea(client, nav_area);
			if (new_nav_area == NULL_NAV_AREA)
			{
				return false;
			}

			nav_area = new_nav_area;

			player_collision = false;
		}

		nav_area.GetRandomPoint(origin);
	} while (!ValidateSpawn(client, origin, mins, maxs, .player_collision = player_collision));

	return true;
}

// Compute the desired path origin against all the navigation area adjacents.
void ComputeRandomSpawnAngles(float origin[3], NavArea nav_area, float result[3])
{
	ArrayList adjacent_nav_areas = new ArrayList();

	GetNavAdjacentTree(adjacent_nav_areas, nav_area, 5);

	DataPack dp = new DataPack();
	dp.WriteFloatArray(origin, sizeof(origin));

	adjacent_nav_areas.SortCustom(CustomSort_AdjacentNavAreas, dp);

	delete dp;

	float center[3];
	view_as<NavArea>(adjacent_nav_areas.Get(0)).GetCenter(center);

	delete adjacent_nav_areas;

	// Build the player angles towards the desired path.
	MakeAnglesFromPoints(origin, center, result);
}

void GetNavAdjacentTree(ArrayList array, NavArea nav_area, int layers)
{
	if (layers <= 0)
	{
		return;
	}

	for (NavDirType current_dir; current_dir < NUM_DIRECTIONS; current_dir++)
	{
		int size = nav_area.GetAdjacentCount(current_dir);

		for (int current_adjacent_idx; current_adjacent_idx < size; current_adjacent_idx++)
		{
			NavArea adjacent_nav_area = nav_area.GetAdjacentArea(current_dir, current_adjacent_idx);

			if (array.FindValue(adjacent_nav_area) == -1)
			{
				array.Push(adjacent_nav_area);
			}

			GetNavAdjacentTree(array, adjacent_nav_area, layers - 1);
		}
	}
}

/*
 * @return              -1 if first should go before second
 *                      0 if first is equal to second
 *                      1 if first should go after second
 */
int CustomSort_AdjacentNavAreas(int index1, int index2, Handle array, DataPack dp)
{
	dp.Reset();

	float origin[3];
	dp.ReadFloatArray(origin, sizeof(origin));

	ArrayList adjacent_nav_areas = view_as<ArrayList>(array);

	NavArea first_nav_area = adjacent_nav_areas.Get(index1),
	second_nav_area = adjacent_nav_areas.Get(index2);

	bool first_corner = IsNavAreaCornered(first_nav_area);
	bool second_corner = IsNavAreaCornered(second_nav_area);

	// First preference is removing any corndered navigation areas.
	if (first_corner != second_corner)
	{
		return second_corner ? -1 : 1;
	}

	float first_center[3], second_center[3];
	first_nav_area.GetCenter(first_center);
	second_nav_area.GetCenter(second_center);

	origin[2] += PLAYER_MODEL_HEIGHT;

	TR_TraceRayFilter(first_center, origin, MASK_ALL, RayType_EndPoint, Filter_ExcludePlayers);
	bool first_hit = TR_DidHit();

	TR_TraceRayFilter(second_center, origin, MASK_ALL, RayType_EndPoint, Filter_ExcludePlayers);
	bool second_hit = TR_DidHit();

	if (first_hit != second_hit)
	{
		return second_hit ? -1 : 1;
	}

	return FloatCompare(GetVectorDistance(g_Bombsites[g_TargetSite].center, first_center), GetVectorDistance(g_Bombsites[g_TargetSite].center, second_center));
}

bool Filter_ExcludePlayers(int entity, int contentsMask)
{
	return !(1 <= entity <= MaxClients);
}

bool IsNavAreaCornered(NavArea nav_area)
{
	int count;

	for (NavDirType current_dir; current_dir < NUM_DIRECTIONS; current_dir++)
	{
		if (!nav_area.GetAdjacentCount(current_dir))
		{
			count++;
		}
	}

	return count >= NUM_DIRECTIONS / 2;

}

NavArea GetSuitableNavArea(int client, NavArea filter = NULL_NAV_AREA)
{
	if (g_Players[client].spawn_role == SpawnRole_None)
	{
		#if defined DEBUG
		LogError("Spawn role is NONE for client %d, should be %d?, aborting.", client, GetClientTeam(client));

		RequestFrame(Frame_VerifySpawnRole, client);
		#endif

		return NULL_NAV_AREA;
	}

	ArrayList suitable_areas = g_BombsiteSpawns[g_TargetSite][g_Players[client].spawn_role - (SpawnRole_Max - NavMeshArea_Max)].Clone();

	// Atempt to erase the filtered nav area.
	if (filter != NULL_NAV_AREA)
	{
		int idx = suitable_areas.FindValue(filter);
		if (idx != -1)
		{
			suitable_areas.Erase(idx);
		}
	}

	NavArea result;

	if (suitable_areas.Length)
	{
		result = suitable_areas.Get(GetURandomInt() % suitable_areas.Length);
	}

	delete suitable_areas;

	return result;
}

void Frame_VerifySpawnRole(int client)
{
	LogError("[Frame_VerifySpawnRole] Spawn role is NONE for client %d, should be %d?", client, GetClientTeam(client));
}

// Generates a randomized origin vector with the given boundaries. (mins[3], maxs[3])
void GenerateSpawnLocation(int client, float mins[3], float maxs[3], float result[3])
{
	float cl_mins[3], cl_maxs[3];
	GetClientMins(client, cl_mins);
	GetClientMaxs(client, cl_maxs);

	// Generate random spawn vectors, and don't stop until a valid one has found
	do
	{
		result[0] = GetRandomFloat(mins[0], maxs[0]);
		result[1] = GetRandomFloat(mins[1], maxs[1]);
		result[2] = max(mins[2], maxs[2]);
	} while (!ValidateSpawn(client, result, cl_mins, cl_maxs, mins, maxs));
}

bool ValidateSpawn(int client, float origin[3], float ent_mins[3], float ent_maxs[3], float mins[3] = NULL_VECTOR, float maxs[3] = NULL_VECTOR, bool &player_collision = false)
{
	origin[2] += PLAYER_MODEL_HEIGHT;

	TR_TraceRayFilter(origin, { 90.0, 0.0, 0.0 }, MASK_ALL, RayType_Infinite, Filter_ValidateSpawnTrace, client);

	float normal[3];
	TR_GetPlaneNormal(INVALID_HANDLE, normal);
	TR_GetEndPosition(origin);

	if (!(normal[2] < 0.5 && normal[2] > -0.5))
	{
		NegateVector(normal);

		origin[0] += normal[0] * -3;
		origin[1] += normal[1] * -3;
		origin[2] += normal[2] * -3;
	}

	if (!IsNullVector(mins) && !IsNullVector(maxs) && !IsVecBetween(origin, mins, maxs))
	{
		return false;
	}

	float hull_origin[3]; hull_origin = origin;
	hull_origin[2] += normal[2] * -3;

	TR_TraceHullFilter(hull_origin, hull_origin, ent_mins, ent_maxs, MASK_ALL, Filter_ValidateSpawnTrace, client);

	player_collision = (1 <= TR_GetEntityIndex() <= MaxClients);

	return !TR_DidHit();
}

bool Filter_ValidateSpawnTrace(int entity, int mask, int data)
{
	return entity != data && !IsEntitySiteBarrier(entity);
}

bool IsVecBetween(float vec[3], float mins[3], float maxs[3], float err = 0.0)
{
	return (
		(mins[0] - err <= vec[0] <= maxs[0] + err) &&
		(mins[1] - err <= vec[1] <= maxs[1] + err) &&
		(mins[2] - err <= vec[2] <= maxs[2] + err)
		);
}

// Builds an angles vector towards pt2 from pt1.
stock void MakeAnglesFromPoints(const float pt1[3], const float pt2[3], float angles[3])
{
	float result[3];
	MakeVectorFromPoints(pt1, pt2, result);
	GetVectorAngles(result, angles);
}

bool IsControllingBot(int client)
{
	return GetEntProp(client, Prop_Send, "m_bIsControllingBot");
}

bool IsEntitySiteBarrier(int entity)
{
	char entity_name[16];
	GetEntityName(entity, entity_name, sizeof(entity_name));

	return strcmp(entity_name, "retake") == true;
}

int GetEntityName(int entity, char[] buffer, int maxlength)
{
	// 'GetEntDataString' doesn't support indexed string!
	/*
	static int m_iNameOffset;
	if (!m_iNameOffset)
	{
		m_iNameOffset = FindSendPropInfo("CBaseEntity", "m_iName");
	}

	return GetEntDataString(entity, m_iNameOffset, buffer, maxlength);
	*/

	return GetEntPropString(entity, Prop_Data, "m_iName", buffer, maxlength);
}