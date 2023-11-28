////////////////////////////////////////////////////////////////////////////////////////////////////////
// Frequency (Frquency_CS.fx) by SirCobra
// Version 0.1.0
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// Frequency_CS.fx creates an effect also known as `Frequency Modulation`, which
// scans the image from left to right and releases a wave whenever a luminance-
// based threshold is reached. The pixel luminance is summed up and modulated
// depending on a given period. Additional parameters give the effect a unique
// look. A masking stage enables filtering affected colors and depth.
// 
// ----------Credits-----------
// Thanks to...
// ... TeoTave for introducing me to this effect!
// ... https://dominik.ws/art/movingdots/ for showcasing a concrete example on how the effect can look!
// ... Marty McFly, Lord of Lunacy and CeeJayDK for technical discussions.
////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "Reshade.fxh"

uniform float timer <
    source = "timer";
> ;

// Shader Start

//  Namespace everything!

namespace COBRA_XFRQ
{

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                            Defines & UI
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Defines

    #define COBRA_XFRQ_VERSION "0.1.0"
    #define COBRA_UTL_MODE 0
    #include ".\CobraUtility.fxh"

    #define COBRA_XFRQ_THREADS 64
    #define COBRA_XFRQ_DISPATCHES ROUNDUP(BUFFER_HEIGHT, COBRA_XFRQ_THREADS)

    // We need Compute Shader Support
    #if (((__RENDERER__ >= 0xb000 && __RENDERER__ < 0x10000) || (__RENDERER__ >= 0x14300)) && __RESHADE__ >= 40800)
        #define COBRA_XFRQ_COMPUTE 1
    #else
        #define COBRA_XFRQ_COMPUTE 0
        #warning "Frequency.fx does only work with ReShade 4.8 or newer, DirectX 11 or newer, OpenGL 4.3 or newer and Vulkan."
    #endif

    #if COBRA_XFRQ_COMPUTE != 0

    // Includes

    // UI

    uniform uint UI_Frequency <
        ui_label     = " Period";
        ui_type      = "slider";
        ui_spacing   = 2;
        ui_min       = 1;
        ui_max       = 200;
        ui_step      = 1;
        ui_tooltip   = "Determines the frequency of the wave appearance. Low values let the wave appear in\n"
                       "short intervals.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >            = 10;

    uniform float UI_Thickness <
        ui_label     = " Thickness";
        ui_type      = "slider";
        ui_min       = 1;
        ui_max       = 100;
        ui_step      = 1;
        ui_units     = "px";
        ui_tooltip   = "The thickness of the wave in pixel.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 2;

    uniform float UI_Gamma <
        ui_label     = " Gamma";
        ui_type      = "slider";
        ui_min       = 0.4;
        ui_max       = 4.4;
        ui_step      = 0.01;
        ui_tooltip   = "The gamma correction value. The default value is 1. The higher this value, the more persistent\n"
                       "highlights will be.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.5;

    uniform float UI_BaseIncrease <
        ui_label     = " Base Increase";
        ui_type      = "slider";
        ui_min       = 0.00;
        ui_max       = 10.00;
        ui_step      = 0.01;
        ui_tooltip   = "This value is added to every pixel to create a base frequency independent of the image.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.150;

    uniform bool UI_BaseMultiply <
        ui_label     = " Multiply Base with Background";
        ui_tooltip   = "The base value is multiplied with the scene value to depend on the image content.\n"
                       "It now serves as a multiplier of the image value.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    uniform float UI_Decay <
        ui_label     = " Decay";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "Decay of the wave frequency after each wave. Highly instable, but can produce\n"
                       "interesting results. Not recommended above with animated waves.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >            = 0.000;

    uniform float UI_Offset <
        ui_label     = " Offset";
        ui_type      = "slider";
        ui_min       = 0.00;
        ui_max       = 100.0;
        ui_step      = 0.1;
        ui_units     = "%%";
        ui_tooltip   = "Initial offset of the first wave.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.00;

    uniform int UI_BlendMode <
        ui_label     = " Blend Mode";
        ui_type      = "combo";
        ui_items     = "Tint\0Color\0Value\0";
        ui_tooltip   = "The blend mode applied to the wave.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 2;

    uniform float3 UI_EffectTint <
        ui_label     = " Tint";
        ui_type      = "color";
        ui_tooltip   = "Specifies the tint of the wave, when blend mode is set to tint.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = float3(1.00, 0.50, 0.50);

