/*
 * • Responsible for parsing and storing all the spawn zones.
 * • As well as features an Edit-Mode which admins can configurate spawn zones.
 */

#assert defined COMPILING_FROM_MAIN

#define MYSQL_TABLE_NAME "retakes_spawn_areas"

#define MAX_MAP_NAME_LENGTH 128

// 'TheNavAreas' address.
TheNavAreas g_TheNavAreas;

char g_CurrentMapName[MAX_MAP_NAME_LENGTH];

void Configuration_OnPluginStart()
{
	g_TheNavAreas = TheNavAreas();
	
	RegisterConVars();
	RegisterCommands();
}

void RegisterConVars()
{
	
	
	// TODO: Create a configuration file.
	// AutoExecConfig();
}

// Register all plugin commands.
void RegisterCommands()
{
	RegConsoleCmd("sm_retakes", Command_Retakes, "Retake settings.");
	
	RegServerCmd("retakes_reloadnav", Command_ReloadNav, "Reloads the navigation spawn areas.");
}

void Configuration_OnMapStart()
{
	// Store the new map name!
	GetCurrentMap(g_CurrentMapName, sizeof(g_CurrentMapName));
	
	// The spawns can be reloaded by running the server command 'retakes_reloadnav'
	LoadSpawnAreas();
}

//================================[ Database ]================================//

