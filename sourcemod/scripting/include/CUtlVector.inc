#if defined _CUtlVector_included
 #endinput
#endif
#define _CUtlVector_included

methodmap CUtlVector
{
    public CUtlVector(Address address)
    {
        return view_as<CUtlVector>(address);
    }
    
    property int size
    {
        public get()
        {
            return LoadFromAddress(view_as<Address>(this) + view_as<Address>(0xC), NumberType_Int32);
        }
    }
    
    property Address elements
    {
        public get()
        {
            return LoadFromAddress(view_as<Address>(this), NumberType_Int32);
        }
    }
    
    public any Get(int index, int size = 4)
    {
        return LoadFromAddress(this.elements + view_as<Address>(index * size), NumberType_Int32);
    }
    
    public int Find(any value)
    {
        int max = this.size;
        
        for (int current_element; current_element < max; current_element++)
        {
            if (this.Get(current_element) == value)
            {
                return current_element;
            }
        }
        
        return -1;
    }
}