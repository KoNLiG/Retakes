/*
 * • Responsible for almost anything non-related to player manager.
 */

#assert defined COMPILING_FROM_MAIN

int g_TargetSite;
int g_ConsecutiveRounds[Bombsite_Max];

// The plugin mind about whether are we waiting for players.
// 'ShouldWaitForPlayers()' function will tell whether
// we actually need to wait for more players.
bool g_IsWaitingForPlayers;

ConVar mp_ignore_round_win_conditions;

void Gameplay_OnPluginStart()
{
    if (!(mp_ignore_round_win_conditions = FindConVar("mp_ignore_round_win_conditions")))
    {
        SetFailState("Failed to find convar 'mp_ignore_round_win_conditions'");
    }
}

void Gameplay_OnMapStart()
{
    g_ConsecutiveRounds = { 0, 0 };
}

void Gameplay_OnRoundPreStart()
{
    if (ShouldWaitForPlayers() && !g_IsWaitingForPlayers)
    {
        SetWaitingForPlayersState(true);
        return;
    }

    SelectBombsite();

    SetRoundInProgress(false);
}

void Gameplay_OnRoundFreezeEnd()
{
    SetRoundInProgress(true);
}

void SelectBombsite()
{
    // 'x ^ 1' is practically the same as '!x' but without a tag mismatch warning.

    int target_site = GetURandomInt() % Bombsite_Max;

    if (retakes_max_consecutive_rounds_same_target_site.IntValue != -1 && g_ConsecutiveRounds[target_site] >= retakes_max_consecutive_rounds_same_target_site.IntValue)
    {
        // Flip the bombsite index.
        target_site = target_site ^ 1;
    }

    Call_OnBombsiteSelected(target_site);

    Call_OnBombsiteSelectedPost(target_site);

    g_ConsecutiveRounds[target_site]++;
    g_ConsecutiveRounds[target_site ^ 1] = 0;
    SetGameBombsite(target_site);

    g_TargetSite = target_site;
}

void SetGameBombsite(int bombsite_index)
{
    GameRules_SetProp("m_iBombSite", bombsite_index);
}

void SetRoundInProgress(bool value)
{
    GameRules_SetProp("m_bRoundInProgress", value);
}

void SetWaitingForPlayersState(bool state)
{
    if (g_IsWaitingForPlayers == state)
    {
        return;
    }

    g_IsWaitingForPlayers = state;

    if (g_IsWaitingForPlayers)
    {
        Frame_DisplayRequiredPlayers();
    }

    mp_ignore_round_win_conditions.BoolValue = state;
}

void Frame_DisplayRequiredPlayers()
{
    if (!g_IsWaitingForPlayers)
    {
        PrintCenterTextAll("");
        return;
    }

	int fade_color[3];
	GetNextFadeColor(fade_color);

	PrintCenterTextAll("<font color='#%06X' class='fontSize-xl'>%t</font>", RGBToHex(fade_color), "Waiting For Players", retakes_player_min.IntValue - GetRetakeClientCount());

	RequestFrame(Frame_DisplayRequiredPlayers);
}

void GetNextFadeColor(int color[3])
{
	static int fade_color[3] = { 255, 0, 0 };

	if (fade_color[0] > 0 && !fade_color[2])
	{
		fade_color[0]--;
		fade_color[1]++;
	}

	if (fade_color[1] > 0 && !fade_color[0])
	{
		fade_color[1]--;
		fade_color[2]++;
	}

	if (fade_color[2] > 0 && !fade_color[1])
	{
		fade_color[2]--;
		fade_color[0]++;
	}

	color = fade_color;
}

int RGBToHex(int color[3])
{
	int hex;
	hex |= ((color[0] & 0xFF) << 16);
	hex |= ((color[1] & 0xFF) << 8);
	hex |= ((color[2] & 0xFF) << 0);

	return hex;
}