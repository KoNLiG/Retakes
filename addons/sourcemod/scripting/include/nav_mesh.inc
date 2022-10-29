#if defined _nav_mesh_included
 #endinput
#endif
#define _nav_mesh_included

#include <CUtlVector>

// https://github.com/perilouswithadollarsign/cstrike15_src/blob/master/game/server/nav.h#L112-L120
enum NavDirType
{
	NORTH = 0,
	EAST = 1,
	SOUTH = 2,
	WEST = 3,

	NUM_DIRECTIONS
};

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
        float nw_corner[3], se_corner[3];
        this.GetNWCorner(nw_corner);
        this.GetSECorner(se_corner);

        corner[0] = se_corner[0];
        corner[1] = nw_corner[1];
        corner[2] = this.neZ;
    }

    public void GetSWCorner(float corner[3])
    {
        float nw_corner[3], se_corner[3];
        this.GetNWCorner(nw_corner);
        this.GetSECorner(se_corner);

        corner[0] = nw_corner[0];
        corner[1] = se_corner[1];
        corner[2] = this.swZ;
    }

    public void GetCenter(float center[3])
	{
		float nw_corner[3], se_corner[3];
		this.GetNWCorner(nw_corner);
		this.GetSECorner(se_corner);

		center[0] = (nw_corner[0] + se_corner[0]) / 2.0;
		center[1] = (nw_corner[1] + se_corner[1]) / 2.0;
		center[2] = (nw_corner[2] + se_corner[2]) / 2.0;
	}
}

methodmap NavArea < NavAreaCriticalData
{
	// Generates a random position within the navigation bounds. [mins, maxs]
    //
    // Note that you should verify the returned position
    // with the entity interacted with.
    //
    // @param pos    Position, treat as a buffer.
    //
    // @error 		 Null NavArea instance.
    public native void GetRandomPoint(float pos[3]);

    // Retrieves the navigation area place index.
    //
    // Note: A single navigation area only has only one place index,
    // 		 while a place index can have many navigation area(s).
    //
    // Note: A valid place index is [1 <= X <= TheNavMesh.GetPlaceCount]
    //
    // @return 		 Place index.
    // @error 		 Null NavArea instance.
    public native int GetPlace();

    // Retrieves whether this navigation area is connected to another.
    //
    // @param area   A navigation area instance to compute against.
    // @param dir    Navigation direction. Searches against all directions if equal to 'NUM_DIRECTIONS'.
    //
    // @return 		 True if both navigation areas are connected to each other, false otherwise.
    // @error 		 Null NavArea instance.
    public native bool IsConnected(NavArea area, NavDirType dir = NUM_DIRECTIONS);

    // Retrieves the amount of adjacent navigation areas by the given direction.
    //
    // @param dir    Navigation direction.
    //
    // @return 		 Amount of adjacent navigation areas.
    // @error 		 Null NavArea instance.
    public native int GetAdjacentCount(NavDirType dir);

    // Retrieves a adjacent navigation area by the given direction and index.
    //
    // @param dir    Navigation direction.
    // @param index  Index, maximum is GetAdjacentCount.
    //
    // @return 		 NavArea instance.
    // @error 		 Null NavArea instance, or invalid area index.
    public native NavArea GetAdjacentArea(NavDirType dir, int index);
}

methodmap TheNavMesh
{
	// Retrieves a place name by the given place index.
    //
    // @param place_index   Place index in the range of [1 <= X <= TheNavMesh.GetPlaceCount].
    // @param buffer        Destination string buffer.
 	// @param maxlength     Maximum length of output string buffer.
    //
    // @return 		 		Number of bytes written.
    // @error 		 		Invalid place index.
    public static native int PlaceToName(int place_index, char[] buffer, int maxlength);

    // Retrieves a NavArea instance based on the given position.
    //
    // @param pos			Position along the map.
    // @param anyZ			Apparently it's completly unused by the source code.
    // @param maxDist		Max distance to consider as "near".
    // @param checkLOS		Whether or not to check LOS to the area. (Line of sight)
    // @param checkGround	If true and the given position height is invalid, false will be returned.
    //
    // @return 		 		NavArea instance, or NULL_NAV_AREA on failure.
    public static native NavArea GetNearestNavArea(const float pos[3], bool anyZ = false, float maxDist = 10000.0, bool checkLOS = false, bool checkGround = true);

    // Retrieves the amount of existing places.
    //
    // @return 		 		Self explanatory.
    public static native int GetPlaceCount();

    // Retrieves a place index by the given name, or -1 on failure.
    public static int NameToPlace(char[] name, bool caseSensitive = true)
    {
        char area_name[256];

        for (int current_place = 1; current_place < TheNavMesh.GetPlaceCount(); current_place++)
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
    MarkNativeAsOptional("NavArea.IsConnected");
    MarkNativeAsOptional("NavArea.GetAdjacentCount");
    MarkNativeAsOptional("NavArea.GetAdjacentArea");
    MarkNativeAsOptional("TheNavMesh.PlaceToName");
    MarkNativeAsOptional("TheNavMesh.GetNearestNavArea");
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
