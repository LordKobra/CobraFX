////////////////////////////////////////////////////////////////////////////////////////////////////////
// Realistic Long-Exposure (RealLongExposure.fx) by SirCobra
// Version 0.4.1 COBRA_RLE_VERSION
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// RealLongExposure.fx enables you to capture changes over time, like in long-exposure photography.
// It will record the game's output for a user-defined amount of seconds, to create the final image,
// just as a camera would do in real life.
////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//                                            Defines & UI
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// Shader Start
// Defines
#define COBRA_RLE_VERSION "0.4.1"
#define COBRA_RLE_UI_GENERAL "\n / General Options /\n"
#define COBRA_RLE_TIME_MAX 8388608.0 // 2^23 / not configurable

// Includes

#include "Reshade.fxh"

uniform float timer <
    source = "timer";
> ;

// Namespace Everything!

namespace COBRA_RLE
{
    // UI

    uniform float UI_ExposureDuration <
        ui_label     = " Exposure Duration";
        ui_type      = "slider";
        ui_spacing   = 2;
        ui_min       = 0.1;
        ui_max       = 120.0;
        ui_step      = 0.1;
        ui_tooltip   = "Exposure duration in seconds.";
        ui_category  = COBRA_RLE_UI_GENERAL;
    >                = 1.0;

    uniform bool UI_StartExposure <
        ui_label     = " Start Exposure";
        ui_tooltip   = "Click to start the exposure process. It will run for the given amount of seconds and then freeze.\nTIP: Bind this to a hotkey for convenient usage (right-click the button).";
        ui_category  = COBRA_RLE_UI_GENERAL;
    >                = false;

    uniform bool UI_ShowGreenOnFinish <
        ui_label     = " Show Green Dot On Finish";
        ui_tooltip   = "Display a green dot at the top to signalize the exposure has finished and entered preview mode.";
        ui_category  = COBRA_RLE_UI_GENERAL;
    >                = false;

    uniform float UI_ISO <
        ui_label     = " ISO";
        ui_type      = "slider";
        ui_min       = 100.0;
        ui_max       = 1600.0;
        ui_step      = 1.0;
        ui_tooltip   = "Sensitivity to light. 100 is normalized to the game. 1600 is 16 times the sensitivity.";
        ui_category  = COBRA_RLE_UI_GENERAL;
    >                = 100.0;

    uniform float UI_Gamma <
        ui_label     = " Gamma";
        ui_type      = "slider";
        ui_min       = 0.4;
        ui_max       = 4.4;
        ui_step      = 0.01;
        ui_tooltip   = "The gamma correction value. The default value is 1. The higher this value, the more persistent\nhighlights will be.";
        ui_category  = COBRA_RLE_UI_GENERAL;
    >                = 1.0;

