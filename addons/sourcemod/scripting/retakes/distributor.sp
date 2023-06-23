/*
 * • Responsible for distributing weapons to players.
 */

#assert defined COMPILING_FROM_MAIN

#define LOADOUT_TEAM_T   0
#define LOADOUT_TEAM_CT  1
#define LOADOUT_TEAM_MAX 2

#define WEAPON_TYPE_PRIMARY   (1 << 0)
#define WEAPON_TYPE_SECONDARY (1 << 1)
#define WEAPON_TYPE_UTILITY   (1 << 2)
#define WEAPON_TYPE_ITEM      (1 << 3)

#define LOADOUT_WEAPON_PRIMARY        0
#define LOADOUT_WEAPON_SECONDARY      1
#define LOADOUT_WEAPON_GRENADE        2
#define LOADOUT_WEAPON_GRENADE_OFFSET (LOADOUT_WEAPON_SECONDARY + 2)
#define LOADOUT_WEAPON_ITEM           3
#define LOADOUT_WEAPON_KNIFE          8
#define LOADOUT_WEAPON_MAX            9

#define LOADOUT_POSITION_RIFLE1     15
#define LOADOUT_POSITION_SECONDARY0 2
#define LOADOUT_POSITION_SECONDARY3 5
#define LOADOUT_POSITION_SECONDARY4 6
#define LOADOUT_POSITION_SMG1       9

#define MAX_SLOT_FIREGRENADE  0
#define MAX_SLOT_SMOKEGRENADE 1
#define MAX_SLOT_MAX          2

enum struct PlayerLoadout
{
    CSWeaponID primary_weapon_id[LOADOUT_TEAM_MAX];
    CSWeaponID secondary_weapon_id[LOADOUT_TEAM_MAX];
}

enum struct Item
{
    CSWeaponID id;

    char classname[32];

    int slot_index;
}

enum struct LoadoutItem
{
    Item item;

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

    void Initialize(const char[] name)
    {
        strcopy(this.name, sizeof(Loadout::name), name);

        for (int i; i < LOADOUT_TEAM_MAX; i++)
        {
            this.items[i] = new ArrayList(sizeof(LoadoutItem));
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

ArrayList g_Items;
ArrayList g_Loadouts;
float     g_GracePeriod;
int       g_LineCount = -1;
int       g_SMCParserDepth;
int       g_SMCParserCount;
int       g_CurrentLoadoutTeam;
ConVar    ammo_grenade_limit_total;
char      g_CurrentLoadout[sizeof(Loadout::name)];
char      g_CurrentWeaponClassName[sizeof(Item::classname)];

void Distributor_OnConfigsExecuted()
{
    // Don't cache if we already got our data.
    if (g_Loadouts)
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
        SetFailState("Unable to find \"data/retakes/distributor.cfg\" file");

        return;
    }

    g_Loadouts = new ArrayList(sizeof(Loadout));
    g_Items    = new ArrayList(sizeof(Item));

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

        SetFailState("%s", buffer);

        delete parser;

        return;
    }

    delete parser;
}

public void Distributor_OnPluginStart()
{
}

public void PTaH_OnInventoryUpdatePost(int client, CCSPlayerInventory inventory)
{
    g_Players[client].distributor.inventory = inventory;
}

void Distributor_OnDatabaseConnection()
{
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
        LogError("There was an error creating the distributor loadout table! (%s)", error);

        return;
    }
}

