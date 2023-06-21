/*
 * • Responsible for distributing weapons to players.
 */

#assert defined COMPILING_FROM_MAIN

#define LOADOUT_TEAM_T   0
#define LOADOUT_TEAM_CT  1
#define LOADOUT_TEAM_MAX 2

#define LOADOUT_WEAPON_PRIMARY       0
#define LOADOUT_WEAPON_SECONDARY     1
#define LOADOUT_WEAPON_GRENADE       2
#define LOADOUT_WEAPON_ITEM          3
#define LOADOUT_WEAPON_GRENADE_ONE   4
#define LOADOUT_WEAPON_GRENADE_TWO   5
#define LOADOUT_WEAPON_GRENADE_THREE 6
#define LOADOUT_WEAPON_GRENADE_FOUR  7
#define LOADOUT_WEAPON_KNIFE         8
#define LOADOUT_WEAPON_MAX           9

#define LOADOUT_GRENADE_OFFSET (LOADOUT_WEAPON_SECONDARY + 2)

#define MAX_SLOT_FIREGRENADE  0
#define MAX_SLOT_SMOKEGRENADE 1
#define MAX_SLOT_MAX          2

#define WEAPON_TYPE_PRIMARY   (1 << 0)
#define WEAPON_TYPE_SECONDARY (1 << 1)
#define WEAPON_TYPE_UTILITY   (1 << 2)
#define WEAPON_TYPE_ITEM      (1 << 3)

enum struct PlayerLoadout
{
    CSWeaponID primary_weapon_id[LOADOUT_TEAM_MAX];
    CSWeaponID secondary_weapon_id[LOADOUT_TEAM_MAX];
}

enum struct LoadoutItem
{
    CSWeaponID item_id;

    char classname[32];

    float chance;

    int flags;

    int max;
}

enum struct Loadout
{
    char name[24];

    ArrayList items[LOADOUT_TEAM_MAX];

    int item_primary_count[LOADOUT_TEAM_MAX];

    int item_secondary_count[LOADOUT_TEAM_MAX];

    // int       item_grenade_count[LOADOUT_TEAM_MAX];

    // int       item_item_count[LOADOUT_TEAM_MAX];

    void Initialize(const char[] name)
    {
        strcopy(this.name, sizeof(Loadout::name), name);

        for (int i; i < LOADOUT_TEAM_MAX; i++)
        {
            this.items[i] = new ArrayList(sizeof(LoadoutItem));
        }
    }

    int FindItemByCSWeaponID(int team, CSWeaponID weapon_id)
    {
        LoadoutItem item_data;

        for (int i; i < this.items[team].Length; i++)
        {
            this.items[team].GetArray(i, item_data, sizeof(item_data));

            if (item_data.item_id == weapon_id)
            {
                return i;
            }
        }

        return -1;
    }

    void Clear()
    {
        for (int i; i < LOADOUT_TEAM_MAX; i++)
        {
            delete this.items[i];
        }
    }
}

ArrayList g_Loadouts;
int       g_LineCount = -1;
int       g_SMCParserDepth;
int       g_SMCParserCount;
int       g_CurrentLoadoutType;
ConVar    ammo_grenade_limit_total;
char      g_CurrentWeaponClassName[sizeof(LoadoutItem::classname)];

void Distributor_OnConfigsExecuted()
{
    if (!retakes_distributor_enable.BoolValue || g_Loadouts)
    {
        return;
    }

    ammo_grenade_limit_total          = FindConVar("ammo_grenade_limit_total");
    ammo_grenade_limit_total.IntValue = retakes_distributor_ammo_limit.IntValue;

    bool file_exists;

    char buffer[PLATFORM_MAX_PATH];

    BuildPath(Path_SM, buffer, sizeof(buffer), "data/retakes/distributor.cfg");

    file_exists = FileExists(buffer);

    if (!file_exists)
    {
        SetFailState("%s : Unable to find \"data/retakes/distributor.cfg\" file", PLUGIN_TAG);

        return;
    }

    g_Loadouts = new ArrayList(sizeof(Loadout));

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
}

public void Distributor_OnPluginStart()
{
}