    uniform float UI_Transparency <
        ui_label     = " Black Transparency";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 100.0;
        ui_step      = 0.1;
        ui_units     = "%%";
        ui_tooltip   = "Transparency of the area not affected by the waves.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.0;

    uniform uint UI_RotationType <
        ui_label     = " Direction";
        ui_type      = "combo";
        ui_items     = "Left\0Bottom\0Right\0Top\0";
        ui_tooltip   = "The direction from which the effect starts.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0;

    uniform int UI_Blur <
        ui_label     = " Blur";
        ui_type      = "combo";
        ui_items     = "None\0Two\0Four\0Six\0Eight\0";
        ui_tooltip   = "The blur applied to the input. Higher values smoothen the wave.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 2;

    uniform bool UI_Animate <
        ui_label     = " Animate";
        ui_tooltip   = "Make the wave move with time.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = true;

    uniform bool UI_Invert <
        ui_label     = " Invert";
        ui_tooltip   = "Invert the wave.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    uniform bool UI_UseDepth <
        ui_label     = " Use Depth";
        ui_tooltip   = "The waves will respond to scene depth instead of the scene luminance.\n"
                       "Requires a working depth buffer.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    uniform float UI_DepthMultiplier <
        ui_label     = " Depth Multiplier";
        ui_type      = "slider";
        ui_min       = 0.01;
        ui_max       = 10.00;
        ui_tooltip   = "Multiplier of the depth value when depth is used.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 1.0;

    uniform float UI_Sensitivity <
        ui_label     = " Sensitivity";
        ui_type      = "slider";
        ui_min       = 0.001;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = " Keep this value at 0.5, unless you got flickering.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = 0.500;

    uniform bool UI_HotsamplingMode <
        ui_label     = " Hotsampling Mode";
        ui_tooltip   = "Activate this, then adjust your options and the effect will stay similar at\n"
                       "all resolutions. Turn this off when you do not intend to hotsample.";
        ui_category  = COBRA_UTL_UI_GENERAL;
    >                = false;

