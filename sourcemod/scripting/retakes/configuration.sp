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
    
    RegConsoleCmd("sm_show_bombsites", Command_ShowBombSites);
}

Action Command_ShowBombSites(int client, int argc)
{
    float client_pos[3];
    GetClientAbsOrigin(client, client_pos);

    float client_mins[3], client_maxs[3];
    GetClientMins(client, client_mins);
    GetClientMaxs(client, client_maxs);

    for (int current_bombsite; current_bombsite < sizeof(g_Bombsites); current_bombsite++)
    {
        LaserBOX(client, g_Bombsites[current_bombsite].mins, g_Bombsites[current_bombsite].maxs);
    }

    return Plugin_Handled;
}

void LaserBOX(int client, float mins[3], float maxs[3])
{
    float posMin[4][3], posMax[4][3];
    
    posMin[0] = mins;
    posMax[0] = maxs;
    posMin[1][0] = posMax[0][0];
    posMin[1][1] = posMin[0][1];
    posMin[1][2] = posMin[0][2];
    posMax[1][0] = posMin[0][0];
    posMax[1][1] = posMax[0][1];
    posMax[1][2] = posMax[0][2];
    posMin[2][0] = posMin[0][0];
    posMin[2][1] = posMax[0][1];
    posMin[2][2] = posMin[0][2];
    posMax[2][0] = posMax[0][0];
    posMax[2][1] = posMin[0][1];
    posMax[2][2] = posMax[0][2];
    posMin[3][0] = posMax[0][0];
    posMin[3][1] = posMax[0][1];
    posMin[3][2] = posMin[0][2];
    posMax[3][0] = posMin[0][0];
    posMax[3][1] = posMin[0][1];
    posMax[3][2] = posMax[0][2];
    
    //BORDER
    Laser(client, posMin[0], posMax[3], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[1], posMax[2], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[3], posMax[0], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[2], posMax[1], { 255, 255, 255, 255 }, 15.0 );
    //CROSS
    Laser(client, posMin[3], posMax[2], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[1], posMax[0], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[2], posMax[3], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[3], posMax[1], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[2], posMax[0], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[0], posMax[1], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[0], posMax[2], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[1], posMax[3], { 255, 255, 255, 255 }, 15.0 );
    
    
    //TOP
    
    //BORDER
    Laser(client, posMax[0], posMax[1], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMax[1], posMax[3], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMax[3], posMax[2], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMax[2], posMax[0], { 255, 255, 255, 255 }, 15.0 );
    //CROSS
    Laser(client, posMax[0], posMax[3], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMax[2], posMax[1], { 255, 255, 255, 255 }, 15.0 );
    
    //BOTTOM
    
    //BORDER
    Laser(client, posMin[0], posMin[1], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[1], posMin[3], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[3], posMin[2], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[2], posMin[0], { 255, 255, 255, 255 }, 15.0 );
    //CROSS
    Laser(client, posMin[0], posMin[3], { 255, 255, 255, 255 }, 15.0 );
    Laser(client, posMin[2], posMin[1], { 255, 255, 255, 255 }, 15.0 );
    
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!g_Players[client].InEditMode() || (tickcount % 8))
    {
        return;
    }

    int bombsite_index = g_Players[client].edit_mode.bombsite_index;

    NavArea temp_nav_area;
    int color[4];
    float nw_corner[3], se_corner[3], ne_corner[3], sw_corner[3];

    for (int i; i < sizeof(g_BombsiteSpawns[]); i++)
    {
        for (int j; j < g_BombsiteSpawns[bombsite_index][i].Length; j++)
        {
            if (!(temp_nav_area = g_BombsiteSpawns[bombsite_index][i].Get(j)))
            {
                continue;
            }

            if (i == NavMeshArea_Defender)
            {
                color = { 204, 186, 124, 155 };
            }
            else if (i == NavMeshArea_Attacker)
            {
                color = { 93, 121, 174, 155 };
            }

            temp_nav_area.GetNWCorner(nw_corner);
            nw_corner[2] += 5.0;
            temp_nav_area.GetSECorner(se_corner);
            se_corner[2] += 5.0;
            temp_nav_area.GetNECorner(ne_corner);
            ne_corner[2] += 5.0;
            temp_nav_area.GetSWCorner(sw_corner);
            sw_corner[2] += 5.0;
            
            Laser(client, ne_corner, se_corner, color);
            Laser(client, nw_corner, ne_corner, color);
            Laser(client, se_corner, sw_corner, color);
            Laser(client, sw_corner, nw_corner, color);
        }
    }

    NavArea nav_area = g_Players[client].edit_mode.GetNavArea(client);
    if (nav_area == NULL_NAV_AREA)
    {
        return;
    }

    color = { 255, 255, 255, 155 };

    int nav_mesh_team;
    if (IsNavAreaConfigurated(nav_area, bombsite_index, nav_mesh_team) != -1)
    {
        color = nav_mesh_team == NavMeshArea_Defender 
                ? { 255, 186, 124, 155 } : { 93, 121, 255, 155 };
    }

    /*
    color[0] = GetRandomInt(0, 255);
    color[1] = GetRandomInt(0, 255);
    color[2] = GetRandomInt(0, 255);
    */

    nav_area.GetNWCorner(nw_corner);
    nw_corner[2] += 5.0;
    nav_area.GetSECorner(se_corner);
    se_corner[2] += 5.0;
    nav_area.GetNECorner(ne_corner);
    ne_corner[2] += 5.0;
    nav_area.GetSWCorner(sw_corner);
    sw_corner[2] += 5.0;
    
    Laser(client, ne_corner, se_corner, color);
    Laser(client, nw_corner, ne_corner, color);
    Laser(client, se_corner, sw_corner, color);
    Laser(client, sw_corner, nw_corner, color);
}

int IsNavAreaConfigurated(NavArea nav_area, int &bombsite_index = -1, int &nav_mesh_team = -1)
{
    int index;

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
                return index;
            }
        }
    }

    return -1;
}

void Laser(int client, const float start[3], const float end[3], int color[4] = { 255, 255, 255, 255 }, float time = 0.2)
{   
    TE_SetupBeamPoints(start, end, g_LaserIndex, 0, 0, 0, time, 3.0, 3.0, 7, 0.0, color, 0);
    TE_SendToClient(client);
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

    Menu menu = new Menu(Handler_SpawnAreas);
    menu.SetTitle(RETAKES_PREFIX_MENU..." Manage Spawn Areas:\n◾ [%s]\n ", place_name);
    
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
            
            // According to the selected item, get the nav mesh area team.
            int nav_mesh_area_team = selected_item,
                // Base value is defender, added the selected item will give the selected spawn role team.
                spawn_role_team = SpawnRole_Defender + selected_item;
            
            g_BombsiteSpawns[g_Players[client].edit_mode.bombsite_index][nav_mesh_area_team].Push(nav_area);

            PrintToChat(client, RETAKES_PREFIX ... " Successfully added a spawn area in bombsite \x06%s\x01 for \x04%s\x01.",
                g_BombsiteNames[g_Players[client].edit_mode.bombsite_index], 
                g_SpawnRoleNames[spawn_role_team]
            );

            g_Players[client].edit_mode.nav_area = NULL_NAV_AREA;

            DisplaySpawnAreasMenu(client);
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