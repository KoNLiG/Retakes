/*
 * • Responsible for parsing and storing all the spawn zones.
 * • As well as features an Edit-Mode which admins can configurate spawn zones.
 */

#assert defined COMPILING_FROM_MAIN

#define MAX_MAP_NAME_LENGTH 128

char g_CurrentMapName[MAX_MAP_NAME_LENGTH];

void Configuration_OnPluginStart()
{
    RegisterConVars();
    RegisterCommands();
}

void RegisterConVars()
{
    retakes_preferred_team = CreateConVar("retakes_preferred_team", "3", "Team to transfer players to when the number of players is not equal between the two teams. 2 - Defenders/T, 3 - Attackers/CT, -1 - No preference");
    retakes_queued_players_team = CreateConVar("retakes_queued_players_team", "3", "Team index queued players will be assigned to after leaving queue. 2 - Defenders/T, 3 - Attackers/CT");
    retakes_player_min = CreateConVar("retakes_player_min", "2", "Minimum amount of players before retakes can start.", _, true, 1.0);
    retakes_bots_are_players = CreateConVar("retakes_bots_are_players", "1", "Server bots will be treated as regular players.", _, true, 0.0, true, 1.0);
    retakes_max_attackers = CreateConVar("retakes_max_attackers", "5", "Max players allowed in the Counter-Terrorist team.", _, true, 1.0, true, 5.0);
    retakes_max_defenders = CreateConVar("retakes_max_defenders", "4", "Max players allowed in the Terrorist team.", _, true, 1.0, true, 5.0);
    // retakes_max_wins_scramble = CreateConVar("sm_retakes_rounds_scramble", "8", "Scramble teams after every x amount of rounds.");

    retakes_adjacent_tree_layers = CreateConVar("retakes_adjacent_tree_layers", "5",
                                                "Amount of layers for navigation area adjacent trees. Used for angles computation. \n \
                                                The lower this value is, the result of random angles computation will be less percise. \n \
                                                The higher this value, means there will be more a lot more angles to choose from, combined with an expensive performance cost.",
                                                .hasMin = true, .min = 1.0, .hasMax = true, .max = 7.0);

    // 'plant_logic.sp' cvars.
    retakes_auto_plant = CreateConVar("retakes_auto_plant", "1", "Whether to automatically plant a c4 if not planted after freeze time/planter has disconnected.", .hasMin = true, .hasMax = true, .max = 1.0);
    retakes_instant_plant = CreateConVar("retakes_instant_plant", "1", "Whether to instantly plant a 'weapon_c4'.", .hasMin = true, .hasMax = true, .max = 1.0);
    retakes_unfreeze_planter = CreateConVar("retakes_unfreeze_planter", "1", "Whether to allow the c4 planter to move during freeze time.", .hasMin = true, .hasMax = true, .max = 1.0);
    retakes_lockup_bombsite = CreateConVar("retakes_lockup_bombsite", "1", "Whether to physically lock up the bombsite during freeze time. Unnecessary if 'retakes_unfreeze_planter' is disabled.", .hasMin = true, .hasMax = true, .max = 1.0);
    retakes_skip_freeze_period = CreateConVar("retakes_skip_freeze_period", "1", "Whether to skip freeze period once c4 is successfully planted.", .hasMin = true, .hasMax = true, .max = 1.0);

    // 'defuse_logic.sp' cvars.
    retakes_instant_defuse = CreateConVar("retakes_instant_defuse", "1", "Whether to instantly defeuse a 'planted_c4'.");
    retakes_explode_no_time = CreateConVar("retakes_explode_no_time", "1", "Whether to explode the 'planted_c4' if the defuser runs out of time.");

    // 'gameplay.sp' cvars.
    retakes_max_consecutive_rounds_same_target_site = CreateConVar("retakes_max_consecutive_rounds_same_target_site", "4", "Limit the number of consecutive rounds targeting the same site. -1 to ignore.");

    // 'database.sp' cvars.
    retakes_database_entry = CreateConVar("retakes_database_entry", "modern_retakes", "Listed database entry in 'databases.cfg'.");
    retakes_database_table_spawns = CreateConVar("retakes_database_table_spawn_ares", "retakes_spawn_areas", "Database table name for spawn area locations.");
    retakes_database_table_distributer = CreateConVar("retakes_database_table_distributer", "retakes_distributer", "Database table name for player weapons.");

    // 'distributer.sp' cvars.
    retakes_distributer_enable = CreateConVar("retakes_distributer_enable", "0", "Enable or disable the weapons distributer.");
    retakes_distributer_grace_period = CreateConVar("retakes_distributer_grace_period", "6.0", "Grace period for allowing players to receive weapons.");
    retakes_distributer_force_weapon = CreateConVar("retakes_distributer_force_weapon", "0", "Force weapons over default equipped weapons.");
    retakes_distributer_ammo_limit = CreateConVar("retakes_distributer_ammo_limit", "4", "Grenade amount limit.");
    retakes_distributer_ammo_limit.AddChangeHook(OnConVarChanged);

    AutoExecConfig(true, "retakes");
    AutoExecConfig_CleanFile();
}

