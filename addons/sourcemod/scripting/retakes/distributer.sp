/*
 * • Responsible for distributing weapons to players.
 */

#assert defined COMPILING_FROM_MAIN

#define LOADOUT_TEAM_T   0
#define LOADOUT_TEAM_CT  1
#define LOADOUT_TEAM_MAX 2

#define WEAPONTYPE_PRIMARY   (1 << 0)
#define WEAPONTYPE_SECONDARY (2 << 1)
#define WEAPONTYPE_UTILITY   (3 << 2)

enum struct PlayerLoadout
{
    int primary_weapon_def_index[2];
    int secondary_weapon_def_index[2];
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

    int Size(int team)
    {
        switch (team)
        {
            case LOADOUT_TEAM_T: return this.items[LOADOUT_TEAM_T].Length;
            case LOADOUT_TEAM_CT: return this.items[LOADOUT_TEAM_CT].Length;
            default: return -1;
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
int       line_count;
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
        SetFailState("%s : Unable to find distributer.cfg file", PLUGIN_TAG);
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

    g_Database.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s_players` (`account_id` INT NOT NULL, `loadout_name` VARCHAR(32), `primary_def_index_t` INT UNSIGNED, `primary_def_index_ct` INT UNSIGNED, `secondary_def_index_t` INT UNSIGNED, `secondary_def_index_ct` INT UNSIGNED, PRIMARY KEY (`account_id`), UNIQUE INDEX `UNIQUE1` (`account_id` ASC)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;", table_name);
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

    LoadoutData loadout_data;

    for (int i = loadouts.Length - 1; i >= 0; i--)
    {
        if (!loadouts.GetArray(i, loadout_data, sizeof(loadout_data)))
        {
            continue;
        }

        PlayerLoadout player_loadout_data;

        for (int j; j < 2; j++)
        {
            player_loadout_data.primary_weapon_def_index[j] = 0;
            player_loadout_data.secondary_weapon_def_index[j] = 0;
        }

        g_Players[client].weapons_map.SetArray(loadout_data.name, player_loadout_data, sizeof(player_loadout_data));
    }

    char query[256];
    char table_name[32];

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "INSERT INTO `%s_players` (`account_id`) VALUES (%d) ON DUPLICATE KEY UPDATE `account_id` = %d", table_name, g_Players[client].account_id, g_Players[client].account_id);
    g_Database.Query(SQL_OnClientConnect, query, g_Players[client].user_id, DBPrio_High);
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

    for (int i; i < g_Players[client].weapons_map.Size; i++)
    {
        loadout_snapshot.GetKey(i, buffer, sizeof(buffer));

        if (!g_Players[client].weapons_map.GetArray(buffer, player_loadout_data, sizeof(player_loadout_data)))
        {
            continue;
        }

        FormatEx(query, sizeof(query), "INSERT INTO (`%s_players`) VALUES (`%s`, %d, %d, %d, %d) WHERE `account_id` = %d;", table_name, buffer, player_loadout_data.primary_weapon_def_index[0], player_loadout_data.primary_weapon_def_index[1], player_loadout_data.secondary_weapon_def_index[0], player_loadout_data.secondary_weapon_def_index[1], g_Players[client].account_id);

        transaction.AddQuery(query);
    }

    g_Database.Execute(transaction, _, SQL_OnClientInfoSavedError, _, DBPrio_High);
}

void SQL_OnClientInfoSavedError(Database database, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    if (!database || error[0])
    {
        LogError("%s There was an error fecthing player data \n\n%s", PLUGIN_TAG, error);
        return;
    }
}

void SQL_OnClientConnect(Database database, DBResultSet results, const char[] error, int userid)
{
    if (!database || !results)
    {
        LogError("%s There was an error fecthing player data \n\n%s", PLUGIN_TAG, error);
        return;
    }

    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    char query[256];
    char table_name[32];

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "SELECT * FROM `%s_players` WHERE `account_id` = %d", table_name, g_Players[client].account_id);
    g_Database.Query(SQL_OnClientInfoFetched, query, g_Players[client].user_id, DBPrio_High);
}

void SQL_OnClientInfoFetched(Database database, DBResultSet results, const char[] error, int userid)
{
    if (!database || !results)
    {
        LogError("There was an error saving player weapon data! %s", error);
        return;
    }

    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    // int loadout_name;
    // int primary_weapon[LOADOUT_TEAM_MAX];
    // int secondary_weapon[LOADOUT_TEAM_MAX];

    // results.FieldNameToNum("loadout_name", loadout_name);
    // results.FieldNameToNum("primary_def_index_t", primary_weapon[LOADOUT_TEAM_T]);
    // results.FieldNameToNum("primary_def_index_ct", primary_weapon[LOADOUT_TEAM_CT]);
    // results.FieldNameToNum("secondary_def_index_t", secondary_weapon[LOADOUT_TEAM_T]);
    // results.FieldNameToNum("secondary_def_index_ct", secondary_weapon[LOADOUT_TEAM_CT]);

    // char buffer[64];
    // PlayerLoadout player_loadout;

    // while (results.FetchRow())
    // {
    //     results.FetchString(loadout_name, buffer, sizeof(buffer));

    //     for (int i; i < 2; i++)
    //     {
    //         player_loadout.primary_weapon_def_index[i] = results.FetchInt(primary_weapon[i]);
    //     }

    //     for (int i; i < 2; i++)
    //     {
    //         player_loadout.secondary_weapon_def_index[i] = results.FetchInt(secondary_weapon[i]);
    //     }
    // }
}

public Action Command_Distributer(int client, int args)
{
    DisplayDistributerMenu(client);
    return Plugin_Handled;
}

void SMCParser_OnStart(SMCParser parser)
{
#if defined DEBUG
    PrintToServer("Loading Distributer configuration file");
#endif
}

SMCResult SMCParser_OnEnterSection(SMCParser parser, const char[] name, bool opt_quotes)
{
#if defined DEBUG
    PrintToServer("Distributer section: %s", name);
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
        if (!strcmp(name, "Counter_Terrorist"))
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
    PrintToServer("Distributer key: [%s] %s", key, value);
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

            static const char key_keys[][] = { "primary_weapon", "secondary_weapon", "utility" };

            for (int i; i < sizeof(key_keys); i++)
            {
                if (!strncmp(key, key_keys[i], sizeof(key_keys[][])))
                {
                    switch (i)
                    {
                        case 0: flags |= WEAPONTYPE_PRIMARY;
                        case 1: flags |= WEAPONTYPE_SECONDARY;
                        case 2: flags |= WEAPONTYPE_UTILITY;
                    }

                    break;
                }
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
        int position;

        char buffer[32];

        LoadoutData loadout_data;

        static LoadoutItemData item_data;

        FormatEx(buffer, sizeof(buffer), "weapon_%s", current_weapon);

        for (int i; i < loadouts.Length; i++)
        {
            if (!loadouts.GetArray(i, loadout_data, sizeof(loadout_data)))
            {
                continue;
            }

            for (int j; j < LOADOUT_TEAM_MAX; j++)
            {
                position = loadout_data.items[j].FindString(buffer);

                if (position != -1)
                {
                    loadout_data.items[j].GetArray(position, item_data, sizeof(item_data));

                    if (!strcmp(key, "chance"))
                    {
                        item_data.chance = StringToFloat(value);
                    }

                    if (!strcmp(key, "max"))
                    {
                        item_data.max = StringToInt(value);
                    }

                    loadout_data.items[j].SetArray(position, item_data, sizeof(item_data));
                }
            }
        }
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
    PrintToServer("Distributer finished parsing %d loadouts", loadouts.Length);
#endif

    if (failed)
    {
        SetFailState("%s : There was a fatal error parsing distributer loadouts at line %d", PLUGIN_TAG, line_count);
        return;
    }

    bool fail_state;

    LoadoutData     loadout;
    LoadoutItemData item_data;

    for (int i = loadouts.Length - 1; i >= 0; i--)
    {
        if (!loadouts.GetArray(i, loadout, sizeof(loadout)))
        {
            continue;
        }

        if (!TranslationPhraseExists(loadout.name))
        {
            fail_state = true;
            LogError("Translation for \"%s\" loadout key not found at line %d", loadout.name, line_count);
        }

        for (int j; j <= LOADOUT_TEAM_MAX; j++)
        {
            for (int k = loadout.Size(j) - 1; k >= 0; k--)
            {
                if (!loadout.items[j].GetArray(k, item_data, sizeof(item_data)))
                {
                    continue;
                }

                if (!TranslationPhraseExists(item_data.classname))
                {
                    fail_state = true;
                    LogError("Translation for \"%s\" weapon key not found at line %d", item_data.classname, line_count);
                }
            }
        }
    }

    if (fail_state)
    {
        SetFailState("%s : There are missing translations for distributer part of the retakes plugin", PLUGIN_TAG);
    }
}

void Distributer_OnRoundPreStart()
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    LoadoutData loadout_data;
    // LoadoutItemData item_data;
    PlayerLoadout player_loadout_data;

    // temp
    loadouts.GetArray(0, loadout_data, sizeof(loadout_data));

    PrintToChatAll("%s", loadout_data.name);

    for (int team, current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (!IsClientConnected(current_client))
        {
            continue;
        }

        team = GetClientTeam(current_client) - LOADOUT_TEAM_MAX;

        if (team <= -1)
        {
            continue;
        }

        if (g_Players[current_client].weapons_map.GetArray(loadout_data.name, player_loadout_data, sizeof(player_loadout_data)))
        {
            g_Players[current_client].weapons_def_index[0] = player_loadout_data.primary_weapon_def_index[team];
            g_Players[current_client].weapons_def_index[1] = player_loadout_data.secondary_weapon_def_index[team];
        }

        else
        {

        }
    }
}

void Distributer_OnPlayerSpawn(int client)
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    char class_name[32];
    CSWeaponID weapon_id[2];

    DisarmClientFirearms(client);

    for (int weapon, current_weapons; current_weapons < 2; current_weapons++)
    {
        //temp
        if (!g_Players[client].weapons_def_index[current_weapons])
        {
            continue;
        }

        weapon_id[current_weapons] = CS_ItemDefIndexToID(g_Players[client].weapons_def_index[current_weapons]);

        if (weapon_id[current_weapons] != CSWeapon_NONE)
        {
            CS_WeaponIDToAlias(weapon_id[current_weapons], class_name, sizeof(class_name));
            Format(class_name, sizeof(class_name), "weapon_%s", class_name);

            weapon = GivePlayerItem(client, class_name);

            if (weapon != -1)
            {
                EquipPlayerWeapon(client, weapon);
            }
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

    FormatEx(buffer, sizeof(buffer), "%T%T %T:\n\n%T\n ", "MenuPrefix", client, loadout_name, client, (view & WEAPONTYPE_PRIMARY) ? "Primary Weapon" : "Secondary Weapon", client, (team == LOADOUT_TEAM_CT) ? "Team CT" : "Team T", client);

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

        for (int j = loadout_data.Size(team) - 1; j >= 0; j--)
        {
            if (!loadout_data.items[team].GetArray(j, item_data, sizeof(item_data)))
            {
                continue;
            }

            if (item_data.flags ^ view)
            {
                continue;
            }

            // Have something better in mind and I'm going to use PTaH
            if (!strcmp(item_data.classname, "weapon_m4a1"))
            {
                item_data.classname = CS_FindEquippedInventoryItem(client, item_data.item_id) ? "weapon_m4a1" : "weapon_m4a1_silencer";
            }

            FormatEx(buffer, sizeof(buffer), "%T", item_data.classname, client);
            menu.AddItem(item_data.classname, buffer);
        }
    }

    if (menu.ItemCount <= 0)
    {
        if (!g_Players[client].close_menu)
        {
            DisplayDistributerLoadoutMenu(g_Players[client].current_loadout_name, client, (view == WEAPONTYPE_PRIMARY) ? WEAPONTYPE_SECONDARY : WEAPONTYPE_PRIMARY);
        }

        g_Players[client].close_menu = true;

        delete menu;

        return;
    }

    FixMenuGap(menu);

    menu.ExitButton = true;

    // if (g_Players[client].close_menu)
    // {
    //     g_Players[client].close_menu = false;
    //     menu.ExitBackButton = true;
    // }

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

                EquipPlayerWeapon(client, weapon);
            }

            // int weapon_def_index[2];
            PlayerLoadout player_loadout_data;
            int team = GetClientTeam(client) - LOADOUT_TEAM_MAX;


            // switch (g_Players[client].current_loadout_view)
            // {
            //     case WEAPONTYPE_PRIMARY: weapon_def_index[0] = CS_WeaponIDToItemDefIndex(CS_AliasToWeaponID(buffer));
            //     case WEAPONTYPE_SECONDARY: weapon_def_index[1] = CS_WeaponIDToItemDefIndex(CS_AliasToWeaponID(buffer));
            // }

            // set the data here.

            if (!g_Players[client].close_menu)
            {
                g_Players[client].close_menu = true;
                DisplayDistributerLoadoutMenu(g_Players[client].current_loadout_name, client, (g_Players[client].current_loadout_view == WEAPONTYPE_PRIMARY) ? WEAPONTYPE_SECONDARY : WEAPONTYPE_PRIMARY);
            }
        }

        case MenuAction_Cancel:
        {
            if (option == MenuCancel_ExitBack)
            {
                DisplayDistributerMenu(client);
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