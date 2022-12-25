/*
 * • Responsible for distributing weapons to players.
 */

#assert defined COMPILING_FROM_MAIN

#define LOADOUT_TEAM_T   0
#define LOADOUT_TEAM_CT  1
#define LOADOUT_TEAM_MAX 2

#define WEAPONTYPE_PRIMARY   (1 << 0)
#define WEAPONTYPE_SECONDARY (1 << 1)
#define WEAPONTYPE_UTILITY   (1 << 2)

enum struct PlayerLoadout
{
    CSWeaponID primary_weapon_id[LOADOUT_TEAM_MAX];
    CSWeaponID secondary_weapon_id[LOADOUT_TEAM_MAX];
}

enum struct LoadoutItemData
{
    CSWeaponID item_id;

    char classname[32];

    float chance;

    int flags;

    int max;
}

enum struct LoadoutData
{
    int kits;

    char name[24];

    ArrayList items[LOADOUT_TEAM_MAX];

    void Initialize(const char[] name)
    {
        strcopy(this.name, sizeof(LoadoutData::name), name);

        for (int i; i < LOADOUT_TEAM_MAX; i++)
        {
            this.items[i] = new ArrayList(sizeof(LoadoutItemData));
        }
    }

    void Clear()
    {
        for (int i; i < LOADOUT_TEAM_MAX; i++)
        {
            delete this.items[i];
        }
    }
}

ArrayList loadouts;
int       smc_parser_depth;
int       smc_parser_count;
int       current_loadout;
int       line_count = -1;
char      current_weapon[sizeof(LoadoutItemData::classname)];
float grace_period;

public void Distributer_OnPluginStart()
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    bool file_exists;

    char buffer[PLATFORM_MAX_PATH];

    BuildPath(Path_SM, buffer, sizeof(buffer), "data/retakes/distributer.cfg");

    file_exists = FileExists(buffer);

    if (!file_exists)
    {
        SetFailState("%s : Unable to find \"data/retakes/distributer.cfg\" file", PLUGIN_TAG);
        return;
    }

    loadouts = new ArrayList(sizeof(LoadoutData));

    SMCParser parser = new SMCParser();

    parser.OnStart        = SMCParser_OnStart;
    parser.OnEnterSection = SMCParser_OnEnterSection;
    parser.OnLeaveSection = SMCParser_OnLeaveSectionn;
    parser.OnKeyValue     = SMCParser_OnKeyValue;
    parser.OnRawLine      = SMCParser_OnRawLine;
    parser.OnEnd          = SMCParser_OnEnd;

    SMCError error = parser.ParseFile(buffer);

    if (error != SMCError_Okay)
    {
        parser.GetErrorString(error, buffer, sizeof(buffer));
        SetFailState("%s : %s", PLUGIN_TAG, buffer);
        delete parser;
        return;
    }

    delete parser;

    RegConsoleCmd("sm_distributer", Command_Distributer);
}

