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
    if (results == null)
    {
        LogError("There was an error saving player weapon data! %s", error);
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

    g_Database.Format(query, sizeof(query), "SELECT * FROM `%s_distributer_players` WHERE `account_id` = '%i'", table_name, g_Players[client].account_id);
}