void Distributor_OnClientPutInServer(int client)
{
    Loadout loadout;

    for (int current_loadouts = g_Loadouts.Length - 1; current_loadouts >= 0; current_loadouts--)
    {
        if (!g_Loadouts.GetArray(current_loadouts, loadout, sizeof(loadout)))
        {
            continue;
        }

        PlayerLoadout player_loadout;

        for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
        {
            player_loadout.primary_weapon_id[current_team]   = CSWeapon_NONE;
            player_loadout.secondary_weapon_id[current_team] = CSWeapon_NONE;
        }

        g_Players[client].distributor.weapons_map.SetArray(loadout.name, player_loadout, sizeof(player_loadout));
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

void Distributor_OnPlayerConnectFull(int client)
{
    if (IsFakeClient(client))
    {
        return;
    }

    CCSPlayerInventory inventory = PTaH_GetPlayerInventory(client);

    if (inventory == CCSPlayerInventory_NULL)
    {
        LogError("There was an error getting a players inventory pointer! (%d)", client);

        return;
    }

    g_Players[client].distributor.inventory = inventory;
}

void Distributor_OnClientDisconnect(int client)
{
    if (IsFakeClient(client))
    {
        return;
    }

    char query[256];
    char table_name[32];
    char loadout_name[sizeof(Loadout::name)];

    PlayerLoadout player_loadout;

    Transaction transaction = new Transaction();

    StringMapSnapshot loadout_snapshot = g_Players[client].distributor.weapons_map.Snapshot();

    retakes_database_table_distributor.GetString(table_name, sizeof(table_name));

    for (int i = loadout_snapshot.Length - 1; i >= 0; i--)
    {
        loadout_snapshot.GetKey(i, loadout_name, sizeof(loadout_name));

        if (!g_Players[client].distributor.weapons_map.GetArray(loadout_name, player_loadout, sizeof(player_loadout)))
        {
            continue;
        }

        FormatEx(query, sizeof(query), "INSERT INTO `%s_players` VALUES (%d, '%s', %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `loadout_name` = '%s', `primary_wep_id_t` = %d, `primary_wep_id_ct` = %d, `secondary_wep_id_t` = %d, `secondary_wep_id_ct` = %d;",
                 table_name,
                 g_Players[client].account_id,
                 loadout_name,
                 player_loadout.primary_weapon_id[LOADOUT_TEAM_T],
                 player_loadout.primary_weapon_id[LOADOUT_TEAM_CT],
                 player_loadout.secondary_weapon_id[LOADOUT_TEAM_T],
                 player_loadout.secondary_weapon_id[LOADOUT_TEAM_CT],
                 loadout_name,
                 player_loadout.primary_weapon_id[LOADOUT_TEAM_T],
                 player_loadout.primary_weapon_id[LOADOUT_TEAM_CT],
                 player_loadout.secondary_weapon_id[LOADOUT_TEAM_T],
                 player_loadout.secondary_weapon_id[LOADOUT_TEAM_CT]);

        transaction.AddQuery(query);
    }

    delete loadout_snapshot;

#if defined DEBUG
    g_Database.Execute(transaction, SQL_OnClientInfoSaved, SQL_OnClientInfoSavedError, .priority = DBPrio_Normal);
#else
    g_Database.Execute(transaction, .onError = SQL_OnClientInfoSavedError, .priority = DBPrio_Normal);
#endif
}

#if defined DEBUG
void SQL_OnClientInfoSaved(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
    LogMessage("Player loadout data transaction completed successfully. (%d queries)", numQueries);
}
#endif

void SQL_OnClientInfoSavedError(Database database, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    if (!database || error[0])
    {
        LogError("There was an error saving player loadout data! (%s)", error);

        return;
    }
}

void SQL_OnClientInfoFetched(Database database, DBResultSet results, const char[] error, int userid)
{
    if (error[0])
    {
        LogError("There was an error fetching player loadout data! (%s)", error);

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

    PlayerLoadout player_loadout;
    char          buffer[sizeof(Loadout::name)];

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
        Loadout loadout;

        loadout.Initialize(name);

        g_Loadouts.PushArray(loadout, sizeof(loadout));
    }

    else if (g_SMCParserDepth == 3 && g_SMCParserCount == 1)
    {
        if (!strcmp(name, "Counter Terrorist"))
        {
            g_CurrentLoadoutTeam = LOADOUT_TEAM_CT;
        }

        else if (!strcmp(name, "Terrorist"))
        {
            g_CurrentLoadoutTeam = LOADOUT_TEAM_T;
        }

        else
        {
            g_CurrentLoadoutTeam = -1;
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
        static LoadoutItem loadout_item;

        if (StrContains(key, "weapon") != -1 || !strcmp(key, "utility") || !strcmp(key, "item"))
        {
            int flags;

            int slot_index = -1;

            char buffer[32];

            FormatEx(buffer, sizeof(buffer), "weapon_%s", value);

            CSWeaponID weapon_id = CS_AliasToWeaponID(buffer);

            if (!weapon_id && strcmp(key, "item"))
            {
                return SMCParse_Continue;
            }

            loadout_item.item.id = weapon_id;

            strcopy(loadout_item.item.classname, sizeof(Item::classname), buffer);

            if (!strncmp(key, "primary_weapon", 9))
            {
                flags |= WEAPON_TYPE_PRIMARY;

                slot_index = CS_SLOT_PRIMARY;
            }

            if (!strncmp(key, "secondary_weapon", 9))
            {
                flags |= WEAPON_TYPE_SECONDARY;

                slot_index = CS_SLOT_SECONDARY;
            }

            if (!strncmp(key, "utility", 7))
            {
                flags |= WEAPON_TYPE_UTILITY;

                slot_index = CS_SLOT_GRENADE;
            }

            if (!strncmp(key, "item", 4))
            {
                flags |= WEAPON_TYPE_ITEM;

                FormatEx(loadout_item.item.classname, sizeof(Item::classname), "item_%s", value);
            }

            loadout_item.item.slot_index = slot_index;

            loadout_item.flags = flags;

            Loadout loadout;

            g_Loadouts.GetArray(g_Loadouts.Length - 1, loadout, sizeof(loadout));

            switch (g_CurrentLoadoutTeam)
            {
                case LOADOUT_TEAM_CT: loadout.items[LOADOUT_TEAM_CT].PushArray(loadout_item, sizeof(loadout_item));
                case LOADOUT_TEAM_T: loadout.items[LOADOUT_TEAM_T].PushArray(loadout_item, sizeof(loadout_item));
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

        Loadout loadout;

        LoadoutItem loadout_item;

        FormatEx(buffer, sizeof(buffer), "weapon_%s", g_CurrentWeaponClassName);

        for (int i; i < g_Loadouts.Length; i++)
        {
            if (!g_Loadouts.GetArray(i, loadout, sizeof(loadout)))
            {
                continue;
            }

            for (int j; j < LOADOUT_TEAM_MAX; j++)
            {
                for (int k; k < loadout.items[j].Length; k++)
                {
                    if (!loadout.items[j].GetArray(k, loadout_item, sizeof(loadout_item)))
                    {
                        continue;
                    }

                    if (!strcmp(buffer, loadout_item.item.classname))
                    {
                        if (!strcmp(key, "chance"))
                        {
                            loadout_item.chance = StringToFloat(value);
                        }

                        if (!strcmp(key, "max"))
                        {
                            loadout_item.max = StringToInt(value);
                        }

                        loadout.items[j].SetArray(k, loadout_item, sizeof(loadout_item));
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
        SetFailState("There was a fatal error parsing the distributor config file at line %d", g_LineCount);

        return;
    }

    bool fail_state;

    Item        item;
    Loadout     loadout;
    LoadoutItem loadout_item;

    for (int current_item = g_Items.Length - 1; current_item >= 0; current_item--)
    {
        if (!g_Items.GetArray(current_item, item, sizeof(item)))
        {
            continue;
        }

        if (!TranslationPhraseExists(item.classname))
        {
            fail_state = true;

            LogError("Translation key \"%s\" for weapon not found!", item.classname);
        }
    }

    for (int item_count[LOADOUT_TEAM_MAX][LOADOUT_WEAPON_MAX], current_loadout = g_Loadouts.Length - 1; current_loadout >= 0; current_loadout--)
    {
        if (!g_Loadouts.GetArray(current_loadout, loadout, sizeof(loadout)))
        {
            continue;
        }

        if (!TranslationPhraseExists(loadout.name))
        {
            fail_state = true;

            LogError("Translation key \"%s\" for loadout not found!", loadout.name);
        }

        for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
        {
            for (int current_item = loadout.items[current_team].Length - 1; current_item >= 0; current_item--)
            {
                if (!loadout.items[current_team].GetArray(current_item, loadout_item, sizeof(loadout_item)))
                {
                    continue;
                }

                g_Items.PushArray(loadout_item.item, sizeof(loadout_item.item));

                if (loadout_item.flags & WEAPON_TYPE_PRIMARY)
                {
                    item_count[current_team][LOADOUT_WEAPON_PRIMARY]++;
                }

                else if (loadout_item.flags & WEAPON_TYPE_SECONDARY)
                {
                    item_count[current_team][LOADOUT_WEAPON_SECONDARY]++;
                }
            }
        }

        for (int i; i < LOADOUT_TEAM_MAX; i++)
        {
            loadout.item_primary_count[i]   = item_count[i][LOADOUT_WEAPON_PRIMARY];
            loadout.item_secondary_count[i] = item_count[i][LOADOUT_WEAPON_SECONDARY];
        }

        g_Loadouts.SetArray(current_loadout, loadout, sizeof(loadout));
    }

    if (fail_state)
    {
        SetFailState("There are translation keys missing for the distributor part of this retakes plugin!");
    }
}

void Distributor_OnRoundPreStart()
{
    Loadout       loadout;
    LoadoutItem   loadout_item;
    PlayerLoadout player_loadout;

    float chance;
    int   maximum;
    int   weapon_id_max[CSWeapon_MAX_WEAPONS];

    static ArrayList filtered_items[LOADOUT_TEAM_MAX][LOADOUT_WEAPON_MAX - LOADOUT_WEAPON_GRENADE_OFFSET];

    for (int i = LOADOUT_TEAM_MAX - 1; i >= 0; i--)
    {
        for (int j = LOADOUT_WEAPON_MAX - LOADOUT_WEAPON_GRENADE_OFFSET - 1; j >= 0; j--)
        {
            if (!filtered_items[i][j])
            {
                filtered_items[i][j] = new ArrayList();
            }
        }
    }

    g_Loadouts.GetArray(GetURandomInt() % g_Loadouts.Length, loadout, sizeof(loadout));

    strcopy(g_CurrentLoadout, sizeof(g_CurrentLoadout), loadout.name);

    for (int i = LOADOUT_TEAM_MAX - 1; i >= 0; i--)
    {
        for (int j = loadout.items[i].Length - 1; j >= 0; j--)
        {
            if (!loadout.items[i].GetArray(j, loadout_item, sizeof(loadout_item)))
            {
                continue;
            }

            switch (loadout_item.flags)
            {
                case WEAPON_TYPE_PRIMARY: filtered_items[i][LOADOUT_WEAPON_PRIMARY].Push(j);
                case WEAPON_TYPE_SECONDARY: filtered_items[i][LOADOUT_WEAPON_SECONDARY].Push(j);
                case WEAPON_TYPE_UTILITY: filtered_items[i][LOADOUT_WEAPON_GRENADE].Push(j);
                case WEAPON_TYPE_ITEM: filtered_items[i][LOADOUT_WEAPON_ITEM].Push(j);
            }
        }
    }

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
            if (g_Players[current_client].distributor.weapons_map.GetArray(loadout.name, player_loadout, sizeof(player_loadout)))
            {
                CSWeaponID primary_weapon_id = player_loadout.primary_weapon_id[current_team];

                CSWeaponID secondary_weapon_id = player_loadout.secondary_weapon_id[current_team];

                if (primary_weapon_id > CSWeapon_NONE)
                {
                    if (loadout.items[current_team].GetArray(loadout.items[current_team].FindValue(primary_weapon_id), loadout_item, sizeof(loadout_item)))
                    {
                        if (loadout_item.max)
                        {
                            if (weapon_id_max[primary_weapon_id] < loadout_item.max)
                            {
                                g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_PRIMARY] = primary_weapon_id;

                                weapon_id_max[primary_weapon_id]++;
                            }

                            else
                            {
                                g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_PRIMARY] = CSWeapon_NONE;
                            }
                        }

                        else
                        {
                            g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_PRIMARY] = primary_weapon_id;
                        }
                    }
                }

                if (secondary_weapon_id > CSWeapon_NONE)
                {
                    if (loadout.items[current_team].GetArray(loadout.items[current_team].FindValue(secondary_weapon_id), loadout_item, sizeof(loadout_item)))
                    {
                        if (loadout_item.max)
                        {
                            if (weapon_id_max[secondary_weapon_id] < loadout_item.max)
                            {
                                g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_SECONDARY] = secondary_weapon_id;

                                weapon_id_max[secondary_weapon_id]++;
                            }

                            else
                            {
                                g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_SECONDARY] = CSWeapon_NONE;
                            }
                        }

                        else
                        {
                            g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_SECONDARY] = secondary_weapon_id;
                        }
                    }
                }
            }
        }

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
                    filtered_items[current_team][current_loadout].Sort(Sort_Random, Sort_Integer);

                    for (int current_weapon = filtered_items[current_team][current_loadout].Length - 1; current_weapon >= 0; current_weapon--)
                    {
                        if (!loadout.items[current_team].GetArray(filtered_items[current_team][current_loadout].Get(current_weapon), loadout_item, sizeof(loadout_item)))
                        {
                            continue;
                        }

                        maximum = loadout_item.max ? loadout_item.max : -1;

                        if (maximum != -1 && weapon_id_max[loadout_item.item.id] >= maximum)
                        {
                            continue;
                        }

                        chance = loadout_item.chance ? loadout_item.chance : 1.0;

                        if (current_weapon == filtered_items[current_team][current_loadout].Length || GetURandomFloat() < chance)
                        {
                            g_Players[current_client].distributor.weapons_id[current_loadout] = loadout_item.item.id;

                            weapon_id_max[loadout_item.item.id]++;

                            break;
                        }
                    }
                }

                case LOADOUT_WEAPON_GRENADE:
                {
                    filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Sort(Sort_Random, Sort_Integer);

                    for (int nade_output, nade_slot_max[MAX_SLOT_MAX], current_nade = filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Length - 1; current_nade >= 0; current_nade--)
                    {
                        if (!loadout.items[current_team].GetArray(filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Get(current_nade), loadout_item, sizeof(loadout_item)) || nade_output > 4)
                        {
                            continue;
                        }

                        if (!strcmp(loadout_item.item.classname, "weapon_incgrenade") || !strcmp(loadout_item.item.classname, "weapon_molotov") && nade_slot_max[MAX_SLOT_FIREGRENADE] >= 1)
                        {
                            nade_slot_max[MAX_SLOT_FIREGRENADE]++;
                        }

                        else if (!strcmp(loadout_item.item.classname, "weapon_smokegrenade") && nade_slot_max[MAX_SLOT_SMOKEGRENADE] >= 1)
                        {
                            nade_slot_max[MAX_SLOT_SMOKEGRENADE]++;
                        }

                        maximum = loadout_item.max ? loadout_item.max : -1;

                        if (maximum != -1 && weapon_id_max[loadout_item.item.id] >= maximum)
                        {
                            continue;
                        }

                        chance = loadout_item.chance ? loadout_item.chance : 1.0;

                        if (GetURandomFloat() < chance)
                        {
                            nade_output++;

                            weapon_id_max[loadout_item.item.id]++;

                            g_Players[current_client].distributor.weapons_id[nade_output + LOADOUT_WEAPON_GRENADE_OFFSET] = loadout_item.item.id;
                        }
                    }
                }

                case LOADOUT_WEAPON_ITEM:
                {
                    filtered_items[current_team][LOADOUT_WEAPON_ITEM].Sort(Sort_Random, Sort_Integer);

                    for (int current_item = filtered_items[current_team][LOADOUT_WEAPON_ITEM].Length - 1; current_item >= 0; current_item--)
                    {
                        if (!loadout.items[current_team].GetArray(filtered_items[current_team][LOADOUT_WEAPON_ITEM].Get(current_item), loadout_item, sizeof(loadout_item)))
                        {
                            continue;
                        }

                        chance = loadout_item.chance ? loadout_item.chance : 1.0;

                        if (GetURandomFloat() < chance)
                        {
                            if (current_team == LOADOUT_TEAM_CT && !strcmp(loadout_item.item.classname, "item_kit"))
                            {
                                g_Players[current_client].distributor.kit = true;
                            }

                            if (!strcmp(loadout_item.item.classname, "item_kevlar"))
                            {
                                g_Players[current_client].distributor.kevlar = true;
                            }

                            else if (!strcmp(loadout_item.item.classname, "item_assultsuit"))
                            {
                                g_Players[current_client].distributor.assult_suit = true;
                            }
                        }
                    }
                }
            }
        }
    }

    for (int i = LOADOUT_TEAM_MAX - 1; i >= 0; i--)
    {
        for (int j = LOADOUT_WEAPON_MAX - LOADOUT_WEAPON_GRENADE_OFFSET - 1; j >= 0; j--)
        {
            filtered_items[i][j].Clear();
        }
    }
}

