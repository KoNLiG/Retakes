/*
 * • Responsible for distributing weapons to players.
 */

#assert defined COMPILING_FROM_MAIN

#define MAX_LOADOUTS_LENGTH 10
#define LOADOUTS_MAX_LENGTH 25
#define LOADOUT_TEAM_T 0
#define LOADOUT_TEAM_CT 1
#define LOADOUT_TEAM_MAX 2

enum WeaponType
{
    WeaponType_FireArm,
    WeaponType_Utility
}

enum struct LoadoutItemData
{
    CSWeaponID item_id;

    char classname[32];

    WeaponType type;

    float chance;

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
        for (int i; i <= LOADOUT_TEAM_CT; i++)
        {
            delete this.items[i];
        }
    }
}

ArrayList loadouts;
int smc_parser_depth;
int smc_parser_count;
int current_loadout;
char current_weapon[sizeof(LoadoutItemData::classname)];

public void Distributer_OnPluginStart()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/retakes/distributer.cfg");

    loadouts = new ArrayList(sizeof(LoadoutData));

    SMCParser parser = new SMCParser();

    parser.OnStart        = SMCParser_OnStart;
    parser.OnEnterSection = SMCParser_OnEnterSection;
    parser.OnLeaveSection = SMCParser_OnLeaveSectionn;
    parser.OnKeyValue     = SMCParser_OnKeyValue;
    parser.OnRawLine      = SMCParser_OnRawLine;
    parser.OnEnd          = SMCParser_OnEnd;
    parser.ParseFile(path);

    delete parser;

    RegConsoleCmd("sm_distributer", Command_Distributer);
}

