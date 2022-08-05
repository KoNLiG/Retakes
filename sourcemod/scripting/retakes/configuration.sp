/*
 * • Responsible for parsing and storing all the spawn zones.
 * • As well as features an Edit-Mode which admins can configurate spawn zones.
 */

#assert defined COMPILING_FROM_MAIN

void RegisterConVars()
{
	
	
	// TODO: Create a configuration file.
	// AutoExecConfig();
}

// Register all plugin commands.
void RegisterCommands()
{
	RegConsoleCmd("sm_retakes", Command_Retakes, "Retake settings.");
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if ((tickcount % 128))
	{
		return;
	}
	
	float aim_position[3];
	GetClientAimPosition(client, aim_position);
	
	NavArea nav_area = TheNavMesh.GetNavArea(aim_position);
	if (!nav_area)
	{
		PrintToChatAll("!nav_area");
		return;
	}
	
	float nw_corner[3], se_corner[3], ne_corner[3], sw_corner[3];
	nav_area.GetNWCorner(nw_corner);
	nw_corner[2] += 5.0;
	nav_area.GetSECorner(se_corner);
	se_corner[2] += 5.0;
	nav_area.GetNECorner(ne_corner);
	ne_corner[2] += 5.0;
	nav_area.GetSWCorner(sw_corner);
	sw_corner[2] += 5.0;
	
	// BUG: always prints 0.0 0.0 0.0
	PrintToChatAll("%f %f %f", nw_corner[0], nw_corner[1], nw_corner[2]);
	PrintToChatAll("%f %f %f", se_corner[0], se_corner[1], se_corner[2]);
	PrintToChatAll("%f %f %f", ne_corner[0], ne_corner[1], ne_corner[2]);
	PrintToChatAll("%f %f %f", sw_corner[0], sw_corner[1], sw_corner[2]);
	
	Laser(nw_corner, ne_corner);
	Laser(ne_corner, se_corner);
	Laser(se_corner, sw_corner);
	Laser(sw_corner, nw_corner);
}

void Laser(const float start[3], const float end[3], int color[4] = { 255, 255, 255, 255 } )
{
	color[0] = GetRandomInt(0, 255);
	color[1] = GetRandomInt(0, 255);
	color[2] = GetRandomInt(0, 255);
	
	TE_SetupBeamPoints(start, end, g_LaserIndex, 0, 0, 0, 15.0, 3.0, 3.0, 7, 0.0, color, 0);
	TE_SendToAll();
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
	menu.AddItem("", "Manage Spawn Areas", CheckCommandAccess(client, "retakes_spawns", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	
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
	g_Players[client].in_edit_mode = true;
	
	Menu menu = new Menu(Handler_SpawnAreas);
	menu.SetTitle(RETAKES_PREFIX_MENU..." Manage Spawn Areas:\n ");
	
	char item_display[32];
	Format(item_display, sizeof(item_display), "Bombsite: %s", g_BombsiteNames[g_Players[client].edit_mode_bombsite]);
	menu.AddItem("", item_display);
	
	menu.AddItem("", "Add Area");
	
	menu.ExitBackButton = true;
	
	menu.Display(client, MENU_TIME_FOREVER);
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
					g_Players[client].edit_mode_bombsite = ++g_Players[client].edit_mode_bombsite % g_Players[client].edit_mode_bombsite;
					
					DisplaySpawnAreasMenu(client);
				}
				case SpawnAreasMenu_AddArea:
				{
					DisplayAddAreaMenu(client);
					
					SetEntityFlags(client, (GetEntityFlags(client) | FL_FROZEN));
				}
			}
		}
		case MenuAction_Cancel:
		{
			int client = param1, cancel_reason = param2;
			
			if (cancel_reason == MenuCancel_ExitBack)
			{
				DisplayRetakesMenu(client);
			}
			
			g_Players[client].in_edit_mode = false;
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
	menu.SetTitle(RETAKES_PREFIX_MENU..." Add Area:\n• Select a team to assign the area to\n ");
	
	menu.AddItem("", "Defender");
	menu.AddItem("", "Attacker\n ");
	
	menu.AddItem("", "Dismiss");
	
	menu.ExitButton = false;
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_AddArea(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, selected_item = param2;
		
		if (selected_item == AddAreaMenu_Dismiss)
		{
			DisplaySpawnAreasMenu(client);
			return 0;
		}
		
		float aim_position[3];
		GetClientAimPosition(client, aim_position);
		
		NavArea nav_area = TheNavMesh.GetNavArea(aim_position);
		if (!nav_area)
		{
			PrintToChat(client, RETAKES_PREFIX..." Unable to find a valid navigation area.");
			return 0;
		}
		
		int nav_mesh_area_team;
		
		switch (selected_item)
		{
			case AddAreaMenu_Defender:
			{
				nav_mesh_area_team = NavMeshArea_Defender;
			}
			case AddAreaMenu_Attacker:
			{
				nav_mesh_area_team = NavMeshArea_Attacker;
			}
		}
		
		g_BombsiteSpawns[g_Players[client].edit_mode_bombsite][nav_mesh_area_team].Push(nav_area);
		
		SetEntityFlags(client, (GetEntityFlags(client) & FL_FROZEN));
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

//================================[ Key Values Configuration ]================================//

void ParseRetakesConfig()
{
	// Find the Config.
	static char file_path[PLATFORM_MAX_PATH];
	if (!file_path[0])
	{
		BuildPath(Path_SM, file_path, sizeof(file_path), "configs/retakes.cfg");
	}
	
	// TODO: Valid?
	delete OpenFile(file_path, "a+");
	
	// Create new kv variable to itirate in
	KeyValues kv = new KeyValues("Retakes");
	
	// Import the file to the new kv variable
	if (!kv.ImportFromFile(file_path))
	{
		LogMessage("Couldn't import any retakes spawn zones. Configuration can be made by running the command 'sm_retakes' in-game");
	}
	
	// Make sure the file isn't empty.
	if (!kv.GotoFirstSubKey())
	{
		LogMessage("Couldn't find any retakes spawn zones. Configuration can be made by running the command 'sm_retakes' in-game");
	}
	else
	{
		// Iterate through...
		do
		{
			/*SpawnZone new_spawn_zone;
            
            new_spawn_zone.bombsite = kv.GetNum("restricted_bombsite");
            new_spawn_zone.role_flags = kv.GetNum("restricted_role");
            
            kv.GetVector("mins", new_spawn_zone.mins);
            kv.GetVector("maxs", new_spawn_zone.maxs);
            
            g_SpawnZones.PushArray(new_spawn_zone);*/
			// Go to the next spawn zone
		} while (kv.GotoNextKey());
	}
	
	kv.Close();
	
	// TODO: Execute 'OnConfigLoaded' forward.
	// Call_OnConfigLoaded();
} 