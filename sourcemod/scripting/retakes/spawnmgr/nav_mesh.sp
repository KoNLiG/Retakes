/*
 * • 
 */

#assert defined COMPILING_FROM_MAIN

enum
{
    OS_LINUX, 
    OS_WINDOWS
}

methodmap BaseGameDataAddressObject
{
    property GameData gamedata
    {
        public get()
        {
            static GameData gamedata;
            if (!gamedata) 
            { 
                gamedata = new GameData("retakes.games");
            }

            return gamedata;
        }
    }

    public Address GetGameDataAddress(char[] name)
    {
        Address addr = this.gamedata.GetAddress(name);
        if (addr == Address_Null)
        {
            ThrowError("GameData Address \"%s\" was not found!", name);
        }

        return addr;
    }

    public int GetGameDataOffset(char[] name)
    {
        int offset = this.gamedata.GetOffset(name);
        if (offset == -1)
        {
            ThrowError("GameData Offset \"%s\" was not found!", name);
        }

        return offset;
    }
}

methodmap CUtlVector < BaseGameDataAddressObject
{
    public int Count()
    {
        static int count_offset;
        if (!count_offset)
        {
            count_offset = this.gamedata.GetOffset("CUtlVector::Count");
        }

        return LoadFromAddress(view_as<Address>(this) + view_as<Address>(count_offset), NumberType_Int32);
    }
}

methodmap NavArea < BaseGameDataAddressObject
{
    public void GetRandomPoint(float pos[3])
    {
        static Handle NavArea_GetRandomPointFunction;
        if (!NavArea_GetRandomPointFunction)
        {
            // Vector GetRandomPoint( void ) const;
            StartPrepSDKCall(SDKCall_Raw);
            PrepSDKCall_SetFromConf(this.gamedata, SDKConf_Signature, "NavArea::GetRandomPoint");
            // Vector
            PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByValue);
            
            if (!(NavArea_GetRandomPointFunction = EndPrepSDKCall()))
            {
                SetFailState("Missing signature 'NavArea::GetRandomPoint'");
            }
        }

        SDKCall(
            NavArea_GetRandomPointFunction, // sdkcall function
            this,                           // this
            pos, sizeof(pos)                // return vector
        );
    }

    public int GetPlace()
    {
        static int m_placeOffset;
        if (!m_placeOffset)
        {
            m_placeOffset = this.GetGameDataOffset("NavArea::m_place");
        }

        return LoadFromAddress(view_as<Address>(this) + view_as<Address>(m_placeOffset), NumberType_Int32);
    }
}

methodmap TheNavMesh < BaseGameDataAddressObject
{
    public TheNavMesh Initialize()
    {
        return view_as<TheNavMesh>(this.GetGameDataAddress("TheNavMesh"));
    }
    
    public int PlaceToName(int place_index, char[] buffer, int buf_size)
    {
        // The operation system of the server,
        // this is needed because `CNavMesh::PlaceToName` takes |this| ptr only for Linux.
        static int os;
        if (!os)
        {
            os = this.GetGameDataOffset("OS");
        }

        static Handle CNavMesh_PlaceToNameFunc;
        if (!CNavMesh_PlaceToNameFunc)
        {
            // Setup `CNavMesh_PlaceToName` SDKCall.
            // const char *CNavMesh::PlaceToName( Place place ) const
            
            // Linux takes |this| ptr, Windows doesn't.
            StartPrepSDKCall(os == OS_LINUX ? SDKCall_Raw : SDKCall_Static);
            PrepSDKCall_SetFromConf(this.gamedata, SDKConf_Signature, "CNavMesh::PlaceToName");
            // Place place (Place == unsigned int)
            PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
            // const char*
            PrepSDKCall_SetReturnInfo(SDKType_String, SDKPass_Pointer);
            
            if (!(CNavMesh_PlaceToNameFunc = EndPrepSDKCall()))
            {
                SetFailState("Missing signature 'CNavMesh::PlaceToName'");
            }
        }

        // Call `CNavMesh::PlaceToName`
        // For Linux, we need to pass |this| ptr.
        if (os == OS_LINUX)
        {
            SDKCall(
                CNavMesh_PlaceToNameFunc,
                this,
                buffer,
                buf_size,
                place_index
            );
        }
        else // Otherwise, we are on Windows. 
        {
            // Windows doesn't need |this| ptr.
            SDKCall(
                CNavMesh_PlaceToNameFunc,
                buffer,
                buf_size,
                place_index
            );
        }
        
        return strlen(buffer);
    }
}

methodmap TheNavAreas < CUtlVector
{
    public TheNavAreas Initialize()
    {
        return view_as<TheNavAreas>(this.GetGameDataAddress("TheNavAreas"));
    }

    public NavArea GetArea(int area_index)
    {
        if (0 <= area_index < this.Count())
        {
            // Dereference the vector element + offset * 4 bytes.
            return LoadFromAddress(
                // Dereference the vector member at offset 0.
                LoadFromAddress(
                    view_as<Address>(this),
                    NumberType_Int32
                ) + view_as<Address>(area_index * 4),
                NumberType_Int32
            );
        }
        
        return view_as<NavArea>(Address_Null);
    }
}

TheNavAreas g_TheNavAreas;
TheNavMesh g_TheNavMesh;

void InitializeNavMesh()
{
    g_TheNavMesh = g_TheNavMesh.Initialize();
    g_TheNavAreas = g_TheNavAreas.Initialize();
}