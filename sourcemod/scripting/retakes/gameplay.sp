/*
 * • Responsible for almost anything non-related to player manager.
 */

#assert defined COMPILING_FROM_MAIN

int g_TargetSite;

void Gameplay_OnPluginStart()
{
}

void Gameplay_RoundPreStart()
{
    g_TargetSite = GetURandomInt() % Bombsite_Max;
    
    // TODO: Execute a forward 'Retakes_OnBombsiteSelect'
    
    SetGameBombsite();
}

void SetGameBombsite()
{
    // Setting 'm_iBombSite' without 'm_bRoundInProgress' being true has no effect.
    GameRules_SetProp("m_bRoundInProgress", true);
    
    GameRules_SetProp("m_iBombSite", g_TargetSite);
} 