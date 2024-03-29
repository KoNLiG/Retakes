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
#define LOADOUT_WEAPON_GRENADE_OFFSET LOADOUT_WEAPON_ITEM
#define LOADOUT_WEAPON_ITEM           3
#define LOADOUT_WEAPON_KNIFE          8
#define LOADOUT_WEAPON_MAX            9

#define LOADOUT_POSITION_RIFLE1     15
#define LOADOUT_POSITION_SECONDARY0 2
#define LOADOUT_POSITION_SECONDARY3 5
#define LOADOUT_POSITION_SECONDARY4 6
#define LOADOUT_POSITION_SMG1       9

enum struct PlayerLoadout
{
    CSWeaponID primary_weapon_id[LOADOUT_TEAM_MAX];
    CSWeaponID secondary_weapon_id[LOADOUT_TEAM_MAX];
}

enum struct LoadoutItem
{
    CSWeaponID id;

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

    void Initialize(const char[] name)
    {
        strcopy(this.name, sizeof(this.name), name);

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

enum struct Round
{
    int  round_num;
    char loadout_name[sizeof(Loadout::name)];
}

ArrayList g_Rounds;
ArrayList g_Loadouts;
float     g_GracePeriod;
int       g_LineCount;
int       g_SMCParserDepth;
int       g_SMCParserCount;
int       g_CurrentLoadoutTeam;
ConVar    ammo_grenade_limit_total;
char      g_CurrentLoadout[sizeof(Loadout::name)];
char      g_CurrentWeaponClassName[sizeof(LoadoutItem::classname)];

void Distributor_OnConfigsExecuted(bool reload = false)
{
    // Don't cache if we already got our data.
    if (g_Loadouts && !reload)
    {
        return;
    }

    ammo_grenade_limit_total          = FindConVar("ammo_grenade_limit_total");
    ammo_grenade_limit_total.IntValue = retakes_distributor_ammo_limit.IntValue;

    bool file_exists;

    char buffer[PLATFORM_MAX_PATH];

    BuildPath(Path_SM, buffer, sizeof(buffer), "data/retakes/retakes.cfg");

    file_exists = FileExists(buffer);

    if (!file_exists)
    {
        SetFailState("Failed to find file '%s'. Make sure the file is located in the correct directory", buffer);

        return;
    }

    g_LineCount = -1;
    g_SMCParserCount = 0;
    g_SMCParserDepth = 0;
    g_CurrentLoadoutTeam = -1;
    g_CurrentLoadout[0] = '\0';
    g_CurrentWeaponClassName[0] = '\0';

    g_Rounds   = new ArrayList(sizeof(Round));
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

        SetFailState("An error occurred while loading the Retakes configuration file. %s", buffer);

        delete parser;

        return;
    }

    delete parser;
}

public void Distributor_OnPluginStart()
{
    RegAdminCmd("sm_distributor_reload", Command_DistributorReload, ADMFLAG_CHEATS, "Reloads the distributor configuration file.");
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
        char database_name[32];

        retakes_database_entry.GetString(database_name, sizeof(database_name));

        LogError("Failed to create distributor loadout table in database '%s'", database_name);

        return;
    }
}

void Distributor_OnClientPutInServer(int client)
{
    Loadout loadout;

    for (int current_loadouts; current_loadouts < g_Loadouts.Length; current_loadouts++)
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
        LogError("Failed to get inventory pointer for player index %d. The pointer is null", client);

        return;
    }

    g_Players[client].distributor.inventory = inventory;
}