void Distributer_OnDatabaseConnection()
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    char query[512];
    char table_name[32];

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s_players` (`account_id` INT NOT NULL, `loadout_name` VARCHAR(32), `primary_wep_id_t` INT UNSIGNED, `primary_wep_id_ct` INT UNSIGNED, `secondary_wep_id_t` INT UNSIGNED, `secondary_wep_id_ct` INT UNSIGNED, PRIMARY KEY (`account_id`, `loadout_name`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;", table_name);
    g_Database.Query(SQL_OnDistributerTableCreated, query, _, DBPrio_High);
}

void SQL_OnDistributerTableCreated(Database database, DBResultSet results, const char[] error, any data)
{
    if (!database || !results)
    {
        LogError("%s There was an error creating the distributer table \n\n%s", PLUGIN_TAG, error);
        return;
    }
}

void Distributer_OnClientPutInServer(int client)
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    if (client <= 0 || IsFakeClient(client))
    {
        return;
    }

    char query[256];
    char table_name[32];

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "SELECT * FROM `%s_players` WHERE `account_id` = %d", table_name, g_Players[client].account_id);
    g_Database.Query(SQL_OnClientInfoFetched, query, g_Players[client].user_id, DBPrio_High);
}

void Distributer_OnClientDisconnect(int client)
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    if (client <= 0 || IsFakeClient(client))
    {
        return;
    }

    char buffer[32];
    char query[256];
    char table_name[32];

    PlayerLoadout player_loadout_data;

    Transaction transaction = new Transaction();

    StringMapSnapshot loadout_snapshot = g_Players[client].weapons_map.Snapshot();

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    for (int i = g_Players[client].weapons_map.Size - 1; i >= 0; i--)
    {
        loadout_snapshot.GetKey(i, buffer, sizeof(buffer));

        if (!g_Players[client].weapons_map.GetArray(buffer, player_loadout_data, sizeof(player_loadout_data)))
        {
            continue;
        }

        FormatEx(query, sizeof(query), "INSERT INTO `%s_players` VALUES (%d, '%s', %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `loadout_name` = '%s', `primary_wep_id_t` = %d, `primary_wep_id_ct` = %d, `secondary_wep_id_t` = %d, `secondary_wep_id_ct` = %d;", 
        table_name, 
        g_Players[client].account_id, 
        buffer, 
        player_loadout_data.primary_weapon_id[LOADOUT_TEAM_T], 
        player_loadout_data.primary_weapon_id[LOADOUT_TEAM_CT], 
        player_loadout_data.secondary_weapon_id[LOADOUT_TEAM_T], 
        player_loadout_data.secondary_weapon_id[LOADOUT_TEAM_CT], 
        buffer, 
        player_loadout_data.primary_weapon_id[LOADOUT_TEAM_T], 
        player_loadout_data.primary_weapon_id[LOADOUT_TEAM_CT], 
        player_loadout_data.secondary_weapon_id[LOADOUT_TEAM_T], 
        player_loadout_data.secondary_weapon_id[LOADOUT_TEAM_CT]);

        LogMessage(query);

        transaction.AddQuery(query);
    }

    delete loadout_snapshot;

    g_Database.Execute(transaction, _, SQL_OnClientInfoSavedError, _, DBPrio_High);
}

void SQL_OnClientInfoSavedError(Database database, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    if (!database || error[0])
    {
        LogError("%s There was an error saving player data \n\n%s", PLUGIN_TAG, error);
        return;
    }
}

void SQL_OnClientInfoFetched(Database database, DBResultSet results, const char[] error, int userid)
{
    if (error[0])
    {
        LogError("There was an error fetching player weapon data! \n\n%s", PLUGIN_TAG, error);
        return;
    }

    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    int loadout_name;
    int primary_weapon[LOADOUT_TEAM_MAX];
    int secondary_weapon[LOADOUT_TEAM_MAX];

    results.FieldNameToNum("loadout_name", loadout_name);
    results.FieldNameToNum("primary_wep_id_t", primary_weapon[LOADOUT_TEAM_T]);
    results.FieldNameToNum("primary_wep_id_ct", primary_weapon[LOADOUT_TEAM_CT]);
    results.FieldNameToNum("secondary_wep_id_t", secondary_weapon[LOADOUT_TEAM_T]);
    results.FieldNameToNum("secondary_wep_id_ct", secondary_weapon[LOADOUT_TEAM_CT]);

    char buffer[64];
    PlayerLoadout player_loadout;

    while (results.FetchRow())
    {
        results.FetchString(loadout_name, buffer, sizeof(buffer));

        for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
        {
            player_loadout.primary_weapon_id[current_team] = view_as<CSWeaponID>(results.FetchInt(primary_weapon[current_team]));
            player_loadout.secondary_weapon_id[current_team] = view_as<CSWeaponID>(results.FetchInt(secondary_weapon[current_team]));
        }

        g_Players[client].weapons_map.SetArray(buffer, player_loadout, sizeof(player_loadout));
    }
}

public Action Command_Distributer(int client, int args)
{
    DisplayDistributerMenu(client);
    return Plugin_Handled;
}

void SMCParser_OnStart(SMCParser parser)
{
#if defined DEBUG
    PrintToServer("Loading distributer configuration file");
#endif
}

SMCResult SMCParser_OnEnterSection(SMCParser parser, const char[] name, bool opt_quotes)
{
#if defined DEBUG
    PrintToServer("Distributer Section Parse: %s", name);
#endif

    if (smc_parser_depth == 1)
    {
        smc_parser_count++;
    }

    if (smc_parser_depth == 2 && smc_parser_count == 1)
    {
        LoadoutData loadout_data;

        loadout_data.Initialize(name);

        loadouts.PushArray(loadout_data, sizeof(loadout_data));
    }

    else if (smc_parser_depth == 3 && smc_parser_count == 1)
    {
        if (!strcmp(name, "Counter Terrorist"))
        {
            current_loadout = LOADOUT_TEAM_CT;
        }

        else if (!strcmp(name, "Terrorist"))
        {
            current_loadout = LOADOUT_TEAM_T;
        }

        else
        {
            current_loadout = -1;
        }
    }

    if (smc_parser_depth == 2 && smc_parser_count == 2)
    {
        strcopy(current_weapon, sizeof(current_weapon), name);
    }

    smc_parser_depth++;

    return SMCParse_Continue;
}

SMCResult SMCParser_OnLeaveSectionn(SMCParser parser)
{
    smc_parser_depth--;

    return SMCParse_Continue;
}

SMCResult SMCParser_OnKeyValue(SMCParser parser, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
#if defined DEBUG
    PrintToServer("Distributer Key Parse: [%s] %s", key, value);
#endif

    if (smc_parser_depth == 4 && smc_parser_count == 1)
    {
        static LoadoutItemData item_data;

        if (StrContains(key, "weapon") != -1 || !strcmp(key, "utility"))
        {
            int flags;

            char buffer[32];

            FormatEx(buffer, sizeof(buffer), "weapon_%s", value);

            CSWeaponID weapon_id = CS_AliasToWeaponID(buffer);

            if (!weapon_id)
            {
                return SMCParse_Continue;
            }

            item_data.item_id = weapon_id;

            strcopy(item_data.classname, sizeof(LoadoutItemData::classname), buffer);

            if (!strncmp(key, "primary_weapon", 9))
            {
                flags |= WEAPONTYPE_PRIMARY;
            }

            else if (!strncmp(key, "secondary_weapon", 9))
            {
                flags |= WEAPONTYPE_SECONDARY;
            }

            else if (!strncmp(key, "utility", 7))
            {
                flags |= WEAPONTYPE_UTILITY;
            }

            item_data.flags = flags;

            LoadoutData loadout_data;

            loadouts.GetArray(loadouts.Length - 1, loadout_data, sizeof(loadout_data));

            switch (current_loadout)
            {
                case LOADOUT_TEAM_CT: loadout_data.items[LOADOUT_TEAM_CT].PushArray(item_data, sizeof(item_data));
                case LOADOUT_TEAM_T: loadout_data.items[LOADOUT_TEAM_T].PushArray(item_data, sizeof(item_data));
                default: return SMCParse_HaltFail;
            }
        }

        if (!strcmp(key, "kits"))
        {
            LoadoutData loadout_data;

            loadouts.GetArray(loadouts.Length - 1, loadout_data, sizeof(loadout_data));

            loadout_data.kits = StringToInt(value);

            loadouts.SetArray(loadouts.Length, loadout_data, sizeof(loadout_data));
        }
    }

    else if (smc_parser_depth == 3 && smc_parser_count == 2)
    {
        // Finish this for weapon maximums and chances.

        // int position;

        // char buffer[32];

        // LoadoutData loadout_data;

        // static LoadoutItemData item_data;

        // FormatEx(buffer, sizeof(buffer), "weapon_%s", current_weapon);

        // for (int i; i < loadouts.Length; i++)
        // {
        //     if (!loadouts.GetArray(i, loadout_data, sizeof(loadout_data)))
        //     {
        //         continue;
        //     }

        //     for (int j; j < LOADOUT_TEAM_MAX; j++)
        //     {
        //         position = loadout_data.items[j].FindString(buffer);

        //         if (position != -1)
        //         {
        //             loadout_data.items[j].GetArray(position, item_data, sizeof(item_data));

        //             if (!strcmp(key, "chance"))
        //             {
        //                 item_data.chance = StringToFloat(value);
        //             }

        //             if (!strcmp(key, "max"))
        //             {
        //                 item_data.max = StringToInt(value);
        //             }

        //             loadout_data.items[j].SetArray(position, item_data, sizeof(item_data));
        //         }
        //     }
        // }
    }

    return SMCParse_Continue;
}

SMCResult SMCParser_OnRawLine(SMCParser parser, const char[] line, int line_num)
{
    line_count++;

    return SMCParse_Continue;
}

void SMCParser_OnEnd(SMCParser parser, bool halted, bool failed)
{
#if defined DEBUG
    PrintToServer("Distributer Finished Parsing: %d loadouts", loadouts.Length);
#endif

    if (failed)
    {
        SetFailState("%s : There was a fatal error parsing the distributer config file at line %d", PLUGIN_TAG, line_count);
        return;
    }

    bool fail_state;

    LoadoutData     loadout_data;
    LoadoutItemData item_data;

    for (int i = loadouts.Length - 1; i >= 0; i--)
    {
        if (!loadouts.GetArray(i, loadout_data, sizeof(loadout_data)))
        {
            continue;
        }

        if (!TranslationPhraseExists(loadout_data.name))
        {
            fail_state = true;
            LogError("Translation for \"%s\" loadout key not found", loadout_data.name);
        }

        for (int j; j < LOADOUT_TEAM_MAX; j++)
        {
            for (int k = loadout_data.items[j].Length - 1; k >= 0; k--)
            {
                if (!loadout_data.items[j].GetArray(k, item_data, sizeof(item_data)))
                {
                    continue;
                }

                if (!TranslationPhraseExists(item_data.classname))
                {
                    fail_state = true;
                    LogError("Translation for \"%s\" weapon key not found", item_data.classname);
                }
            }
        }
    }

    if (fail_state)
    {
        SetFailState("%s : There are missing translations for the distributer part of the retakes plugin", PLUGIN_TAG);
    }
}

void Distributer_OnRoundPreStart()
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    LoadoutData loadout_data;
    LoadoutItemData item_data;
    PlayerLoadout player_loadout_data;

    loadouts.GetArray(GetURandomInt() % loadouts.Length, loadout_data, sizeof(loadout_data));

    for (int team, iterations, max_iterations, current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (!IsClientInGame(current_client))
        {
            continue;
        }

        team = GetClientTeam(current_client) - LOADOUT_TEAM_MAX;

        if (team <= -1)
        {
            continue;
        }

        g_Players[current_client].ClearLoadout();

        if (g_Players[current_client].weapons_map.GetArray(loadout_data.name, player_loadout_data, sizeof(player_loadout_data)))
        {
            g_Players[current_client].weapons_id[0] = player_loadout_data.primary_weapon_id[team];
            g_Players[current_client].weapons_id[1] = player_loadout_data.secondary_weapon_id[team];
        }

        else
        {
            max_iterations = loadout_data.items[team].Length;

            while (iterations < max_iterations)
            {
                loadout_data.items[team].GetArray(GetURandomInt() % max_iterations, item_data, sizeof(item_data));

                if (item_data.flags & WEAPONTYPE_PRIMARY && !g_Players[current_client].weapons_id[0])
                {
                    g_Players[current_client].weapons_id[0] = item_data.item_id;
                }

                else if (item_data.flags & WEAPONTYPE_SECONDARY && !g_Players[current_client].weapons_id[1])
                {
                    g_Players[current_client].weapons_id[1] = item_data.item_id;
                }

                iterations++;
            }
        }
    }
}

void Distributer_OnPlayerSpawnPost(int client)
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    DisarmClientFirearms(client);

    RequestFrame(Frame_DistributeWeapons, client);
}

void Frame_DistributeWeapons(int client)
{
    char class_name[32];

    for (int weapon, current_weapons; current_weapons < CS_SLOT_KNIFE; current_weapons++)
    {
        if (g_Players[client].weapons_id[current_weapons] == CSWeapon_NONE)
        {
            continue;
        }

        CS_WeaponIDToAlias(g_Players[client].weapons_id[current_weapons], class_name, sizeof(class_name));
        Format(class_name, sizeof(class_name), "weapon_%s", class_name);

        weapon = GivePlayerItem(client, class_name);

        if (weapon != -1)
        {
            EquipPlayerWeapon(client, weapon);
        }
    }
}

void DisplayDistributerMenu(int client)
{
    char buffer[64];

    LoadoutData loadout;

    Menu menu = new Menu(Handler_DistributerMenu);

    FormatEx(buffer, sizeof(buffer), "%T%T:\n ", "MenuPrefix", client, "Distributer", client);

    menu.SetTitle(buffer);

    for (int i = loadouts.Length - 1; i >= 0; i--)
    {
        if (!loadouts.GetArray(i, loadout, sizeof(loadout)))
        {
            continue;
        }

        FormatEx(buffer, sizeof(buffer), "%T", loadout.name, client);
        menu.AddItem(loadout.name, buffer);
    }

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_DistributerMenu(Menu menu, MenuAction action, int client, int option)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char buffer[32];

            menu.GetItem(option, buffer, sizeof(buffer));

            strcopy(g_Players[client].current_loadout_name, sizeof(Player::current_loadout_name), buffer);

            g_Players[client].close_menu = false;

            DisplayDistributerLoadoutMenu(buffer, client);
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

void DisplayDistributerLoadoutMenu(const char[] loadout_name, int client, int view = WEAPONTYPE_PRIMARY)
{
    char buffer[64];

    LoadoutData loadout_data;

    LoadoutItemData item_data;

    g_Players[client].current_loadout_view = view;

    int team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

    Menu menu = new Menu(Handler_DistributerLoadoutMenu);

    FormatEx(buffer, sizeof(buffer), "%T%T %T:\n\n%T\n ", "MenuPrefix", client, loadout_name, client, view & WEAPONTYPE_PRIMARY ? "Primary Weapon" : "Secondary Weapon", client, (team == LOADOUT_TEAM_CT) ? "Team CT" : "Team T", client);

    menu.SetTitle(buffer);

    for (int i = loadouts.Length - 1; i >= 0; i--)
    {
        if (!loadouts.GetArray(i, loadout_data, sizeof(loadout_data)))
        {
            continue;
        }

        if (strcmp(loadout_data.name, loadout_name))
        {
            continue;
        }

        for (int j = loadout_data.items[team].Length - 1; j >= 0; j--)
        {
            if (!loadout_data.items[team].GetArray(j, item_data, sizeof(item_data)))
            {
                continue;
            }

            if (item_data.flags ^ view)
            {
                continue;
            }

            // There really isn't much we can do about this because we will never know which weapon to display the default for, since users control the loadouts. Note: PTaH.
            if (!retakes_distributer_force_weapon.BoolValue)
            {
                if (item_data.item_id == CSWeapon_M4A1 || item_data.item_id == CSWeapon_M4A1_SILENCER)
                {
                    if (!CS_FindEquippedInventoryItem(client, item_data.item_id))
                    {
                        item_data.classname = item_data.item_id != CSWeapon_M4A1 ? "weapon_m4a1" : "weapon_m4a1_silencer";
                    }
                }

                else if (item_data.item_id == CSWeapon_USP_SILENCER || item_data.item_id == CSWeapon_HKP2000)
                {
                    if (!CS_FindEquippedInventoryItem(client, item_data.item_id))
                    {
                        item_data.classname = item_data.item_id != CSWeapon_USP_SILENCER ? "weapon_usp_silencer" : "weapon_hkp2000";
                    }
                }
            }

            FormatEx(buffer, sizeof(buffer), "%T", item_data.classname, client);
            menu.AddItem(item_data.classname, buffer);
        }
    }

    if (menu.ItemCount <= 0)
    {
        if (!g_Players[client].close_menu)
        {
            DisplayDistributerLoadoutMenu(g_Players[client].current_loadout_name, client, view & WEAPONTYPE_PRIMARY ? WEAPONTYPE_SECONDARY : WEAPONTYPE_PRIMARY);
        }

        g_Players[client].close_menu = true;

        delete menu;

        return;
    }

    FixMenuGap(menu);

    menu.ExitButton = true;
    menu.ExitBackButton = true;

    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_DistributerLoadoutMenu(Menu menu, MenuAction action, int client, int option)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char buffer[32];

            menu.GetItem(option, buffer, sizeof(buffer));

            if (GetGameTime() < grace_period)
            {
                int weapon = GivePlayerItem(client, buffer);

                if (weapon != -1)
                {
                    EquipPlayerWeapon(client, weapon);
                }
            }

            char loadout_name[48];
            PlayerLoadout player_loadout_data;
            int view = g_Players[client].current_loadout_view;
            int team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

            strcopy(loadout_name, sizeof(loadout_name), g_Players[client].current_loadout_name);

            g_Players[client].weapons_map.GetArray(loadout_name, player_loadout_data, sizeof(player_loadout_data));

            if (view & WEAPONTYPE_PRIMARY)
            {
                player_loadout_data.primary_weapon_id[team] = CS_AliasToWeaponID(buffer);
            }

            else if (view & WEAPONTYPE_SECONDARY)
            {
                player_loadout_data.secondary_weapon_id[team] = CS_AliasToWeaponID(buffer);
            }

            g_Players[client].weapons_map.SetArray(loadout_name, player_loadout_data, sizeof(player_loadout_data));

            if (!g_Players[client].close_menu)
            {
                g_Players[client].close_menu = true;
                DisplayDistributerLoadoutMenu(g_Players[client].current_loadout_name, client, view & WEAPONTYPE_PRIMARY ? WEAPONTYPE_SECONDARY : WEAPONTYPE_PRIMARY);
            }

            PrintToChat(client, "%t%t", "MessagesPrefix", "New Weapon", view & WEAPONTYPE_PRIMARY ? "Weapon Type Primary" : "Weapon Type Secondary", buffer);
        }

        case MenuAction_Cancel:
        {
            if (option == MenuCancel_ExitBack)
            {
                int view = g_Players[client].current_loadout_view;

                if (view & WEAPONTYPE_SECONDARY && g_Players[client].close_menu)
                {
                    DisplayDistributerMenu(client);
                }

                if (view & WEAPONTYPE_SECONDARY)
                {
                    DisplayDistributerLoadoutMenu(g_Players[client].current_loadout_name, client, WEAPONTYPE_PRIMARY);

                    g_Players[client].close_menu = false;
                }

                else if (view & WEAPONTYPE_PRIMARY)
                {
                    DisplayDistributerMenu(client);
                }
            }
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

bool CS_FindEquippedInventoryItem(int client, CSWeaponID weapon_id)
{
    for (int i = GetEntPropArraySize(client, Prop_Send, "m_EquippedLoadoutItemDefIndices") - 1; i >= 0; i--)
    {
        if (CS_WeaponIDToItemDefIndex(weapon_id) == GetEntProp(client, Prop_Send, "m_EquippedLoadoutItemDefIndices", _, i))
        {
            return true;
        }
    }

    return false;
}