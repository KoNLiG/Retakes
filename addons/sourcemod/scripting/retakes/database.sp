/*
 * • Responsible for creating and maintaining a database connection.
 * • Provides an interface for all the other modules.
 */

#assert defined COMPILING_FROM_MAIN

Database g_Database;

void Database_OnPluginStart()
{
    char database_entry[64];
    retakes_database_entry.GetString(database_entry, sizeof(database_entry));

    Database.Connect(SQL_OnDatabaseConnected, database_entry);
}

void SQL_OnDatabaseConnected(Database db, const char[] error, any data)
{
    if (!(g_Database = db))
    {
        SetFailState("Unable to maintain connection to MySQL server (%s)", error);
    }

    // Late load support.
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
           OnClientPutInServer(current_client);
        }
    }

    Configuration_OnDatabaseConnection();
    Distributer_OnDatabaseConnection();
}

void SQL_Distributer_TransactionTables(Database database, any data, int num_queries, Handle[] results, any[] query_data)
{
#if defined DEBUG
    PrintToServer("Succesfully created distributer SQL tables!");
#endif
}

void SQL_Distributer_TransactionFailure(Database database, any data, int num_queries, const char[] error, int fail_index, any[] query_data)
{
    SetFailState("There was an error creating distributer tables: %s", error);
}

void SQL_Distributer_OnClientConnect(Database database, DBResultSet results, const char[] error, int userid)
{
    if (!database || !results || error[0])
    {
        LogError("There was an error saving player weapon data! %s", error);
        return;
    }

    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    int key;
    results.FieldNameToNum("id", key);
    g_Players[client].key = results.FetchInt(key);

    char query[256];
    char table_name[32];

    retakes_database_table_distributer.GetString(table_name, sizeof(table_name));

    g_Database.Format(query, sizeof(query), "SELECT * FROM `%s_distributer_loadouts` WHERE `id` = '%i'", table_name, g_Players[client].key);
    g_Database.Query(SQL_Distributer_OnClientInfoFetched, query, g_Players[client].user_id, DBPrio_High);
}

void SQL_Distributer_OnClientInfoFetched(Database database, DBResultSet results, const char[] error, int userid)
{
    if (!database || !results || error[0])
    {
        LogError("There was an error saving player weapon data! %s", error);
        return;
    }

    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    int primary_weapon;
    int secondary_Weapon;

    results.FieldNameToNum("primary_weapon_item_index", primary_weapon);
    results.FieldNameToNum("secondary_Weapon", secondary_Weapon);

}