void Configuration_OnDatabaseConnection()
{
	char query[256];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s`(`map_name` VARCHAR(%d) NOT NULL, `nav_area_index` INT NOT NULL, `bombsite_index` INT NOT NULL, `nav_mesh_area_team` INT NOT NULL, UNIQUE(`nav_area_index`, `bombsite_index`, `nav_mesh_area_team`))", MYSQL_TABLE_NAME, MAX_MAP_NAME_LENGTH);
	g_Database.Query(SQL_OnSpawnTableCreated, query);
	
	// Load all the spawn areas here, if couldn't on 'Configuration_OnMapStart'.
	LoadSpawnAreas();
}

void SQL_OnSpawnTableCreated(Database db, DBResultSet results, const char[] error, any data)
{
	// An error has occurred
	if (!db || !results || error[0])
	{
		ThrowError("Couldn't create navigation spawn areas table (%s)", error);
	}
}

void LoadSpawnAreas()
{
	if (!g_Database)
	{
		return;
	}
	
	// Clear the old spawns.
	for (int i; i < sizeof(g_BombsiteSpawns); i++)
	{
		for (int j; j < sizeof(g_BombsiteSpawns[]); j++)
		{
			g_BombsiteSpawns[i][j].Clear();
		}
	}
	
	char query[256];
	Format(query, sizeof(query), "SELECT `nav_area_index`, `bombsite_index`, `nav_mesh_area_team` FROM `%s` WHERE `map_name` = '%s'", MYSQL_TABLE_NAME, g_CurrentMapName);
	g_Database.Query(SQL_OnLoadSpawnAreas, query);
}

void SQL_OnLoadSpawnAreas(Database db, DBResultSet results, const char[] error, any data)
{
	// An error has occurred
	if (!db || !results || error[0])
	{
		ThrowError("Couldn't load navigation spawn areas (%s)", error);
	}
	
	if (!results.FetchRow())
	{
		LogError("Couldn't import any retakes navigation areas. Configuration can be made by running the command 'sm_retakes' in-game");
		return;
	}
	
	// Iterate through all the map spawn areas...
	do
	{
		int nav_area_index = results.FetchInt(0);
		if (!(0 <= nav_area_index < g_TheNavAreas.size))
		{
			LogError("Invalid navigation area index. (%d)", nav_area_index);
			continue;
		}
		
		int bombsite_index = results.FetchInt(1);
		if (!(Bombsite_None < bombsite_index < Bombsite_Max))
		{
			LogError("Invalid bombsite index for navigation area #%d.", nav_area_index);
			continue;
		}
		
		int nav_mesh_area_team = results.FetchInt(2);
		if (!(-1 < nav_mesh_area_team < NavMeshArea_Max))
		{
			LogError("Invalid team index for navigation area #%d.", nav_area_index);
			continue;
		}
		
		NavArea nav_area = g_TheNavAreas.Get(nav_area_index);
		if (nav_area == NULL_NAV_AREA)
		{
			LogError("Failed to retrieve a CNavArea address for index #%d.", nav_area_index);
			continue;
		}
		
		g_BombsiteSpawns[bombsite_index][nav_mesh_area_team].Push(nav_area);
		
	} while (results.FetchRow());
}

void InsertSpawnArea(int nav_area_index, int bombsite_index, int nav_mesh_area_team)
{
	char query[256];
	Format(query, sizeof(query), "INSERT INTO `%s` VALUES ('%s', %d, %d, %d)", MYSQL_TABLE_NAME, g_CurrentMapName, nav_area_index, bombsite_index, nav_mesh_area_team);
	g_Database.Query(SQL_OnInsertSpawnArea, query);
}

void SQL_OnInsertSpawnArea(Database db, DBResultSet results, const char[] error, any data)
{
	// An error has occurred
	if (!db || !results || error[0])
	{
		ThrowError("Couldn't insert a navigation spawn area (%s)", error);
	}
}

void DeleteSpawnArea(int nav_area_index, int bombsite_index, int nav_mesh_area_team)
{
	char query[256];
	Format(query, sizeof(query), "DELETE FROM `%s` WHERE `map_name` = '%s' AND `nav_area_index` = '%d' AND `bombsite_index` = '%d' AND `nav_mesh_area_team` = '%d'", MYSQL_TABLE_NAME, g_CurrentMapName, nav_area_index, bombsite_index, nav_mesh_area_team);
	g_Database.Query(SQL_OnDeleteSpawnArea, query);
}

void SQL_OnDeleteSpawnArea(Database db, DBResultSet results, const char[] error, any data)
{
	// An error has occurred
	if (!db || !results || error[0])
	{
		ThrowError("Couldn't delete a navigation spawn area (%s)", error);
	}
}

//================================[ Player events ]================================//

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if ((tickcount % RoundToFloor(g_ServerTickrate / 16.0)) || !g_Players[client].InEditMode())
	{
		return;
	}
	
	int bombsite_index = g_Players[client].edit_mode.bombsite_index;
	
	int color[4];
	
	// Visually display all the configurated spawn areas.
	// Each spawn area will be displayed with a colored defined by
	// its team index.
	for (int i; i < sizeof(g_BombsiteSpawns[]); i++)
	{
		for (int j; j < g_BombsiteSpawns[bombsite_index][i].Length; j++)
		{
			NavArea nav_area = g_BombsiteSpawns[bombsite_index][i].Get(j);
			if (!nav_area)
			{
				continue;
			}
			
			GetNavMeshTeamColor(i, color);
			
			HighlightSpawnArea(client, nav_area, color);
		}
	}
	
	// Handle the nav area at the client's aim position.
	NavArea nav_area = g_Players[client].edit_mode.GetNavArea(client);
	if (nav_area == NULL_NAV_AREA)
	{
		return;
	}
	
	color = { 255, 255, 255, 155 };
	
	int nav_mesh_area_team = -1, array_idx;
	if (IsNavAreaConfigurated(nav_area, bombsite_index, nav_mesh_area_team, array_idx))
	{
		// Delete the existing spawn area.
		// Must hold MOUSE1 + MOUSE2 for exactly a second.
		if (!(tickcount % RoundToFloor(g_ServerTickrate)) && (buttons & IN_ATTACK) && (buttons & IN_ATTACK2))
		{
			int nav_area_index = g_TheNavAreas.Find(nav_area);
			if (nav_area_index == -1)
			{
				PrintToChat(client, RETAKES_PREFIX..." \x07An error occured while deleting the existing spawn area.\x01");
				return;
			}
			
			DeleteSpawnArea(nav_area_index, bombsite_index, nav_mesh_area_team);
			
			g_BombsiteSpawns[bombsite_index][nav_mesh_area_team].Erase(array_idx);
			
			// Base value is defender, added the nav mesh area team will give the selected spawn role team.
			int spawn_role_team = SpawnRole_Defender + nav_mesh_area_team;
			
			PrintToChat(client, RETAKES_PREFIX..." Successfully deleted a spawn area in bombsite \x07%s\x01 for \x02%s\x01.", 
				g_BombsiteNames[g_Players[client].edit_mode.bombsite_index], 
				g_SpawnRoleNames[spawn_role_team]
				);
			
			return;
		}
		
		GetNavMeshTeamColor(nav_mesh_area_team, color);
	}
	
	HighlightSpawnArea(client, nav_area, color);
}

void GetNavMeshTeamColor(int team, int color[4])
{
	color = team == NavMeshArea_Defender ? { 228, 98, 30, 155 }  : { 20, 21, 255, 155 };
}

void HighlightSpawnArea(int client, NavArea nav_area, int color[4])
{
	float nw_corner[3], se_corner[3], ne_corner[3], sw_corner[3];
	
	nav_area.GetNWCorner(nw_corner);
	ValidateLaserOrigin(nw_corner);
	nav_area.GetSECorner(se_corner);
	ValidateLaserOrigin(se_corner);
	nav_area.GetNECorner(ne_corner);
	ValidateLaserOrigin(ne_corner);
	nav_area.GetSWCorner(sw_corner);
	ValidateLaserOrigin(sw_corner);
	
	Laser(client, ne_corner, se_corner, color);
	Laser(client, nw_corner, ne_corner, color);
	Laser(client, se_corner, sw_corner, color);
	Laser(client, sw_corner, nw_corner, color);
}

void Laser(int client, const float start[3], const float end[3], int color[4] = { 255, 255, 255, 255 }, float time = 0.2)
{
	TE_SetupBeamPoints(start, end, g_LaserIndex, 0, 0, 0, time, 1.5, 1.5, 0, 0.0, color, 0);
	TE_SendToClient(client);
}

void ValidateLaserOrigin(float origin[3])
{
	origin[2] += 64.0;
	
	TR_TraceRayFilter(origin, { 90.0, 0.0, 0.0 }, MASK_SOLID_BRUSHONLY, RayType_Infinite, Filter_ExcludePlayers);
	
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
}

bool Filter_ExcludePlayers(int entity, int contentsMask)
{
	return !(1 <= entity <= MaxClients)
}

//================================[ Commands Callbacks ]================================//

Action Command_Retakes(int client, int argc)
{
	if (!client)
	{
		ReplyToCommand(client, "You cannot use this command from the server console.");
		return Plugin_Handled;
	}
	
	DisplayRetakesMenu(client);
	
	return Plugin_Handled;
}

Action Command_ReloadNav(int argc)
{
	LoadSpawnAreas();
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

enum
{
	MainMenu_DummyItem, 
	MainMenu_ManageSpawnAreas
}

void DisplayRetakesMenu(int client)
{
	Menu menu = new Menu(Handler_Retakes);
	menu.SetTitle(RETAKES_PREFIX_MENU..." Settings:\n ");
	
	menu.AddItem("", "Dummy Item");
	//menu.AddItem("", "Manage Spawn Areas", CheckCommandAccess(client, "retakes_spawns", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	menu.AddItem("", "Manage Spawn Areas");
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_Retakes(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, selected_item = param2;
		
		switch (selected_item)
		{
			case MainMenu_DummyItem:
			{
			}
			case MainMenu_ManageSpawnAreas:
			{
				DisplaySpawnAreasMenu(client);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

enum
{
	SpawnAreasMenu_Bombsite, 
	SpawnAreasMenu_AddArea
}

void DisplaySpawnAreasMenu(int client)
{
	g_Players[client].edit_mode.Enter();
	
	char place_name[64] = "N/A";
	
	NavArea nav_area = g_Players[client].edit_mode.GetNavArea(client);
	if (nav_area != NULL_NAV_AREA)
	{
		int place_index = nav_area.GetPlace();
		if (place_index > 0 && TheNavMesh.PlaceToName(place_index, place_name, sizeof(place_name)))
		{
			StringToLower(place_name);
			
			Format(place_name, sizeof(place_name), "%T", place_name, client);
		}
	}
	
	char configurated_spawn_area[128] = " \n";
	if (IsNavAreaConfigurated(nav_area, g_Players[client].edit_mode.bombsite_index))
	{
		Format(configurated_spawn_area, sizeof(configurated_spawn_area), " \n\n• ╭This spawn area is already configurated!\n   ╰┄Hold MOUSE1 + MOUSE2 to delete it.\n ");
	}
	
	Menu menu = new Menu(Handler_SpawnAreas);
	menu.SetTitle(RETAKES_PREFIX_MENU..." Manage Spawn Areas:\n◾ Aiming at: %s\n%s", place_name, configurated_spawn_area);
	
	char item_display[32];
	Format(item_display, sizeof(item_display), "Bombsite: %s", g_BombsiteNames[g_Players[client].edit_mode.bombsite_index]);
	menu.AddItem("", item_display);
	
	menu.AddItem("", "Add Area", nav_area != NULL_NAV_AREA ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.ExitBackButton = true;
	
	FixMenuGap(menu);
	
	menu.Display(client, 1);
}

int Handler_SpawnAreas(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			switch (selected_item)
			{
				case SpawnAreasMenu_Bombsite:
				{
					g_Players[client].edit_mode.NextBombsite();
					
					DisplaySpawnAreasMenu(client);
				}
				case SpawnAreasMenu_AddArea:
				{
					NavArea nav_area = g_Players[client].edit_mode.GetNavArea(client);
					if (nav_area != NULL_NAV_AREA)
					{
						g_Players[client].edit_mode.nav_area = nav_area;
						
						DisplayAddAreaMenu(client);
					}
					else
					{
						DisplaySpawnAreasMenu(client);
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			
			if (cancel_reason == MenuCancel_Timeout)
			{
				DisplaySpawnAreasMenu(client);
				return 0;
			}
			
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayRetakesMenu(client);
			}
			
			g_Players[client].edit_mode.Exit();
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

enum
{
	AddAreaMenu_Defender, 
	AddAreaMenu_Attacker, 
	AddAreaMenu_Dismiss
}

void DisplayAddAreaMenu(int client)
{
	Menu menu = new Menu(Handler_AddArea);
	menu.SetTitle(RETAKES_PREFIX_MENU..." Add Area:\n \n• Select a team to assign the area to\n ");
	
	menu.AddItem("", "Defender");
	menu.AddItem("", "Attacker\n ");
	
	menu.AddItem("", "Dismiss");
	
	menu.ExitButton = false;
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_AddArea(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int client = param1, selected_item = param2;
			
			if (selected_item == AddAreaMenu_Dismiss)
			{
				DisplaySpawnAreasMenu(client);
				
				g_Players[client].edit_mode.nav_area = NULL_NAV_AREA;
				
				return 0;
			}
			
			NavArea nav_area = g_Players[client].edit_mode.GetNavArea(client);
			if (nav_area == NULL_NAV_AREA)
			{
				PrintToChat(client, RETAKES_PREFIX..." Unable to find a valid navigation area.");
				return 0;
			}
			
			g_Players[client].edit_mode.nav_area = NULL_NAV_AREA;
			
			DisplaySpawnAreasMenu(client);
			
			// According to the selected item, get the nav mesh area team.
			int nav_mesh_area_team = selected_item, 
			// Base value is defender, added the selected item will give the selected spawn role team.
			spawn_role_team = SpawnRole_Defender + selected_item;
			
			if (IsNavAreaConfigurated(nav_area, g_Players[client].edit_mode.bombsite_index, nav_mesh_area_team))
			{
				PrintToChat(client, RETAKES_PREFIX..." \x07This spawn area is already configurated!\x01");
				return 0;
			}
			
			int nav_area_index = g_TheNavAreas.Find(nav_area);
			if (nav_area_index == -1)
			{
				PrintToChat(client, RETAKES_PREFIX..." \x07An error occured while adding the new spawn area.\x01");
				return 0;
			}
			
			InsertSpawnArea(nav_area_index, g_Players[client].edit_mode.bombsite_index, nav_mesh_area_team);
			
			g_BombsiteSpawns[g_Players[client].edit_mode.bombsite_index][nav_mesh_area_team].Push(nav_area);
			
			PrintToChat(client, RETAKES_PREFIX..." Successfully added a spawn area in bombsite \x06%s\x01 for \x04%s\x01.", 
				g_BombsiteNames[g_Players[client].edit_mode.bombsite_index], 
				g_SpawnRoleNames[spawn_role_team]
				);
		}
		case MenuAction_Cancel:
		{
			int client = param1;
			g_Players[client].edit_mode.Exit();
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	
	return 0;
}

void FixMenuGap(Menu menu)
{
	int max = (6 - menu.ItemCount);
	for (int i; i < max; i++)
	{
		menu.AddItem("", "", ITEMDRAW_NOTEXT);
	}
}

bool IsNavAreaConfigurated(NavArea nav_area, int &bombsite_index = -1, int &nav_mesh_team = -1, int &index = -1)
{
	for (int i; i < sizeof(g_BombsiteSpawns); i++)
	{
		if (bombsite_index != -1 && bombsite_index != i)
		{
			continue;
		}
		
		for (int j; j < sizeof(g_BombsiteSpawns[]); j++)
		{
			if (nav_mesh_team != -1 && nav_mesh_team != j)
			{
				continue;
			}
			
			if ((index = g_BombsiteSpawns[i][j].FindValue(nav_area)) != -1)
			{
				bombsite_index = i;
				nav_mesh_team = j;
				return true;
			}
		}
	}
	
	return false;
} 