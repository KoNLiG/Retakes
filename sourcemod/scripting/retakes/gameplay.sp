/*
 * • Responsible for almost anything non-related to player manager.
 */

#assert defined COMPILING_FROM_MAIN

int g_TargetSite;
int g_ConsecutiveRounds[Bombsite_Max];

void Gameplay_OnPluginStart()
{
}

void Gameplay_OnMapStart()
{
    g_ConsecutiveRounds = { 0, 0 };
}

void Gameplay_OnRoundPreStart()
{
    SelectBombsite();
}

void SelectBombsite()
{
    int target_site = GetURandomInt() % Bombsite_Max;

    if (retakes_max_consecutive_rounds_same_target_site.IntValue != -1 && g_ConsecutiveRounds[target_site] >= retakes_max_consecutive_rounds_same_target_site.IntValue)
    {
        // Flip the bombsite index.
        target_site = target_site ^ 1;
    }

    // TODO: Execute a forward 'Retakes_OnBombsiteSelected'

    // TODO: Execute a forward 'Retakes_OnBombsiteSelectedPost'

    g_ConsecutiveRounds[target_site]++;
    g_ConsecutiveRounds[target_site ^ 1] = 0;
    SetGameBombsite(target_site);

    g_TargetSite = target_site;
}

void SetGameBombsite(int bombsite_index)
{
    // Setting 'm_iBombSite' without 'm_bRoundInProgress' being true has no effect.
    GameRules_SetProp("m_bRoundInProgress", true);

    GameRules_SetProp("m_iBombSite", bombsite_index);
}