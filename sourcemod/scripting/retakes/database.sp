/*
 * • Responsible for creating and maintaining a database connection.
 * • Provides an interface for all the other modules.
 */

#assert defined COMPILING_FROM_MAIN

#define DATABASE_ENTRY "modern_retakes" // Listed entry in 'databases.cfg'

Database g_Database;

void Database_OnPluginStart()
{
	Database.Connect(SQL_OnDatabaseConnected, DATABASE_ENTRY);
}

void SQL_OnDatabaseConnected(Database db, const char[] error, any data)
{
	if (!(g_Database = db))
	{
		SetFailState("Unable to maintain connection to MySQL server (%s)", error);
	}
	
	Configuration_OnDatabaseConnection();
} 