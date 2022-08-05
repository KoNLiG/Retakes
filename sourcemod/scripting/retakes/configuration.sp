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
    menu.SetTitle("%s Settings:\n ", RETAKES_PREFIX_MENU);
    
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
                // nothing...
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

void DisplaySpawnAreasMenu(int client)
{
    Menu menu = new Menu(Handler_SpawnAreas);
    menu.SetTitle("%s ", RETAKES_PREFIX_MENU);

    

    // g_BombsiteSpawns

    menu.Display(client, MENU_TIME_FOREVER);
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