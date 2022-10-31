/*
 *  • Registeration of all natives and forwards.
 *  • Registeration of the plugin library.
 */

#assert defined COMPILING_FROM_MAIN

// Global forward handles.
GlobalForward g_OnBombsiteSelected;
GlobalForward g_OnBombsiteSelectedPost;

void InitializeAPI()
{
    CreateNatives();
    CreateForwards();

    RegPluginLibrary(RETAKES_LIB_NAME);
}

// Natives
void CreateNatives()
{
    CreateNative("Retakes_GetTargetBombsite", Native_GetTargetBombsite);
}

any Native_GetTargetBombsite(Handle plugin, int numParams)
{
    return g_TargetSite;
}

// Forwards.
void CreateForwards()
{
    g_OnBombsiteSelected = new GlobalForward(
		"Retakes_OnBombsiteSelected",
		ET_Ignore,  // Ignore any return values. (void)
		Param_CellByRef  // int &bombsite_index
		);

    g_OnBombsiteSelectedPost = new GlobalForward(
		"Retakes_OnBombsiteSelectedPost",
		ET_Ignore,  // Ignore any return values. (void)
		Param_Cell  // int bombsite_index
		);
}

void Call_OnBombsiteSelected(int &bombsite_index)
{
    Call_StartForward(g_OnBombsiteSelected);
    Call_PushCellRef(bombsite_index);
    Call_Finish();
}

void Call_OnBombsiteSelectedPost(int bombsite_index)
{
    Call_StartForward(g_OnBombsiteSelectedPost);
    Call_PushCell(bombsite_index);
    Call_Finish();
}