/*
 * • Responsible for almost anything non-related to player manager.
 */

#assert defined COMPILING_FROM_MAIN

int g_TargetSite;
int g_ConsecutiveRounds[Bombsite_Max];

// 'g_IsWaitingForPlayers' determines if we're currently in the 'waiting for players' state.
// 'ShouldWaitForPlayers()' function determines whether we should wait for players,
// but it doesn't necessarily mean it's equal to 'g_IsWaitingForPlayers'.
bool g_IsWaitingForPlayers;

ConVar mp_ignore_round_win_conditions;
ConVar mp_freezetime;

void Gameplay_OnPluginStart()
{
    if (!(mp_ignore_round_win_conditions = FindConVar("mp_ignore_round_win_conditions")))
    {
        SetFailState("Failed to find convar 'mp_ignore_round_win_conditions'");
    }

    if (!(mp_freezetime = FindConVar("mp_freezetime")))
    {
        SetFailState("Failed to find convar 'mp_freezetime'");
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

void Gameplay_OnRoundStart()
{
    DisplayTargetSite();
}

void Gameplay_OnRoundFreezeEnd()
{
    SetRoundInProgress(true);
}

void Gameplay_OnClientDisconnectPost()
{
    if (g_IsWaitingForPlayers && !GetRetakeClientCount())
    {
        SetWaitingForPlayersState(false);
    }
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

bool IsRoundInProgress()
{
    return view_as<bool>(GameRules_GetProp("m_bRoundInProgress"));
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
        PrintCenterTextAll(NULL_STRING);

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

void DisplayTargetSite()
{
    Event show_survival_respawn_status = CreateEvent("show_survival_respawn_status");
    if (!show_survival_respawn_status)
    {
        return;
    }

    show_survival_respawn_status.SetInt("duration", mp_freezetime.IntValue);
    show_survival_respawn_status.SetInt("userid", -1);

    char message[128];
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (!IsClientInGame(current_client) || IsFakeClient(current_client) || g_Players[current_client].spawn_role != SpawnRole_Attacker)
        {
            continue;
        }

        // Format the buffer for each individual language.
        FormatEx(message, sizeof(message), "%T", "Bombsite HTML", current_client, g_TargetSite == Bombsite_A ? "Bombsite A" : "Bombsite B");
        show_survival_respawn_status.SetString("loc_token", message);

        show_survival_respawn_status.FireToClient(current_client);
    }

    show_survival_respawn_status.Cancel();
}