void Distributor_OnDatabaseConnection()
{
    if (!retakes_distributor_enable.BoolValue)
    {
        return;
    }

    char query[512];
    char table_name[32];

    retakes_database_table_distributor.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s_players` (`account_id` INT NOT NULL, `loadout_name` VARCHAR(32), `primary_wep_id_t` INT UNSIGNED, `primary_wep_id_ct` INT UNSIGNED, `secondary_wep_id_t` INT UNSIGNED, `secondary_wep_id_ct` INT UNSIGNED, PRIMARY KEY (`account_id`, `loadout_name`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;", table_name);
    g_Database.Query(SQL_OnDistributorTableCreated, query, .prio = DBPrio_High);
}

void SQL_OnDistributorTableCreated(Database database, DBResultSet results, const char[] error, any data)
{
    if (!database || !results)
    {
        LogError("%s There was an error creating the distributor table \n\n%s", PLUGIN_TAG, error);
        return;
    }
}

void Distributor_OnClientPutInServer(int client)
{
    if (!retakes_distributor_enable.BoolValue || !client)
    {
        return;
    }

    Loadout loadout_data;

    for (int current_loadouts = g_Loadouts.Length - 1; current_loadouts >= 0; current_loadouts--)
    {
        if (!g_Loadouts.GetArray(current_loadouts, loadout_data, sizeof(loadout_data)))
        {
            continue;
        }

        PlayerLoadout player_loadout_data;

        for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
        {
            player_loadout_data.primary_weapon_id[current_team]   = CSWeapon_NONE;
            player_loadout_data.secondary_weapon_id[current_team] = CSWeapon_NONE;
        }

        g_Players[client].distributor.weapons_map.SetArray(loadout_data.name, player_loadout_data, sizeof(player_loadout_data));
    }

    if (IsFakeClient(client))
    {
        return;
    }

    char query[256];
    char table_name[32];

    retakes_database_table_distributor.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "SELECT * FROM `%s_players` WHERE `account_id` = %d", table_name, g_Players[client].account_id);
    g_Database.Query(SQL_OnClientInfoFetched, query, g_Players[client].user_id, DBPrio_High);
}

void Distributor_OnClientDisconnect(int client)
{
    if (!retakes_distributor_enable.BoolValue || !client || IsFakeClient(client))
    {
        return;
    }

    char buffer[32];
    char query[256];
    char table_name[32];

    PlayerLoadout player_loadout_data;

    Transaction transaction = new Transaction();

    StringMapSnapshot loadout_snapshot = g_Players[client].distributor.weapons_map.Snapshot();

    retakes_database_table_distributor.GetString(table_name, sizeof(table_name));

    for (int i = loadout_snapshot.Length - 1; i >= 0; i--)
    {
        loadout_snapshot.GetKey(i, buffer, sizeof(buffer));

        if (!g_Players[client].distributor.weapons_map.GetArray(buffer, player_loadout_data, sizeof(player_loadout_data)))
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

        transaction.AddQuery(query);
    }

    delete loadout_snapshot;

#if defined DEBUG
    g_Database.Execute(transaction, SQL_OnClientInfoSaved, SQL_OnClientInfoSavedError, .priority = DBPrio_High);
#else
    g_Database.Execute(transaction, .onError = SQL_OnClientInfoSavedError, .priority = DBPrio_High);
#endif
}

#if defined DEBUG
void        SQL_OnClientInfoSaved(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
    LogMessage("Player data transaction completed successfully (%d queries)", numQueries);
}
#endif

void SQL_OnClientInfoSavedError(Database database, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    if (!database || error[0])
    {
        LogError("%s There was an error saving player data (%s)", PLUGIN_TAG, error);
        return;
    }
}

void SQL_OnClientInfoFetched(Database database, DBResultSet results, const char[] error, int userid)
{
    if (error[0])
    {
        LogError("%s There was an error fetching player weapon data! (%s)", PLUGIN_TAG, error);
        return;
    }

    int client = GetClientOfUserId(userid);

    if (!client || !results.RowCount)
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

    char          buffer[64];
    PlayerLoadout player_loadout;

    while (results.FetchRow())
    {
        results.FetchString(loadout_name, buffer, sizeof(buffer));

        for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
        {
            player_loadout.primary_weapon_id[current_team]   = view_as<CSWeaponID>(results.FetchInt(primary_weapon[current_team]));
            player_loadout.secondary_weapon_id[current_team] = view_as<CSWeaponID>(results.FetchInt(secondary_weapon[current_team]));
        }

        g_Players[client].distributor.weapons_map.SetArray(buffer, player_loadout, sizeof(player_loadout));
    }
}

public Action Command_Distributor(int client, int args)
{
    DisplayDistributorMenu(client);
    return Plugin_Handled;
}

void SMCParser_OnStart(SMCParser parser)
{
#if defined DEBUG
    LogMessage("Loading distributor configuration file");
#endif
}

SMCResult SMCParser_OnEnterSection(SMCParser parser, const char[] name, bool opt_quotes)
{
#if defined DEBUG
    LogMessage("Distributor Section Parse: %s", name);
#endif

    if (g_SMCParserDepth == 1)
    {
        g_SMCParserCount++;
    }

    if (g_SMCParserDepth == 2 && g_SMCParserCount == 1)
    {
        Loadout loadout_data;

        loadout_data.Initialize(name);

        g_Loadouts.PushArray(loadout_data, sizeof(loadout_data));
    }

    else if (g_SMCParserDepth == 3 && g_SMCParserCount == 1)
    {
        if (!strcmp(name, "Counter Terrorist"))
        {
            g_CurrentLoadoutType = LOADOUT_TEAM_CT;
        }

        else if (!strcmp(name, "Terrorist"))
        {
            g_CurrentLoadoutType = LOADOUT_TEAM_T;
        }

        else
        {
            g_CurrentLoadoutType = -1;
        }
    }

    if (g_SMCParserDepth == 2 && g_SMCParserCount == 3)
    {
        strcopy(g_CurrentWeaponClassName, sizeof(g_CurrentWeaponClassName), name);
    }

    g_SMCParserDepth++;

    return SMCParse_Continue;
}

SMCResult SMCParser_OnLeaveSectionn(SMCParser parser)
{
    g_SMCParserDepth--;

    return SMCParse_Continue;
}

SMCResult SMCParser_OnKeyValue(SMCParser parser, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
#if defined DEBUG
    LogMessage("Distributor Key Parse: [%s] %s", key, value);
#endif

    if (g_SMCParserDepth == 4 && g_SMCParserCount == 1)
    {
        static LoadoutItem item_data;

        if (StrContains(key, "weapon") != -1 || !strcmp(key, "utility") || !strcmp(key, "item"))
        {
            int flags;

            char buffer[32];

            FormatEx(buffer, sizeof(buffer), "weapon_%s", value);

            CSWeaponID weapon_id = CS_AliasToWeaponID(buffer);

            if (!weapon_id && strcmp(key, "item"))
            {
                return SMCParse_Continue;
            }

            item_data.item_id = weapon_id;

            strcopy(item_data.classname, sizeof(LoadoutItem::classname), buffer);

            if (!strncmp(key, "primary_weapon", 9))
            {
                flags |= WEAPON_TYPE_PRIMARY;
            }

            if (!strncmp(key, "secondary_weapon", 9))
            {
                flags |= WEAPON_TYPE_SECONDARY;
            }

            if (!strncmp(key, "utility", 7))
            {
                flags |= WEAPON_TYPE_UTILITY;
            }

            if (!strncmp(key, "item", 4))
            {
                flags |= WEAPON_TYPE_ITEM;

                FormatEx(item_data.classname, sizeof(LoadoutItem::classname), "item_%s", value);
            }

            item_data.flags = flags;

            Loadout loadout_data;

            g_Loadouts.GetArray(g_Loadouts.Length - 1, loadout_data, sizeof(loadout_data));

            switch (g_CurrentLoadoutType)
            {
                case LOADOUT_TEAM_CT: loadout_data.items[LOADOUT_TEAM_CT].PushArray(item_data, sizeof(item_data));
                case LOADOUT_TEAM_T: loadout_data.items[LOADOUT_TEAM_T].PushArray(item_data, sizeof(item_data));
                default: return SMCParse_HaltFail;
            }
        }
    }

    else if (g_SMCParserDepth == 2 && g_SMCParserCount == 2)
    {
        if (!strcmp(key, "loadout_commands"))
        {
            char value_str[64];
            char buffer[24][24];

            strcopy(value_str, sizeof(value_str), value);

            TrimString(value_str);

            ExplodeString(value_str, ",", buffer, sizeof(buffer[]), 24);

            for (int i; i < 24; i++)
            {
                if (buffer[i][0] == '\0')
                {
                    continue;
                }

                Format(buffer[i], 24, "sm_%s", buffer[i]);
                RegConsoleCmd(buffer[i], Command_Distributor);
            }
        }
    }

    else if (g_SMCParserDepth == 3 && g_SMCParserCount == 3)
    {
        char buffer[32];

        Loadout loadout_data;

        static LoadoutItem item_data;

        FormatEx(buffer, sizeof(buffer), "weapon_%s", g_CurrentWeaponClassName);

        for (int i; i < g_Loadouts.Length; i++)
        {
            g_Loadouts.GetArray(i, loadout_data, sizeof(loadout_data));

            for (int j; j < LOADOUT_TEAM_MAX; j++)
            {
                for (int k; k < loadout_data.items[j].Length; k++)
                {
                    loadout_data.items[j].GetArray(k, item_data, sizeof(item_data));

                    if (!strcmp(buffer, item_data.classname))
                    {
                        if (!strcmp(key, "chance"))
                        {
                            item_data.chance = StringToFloat(value);
                        }

                        if (!strcmp(key, "max"))
                        {
                            item_data.max = StringToInt(value);
                        }

                        loadout_data.items[j].SetArray(k, item_data, sizeof(item_data));
                    }
                }
            }
        }
    }

    return SMCParse_Continue;
}

SMCResult SMCParser_OnRawLine(SMCParser parser, const char[] line, int line_num)
{
    g_LineCount++;

    return SMCParse_Continue;
}

void SMCParser_OnEnd(SMCParser parser, bool halted, bool failed)
{
#if defined DEBUG
    LogMessage("Distributor Finished Parsing: %d loadouts", g_Loadouts.Length);
#endif

    if (failed)
    {
        SetFailState("%s : There was a fatal error parsing the distributor config file at line %d", PLUGIN_TAG, g_LineCount);

        return;
    }

    bool fail_state;

    Loadout     loadout_data;
    LoadoutItem item_data;

    for (int item_count[LOADOUT_TEAM_MAX][LOADOUT_WEAPON_MAX], current_loadout = g_Loadouts.Length - 1; current_loadout >= 0; current_loadout--)
    {
        if (!g_Loadouts.GetArray(current_loadout, loadout_data, sizeof(loadout_data)))
        {
            continue;
        }

        if (!TranslationPhraseExists(loadout_data.name))
        {
            fail_state = true;

            LogError("Translation for \"%s\" loadout key not found", loadout_data.name);
        }

        for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
        {
            for (int current_item = loadout_data.items[current_team].Length - 1; current_item >= 0; current_item--)
            {
                if (!loadout_data.items[current_team].GetArray(current_item, item_data, sizeof(item_data)))
                {
                    continue;
                }

                if (!TranslationPhraseExists(item_data.classname))
                {
                    fail_state = true;

                    LogError("Translation for \"%s\" weapon key not found", item_data.classname);
                }

                if (item_data.flags & WEAPON_TYPE_PRIMARY)
                {
                    item_count[current_team][LOADOUT_WEAPON_PRIMARY]++;
                }

                else if (item_data.flags & WEAPON_TYPE_SECONDARY)
                {
                    item_count[current_team][LOADOUT_WEAPON_SECONDARY]++;
                }

                // else if (item_data.flags & WEAPON_TYPE_UTILITY)
                // {
                //     item_count[current_team][LOADOUT_WEAPON_GRENADE]++;
                // }

                // else if (item_data.flags & WEAPON_TYPE_ITEM)
                // {
                //     item_count[current_team][LOADOUT_WEAPON_ITEM]++;
                // }
            }
        }

        for (int i; i < LOADOUT_TEAM_MAX; i++)
        {
            loadout_data.item_primary_count[i]   = item_count[i][LOADOUT_WEAPON_PRIMARY];
            loadout_data.item_secondary_count[i] = item_count[i][LOADOUT_WEAPON_SECONDARY];
            // loadout_data.item_grenade_count[i]   = item_count[i][LOADOUT_WEAPON_GRENADE];
            // loadout_data.item_item_count[i] = item_count[i][LOADOUT_WEAPON_ITEM];
        }

        g_Loadouts.SetArray(current_loadout, loadout_data, sizeof(loadout_data));
    }

    if (fail_state)
    {
        SetFailState("%s : There are missing translations for the distributor part of the retakes plugin", PLUGIN_TAG);
    }
}

void Distributor_OnRoundPreStart()
{
    if (!retakes_distributor_enable.BoolValue)
    {
        return;
    }

    LoadoutItem item_data;
    Loadout     loadout_data;
    PlayerLoadout   player_loadout_data;

    int weapon_id_max[CSWeapon_MAX_WEAPONS];

    ArrayList filtered_items[LOADOUT_TEAM_MAX][LOADOUT_WEAPON_MAX - LOADOUT_GRENADE_OFFSET];

    for (int i = LOADOUT_TEAM_MAX - 1; i >= 0; i--)
    {
        for (int j = LOADOUT_WEAPON_MAX - LOADOUT_GRENADE_OFFSET - 1; j >= 0; j--)
        {
            filtered_items[i][j] = new ArrayList();
        }
    }

#if defined DEBUG
    PrintToChatAll("loadouts.Length: %d", g_Loadouts.Length);
#endif

    g_Loadouts.GetArray(GetURandomInt() % g_Loadouts.Length, loadout_data, sizeof(loadout_data));

    for (int i = LOADOUT_TEAM_MAX - 1; i >= 0; i--)
    {
        for (int j = loadout_data.items[i].Length - 1; j >= 0; j--)
        {
            loadout_data.items[i].GetArray(j, item_data, sizeof(item_data));

            switch (item_data.flags)
            {
                case WEAPON_TYPE_PRIMARY: filtered_items[i][LOADOUT_WEAPON_PRIMARY].Push(j);
                case WEAPON_TYPE_SECONDARY: filtered_items[i][LOADOUT_WEAPON_SECONDARY].Push(j);
                case WEAPON_TYPE_UTILITY: filtered_items[i][LOADOUT_WEAPON_GRENADE].Push(j);
                case WEAPON_TYPE_ITEM: filtered_items[i][LOADOUT_WEAPON_ITEM].Push(j);
            }
        }
    }

    // for (int i = LOADOUT_TEAM_MAX - 1; i >= 0; i--)
    // {
    //     filtered_items[i][LOADOUT_WEAPON_PRIMARY].Sort(Sort_Random, Sort_Integer);
    //     filtered_items[i][LOADOUT_WEAPON_SECONDARY].Sort(Sort_Random, Sort_Integer);
    //     filtered_items[i][LOADOUT_WEAPON_GRENADE].Sort(Sort_Random, Sort_Integer);
    //     filtered_items[i][LOADOUT_WEAPON_ITEM].Sort(Sort_Random, Sort_Integer);
    // }

    for (int current_team, current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (!IsClientInGame(current_client))
        {
            continue;
        }

        current_team = GetClientTeam(current_client) - LOADOUT_TEAM_MAX;

        if (current_team <= -1)
        {
            continue;
        }

        g_Players[current_client].distributor.ClearLoadout();

        if (!IsFakeClient(current_client))
        {
            g_Players[current_client].distributor.weapons_map.GetArray(loadout_data.name, player_loadout_data, sizeof(player_loadout_data));

            CSWeaponID primary_weapon_id = player_loadout_data.primary_weapon_id[current_team];

            CSWeaponID secondary_weapon_id = player_loadout_data.secondary_weapon_id[current_team];

            int item_position;

            if (primary_weapon_id > CSWeapon_NONE)
            {
                item_position = loadout_data.FindItemByCSWeaponID(current_team, primary_weapon_id);

                loadout_data.items[current_team].GetArray(item_position, item_data, sizeof(item_data));

                if (item_data.max)
                {
                    if (weapon_id_max[primary_weapon_id] < item_data.max)
                    {
                        g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_PRIMARY] = item_data.item_id;

                        weapon_id_max[primary_weapon_id]++;
                    }

                    else
                    {
                        g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_PRIMARY] = CSWeapon_NONE;
                    }
                }

                else
                {
                    g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_PRIMARY] = item_data.item_id;
                }
            }

            else if (secondary_weapon_id > CSWeapon_NONE)
            {
                item_position = loadout_data.FindItemByCSWeaponID(current_team, secondary_weapon_id);

                loadout_data.items[current_team].GetArray(item_position, item_data, sizeof(item_data));

                if (item_data.max)
                {
                    if (weapon_id_max[secondary_weapon_id] < item_data.max)
                    {
                        g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_SECONDARY] = item_data.item_id;

                        weapon_id_max[secondary_weapon_id]++;
                    }

                    else
                    {
                        g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_SECONDARY] = CSWeapon_NONE;
                    }
                }

                else
                {
                    g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_SECONDARY] = item_data.item_id;
                }
            }
        }

        int   maximum;
        float chance;

        for (int current_loadout; current_loadout <= LOADOUT_WEAPON_ITEM; current_loadout++)
        {
            if (g_Players[current_client].distributor.weapons_id[current_loadout])
            {
                continue;
            }

            switch (current_loadout)
            {
                case LOADOUT_WEAPON_PRIMARY, LOADOUT_WEAPON_SECONDARY:
                {
                    int item_position;

                    filtered_items[current_team][current_loadout].Sort(Sort_Random, Sort_Integer);

                    for (int current_weapon = filtered_items[current_team][current_loadout].Length - 1; current_weapon >= 0; current_weapon--)
                    {
                        item_position = filtered_items[current_team][current_loadout].Get(current_weapon);

                        if (!loadout_data.items[current_team].GetArray(item_position, item_data, sizeof(item_data)))
                        {
                            continue;
                        }

                        maximum = item_data.max ? item_data.max : -1;

                        if (maximum != -1 && weapon_id_max[item_data.item_id] >= maximum)
                        {
                            continue;
                        }

                        chance = item_data.chance ? item_data.chance : 1.0;

                        if (current_weapon == filtered_items[current_team][current_loadout].Length || GetURandomFloat() < chance)
                        {
                            g_Players[current_client].distributor.weapons_id[current_loadout] = item_data.item_id;

                            weapon_id_max[item_data.item_id]++;

                            break;
                        }
                    }
                }

                case LOADOUT_WEAPON_GRENADE:
                {
                    filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Sort(Sort_Random, Sort_Integer);

                    for (int nade_output, nade_slot_max[MAX_SLOT_MAX], current_nade = filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Length - 1; current_nade >= 0; current_nade--)
                    {
                        if (!loadout_data.items[current_team].GetArray(filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Get(current_nade), item_data, sizeof(item_data)) || nade_output > 4)
                        {
                            continue;
                        }

                        if (!strcmp(item_data.classname, "weapon_incgrenade") || !strcmp(item_data.classname, "weapon_molotov") && nade_slot_max[MAX_SLOT_FIREGRENADE] >= 1)
                        {
                            nade_slot_max[MAX_SLOT_FIREGRENADE]++;
                        }

                        else if (!strcmp(item_data.classname, "weapon_smokegrenade") && nade_slot_max[MAX_SLOT_SMOKEGRENADE] >= 1)
                        {
                            nade_slot_max[MAX_SLOT_SMOKEGRENADE]++;
                        }

                        maximum = item_data.max ? item_data.max : -1;

                        if (maximum != -1 && weapon_id_max[item_data.item_id] >= maximum)
                        {
                            continue;
                        }

                        chance = item_data.chance ? item_data.chance : 1.0;

                        if (GetURandomFloat() < chance)
                        {
                            nade_output++;

                            weapon_id_max[item_data.item_id]++;

                            g_Players[current_client].distributor.weapons_id[nade_output + LOADOUT_GRENADE_OFFSET] = item_data.item_id;
                        }
                    }
                }

                case LOADOUT_WEAPON_ITEM:
                {
                    filtered_items[current_team][LOADOUT_WEAPON_ITEM].Sort(Sort_Random, Sort_Integer);

                    for (int current_item = filtered_items[current_team][LOADOUT_WEAPON_ITEM].Length - 1; current_item >= 0; current_item--)
                    {
                        if (!loadout_data.items[current_team].GetArray(filtered_items[current_team][LOADOUT_WEAPON_ITEM].Get(current_item), item_data, sizeof(item_data)))
                        {
                            continue;
                        }

                        maximum = item_data.max ? item_data.max : -1;

                        if (maximum != -1 && weapon_id_max[item_data.item_id] >= maximum)
                        {
                            continue;
                        }

                        chance = item_data.chance ? item_data.chance : 1.0;

                        if (GetURandomFloat() < chance)
                        {
                            if (current_team == LOADOUT_TEAM_CT && !strcmp(item_data.classname, "item_kit"))
                            {
                                g_Players[current_client].distributor.kit = true;
                            }

                            if (!strcmp(item_data.classname, "item_kevlar"))
                            {
                                g_Players[current_client].distributor.kevlar = true;
                            }

                            else if (!strcmp(item_data.classname, "item_assultsuit"))
                            {
                                g_Players[current_client].distributor.assult_suit = true;
                            }

                            // weapon_id_max[item_data.item_id]++;
                        }
                    }
                }
            }
        }
    }

    for (int i = LOADOUT_TEAM_MAX - 1; i >= 0; i--)
    {
        for (int j = LOADOUT_WEAPON_MAX - LOADOUT_GRENADE_OFFSET - 1; j >= 0; j--)
        {
            delete filtered_items[i][j];
        }
    }
}

void Distributor_OnRoundFreezeEnd()
{
    int planter = GetPlanter();
    if (planter != -1)
    {
        Frame_DistributeWeapons(g_Players[planter].user_id);
    }
}

void Distributor_OnPlayerSpawn(int client)
{
    if (!retakes_distributor_enable.BoolValue || GetPlanter() == client)
    {
        return;
    }

    RequestFrame(Frame_DistributeWeapons, g_Players[client].user_id);
}

void Frame_DistributeWeapons(int userid)
{
    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    char class_name[32];

    for (int weapon, current_weapon = LOADOUT_WEAPON_MAX - 1; current_weapon >= 0; current_weapon--)
    {
        if (g_Players[client].distributor.weapons_id[current_weapon] == CSWeapon_NONE || current_weapon == LOADOUT_WEAPON_GRENADE || current_weapon == LOADOUT_WEAPON_ITEM)
        {
            continue;
        }

        CS_WeaponIDToAlias(g_Players[client].distributor.weapons_id[current_weapon], class_name, sizeof(class_name));
        Format(class_name, sizeof(class_name), "weapon_%s", class_name);

        weapon = GivePlayerItem(client, class_name);

        if (current_weapon <= LOADOUT_WEAPON_SECONDARY && weapon != -1)
        {
            EquipPlayerWeapon(client, weapon);
        }
    }

    if (g_Players[client].distributor.kit)
    {
        SetEntProp(client, Prop_Send, "m_bHasDefuser", true);
    }

    if (g_Players[client].distributor.assult_suit)
    {
        SetEntProp(client, Prop_Send, "m_bHasHelmet", true);
        SetEntProp(client, Prop_Send, "m_ArmorValue", 100);
    }

    else if (g_Players[client].distributor.kevlar)
    {
        SetEntProp(client, Prop_Send, "m_ArmorValue", 100);
    }
}

void DisplayDistributorMenu(int client)
{
    char buffer[64];

    Loadout loadout;

    Menu menu = new Menu(Handler_DistributorMenu);

    FormatEx(buffer, sizeof(buffer), "%T%T:\n ", "MenuPrefix", client, "Distributor", client);

    menu.SetTitle(buffer);

    for (int i = g_Loadouts.Length - 1; i >= 0; i--)
    {
        if (!g_Loadouts.GetArray(i, loadout, sizeof(loadout)))
        {
            continue;
        }

        FormatEx(buffer, sizeof(buffer), "%T", loadout.name, client);
        menu.AddItem(loadout.name, buffer);
    }

    if (menu.ItemCount <= 0)
    {
        delete menu;
        return;
    }

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_DistributorMenu(Menu menu, MenuAction action, int client, int option)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char buffer[32];

            menu.GetItem(option, buffer, sizeof(buffer));

            strcopy(g_Players[client].distributor.current_loadout_name, sizeof(Distributor::current_loadout_name), buffer);

            g_Players[client].distributor.close_menu = false;

            DisplayDistributorLoadoutMenu(buffer, client);
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

void DisplayDistributorLoadoutMenu(const char[] loadout_name, int client, int view = WEAPON_TYPE_PRIMARY)
{
    char buffer[64];

    Loadout loadout_data;

    LoadoutItem item_data;

    g_Players[client].distributor.current_loadout_view = view;

    int team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

    Menu menu = new Menu(Handler_DistributorLoadoutMenu);

    FormatEx(buffer, sizeof(buffer), "%T%T %T:\n\n%T\n ", "MenuPrefix", client, loadout_name, client, view & WEAPON_TYPE_PRIMARY ? "Primary Weapon" : "Secondary Weapon", client, team == LOADOUT_TEAM_CT ? "Team CT" : "Team T", client);

    menu.SetTitle(buffer);

    for (int current_loadout = g_Loadouts.Length - 1; current_loadout >= 0; current_loadout--)
    {
        if (!g_Loadouts.GetArray(current_loadout, loadout_data, sizeof(loadout_data)))
        {
            continue;
        }

        if (strcmp(loadout_data.name, loadout_name))
        {
            continue;
        }

        for (int current_item = loadout_data.items[team].Length - 1; current_item >= 0; current_item--)
        {
            if (!loadout_data.items[team].GetArray(current_item, item_data, sizeof(item_data)))
            {
                continue;
            }

            if (item_data.flags ^ view)
            {
                continue;
            }

            if (!retakes_distributor_force_weapon.BoolValue)
            {
                if (item_data.item_id == CSWeapon_M4A1 || item_data.item_id == CSWeapon_M4A1_SILENCER)
                {
                    if (!CS_FindEquippedInventoryItem(client, item_data.item_id))
                    {
                        item_data.classname = item_data.item_id != CSWeapon_M4A1 ? "weapon_m4a1" : "weapon_m4a1_silencer";
                    }
                }

                if (item_data.item_id == CSWeapon_USP_SILENCER || item_data.item_id == CSWeapon_HKP2000)
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
        if (!g_Players[client].distributor.close_menu)
        {
            DisplayDistributorLoadoutMenu(g_Players[client].distributor.current_loadout_name, client, view & WEAPON_TYPE_PRIMARY ? WEAPON_TYPE_SECONDARY : WEAPON_TYPE_PRIMARY);
        }

        g_Players[client].distributor.close_menu = true;

        delete menu;

        return;
    }

    FixMenuGap(menu);

    menu.ExitButton     = true;
    menu.ExitBackButton = true;

    menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_DistributorLoadoutMenu(Menu menu, MenuAction action, int client, int option)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char buffer[32];

            menu.GetItem(option, buffer, sizeof(buffer));

            if (GetGameTime() < retakes_distributor_grace_period.FloatValue)
            {
                int weapon = GivePlayerItem(client, buffer);

                if (weapon != -1)
                {
                    EquipPlayerWeapon(client, weapon);
                }
            }

            char          loadout_name[48];
            PlayerLoadout player_loadout_data;
            int           view = g_Players[client].distributor.current_loadout_view;
            int           team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

            strcopy(loadout_name, sizeof(loadout_name), g_Players[client].distributor.current_loadout_name);

            g_Players[client].distributor.weapons_map.GetArray(loadout_name, player_loadout_data, sizeof(player_loadout_data));

            if (view & WEAPON_TYPE_PRIMARY)
            {
                player_loadout_data.primary_weapon_id[team] = CS_AliasToWeaponID(buffer);
            }

            else if (view & WEAPON_TYPE_SECONDARY)
            {
                player_loadout_data.secondary_weapon_id[team] = CS_AliasToWeaponID(buffer);
            }

            g_Players[client].distributor.weapons_map.SetArray(loadout_name, player_loadout_data, sizeof(player_loadout_data));

            if (!g_Players[client].distributor.close_menu)
            {
                g_Players[client].distributor.close_menu = true;

                DisplayDistributorLoadoutMenu(g_Players[client].distributor.current_loadout_name, client, view & WEAPON_TYPE_PRIMARY ? WEAPON_TYPE_SECONDARY : WEAPON_TYPE_PRIMARY);
            }

            PrintToChat(client, "%t%t", "MessagesPrefix", "New Weapon", view & WEAPON_TYPE_PRIMARY ? "Weapon Type Primary" : "Weapon Type Secondary", buffer);
        }

        case MenuAction_Cancel:
        {
            if (option == MenuCancel_ExitBack)
            {
                int view = g_Players[client].distributor.current_loadout_view;

                if (view & WEAPON_TYPE_SECONDARY && g_Players[client].distributor.close_menu)
                {
                    DisplayDistributorMenu(client);
                }

                if (view & WEAPON_TYPE_SECONDARY)
                {
                    DisplayDistributorLoadoutMenu(g_Players[client].distributor.current_loadout_name, client, WEAPON_TYPE_PRIMARY);

                    g_Players[client].distributor.close_menu = false;
                }

                if (view & WEAPON_TYPE_PRIMARY)
                {
                    DisplayDistributorMenu(client);
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
        if (CS_WeaponIDToItemDefIndex(weapon_id) == GetEntProp(client, Prop_Send, "m_EquippedLoadoutItemDefIndices", .element = i))
        {
            return true;
        }
    }

    return false;
}