void OnConVarChanged(ConVar convar, const char[] old_value, const char[] new_value)
{
    if (convar == retakes_distributer_ammo_limit)
    {
        FindConVar("ammo_grenade_limit_total").IntValue = StringToInt(new_value);
    }
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
    char table_name[64];

    retakes_database_table_spawns.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s`(`map_name` VARCHAR(%d) NOT NULL, `nav_area_id` INT NOT NULL, `bombsite_index` INT NOT NULL, `nav_mesh_area_team` INT NOT NULL)", table_name, MAX_MAP_NAME_LENGTH);
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
    char table_name[64];

    retakes_database_table_spawns.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "SELECT `nav_area_id`, `bombsite_index`, `nav_mesh_area_team` FROM `%s` WHERE `map_name` = '%s'", table_name, g_CurrentMapName);
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
        int nav_area_id = results.FetchInt(0);
        NavArea nav_area = TheNavMesh.GetNavAreaByID(nav_area_id);

        if (nav_area == NULL_NAV_AREA)
        {
            LogError("Invalid navigation area id. (%d)", nav_area_id);
            continue;
        }

        int bombsite_index = results.FetchInt(1);
        if (!(Bombsite_None < bombsite_index < Bombsite_Max))
        {
            LogError("Invalid bombsite index for navigation area #%d.", nav_area_id);
            continue;
        }

        int nav_mesh_area_team = results.FetchInt(2);
        if (!(-1 < nav_mesh_area_team < NavMeshArea_Max))
        {
            LogError("Invalid team index for navigation area #%d.", nav_area_id);
            continue;
        }

        g_BombsiteSpawns[bombsite_index][nav_mesh_area_team].Push(nav_area);
    } while (results.FetchRow());
}

void InsertSpawnArea(int nav_area_id, int bombsite_index, int nav_mesh_area_team)
{
    char query[256];
    char table_name[64];

    retakes_database_table_spawns.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "INSERT INTO `%s` VALUES ('%s', %d, %d, %d)", table_name, g_CurrentMapName, nav_area_id, bombsite_index, nav_mesh_area_team);
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

void DeleteSpawnArea(int nav_area_id, int bombsite_index, int nav_mesh_area_team)
{
    char query[256];
    char table_name[64];

    retakes_database_table_spawns.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "DELETE FROM `%s` WHERE `map_name` = '%s' AND `nav_area_id` = '%d' AND `bombsite_index` = '%d' AND `nav_mesh_area_team` = '%d'", table_name, g_CurrentMapName, nav_area_id, bombsite_index, nav_mesh_area_team);
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
            int nav_area_id = nav_area.ID;
            if (nav_area_id <= 0)
            {
                PrintToChat(client, "%T%T", "MessagesPrefix", client, "Spawn Area Delete Error", client);
                return;
            }

            DeleteSpawnArea(nav_area_id, bombsite_index, nav_mesh_area_team);

            g_BombsiteSpawns[bombsite_index][nav_mesh_area_team].Erase(array_idx);

            // Base value is defender, added the nav mesh area team will give the selected spawn role team.
            int spawn_role_team = SpawnRole_Defender + nav_mesh_area_team;

            PrintToChat(client, "%T%T",
                "MessagesPrefix",
                client,
                "Deleted Spawn Area",
                client,
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
    TE_SendToClientInRange(client, start, RangeType_Visibility);
}

void TE_SendToClientInRange(int client, const float origin[3], ClientRangeType rangeType, float delay = 0.0)
{
    int[] clients = new int[MaxClients];
    int total = GetClientsInRange(origin, rangeType, clients, MaxClients);

    if (IsValueInArray(client, clients, total) != -1)
    {
        TE_SendToClient(client, delay);
    }
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

//================================[ Commands Callbacks ]================================//

Action Command_Retakes(int client, int argc)
{
    if (!client)
    {
        ReplyToCommand(client, "%T", "No Command Access", client);
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
    MainMenu_ManageSpawnAreas
}

void DisplayRetakesMenu(int client)
{
    Menu menu = new Menu(Handler_Retakes);
    menu.SetTitle("%T%T:\n ", "MenuPrefix", client, "Settings", client);

    char item_display[32];
    Format(item_display, sizeof(item_display), "%T", "Manage Spawn Areas", client);
    menu.AddItem("", item_display, CheckCommandAccess(client, "retakes_spawns", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);

    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_Retakes(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        int client = param1, selected_item = param2;

        switch (selected_item)
        {
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
        Format(configurated_spawn_area, sizeof(configurated_spawn_area), " \n\n• ╭%T!\n   ╰┄%T.\n ", "Configurated Spawn Area", client, "Hold To Delete", client);
    }

    Menu menu = new Menu(Handler_SpawnAreas);
    menu.SetTitle("%T%T:\n◾ %T: %s\n%s", "MenuPrefix", client, "Manage Spawn Areas", client, "Aiming at", client, place_name, configurated_spawn_area);

    char item_display[32];
    Format(item_display, sizeof(item_display), "%T: %s", "Bombsite", client, g_BombsiteNames[g_Players[client].edit_mode.bombsite_index]);
    menu.AddItem("", item_display);

    Format(item_display, sizeof(item_display), "%T", "Add Area", client);
    menu.AddItem("", item_display, nav_area != NULL_NAV_AREA ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

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
    menu.SetTitle("%T%T:\n \n• %T\n ", "MenuPrefix", client, "Add Area", client, "Select Team", client);

    char item_display[16];

    Format(item_display, sizeof(item_display), "%T", "Defender", client);
    menu.AddItem("", item_display);

    Format(item_display, sizeof(item_display), "%T\n ", "Attacker", client);
    menu.AddItem("", item_display);

    Format(item_display, sizeof(item_display), "%T", "Dismiss", client);
    menu.AddItem("", item_display);

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
                PrintToChat(client, "%T%T.", "MessagesPrefix", client, "Invalid Nav Area", client);
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
                PrintToChat(client, "%T%T.", "MessagesPrefix", client, "Configurated Spawn Area", client);
                return 0;
            }

            int nav_area_id = nav_area.ID;
            if (nav_area_id <= 0)
            {
                PrintToChat(client, "%T%T.", "MessagesPrefix", client, "Spawn Area Add Error", client);
                return 0;
            }

            InsertSpawnArea(nav_area_id, g_Players[client].edit_mode.bombsite_index, nav_mesh_area_team);

            g_BombsiteSpawns[g_Players[client].edit_mode.bombsite_index][nav_mesh_area_team].Push(nav_area);

            PrintToChat(client, "%T%T",
                "MessagesPrefix",
                client,
                "Added Spawn Area",
                client,
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