#include <sourcemod>
#include <nav_mesh>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "[Testsuite] Nav Mesh",
    author = "KoNLiG",
    description = "A light test plugin for the navigation mesh library.",
    version = "1.0.0",
    url = "https://github.com/KoNLiG/Retakes"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_print_all_places", Command_PrintAllPlaces);
    RegConsoleCmd("sm_print_nav_area_place", Command_PrintNavAreaPlace);
}

Action Command_PrintAllPlaces(int client, int args)
{
    char name[256];
    int place_count = TheNavMesh.GetPlaceCount();

    PrintToConsole(client, "place_count: %d", place_count);

    for (int i = 1; i < place_count; i++)
    {
        if (TheNavMesh.PlaceToName(i, name, sizeof(name)))
        {
            PrintToConsole(client, "[%d] %s", i, name);
        }
    }

    return Plugin_Handled;
}

Action Command_PrintNavAreaPlace(int client, int args)
{
    float pos[3];
    GetClientAbsOrigin(client, pos);

    NavArea nav_area = TheNavMesh.GetNearestNavArea(pos);
    if (!nav_area)
    {
        PrintToChat(client, "nav_area is null.");
        return Plugin_Handled;
    }

    PrintToChat(client, "nav_area.GetAdjacentCount(): %d", nav_area.GetAdjacentCount(NORTH));

    return Plugin_Handled;
}