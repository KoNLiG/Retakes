/*
 * • Responsible for almost anything non-related to player manager.
 */

#assert defined COMPILING_FROM_MAIN

int g_TargetSite;

void Gameplay_OnPluginStart()
{
}

void Gameplay_OnRoundEnd(int winner)
{
    if (winner == CS_TEAM_CT)
    {
        g_WinRowCount++;

        if (g_WinRowCount == g_MaxRoundWinsBeforeScramble.IntValue)
        {
            g_ScrambleTeamsPreRoundStart = true;
            g_WinRowCount = 0;
        }
    }

    else if (winner == CS_TEAM_T)
        g_WinRowCount = 0;
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