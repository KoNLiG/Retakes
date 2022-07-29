#if defined _nav_mesh_included
 #endinput
#endif
#define _nav_mesh_included

#include <CUtlVector>

enum NavArea
{
    NULL_NAV_AREA = 0
}

methodmap NavAreaCriticalData
{
    public native void GetNWCorner(float corner[3]);
    
    public native void GetSECorner(float corner[3]);
    
    // Get Z values of the the other two corners of the area
    property float neZ
    {
        public native get();
    }
    
    property float swZ
    {
        public native get();
    }
    
    public void GetNECorner(float corner[3])
    {
        float NWCorner[3], SECorner[3];
        this.GetNWCorner(NWCorner);
        this.GetSECorner(SECorner);
        
        corner[0] = SECorner[0];
        corner[1] = NWCorner[1];
        corner[2] = this.neZ;
    }
    
    public void GetSWCorner(float corner[3])
    {
        float NWCorner[3], SECorner[3];
        this.GetNWCorner(NWCorner);
        this.GetSECorner(SECorner);
        
        corner[0] = NWCorner[0];
        corner[1] = SECorner[1];
        corner[2] = this.swZ;
    }
}

methodmap NavArea < NavAreaCriticalData
{
    public native void GetRandomPoint(float pos[3]);
    
    public native int GetPlace();
}

methodmap TheNavMesh
{
    public static native int PlaceToName(int place_index, char[] buffer, int maxlength);
    
    // Retrieves a CNavArea address by the given origin, or NULL_NAV_AREA on fail.
    public static native NavArea GetNavArea(const float pos[3], float beneathLimit = 120.0, bool checkLOS = false);
    
    public static native int GetPlaceCount();
    
    // Retrieves a place index by the given name, or -1 on fail.
    public static int NameToPlace(char[] name, bool caseSensitive = true)
    {
        char area_name[256];
        
        for (int current_place; current_place < TheNavMesh.GetPlaceCount(); current_place++)
        {
            TheNavMesh.PlaceToName(current_place, area_name, sizeof(area_name));
            if (StrEqual(area_name, name, caseSensitive))
            {
                return current_place;
            }
        }
        
        return -1;
    }
}

methodmap TheNavAreas < CUtlVector
{
    public native TheNavAreas();
}

/**
 * Called after a client enterd a new navigation area.
 *
 * @param client			Client index
 * @param nav_area			Navigation area object the player has entered.
 */
forward void NavMesh_OnPlayerEnter(int client, NavArea nav_area);

/**
 * Called after a client exit a navigation area.
 *
 * @param client			Client index
 * @param nav_area			Previous navigation area object.
 */
forward void NavMesh_OnPlayerExit(int client, NavArea nav_area);

#if !defined REQUIRE_PLUGIN
public void __pl_nav_mesh_SetNTVOptional()
{
    MarkNativeAsOptional("NavAreaCriticalData.GetNWCorner");
    MarkNativeAsOptional("NavAreaCriticalData.GetSECorner");
    MarkNativeAsOptional("NavAreaCriticalData.neZ.get");
    MarkNativeAsOptional("NavAreaCriticalData.swZ.get");
    MarkNativeAsOptional("NavArea.GetRandomPoint");
    MarkNativeAsOptional("NavArea.GetPlace");
    MarkNativeAsOptional("TheNavMesh.PlaceToName");
    MarkNativeAsOptional("TheNavMesh.GetNavArea");
    MarkNativeAsOptional("TheNavMesh.PlaceCount.get");
    MarkNativeAsOptional("TheNavAreas.TheNavAreas");
}
#endif

public SharedPlugin __pl_nav_mesh =
{
    name = "nav_mesh",
    file = "nav_mesh.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};