void Distributor_OnClientDisconnect(int client)
{
    if (IsFakeClient(client) || !g_Players[client].distributor.weapons_map)
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

    for (int i; i < loadout_snapshot.Length; i++)
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
void        SQL_OnClientInfoSaved(Database db, any data, int num_queries, Handle[] results, any[] query_data)
{
    char database_name[32];

    retakes_database_entry.GetString(database_name, sizeof(database_name));

    LogMessage("Successfully saved player loadout data to database '%s'. %d queries were executed", database_name, num_queries);
}
#endif

void SQL_OnClientInfoSavedError(Database database, any data, int num_queries, const char[] error, int fail_index, any[] query_data)
{
    if (!database || error[0])
    {
        char database_name[32];

        retakes_database_entry.GetString(database_name, sizeof(database_name));

        LogError("Failed to save player loadout data to database '%s'. %s", database_name, error);

        return;
    }
}

void SQL_OnClientInfoFetched(Database database, DBResultSet results, const char[] error, int userid)
{
    if (!database || error[0])
    {
        char database_name[32];

        retakes_database_entry.GetString(database_name, sizeof(database_name));

        LogError("Failed to fetch player loadout data from database '%s'. %s", database_name, error);

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
    if (!g_Loadouts.Length)
    {
        PrintToChat(client, "%t", "Retakes Loadouts Are Unavailable");

        return Plugin_Handled;
    }

    DisplayDistributorMenu(client);

    return Plugin_Handled;
}

public Action Command_DistributorReload(int client, int args)
{
    Distributor_OnConfigsExecuted(true);

    return Plugin_Handled;
}

public Action CS_OnTerminateRound(float& delay, CSRoundEndReason& reason)
{
    if (reason == CSRoundEnd_GameStart)
    {

    }

    return Plugin_Continue;
}

void SMCParser_OnStart(SMCParser parser)
{
#if defined DEBUG
    LogMessage("Retakes - Configuration file loading initiated");
#endif
}

SMCResult SMCParser_OnEnterSection(SMCParser parser, const char[] name, bool opt_quotes)
{
#if defined DEBUG
    LogMessage("SMCParser - Entered section '%s' for parsing", name);
#endif

    if (g_SMCParserDepth == 1)
    {
        g_SMCParserCount++;
    }

    if (g_SMCParserDepth == 2 && g_SMCParserCount == 2)
    {
        Loadout loadout;

        loadout.Initialize(name);

        g_Loadouts.PushArray(loadout, sizeof(loadout));
    }

    else if (g_SMCParserDepth == 3 && g_SMCParserCount == 2)
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

    if (g_SMCParserDepth == 2 && g_SMCParserCount == 4)
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
    LogMessage("SMCParser - Processing key '%s' with value '%s'", key, value);
#endif

    if (g_SMCParserDepth == 2 && g_SMCParserCount == 1)
    {
        static Round round;

        round.round_num = IsStringNumeric(key) ? StringToInt(key) : -1;
        strcopy(round.loadout_name, sizeof(Round::loadout_name), value);

        if (round.round_num >= 0 && strlen(round.loadout_name))
        {
            g_Rounds.PushArray(round, sizeof(round));
        }
    }

    else if (g_SMCParserDepth == 4 && g_SMCParserCount == 2)
    {
        static LoadoutItem loadout_item;

        if (StrContains(key, "Weapon") != -1 || !strcmp(key, "Utility") || !strcmp(key, "Item"))
        {
            if (g_CurrentLoadoutTeam == -1)
            {
                return SMCParse_HaltFail;
            }

            int flags;

            char buffer[32];

            FormatEx(buffer, sizeof(buffer), "weapon_%s", value);

            CSWeaponID weapon_id = CS_AliasToWeaponID(buffer);

            if (!weapon_id && strcmp(key, "Item"))
            {
                return SMCParse_Continue;
            }

            strcopy(loadout_item.classname, sizeof(LoadoutItem::classname), buffer);

            if (!strncmp(key, "Primary Weapon", 9))
            {
                flags |= WEAPON_TYPE_PRIMARY;
            }

            if (!strncmp(key, "Secondary Weapon", 9))
            {
                flags |= WEAPON_TYPE_SECONDARY;
            }

            if (!strncmp(key, "Utility", 7))
            {
                flags |= WEAPON_TYPE_UTILITY;
            }

            if (!strncmp(key, "Item", 4))
            {
                flags |= WEAPON_TYPE_ITEM;

                if (!strcmp(value, "kit"))
                {
                    weapon_id = CSWeapon_DEFUSER;
                }

                else if (!strcmp(value, "kevlar"))
                {
                    weapon_id = CSWeapon_KEVLAR;
                }

                else if (!strcmp(value, "assaultsuit"))
                {
                    weapon_id = CSWeapon_ASSAULTSUIT;
                }

                FormatEx(loadout_item.classname, sizeof(LoadoutItem::classname), "item_%s", value);
            }

            loadout_item.id = weapon_id;

            loadout_item.flags = flags;

            Loadout loadout;

            g_Loadouts.GetArray(g_Loadouts.Length - 1, loadout, sizeof(loadout));

            loadout.items[g_CurrentLoadoutTeam].PushArray(loadout_item, sizeof(loadout_item));
        }
    }

    else if (g_SMCParserDepth == 2 && g_SMCParserCount == 3)
    {
        if (!strcmp(key, "Loadout Commands"))
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

    else if (g_SMCParserDepth == 3 && g_SMCParserCount == 4)
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

                    if (!strcmp(buffer, loadout_item.classname))
                    {
                        if (!strcmp(key, "chance"))
                        {
                            loadout_item.chance = StringToFloat(value);
                        }

                        if (!strcmp(key, "max_amount"))
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
    LogMessage("SMCParser - Parsing completed with %d loadouts processed", g_Loadouts.Length);
    LogMessage("Retakes - Configuration file loaded successfully");
#endif

    if (failed || halted)
    {
        SetFailState("There was a fatal error parsing the retakes config file at line %d", g_LineCount);

        return;
    }

    if (!g_Loadouts.Length)
    {
        SetFailState("There are no loadouts defined in the retakes config file");

        return;
    }

    bool fail_state;

    Loadout     loadout;
    LoadoutItem loadout_item;

    for (int item_failed[CSWeapon_MAX_WEAPONS], item_count[LOADOUT_TEAM_MAX][LOADOUT_WEAPON_MAX], current_loadout; current_loadout < g_Loadouts.Length; current_loadout++)
    {
        if (!g_Loadouts.GetArray(current_loadout, loadout, sizeof(loadout)))
        {
            continue;
        }

        if (!TranslationPhraseExists(loadout.name))
        {
            fail_state = true;

            LogError("Translation key \"%s\" for loadout not found", loadout.name);
        }

        for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
        {
            for (int current_item; current_item < g_Loadouts.Length; current_item++)
            {
                if (!loadout.items[current_team].GetArray(current_item, loadout_item, sizeof(loadout_item)))
                {
                    continue;
                }

                if (!TranslationPhraseExists(loadout_item.classname))
                {
                    fail_state = true;

                    if (!item_failed[loadout_item.id])
                    {
                        LogError("Translation key \"%s\" for weapon not found", loadout_item.classname);

                        item_failed[loadout_item.id]++;
                    }
                }

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
        SetFailState("There are missing translation keys for this retakes plugin. Make sure the translation files contain all the required keys");
    }
}

void Distributor_OnRoundPreStart()
{
    Loadout       loadout;
    LoadoutItem   loadout_item;
    PlayerLoadout player_loadout;

    float      chance;
    int        max_items;
    bool       maxed_out;
    CSWeaponID primary_weapon_id;
    CSWeaponID secondary_weapon_id;
    static int max_weapon_ids[CSWeapon_MAX_WEAPONS_NO_KNIFES];
    static int weapon_indices[LOADOUT_TEAM_MAX][LOADOUT_WEAPON_MAX][CSWeapon_MAX_WEAPONS_NO_KNIFES];

    static ArrayList filtered_items[LOADOUT_TEAM_MAX][LOADOUT_WEAPON_MAX - LOADOUT_WEAPON_GRENADE_OFFSET];

    for (int i; i < LOADOUT_TEAM_MAX; i++)
    {
        for (int j; j < LOADOUT_WEAPON_MAX - LOADOUT_WEAPON_GRENADE_OFFSET; j++)
        {
            if (!filtered_items[i][j])
            {
                filtered_items[i][j] = new ArrayList();
            }
        }
    }

    Round round;

    Loadout load_loadout;

    static char loadout_key[sizeof(Loadout::name)];

    int total_rounds_played = GameRules_GetProp("m_totalRoundsPlayed");

    for (int i; i < g_Rounds.Length; i++)
    {
        g_Rounds.GetArray(i, round, sizeof(round));

        if (round.round_num > total_rounds_played)
        {
            break;
        }

        if (round.round_num != total_rounds_played)
        {
            continue;
        }

        strcopy(loadout_key, sizeof(loadout_key), round.loadout_name);

        for (int j; j < g_Loadouts.Length; j++)
        {
            g_Loadouts.GetArray(j, load_loadout, sizeof(load_loadout));

            if (!strcmp(loadout_key, loadout.name))
            {
                break;
            }
        }
    }

    loadout = load_loadout;

    strcopy(g_CurrentLoadout, sizeof(g_CurrentLoadout), loadout.name);

    for (int current_team; current_team < LOADOUT_TEAM_MAX; current_team++)
    {
        for (int current_item; current_item < loadout.items[current_team].Length; current_item++)
        {
            loadout.items[current_team].GetArray(current_item, loadout_item, sizeof(loadout_item));

            for (int current_loadout; current_loadout < 4; current_loadout++)
            {
                if (loadout_item.flags & 1 << current_loadout)
                {
                    filtered_items[current_team][current_loadout].Push(current_item);

                    weapon_indices[current_team][current_loadout][loadout_item.id] = current_item;

                    break;
                }
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
                primary_weapon_id = player_loadout.primary_weapon_id[current_team];

                secondary_weapon_id = player_loadout.secondary_weapon_id[current_team];

                if (primary_weapon_id > CSWeapon_NONE)
                {
                    loadout.items[current_team].GetArray(weapon_indices[current_team][LOADOUT_WEAPON_PRIMARY][primary_weapon_id], loadout_item, sizeof(loadout_item));

                    maxed_out = loadout_item.max && max_weapon_ids[primary_weapon_id] < loadout_item.max;

                    if (maxed_out)
                    {
                        max_weapon_ids[primary_weapon_id]++;
                    }

                    g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_PRIMARY] = maxed_out ? CSWeapon_NONE : primary_weapon_id;
                }

                if (secondary_weapon_id > CSWeapon_NONE)
                {
                    loadout.items[current_team].GetArray(weapon_indices[current_team][LOADOUT_WEAPON_SECONDARY][secondary_weapon_id], loadout_item, sizeof(loadout_item));

                    maxed_out = loadout_item.max && max_weapon_ids[secondary_weapon_id] < loadout_item.max;

                    if (maxed_out)
                    {
                        max_weapon_ids[secondary_weapon_id]++;
                    }

                    g_Players[current_client].distributor.weapons_id[LOADOUT_WEAPON_SECONDARY] = maxed_out ? CSWeapon_NONE : secondary_weapon_id;
                }
            }
        }

        for (int current_loadout; current_loadout <= LOADOUT_WEAPON_ITEM; current_loadout++)
        {
            if (g_Players[current_client].distributor.weapons_id[current_loadout])
            {
                continue;
            }

            filtered_items[current_team][current_loadout].Sort(Sort_Random, Sort_Integer);

            switch (current_loadout)
            {
                case LOADOUT_WEAPON_PRIMARY, LOADOUT_WEAPON_SECONDARY:
                {
                    for (int current_weapon; current_weapon < filtered_items[current_team][current_loadout].Length; current_weapon++)
                    {
                        loadout.items[current_team].GetArray(filtered_items[current_team][current_loadout].Get(current_weapon), loadout_item, sizeof(loadout_item));

                        max_items = loadout_item.max ? loadout_item.max : -1;

                        if (max_items != -1 && max_weapon_ids[loadout_item.id] >= max_items)
                        {
                            continue;
                        }

                        chance = loadout_item.chance ? loadout_item.chance : 1.0;

                        if (GetURandomFloat() < chance || current_weapon == filtered_items[current_team][current_loadout].Length - 1)
                        {
                            g_Players[current_client].distributor.weapons_id[current_loadout] = loadout_item.id;

                            max_weapon_ids[loadout_item.id]++;

                            break;
                        }
                    }
                }

                case LOADOUT_WEAPON_GRENADE:
                {
                    for (int grenade_output, grenade_slot_max[CSWeapon_MAX_WEAPONS_NO_KNIFES], current_nade; current_nade < filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Length; current_nade++)
                    {
                        if (grenade_output > 4)
                        {
                            break;
                        }

                        loadout.items[current_team].GetArray(filtered_items[current_team][LOADOUT_WEAPON_GRENADE].Get(current_nade), loadout_item, sizeof(loadout_item));

                        max_items = loadout_item.max ? loadout_item.max : -1;

                        if (max_items != -1 && max_weapon_ids[loadout_item.id] >= max_items || grenade_slot_max[loadout_item.id] > 1)
                        {
                            continue;
                        }

                        chance = loadout_item.chance ? loadout_item.chance : 1.0;

                        if (GetURandomFloat() < chance)
                        {
                            grenade_output++;

                            if (loadout_item.id == CSWeapon_MOLOTOV || loadout_item.id == CSWeapon_INCGRENADE || loadout_item.id == CSWeapon_SMOKEGRENADE)
                            {
                                grenade_slot_max[loadout_item.id]++;
                            }

                            max_weapon_ids[loadout_item.id]++;

                            g_Players[current_client].distributor.weapons_id[grenade_output + LOADOUT_WEAPON_GRENADE_OFFSET] = loadout_item.id;
                        }
                    }
                }

                case LOADOUT_WEAPON_ITEM:
                {
                    for (int current_item; current_item < filtered_items[current_team][LOADOUT_WEAPON_ITEM].Length; current_item++)
                    {
                        loadout.items[current_team].GetArray(filtered_items[current_team][LOADOUT_WEAPON_ITEM].Get(current_item), loadout_item, sizeof(loadout_item));

                        chance = loadout_item.chance ? loadout_item.chance : 1.0;

                        if (GetURandomFloat() < chance)
                        {
                            switch (loadout_item.id)
                            {
                                case CSWeapon_DEFUSER: g_Players[current_client].distributor.kit = (current_team == LOADOUT_TEAM_CT);
                                case CSWeapon_KEVLAR: g_Players[current_client].distributor.kevlar = true;
                                case CSWeapon_ASSAULTSUIT: g_Players[current_client].distributor.assult_suit = true;
                            }
                        }
                    }
                }
            }
        }
    }

    for (int i; i < LOADOUT_TEAM_MAX; i++)
    {
        for (int j; j < LOADOUT_WEAPON_MAX - LOADOUT_WEAPON_GRENADE_OFFSET; j++)
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
        Frame_DistributeLoadout(g_Players[planter].user_id);
    }
}

void Distributor_OnPlayerSpawn(int client)
{
    if (!IsRoundInProgress() || GetPlanter() == client)
    {
        return;
    }

    RequestFrame(Frame_DistributeLoadout, g_Players[client].user_id);
}

void Frame_DistributeLoadout(int userid)
{
    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    char classname[32];

    for (int weapon, current_loadout; current_loadout < LOADOUT_WEAPON_MAX; current_loadout++)
    {
        if (g_Players[client].distributor.weapons_id[current_loadout] == CSWeapon_NONE || current_loadout == LOADOUT_WEAPON_GRENADE || current_loadout == LOADOUT_WEAPON_ITEM)
        {
            continue;
        }

        CS_WeaponIDToAlias(g_Players[client].distributor.weapons_id[current_loadout], classname, sizeof(classname));
        Format(classname, sizeof(classname), "weapon_%s", classname);

        weapon = GivePlayerItem(client, classname);

        if (current_loadout <= LOADOUT_WEAPON_KNIFE && weapon != -1)
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

    FormatEx(buffer, sizeof(buffer), "%T%T:\n ", "Menu Prefix", client, "Distributor", client);

    menu.SetTitle(buffer);

    for (int i; i < g_Loadouts.Length; i++)
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

            strcopy(g_Players[client].distributor.loadout_key, sizeof(Distributor::loadout_key), buffer);

            g_Players[client].distributor.should_close = false;

            DisplayDistributorLoadoutMenu(buffer, client);
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

void DisplayDistributorLoadoutMenu(const char[] loadout_name, int client, int weapon_type = WEAPON_TYPE_PRIMARY)
{
    char buffer[64];

    CSWeaponID weapon_id;

    Loadout loadout;

    LoadoutItem loadout_item;

    g_Players[client].distributor.loadout_type = weapon_type;

    int team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

    Menu menu = new Menu(Handler_DistributorLoadoutMenu);

    FormatEx(buffer, sizeof(buffer), "%T%T %T:\n\n%T\n ", "Menu Prefix", client, loadout_name, client, weapon_type & WEAPON_TYPE_PRIMARY ? "Primary Weapon" : "Secondary Weapon", client, team == LOADOUT_TEAM_CT ? "Team CT" : "Team T", client);

    menu.SetTitle(buffer);

    for (int current_loadout; current_loadout < g_Loadouts.Length; current_loadout++)
    {
        if (strcmp(loadout.name, loadout_name))
        {
            continue;
        }

        for (int current_item; current_item < loadout.items[team].Length; current_item++)
        {
            if (loadout_item.flags ^ weapon_type)
            {
                continue;
            }

            if (!retakes_distributor_force_weapon.BoolValue)
            {
                weapon_id = GetEquippedInventoryItemByID(client, team + LOADOUT_TEAM_MAX, loadout_item.id);

                if (weapon_id != loadout_item.id)
                {
                    CS_WeaponIDToAlias(weapon_id, buffer, sizeof(buffer));

                    FormatEx(loadout_item.classname, sizeof(LoadoutItem::classname), "weapon_%s", buffer);
                }
            }

            FormatEx(buffer, sizeof(buffer), "%T", loadout_item.classname, client);
            menu.AddItem(loadout_item.classname, buffer);
        }
    }

    if (menu.ItemCount <= 0)
    {
        int item_count = weapon_type & WEAPON_TYPE_PRIMARY ? loadout.item_primary_count[team] : loadout.item_secondary_count[team];

        // Check if there are items and the menu is not supposed to be closed
        if (item_count > 0 && !g_Players[client].distributor.should_close)
        {
            // Recursively open the loadout menu with the opposite view type
            DisplayDistributorLoadoutMenu(g_Players[client].distributor.loadout_key, client, weapon_type & WEAPON_TYPE_PRIMARY ? WEAPON_TYPE_SECONDARY : WEAPON_TYPE_PRIMARY);
        }

        g_Players[client].distributor.should_close = true;

        delete menu;

        return;
    }

    FixMenuGap(menu);

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

            int weapon_type = g_Players[client].distributor.loadout_type;

            if (g_GracePeriod > GetGameTime() - retakes_distributor_grace_period.FloatValue)
            {
                if (!strcmp(g_Players[client].distributor.loadout_key, g_CurrentLoadout))
                {
                    DisarmClient(client, weapon_type == WEAPON_TYPE_PRIMARY ? CS_SLOT_PRIMARY : CS_SLOT_SECONDARY);

                    int weapon = GivePlayerItem(client, buffer);

                    if (weapon != -1)
                    {
                        EquipPlayerWeapon(client, weapon);
                    }
                }
            }

            PlayerLoadout player_loadout;
            char          loadout_name[48];
            int           team = GetClientTeam(client) - LOADOUT_TEAM_MAX;

            strcopy(loadout_name, sizeof(loadout_name), g_Players[client].distributor.loadout_key);

            if (g_Players[client].distributor.weapons_map.GetArray(loadout_name, player_loadout, sizeof(player_loadout)))
            {
                if (weapon_type & WEAPON_TYPE_PRIMARY)
                {
                    player_loadout.primary_weapon_id[team] = weapon_id;
                }

                else if (weapon_type & WEAPON_TYPE_SECONDARY)
                {
                    player_loadout.secondary_weapon_id[team] = weapon_id;
                }

                g_Players[client].distributor.weapons_map.SetArray(loadout_name, player_loadout, sizeof(player_loadout));
            }

            // Check if the menu is not supposed to be closed
            if (!g_Players[client].distributor.should_close)
            {
                g_Players[client].distributor.should_close = true;

                // Recursively open the loadout menu with the opposite view type
                DisplayDistributorLoadoutMenu(g_Players[client].distributor.loadout_key, client, weapon_type & WEAPON_TYPE_PRIMARY ? WEAPON_TYPE_SECONDARY : WEAPON_TYPE_PRIMARY);
            }

            else
            {
                DisplayDistributorMenu(client);
            }

            PrintToChat(client, "%t%t", "Messages Prefix", "Loadout Weapon Selected", buffer, team == LOADOUT_TEAM_CT ? "Counter Terrorist Abbreviation" : "Terrorist Abbreviation", loadout_name);
        }

        case MenuAction_Cancel:
        {
            if (option == MenuCancel_ExitBack)
            {
                int view = g_Players[client].distributor.loadout_type;

                // Check if the current view has the WEAPON_TYPE_SECONDARY flag and the menu should be closed
                if (view & WEAPON_TYPE_SECONDARY && g_Players[client].distributor.should_close)
                {
                    // If the menu is supposed to be closed, return to the main distributor menu
                    DisplayDistributorMenu(client);
                }

                if (view & WEAPON_TYPE_SECONDARY)
                {
                    // Return to the primary loadout menu
                    DisplayDistributorLoadoutMenu(g_Players[client].distributor.loadout_key, client, WEAPON_TYPE_PRIMARY);

                    g_Players[client].distributor.should_close = false;
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

CSWeaponID GetEquippedInventoryItemByID(int client, int team, CSWeaponID weapon_id)
{
    if (!g_Players[client].distributor.inventory)
    {
        return weapon_id;
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
        return weapon_id;
    }

    item_definition = item_view.GetItemDefinition();

    if (!item_definition)
    {
        return weapon_id;
    }

    weapon_definition_index = item_definition.GetDefinitionIndex();

    // Return the weapon ID based on whether it matches the specified weapon ID or the other weapon ID
    return weapon_definition_index == CS_WeaponIDToItemDefIndex(weapon_id) ? weapon_id : CS_ItemDefIndexToID(weapon_definition_index);
}