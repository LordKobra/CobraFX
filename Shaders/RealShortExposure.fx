////////////////////////////////////////////////////////////////////////////////////////////////////////
// Real Short Exposure  AKA Motion Blur (RealShortExposure.fx) by SirCobra
// Version 0.2.1
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
// --------Description---------
// This shader blends the last few frames together, to create a continuos version of the
// RealLongExposure.fx effect. This can also be considered as motion blur.
// ----------Credits-----------
// Thanks to Lord of Lunacy and Marty McFly for various tips!
////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "Reshade.fxh"
uniform uint framecount < source = "framecount";
> ;

// Shader Start

// Namespace Everything

namespace ShortExposure
{

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                            Defines & UI
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Defines

    #define COBRA_RSE_VERSION "0.1.1"
    #define COBRA_UTL_MODE 0
    #include ".\CobraUtility.fxh"

    // We need Compute Shader Support
    #if (((__RENDERER__ >= 0xb000 && __RENDERER__ < 0x10000) || (__RENDERER__ >= 0x14300)) && __RESHADE__ >= 40800)
        #define COBRA_RSE_COMPUTE 1
    #else
        #define COBRA_RSE_COMPUTE 0
        #warning "RealShortExposure.fx does only work with ReShade 4.8 or newer, DirectX 11 or newer, OpenGL 4.3 or newer and Vulkan."
    #endif

    #define COBRA_RSE_YSIZE 20

    // UI

    uniform uint UI_Frames <
        ui_label     = " Frames";
        ui_type      = "slider";
        ui_spacing   = 2;
        ui_min       = 1;
        ui_max       = 8;
        ui_step      = 1;
        ui_tooltip   = "The amount of frames to blend in the buffer.";
    >                = 4;

    uniform float UI_Gamma <
        ui_label     = " Gamma";
        ui_type      = "slider";
        ui_min       = 0.4;
        ui_max       = 4.4;
        ui_step      = 0.01;
        ui_tooltip   = "The gamma correction value. The default value is 1. The higher this value, the more persistent\n"
                       "highlights will be.";
    >                = 1.0;

    uniform int UI_BufferEnd <
        ui_type      = "radio";
        ui_spacing  = 2;
        ui_text     = " Shader Version: " COBRA_RSE_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                         Textures & Samplers
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture TEX_Exposure
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA32F;
    };

    texture TEX_Exposure2
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA32F;
    };

    sampler2D SAM_Exposure
    {
        Texture   = TEX_Exposure;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    sampler2D SAM_Exposure2
    {
        Texture   = TEX_Exposure2;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };
    // Storage

    storage2D<float4> STOR_Exposure { Texture = TEX_Exposure; };
    storage2D<float4> STOR_Exposure2 { Texture = TEX_Exposure2; };

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    #define COBRA_UTL_MODE 2
    #include ".\CobraUtility.fxh"

    float4 get_exposure(float4 value)
    {
        return pow(abs(value.rgba), UI_Gamma);
    }

    void encode_position(inout float4 source, inout float4 source2, float3 value, uint index)
    {
        uint4 idv     = uint4(3, 2, 1, 0) == index;
        uint4 idr     = uint4(3, 2, 1, 0) > UI_Frames - 1;
        uint4 idv2    = uint4(7, 6, 5, 4) == index;
        uint4 idr2    = uint4(7, 6, 5, 4) > UI_Frames - 1;
        uint3 ival    = value * 255.9999847412109375;
        float encoded = ival.x << 16u | ival.y << 8u | ival.z;
        source        = idv * encoded + (1 - idv - idr) * source;
        source2       = idv2 * encoded + (1 - idv2 - idr2) * source2;
    }

    float3 decode_values(float4 source)
    {
        uint4 usource = uint4(source);
        float4 r      = (usource >> 16u) / 255.9999847412109375;
        float4 g      = ((usource >> 8u) % 256) / 255.9999847412109375;
        float4 b      = (usource % 256) / 255.9999847412109375;
        float3 result;
        result.r = dot(get_exposure(r), 1.0);
        result.g = dot(get_exposure(g), 1.0);
        result.b = dot(get_exposure(b), 1.0);
        return result;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void CS_ShortExposure(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID, uint gi : SV_GroupIndex)
    {
        [branch] if (any(id.xy >= BUFFER_SCREEN_SIZE)) return;

        uint index = framecount % UI_Frames;
        uint2 vpos = uint2(id.x, id.y);

        float3 value   = tex2Dfetch(ReShade::BackBuffer, vpos).rgb;
        float4 source  = tex2Dfetch(STOR_Exposure, vpos);
        float4 source2 = tex2Dfetch(STOR_Exposure2, vpos);
        encode_position(source, source2, value, index);

        barrier();
        tex2Dstore(STOR_Exposure, vpos, source);
        tex2Dstore(STOR_Exposure2, vpos, source2);
    }

    vs2ps VS_DisplayExposure(uint id : SV_VertexID)
    {
        vs2ps o = vs_basic(id, 0);
        return o;
    }

    void PS_DisplayExposure(vs2ps o, out float4 fragment : SV_Target)
    {
        float4 source  = tex2Dfetch(SAM_Exposure, int2(floor(o.vpos.xy)));
        float4 source2 = tex2Dfetch(SAM_Exposure2, int2(floor(o.vpos.xy)));
        fragment.rgb   = (decode_values(source) + decode_values(source2)) / UI_Frames;
        fragment.rgb   = pow(abs(fragment.rgb), 1 / UI_Gamma);
        fragment.a     = 1.0;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_RealShortExposure <
        ui_label     = "Real Short Exposure";
        ui_tooltip   = "------About-------\n"
                       "RealShortExposure.fx blends the last few frames together, to create a continuos version of the\n"
                       "RealLongExposure.fx effect. This can also be considered as motion blur.\n\n"
                       "Version:    " COBRA_RSE_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass ShortExposure
        {
            ComputeShader = CS_ShortExposure<8, ROUNDUP(BUFFER_HEIGHT, COBRA_RSE_YSIZE)>;
            DispatchSizeX = ROUNDUP(BUFFER_WIDTH, 8);
            DispatchSizeY = COBRA_RSE_YSIZE;
        }

        pass DisplayExposure
        {
            VertexShader = VS_DisplayExposure;
            PixelShader  = PS_DisplayExposure;
        }
    }
}