void Distributer_OnDatabaseConnection()
{
    char query[512];
    char table_name[32];

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    Transaction transaction = new Transaction();

    g_Database.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s_distributer_players` (`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `account_id` INT NOT NULL, PRIMARY KEY (`id`), UNIQUE `account_id_unique` (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;", table_name);
    transaction.AddQuery(query);

    g_Database.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `%s_distributer_loadouts` (`player_id` BIGINT UNSIGNED NOT NULL, `loadout` VARCHAR(32), `primary_weapon_item_index` INT UNSIGNED, `secondary_weapon_item_index` INT UNSIGNED, PRIMARY KEY (`player_id`), CONSTRAINT `fk_retakes_distributer_loadouts` FOREIGN KEY (`player_id`) REFERENCES `%s_distributer_players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;", table_name, table_name);
    transaction.AddQuery(query);

    g_Database.Execute(transaction, SQL_Distributer_TransactionTables, SQL_Distributer_TransactionFailure, _, DBPrio_High);
}

void Distributer_OnClientPutInServer(int client)
{
    char query[256];
    char table_name[32];

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "INSERT INTO `%s_distributer_players` (`account_id`) VALUES ('%s') ON DUPLICATE KEY UPDATE `account_id` = %i", table_name, g_Players[client].account_id, g_Players[client].account_id);
    g_Database.Query(SQL_Distributer_OnClientConnect, query, g_Players[client].user_id);
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
        LoadoutData loadout;

        loadout.Initialize(name);

        loadouts.PushArray(loadout, sizeof(loadout));
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

        if (!strcmp(key, "weapon") || !strcmp(key, "utility"))
        {
            char buffer[32];

            FormatEx(buffer, sizeof(buffer), "weapon_%s", value);

            CSWeaponID weapon_id = CS_AliasToWeaponID(buffer);

            if (!weapon_id)
            {
                return SMCParse_Continue;
            }

            item_data.item_id = weapon_id;

            strcopy(item_data.classname, sizeof(LoadoutItemData::classname), buffer);

            item_data.type = WeaponType_FireArm;

            if (!strcmp(key, "utility"))
            {
                item_data.type = WeaponType_Utility;
            }

            LoadoutData loadout;

            loadouts.GetArray(loadouts.Length - 1, loadout, sizeof(loadout));

            switch (current_loadout)
            {
                case LOADOUT_TEAM_CT: loadout.items[LOADOUT_TEAM_CT].PushArray(item_data, sizeof(item_data));
                case LOADOUT_TEAM_T: loadout.items[LOADOUT_TEAM_T].PushArray(item_data, sizeof(item_data));
                default: return SMCParse_HaltFail;
            }
        }

        if (!strcmp(key, "kits"))
        {
            LoadoutData loadout;

            loadouts.GetArray(loadouts.Length - 1, loadout, sizeof(loadout));

            loadout.kits = StringToInt(value);

            loadouts.SetArray(loadouts.Length, loadout, sizeof(loadout));
        }
    }

    else if (smc_parser_depth == 3 && smc_parser_count == 2)
    {
        int position;

        char buffer[32];

        LoadoutData loadout;

        static LoadoutItemData item_data;

        FormatEx(buffer, sizeof(buffer), "weapon_%s", current_weapon);

        for (int i; i < loadouts.Length; i++)
        {
            if (!loadouts.GetArray(i, loadout, sizeof(loadout)))
            {
                continue;
            }

            for (int j; j < LOADOUT_TEAM_MAX; j++)
            {
                position = loadout.items[j].FindString(buffer);

                if (position != -1)
                {
                    loadout.items[j].GetArray(position, item_data, sizeof(item_data));

                    if (!strcmp(key, "chance"))
                    {
                        item_data.chance = StringToFloat(value);
                    }

                    if (!strcmp(key, "max"))
                    {
                        item_data.max = StringToInt(value);
                    }

                    loadout.items[j].SetArray(position, item_data, sizeof(item_data));
                }
            }
        }
    }

    return SMCParse_Continue;
}

SMCResult SMCParser_OnRawLine(SMCParser parser, const char[] line, int line_num)
{
    return SMCParse_Continue;
}

void SMCParser_OnEnd(SMCParser parser, bool halted, bool failed)
{
#if defined DEBUG
    PrintToServer("Distributer finished parsing %i loadouts", loadouts.Length);
#endif

    if (failed)
    {
        SetFailState("There was a fatal error");
    }

    bool fail_state;

    LoadoutData loadout;
    LoadoutItemData item_data;

    for (int i = loadouts.Length - 1; i >= 0; i--)
    {
        if (!loadouts.GetArray(i, loadout, sizeof(loadout)))
        {
            continue;
        }

        if (!strlen(loadout.name))
        {
            continue;
        }

        if (!TranslationPhraseExists(loadout.name))
        {
            fail_state = true;
            LogError("Translation for \"%s\" loadout key not found", loadout.name);
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
                    LogError("Translation for \"%s\" weapon key not found", item_data.classname);
                }
            }
        }
    }

    if (fail_state)
    {
        SetFailState("There are missing translations for distributer");
    }
}

void Distributer_OnPlayerSpawn(int client)
{
    if (!retakes_distributer_enable.BoolValue)
    {
        return;
    }

    if (IsFakeClient(client))
    {
        return;
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

            DisplayDistributerLoadoutMenu(buffer, client);
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

void DisplayDistributerLoadoutMenu(const char[] loadout_name, int client)
{
    char buffer[64];

    LoadoutData loadout;

    LoadoutItemData item_data;

    int team = GetClientTeam(client) - 2;

    Menu menu = new Menu(Handler_DistributerLoadoutMenu);

    FormatEx(buffer, sizeof(buffer), "%T%T:\n ", "MenuPrefix", client, loadout_name, client);

    menu.SetTitle(buffer);

    for (int i = loadouts.Length - 1; i >= 0; i--)
    {
        if (!loadouts.GetArray(i, loadout, sizeof(loadout)))
        {
            continue;
        }

        if (strcmp(loadout.name, loadout_name))
        {
            continue;
        }

        for (int j = loadout.Size(team) - 1; j >= 0; j--)
        {
            if (!loadout.items[team].GetArray(j, item_data, sizeof(item_data)))
            {
                continue;
            }

            if (item_data.type == WeaponType_Utility)
            {
                continue;
            }

            if (!strcmp(item_data.classname, "weapon_m4a1"))
            {
                item_data.classname = CS_FindEquippedInventoryItem(client, item_data.item_id) ? "weapon_m4a1" : "weapon_m4a1_silencer";
            }

            FormatEx(buffer, sizeof(buffer), "%T", item_data.classname, client);
            menu.AddItem(item_data.classname, buffer);
        }
    }

    if (menu.ItemCount <= 3)
    {
        for (int i; i <= 2; i++)
        {
            menu.AddItem(NULL_STRING, NULL_STRING, ITEMDRAW_NOTEXT);
        }
    }

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

            int weapon = GivePlayerItem(client, buffer);

            EquipPlayerWeapon(client, weapon);


            // DisplayDistributerLoadoutMenu(..., ...)
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
    for (int i = GetEntPropArraySize(client, Prop_Send, "m_EquippedLoadoutItemDefIndices") - 1; i >= 0 ; i--)
    {
        if (CS_WeaponIDToItemDefIndex(weapon_id) == GetEntProp(client, Prop_Send, "m_EquippedLoadoutItemDefIndices", _, i))
        {
            return true;
        }
    }

    return false;
}