void Distributor_OnRoundStart()
{
    g_GracePeriod = GetGameTime();
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
    if (GetPlanter() == client)
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

    CSWeaponID weapon_id;

    Loadout loadout;

    LoadoutItem loadout_item;

    g_Players[client].distributor.current_loadout_view = view;

    int team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

    Menu menu = new Menu(Handler_DistributorLoadoutMenu);

    FormatEx(buffer, sizeof(buffer), "%T%T %T:\n\n%T\n ", "MenuPrefix", client, loadout_name, client, view & WEAPON_TYPE_PRIMARY ? "Primary Weapon" : "Secondary Weapon", client, team == LOADOUT_TEAM_CT ? "Team CT" : "Team T", client);

    menu.SetTitle(buffer);

    for (int current_loadout = g_Loadouts.Length - 1; current_loadout >= 0; current_loadout--)
    {
        if (!g_Loadouts.GetArray(current_loadout, loadout, sizeof(loadout)))
        {
            continue;
        }

        if (strcmp(loadout.name, loadout_name))
        {
            continue;
        }

        for (int current_item = loadout.items[team].Length - 1; current_item >= 0; current_item--)
        {
            if (!loadout.items[team].GetArray(current_item, loadout_item, sizeof(loadout_item)))
            {
                continue;
            }

            if (loadout_item.flags ^ view)
            {
                continue;
            }

            if (!retakes_distributor_force_weapon.BoolValue)
            {
                weapon_id = GetEquippedInventoryItemByID(client, team + LOADOUT_TEAM_MAX, loadout_item.item.id);

                if (weapon_id != loadout_item.item.id)
                {
                    CS_WeaponIDToAlias(weapon_id, buffer, sizeof(buffer));

                    FormatEx(loadout_item.item.classname, sizeof(Item::classname), "weapon_%s", buffer);
                }
            }

            FormatEx(buffer, sizeof(buffer), "%T", loadout_item.item.classname, client);
            menu.AddItem(loadout_item.item.classname, buffer);
        }
    }

    if (menu.ItemCount <= 0)
    {
        if ((view & WEAPON_TYPE_PRIMARY ? loadout.item_primary_count[team] : loadout.item_primary_count[team]) > 0)
        {
            // If there are items, but the menu is not supposed to be closed,
            // recursively open the loadout menu with the opposite view type.
            if (!g_Players[client].distributor.close_menu)
            {
                DisplayDistributorLoadoutMenu(g_Players[client].distributor.current_loadout_name, client, view & WEAPON_TYPE_PRIMARY ? WEAPON_TYPE_SECONDARY : WEAPON_TYPE_PRIMARY);
            }
        }

        // Set the close_menu flag to true, indicating that the menu should be closed
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

            CSWeaponID weapon_id = CS_AliasToWeaponID(buffer);

            if (g_GracePeriod > GetGameTime() - retakes_distributor_grace_period.FloatValue)
            {
                if (!strcmp(g_Players[client].distributor.current_loadout_name, g_CurrentLoadout))
                {
                    DisarmClient(client, GetWeaponSlotIndexByCSWeaponID(weapon_id));

                    int weapon = GivePlayerItem(client, buffer);

                    if (weapon != -1)
                    {
                        EquipPlayerWeapon(client, weapon);
                    }
                }
            }

            PlayerLoadout player_loadout;
            char          loadout_name[48];
            int           view = g_Players[client].distributor.current_loadout_view;
            int           team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

            strcopy(loadout_name, sizeof(loadout_name), g_Players[client].distributor.current_loadout_name);

            if (g_Players[client].distributor.weapons_map.GetArray(loadout_name, player_loadout, sizeof(player_loadout)))
            {
                if (view & WEAPON_TYPE_PRIMARY)
                {
                    player_loadout.primary_weapon_id[team] = weapon_id;
                }

                else if (view & WEAPON_TYPE_SECONDARY)
                {
                    player_loadout.secondary_weapon_id[team] = weapon_id;
                }

                g_Players[client].distributor.weapons_map.SetArray(loadout_name, player_loadout, sizeof(player_loadout));
            }

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

                // Check if the current view is WEAPON_TYPE_SECONDARY and the menu should be closed
                if (view & WEAPON_TYPE_SECONDARY && g_Players[client].distributor.close_menu)
                {
                    // If the menu is supposed to be closed, return to the main distributor menu
                    DisplayDistributorMenu(client);
                }

                if (view & WEAPON_TYPE_SECONDARY)
                {
                    // Return to the primary loadout menu
                    DisplayDistributorLoadoutMenu(g_Players[client].distributor.current_loadout_name, client, WEAPON_TYPE_PRIMARY);

                    // Reset the close_menu flag to false, indicating that the menu should not be closed
                    g_Players[client].distributor.close_menu = false;
                }

                if (view & WEAPON_TYPE_PRIMARY)
                {
                    // Return to the main distributor menu
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

int GetWeaponSlotIndexByCSWeaponID(CSWeaponID weapon_id)
{
    Item item;

    for (int i; i < g_Items.Length; i++)
    {
        g_Items.GetArray(i, item, sizeof(item));

        if (item.id == weapon_id)
        {
            return item.slot_index;
        }
    }

    return -1;
}

CSWeaponID GetEquippedInventoryItemByID(int client, int team, CSWeaponID weapon_id)
{
    if (!g_Players[client].distributor.inventory)
    {
        return CSWeapon_NONE;
    }

    int weapon_definition_index;

    CEconItemView       item_view;
    CEconItemDefinition item_definition;

    switch (weapon_id)
    {
        case CSWeapon_M4A1, CSWeapon_M4A1_SILENCER: item_view = g_Players[client].distributor.inventory.GetItemInLoadout(CS_TEAM_CT, LOADOUT_POSITION_RIFLE1);
        case CSWeapon_USP_SILENCER, CSWeapon_HKP2000: item_view = g_Players[client].distributor.inventory.GetItemInLoadout(CS_TEAM_CT, LOADOUT_POSITION_SECONDARY0);

        case CSWeapon_TEC9, CSWeapon_FIVESEVEN, CSWeapon_CZ75A:
        {
            if (weapon_id == CSWeapon_TEC9)
            {
                team = CS_TEAM_T;
            }

            else if (weapon_id == CSWeapon_FIVESEVEN)
            {
                team = CS_TEAM_CT;
            }

            else
            {
                team = GetClientTeam(client);

                if (team <= CS_TEAM_SPECTATOR)
                {
                    team = CS_TEAM_CT;
                }
            }

            item_view = g_Players[client].distributor.inventory.GetItemInLoadout(team, LOADOUT_POSITION_SECONDARY3);
        }

        case CSWeapon_DEAGLE, CSWeapon_REVOLVER: item_view = g_Players[client].distributor.inventory.GetItemInLoadout(team, LOADOUT_POSITION_SECONDARY4);
        case CSWeapon_MP7, CSWeapon_MP5NAVY: item_view = g_Players[client].distributor.inventory.GetItemInLoadout(team, LOADOUT_POSITION_SMG1);

        default: return weapon_id;
    }

    if (!item_view)
    {
        return CSWeapon_NONE;
    }

    item_definition = item_view.GetItemDefinition();

    if (!item_definition)
    {
        return CSWeapon_NONE;
    }

    weapon_definition_index = item_definition.GetDefinitionIndex();

    // Return the weapon ID based on whether it matches the specified weapon ID or the other weapon ID
    return weapon_definition_index == CS_WeaponIDToItemDefIndex(weapon_id) ? weapon_id : CS_ItemDefIndexToID(weapon_definition_index);
}