    #define COBRA_UTL_MODE 1
    #include ".\CobraUtility.fxh"

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " Shader Version: " COBRA_XFRQ_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                             Textures & Samplers & Storage & Shared Memory
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture TEX_Frequency
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R8;
    };

    texture TEX_Mask
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = R16F;
    };

    // Sampler

    sampler2D SAM_Frequency { Texture = TEX_Frequency; };
    sampler2D SAM_Mask { Texture = TEX_Mask; };

    // Storage

    storage STOR_Frequency { Texture = TEX_Frequency; };
    storage STOR_Mask { Texture = TEX_Mask; };

    // Groupshared Memory

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    #define COBRA_UTL_MODE 2
    #define COBRA_UTL_COLOR 1
    #include "CobraUtility.fxh"

    // rotate the screen
    float2 rotate(float2 texcoord1, bool revert)
    {
        float2 texcoord = texcoord1.xy;
        uint ANGLE      = UI_RotationType * 90 + (360 - 2 * UI_RotationType * 90) * revert;
        float2 rotated  = texcoord;

        // easy cases to avoid dividing by zero; values 0 & 360 are trivial
        rotated = (ANGLE == 90) ? float2(texcoord.y, 1 - texcoord.x) : rotated;
        rotated = (ANGLE == 180) ? float2(1 - texcoord.x, 1 - texcoord.y) : rotated;
        rotated = (ANGLE == 270) ? float2(1 - texcoord.y, texcoord.x) : rotated;
        return rotated.xy;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void VS_Clear(in uint id : SV_VertexID, out float4 position : SV_Position)
    {
        position = -3.0;
    }

    void PS_Clear(float4 position : SV_Position, out float4 fragment : SV_TARGET0)
    {
        fragment = 0.0;
        discard;
    }

    void PS_Mask(float4 vpos : SV_Position, out float fragment : SV_TARGET)
    {
        float val    = 0.0;
        uint counter = 0;
        [unroll] for (int i = -8; i <= 8; i++)
        {
            if (((vpos.y + i) > 0) && ((vpos.y + i) < BUFFER_HEIGHT) && (abs(i) <= (2 * UI_Blur)))
            {
                float2 texcoord = (vpos.xy + int2(0, i)) / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
                texcoord        = rotate(texcoord, false);
                float3 rgb      = tex2D(ReShade::BackBuffer, texcoord).rgb;
                float depth     = ReShade::GetLinearizedDepth(texcoord);
                float f         = check_focus(rgb, depth, texcoord);
                if (f)
                {
                    val += UI_UseDepth ? f * UI_DepthMultiplier * pow(abs(depth), UI_Gamma) : f * dot(pow(abs(rgb), UI_Gamma), 1.0);
                    counter++;
                }
            }
        }

        float HS_MULT       = UI_HotsamplingMode ? 1920.0 / BUFFER_WIDTH : 1.0;
        fragment            = val / max(counter, 0.5);
        float intermediate  = UI_BaseMultiply ? fragment : 1.0;
        fragment            = fragment + UI_BaseIncrease * intermediate;
        fragment           *= HS_MULT;
    }

    void CS_Frequency(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        if (id.y >= BUFFER_HEIGHT)
            return;

        float accum      = UI_Offset / 100.0 * UI_Frequency - (UI_Animate * timer / 1000.0);
        float decay      = 1.0;
        uint remaining   = 0;
        bool was_blended = false;
        for (uint i = 0; i < BUFFER_WIDTH; i++)
        {
            float val = tex2Dfetch(SAM_Mask, int2(i, id.y)).r;
            accum += val;

            if (fmod(accum, UI_Frequency * decay) > UI_Sensitivity * UI_Frequency)
            {
                was_blended = true;
            }
            else if (was_blended)
            {
                remaining = UI_HotsamplingMode ? UI_Thickness * float(BUFFER_WIDTH) / 1920.0 : UI_Thickness;
                decay *= 1.0 + UI_Decay;
                was_blended = false;
            }

            if (remaining > 0)
            {
                remaining--;
                tex2Dstore(STOR_Frequency, int2(i, id.y), 1.0);
            }
        }
    }

    // reproject to output window
    void PS_PrintFrequency(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        float3 value        = tex2Dfetch(ReShade::BackBuffer, floor(vpos.xy)).rgb;
        float3 intermediate = UI_BlendMode == 2 ? dot(value.rgb, 1.0) / 3.0 : value;
        intermediate        = UI_BlendMode == 0 ? UI_EffectTint : intermediate;
        float2 texcoord_new = rotate(texcoord, true);
        float intensity     = tex2D(SAM_Frequency, texcoord_new).r;
        intensity           = intensity + (1.0 - 2.0 * intensity) * UI_Invert;
        fragment.rgb        = intensity * intermediate + (1.0 - intensity) * value * UI_Transparency / 100.0;
        fragment.a          = 1.0;
        fragment.rgb        = UI_ShowMask ? 1.0 - tex2D(SAM_Mask, texcoord_new).rrr : fragment.rgb;
        fragment            = (UI_ShowSelectedHue * UI_FilterColor) ? show_hue(texcoord, fragment) : fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_Frequency <
        ui_label     = "Frequency";
        ui_tooltip   = "------About-------\n"
                       "Frequency_CS.fx creates an effect also known as 'Frequency Modulation', which\n"
                       "scans the image from left to right and releases a wave whenever a luminance-\n"
                       "based threshold is reached. The pixel luminance is summed up and modulated\n"
                       "depending on a given period. Additional parameters give the effect a unique\n"
                       "look. A masking stage enables filtering affected colors and depth.\n\n"
                       "Version:    " COBRA_XFRQ_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass Mask
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_Mask;
            RenderTarget = TEX_Mask;
        }

        pass PrepareFrequency
        {
            VertexShader       = VS_Clear;
            PixelShader        = PS_Clear;
            RenderTarget0      = TEX_Frequency;
            ClearRenderTargets = true;
            PrimitiveTopology  = POINTLIST;
            VertexCount        = 1;
        }

        pass Frequency
        {
            ComputeShader = CS_Frequency<1, COBRA_XFRQ_THREADS>;
            DispatchSizeX = 1;
            DispatchSizeY = COBRA_XFRQ_DISPATCHES;
        }

        pass PrintFrequency
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_PrintFrequency;
        }
    }

#endif // Shader End

} // Namespace End

/*-------------.
| ::  TODO  :: |
'--------------/

* RGB channels independent
* full rotation support
* hotsampling
* mask displacement (2 Techniques)
* 3rd Technique for Frequency AA
*/
