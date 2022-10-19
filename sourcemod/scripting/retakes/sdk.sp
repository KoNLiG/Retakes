/*
 * • SDK related stuff.
 * • Detour hooks, game function calls, etc...
 */

#assert defined COMPILING_FROM_MAIN

void SDK_OnPluginStart()
{
    GameData gamedata = new GameData("retakes.games");
    
    SetupDHooks(gamedata);
    
    delete gamedata;
}

void SetupDHooks(GameData gamedata)
{
    DynamicDetour IsRetakeLoaded;
    
    if (!(IsRetakeLoaded = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Bool, ThisPointer_Ignore)))
    {
        SetFailState("Failed to setup detour for 'IsRetakeLoaded'");
    }
    
    if (!IsRetakeLoaded.SetFromConf(gamedata, SDKConf_Signature, "IsRetakeLoaded"))
    {
        SetFailState("Failed to load 'IsRetakeLoaded' signature from gamedata");
    }
    
    if (!IsRetakeLoaded.Enable(Hook_Pre, Detour_OnIsRetakeLoaded))
    {
        SetFailState("Failed to enable 'IsRetakeLoaded' detour");
    }
}

// Completely skip the function and override the return value to 'false'.
// Result is the most of the in-game retake mod features will be automatically disabled, 
// with some extra stuff that we want to preserve such as: 
// 1. "Retake/Defend Site A/B!" where the player money is displayed.
// 2. An arrow that directs you towards the current site to retake, only as an attacker.
MRESReturn Detour_OnIsRetakeLoaded(DHookReturn hReturn)
{
    hReturn.Value = false;
    
    return MRES_Supercede;
} 