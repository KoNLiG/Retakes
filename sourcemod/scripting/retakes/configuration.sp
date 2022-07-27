/*
 * • Responsible for parsing and storing all the spawn zones.
 * • As well as features an Edit-Mode which admins can configurate spawn zones.
 */

#assert defined COMPILING_FROM_MAIN

// Arraylist which will store SpawnZone's. 
// See retakes.inc for the enum struct contents.
ArrayList g_SpawnZones;

void RegisterConVars()
{
	
	
	// TODO: Create a configuration file.
	// AutoExecConfig();
}

// Register all plugin commands.
void RegisterCommands()
{
	// Reloads the retakes configuration file.
	RegServerCmd("retakes_reloadcfg", Command_ReloadCfg, "Reloads the retakes configuration file. (Spawn Zones)");
	
	// Manage the retakes spawn zones.
	RegAdminCmd("sm_retakes", Command_Retakes, ADMFLAG_ROOT, "Manage the retakes spawn zones.");
}

//================================[ Commands Callbacks ]================================//

Action Command_ReloadCfg(int argc)
{
	ParseRetakesConfig();
	return Plugin_Handled;
}

Action Command_Retakes(int client, int argc)
{
	if (!client)
	{
		PrintToConsole(client, "You cannot use this command from the server console.");
		return Plugin_Handled;
	}
	
	DisplayConfigurationMenu(client);
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void DisplayConfigurationMenu(int client)
{
	Menu menu = new Menu(Handler_Configuration);
	menu.SetTitle("%s Configuration menu:\n ", RETAKES_PREFIX_MENU);
	
	int num_spawn_zones = g_SpawnZones.Length;
	
	char item_str[128];
	Format(item_str, sizeof(item_str), "New spawn zone\n \n◾ List of existing spawn zones:\n \n%s", !num_spawn_zones ? "No spawn zones found." : "");
	menu.AddItem("", item_str);
	
	if (num_spawn_zones)
	{
		// Loop through all the spawn zones and insert each into the menu.
		char display_str[RETAKES_MAX_NAME_LENGTH * 2], spawn_zone_name[RETAKES_MAX_NAME_LENGTH];
		for (int current_spawn_zone; current_spawn_zone < num_spawn_zones; current_spawn_zone++)
		{
			g_SpawnZones.GetString(current_spawn_zone, spawn_zone_name, sizeof(spawn_zone_name));
			
			FormatEx(display_str, sizeof(display_str), "• %s [#%d]", spawn_zone_name, current_spawn_zone + 1);
			
			menu.AddItem(spawn_zone_name, display_str);
		}
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_Configuration(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, selected_item = param2;
		
		// Redirect client to new spawn zone creation menu.
		if (!selected_item)
		{
			// DisplayNewSpawnZoneMenu(client);
		}
		else
		{
			char spawn_zone_name[RETAKES_MAX_NAME_LENGTH];
			menu.GetItem(selected_item, spawn_zone_name, sizeof(spawn_zone_name));
			
			int spawn_zone_index = g_SpawnZones.FindString(spawn_zone_name);
			if (spawn_zone_index == -1)
			{
				PrintToChat(client, "%s The selected spawn zone is no longer available.", RETAKES_PREFIX);
				return 0;
			}
			
			
		}
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
	if (!g_SpawnZones)
	{
		//g_SpawnZones = new ArrayList(sizeof(SpawnZone));
	}
	else
	{
		// Clear old data.
		//g_SpawnZones.Clear();
	}
	
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