    uniform uint UI_Delay <
        ui_label     = " Delay";
        ui_type      = "slider";
        ui_min       = 0;
        ui_max       = 100;
        ui_step      = 1;
        ui_tooltip   = "The delay before exposure starts in milliseconds.";
        ui_category  = COBRA_RLE_UI_GENERAL;
    >                = 1;

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " Shader Version: " COBRA_RLE_VERSION;
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
    texture TEX_ExposureCopy
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA32F;
    };
    texture TEX_Timer
    {
        Width  = 2;
        Height = 1;
        Format = R32F;
    };
    texture TEX_TimerCopy
    {
        Width  = 2;
        Height = 1;
        Format = R32F;
    };

    // Sampler

    sampler2D SAM_Exposure
    {
        Texture = TEX_Exposure;
    };
    sampler2D SAM_ExposureCopy
    {
        Texture = TEX_ExposureCopy;
    };
    sampler2D SAM_Timer
    {
        Texture = TEX_Timer;
    };
    sampler2D SAM_TimerCopy
    {
        Texture = TEX_TimerCopy;
    };

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    float encode_timer(float value)
    {
        return value / COBRA_RLE_TIME_MAX;
    }

    float decode_timer(float value)
    {
        return value * COBRA_RLE_TIME_MAX;
    }

    // return the exposure weight of a single frame
    float4 get_exposure(float4 value)
    {
        float iso_norm = UI_ISO / 100.0;
        value.rgb      = iso_norm * pow(abs(value.rgb), UI_Gamma) / 14400.0;
        return value;
    }

    // show the green dot signalizing the frame is finished
    float4 show_green(float2 texcoord, float4 fragment)
    {
        const float2 POS  = float2(0.5, 0.06);
        const float RANGE = 0.02;
        if (sqrt((POS.x - texcoord.x) * (POS.x - texcoord.x) + (POS.y - texcoord.y) * (POS.y - texcoord.y)) < RANGE)
        {
            fragment = float4(0.5, 1.0, 0.5, 1.0);
        }

        return fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void PS_LongExposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        float start_time    = decode_timer(tex2Dfetch(SAM_Timer, int2(0, 0)).r);
        float frame_counter = decode_timer(tex2Dfetch(SAM_Timer, int2(1, 0)).r);
        int2 intcoords      = floor(texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT));
        float4 game_rgb     = tex2Dfetch(ReShade::BackBuffer, intcoords);
        game_rgb            = get_exposure(game_rgb);
        fragment            = tex2Dfetch(SAM_ExposureCopy, intcoords);
        // during exposure: active -> add rgb, inactive -> keep current
        // after exposure: reset so it is ready for activation
        if (UI_StartExposure && abs(timer - start_time) > UI_Delay)
        {
            if (abs(timer - start_time) < 1000 * UI_ExposureDuration)
            {
                fragment.rgb += game_rgb.rgb;
            }
        }
        else
        {
            fragment = float4(0, 0, 0, 1);
        }
    }

    void PS_CopyExposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        int2 intcoords = floor(texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT));
        fragment       = tex2Dfetch(SAM_Exposure, intcoords);
    }

    void PS_UpdateTimer(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        // timer 2x1
        // value 1: starting point - modified while shader offline - frozen on activation of StartExposure
        // value 2: framecounter - 0 while offline - counting up while online
        float start_time    = decode_timer(tex2Dfetch(SAM_TimerCopy, int2(0, 0)).r);
        float frame_counter = decode_timer(tex2Dfetch(SAM_TimerCopy, int2(1, 0)).r);
        float new_value;
        if (texcoord.x < 0.5)
        {
            new_value = UI_StartExposure ? start_time : timer;
        }
        else
        {
            if (abs(timer - start_time) < 1000 * UI_ExposureDuration)
            {
                new_value = (UI_StartExposure && abs(timer - start_time) > UI_Delay) ? frame_counter + 1 : 0;
            }
            else
            {
                new_value = UI_StartExposure ? frame_counter : 0;
            }
        }

        fragment = encode_timer(new_value);
    }

    void PS_CopyTimer(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        fragment = tex2D(SAM_Timer, texcoord).r;
    }

    void PS_DisplayExposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        int2 intcoords      = floor(texcoord * float2(BUFFER_WIDTH, BUFFER_HEIGHT));
        float4 exposure_rgb = tex2Dfetch(SAM_Exposure, intcoords);
        float4 game_rgb     = tex2Dfetch(ReShade::BackBuffer, intcoords);
        game_rgb.a          = 1.0;
        float start_time    = decode_timer(tex2Dfetch(SAM_Timer, int2(0, 0)).r);
        float frame_counter = decode_timer(tex2Dfetch(SAM_Timer, int2(1, 0)).r);
        float4 result       = float4(0, 0, 0, 1);
        if (UI_StartExposure && frame_counter)
        {
            result.rgb = exposure_rgb.rgb * (14400 / frame_counter);
            result.rgb = pow(abs(result.rgb), 1 / UI_Gamma);
        }
        else
        {
            result = game_rgb;
        }

        fragment = ((int)UI_ShowGreenOnFinish * (int)UI_StartExposure * (int)(timer - start_time > 1000 * UI_ExposureDuration)) ? show_green(texcoord, result) : result;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_RealLongExposure <
        ui_label     = "Realistic Long-Exposure";
        ui_tooltip   = "------About-------\n"
                       "RealLongExposure.fx enables you to capture changes over time, like in long-exposure photography.\n"
                       "It will record the game's output for a user-defined amount of seconds, to create the final image,\n"
                       "just as a camera would do in real life.\n\n"
                       "Version:    " COBRA_RLE_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass LongExposure
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_LongExposure;
            RenderTarget = TEX_Exposure;
        }
        pass CopyExposure
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_CopyExposure;
            RenderTarget = TEX_ExposureCopy;
        }
        pass UpdateTimer
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_UpdateTimer;
            RenderTarget = TEX_Timer;
        }
        pass CopyTimer
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_CopyTimer;
            RenderTarget = TEX_TimerCopy;
        }
        pass DisplayExposure
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_DisplayExposure;
        }
    }
}
