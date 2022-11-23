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