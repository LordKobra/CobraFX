/////////////////////////////////////////////////////////
// Long Exposure (LongExposure.fx) by SirCobra
// Version 0.1.1
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// OUTDATED: This shader is outdated. Visit the repository for its successor:
// "RealLongExposure.fx".
//
// There are two modes: Filter by brightness or all colors.
// If you filter by brightness, brighter pixels will stay longer in the frame.
//
// If you do not filter by brightness, every change will have an impact.
// To preserve every change on a static scenery, it is recommended to freeze the current image and not move the camera.
// It will give the shader an expectation of the original image, so it can better keep track of changes.
// Exposure Duration and Precision will let you decide how long the effect should stay.
/////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//                                            Defines & UI
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// Shader Start
// Defines

#ifndef M_PI
	#define M_PI 3.1415927
#endif

// Includes
#include "Reshade.fxh"

// Namespace Everything!

namespace COBRA_LE
{
    // UI

    uniform float UI_ExposureDuration <
		ui_label     = " Exposure Duration";
        ui_type 	= "slider";
        ui_min      = 0.000;
        ui_max      = 1.000;
        ui_step     = 0.001;
        ui_tooltip  = "Exposure duration. 0 means no duration, 1 means infinite duration.";
    >           	= 0.5;

    uniform float UI_Precision <
		ui_label     = " Precision";
        ui_type 	= "slider";
        ui_min      = 1;
        ui_max      = 10;
        ui_step     = 1;
        ui_tooltip  = "Scaling precision for longer exposures. 1 means high precision on\nlow exposures, 10 high precision on high exposures.";
    >           	= 1;

    uniform float UI_Intensity <
		ui_label     = " Intensity";
        ui_type 	= "slider";
        ui_min      = 0.000;
        ui_max      = 1.000;
        ui_step     = 0.001;
        ui_tooltip  = "Exposure intensity. 0 means no changes at all, 1 means instant changes.";
    >           	= 0.33;

    uniform bool UI_ByBrightness <
		ui_label     = " Brightness Mode";
        ui_tooltip = "Turn off to capture all colors. Turn on to go by brightness only.\n";
    >              = false;

    uniform bool UI_Freeze <
		ui_label     = " Freeze Scene";
        ui_tooltip = "Freezes the scene. Do this on a static scene without moving the camera, so the shader can better preserve changes.\n";
    >              = false;

    uniform float UI_FreezeThreshold <
		ui_label     = " Freeze Threshold";
        ui_type 	= "drag";
        ui_min      = 0.00;
        ui_max      = 1;
        ui_step     = 0.01;
        ui_tooltip  = "This determines the minimum difference in color necessary to overwrite the frozen image.";
    >           	= 0.00;

    uniform int UI_BufferEnd <
        ui_type 	= "radio";
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
        Format = RGBA16;
    };
    texture TEX_ExposureCopy
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16;
    };
    texture TEX_Freeze
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };
    texture TEX_FreezeCopy
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA8;
    };

    // Sampler
    
    sampler2D SAM_Exposure { Texture = TEX_Exposure; };
    sampler2D SAM_ExposureCopy { Texture = TEX_ExposureCopy; };
    sampler2D SAM_Freeze { Texture = TEX_Freeze; };
    sampler2D SAM_FreezeCopy { Texture = TEX_FreezeCopy; };

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    float4 mix_color(float4 b, float4 o, float4 s) // base, original, sample
    {
        const float E2 = sqrt(saturate(1 - (UI_ExposureDuration - 1) * (UI_ExposureDuration - 1))); // saturate(tan(1.471*(ExposureDuration - 1)) / 10 + 1);
        float4 output_color;
        if (UI_ByBrightness)
        {
            output_color.rgb = (dot(o.rgb,1) < dot(s.rgb,1)) ? o.rgb + UI_Intensity * abs(s.rgb - o.rgb) : o.rgb - (1/ UI_Precision * (1 - E2)) * abs(s.rgb-o.rgb);
        }
        else
        {
            if (UI_Freeze) // base.r check diff originalColor sampleColor to r d(base,sample) d(base, original) if d_bs < d_bo, keep, else increase by d_bo+q*(d_bs-d_bo or fixed)
            {
                float d_bs = abs(b.r - s.r) + abs(b.g - s.g) + abs(b.b - s.b);
                // application
                output_color.rgb = o.rgb + (s.rgb-o.rgb) * UI_Intensity * saturate(d_bs / 3 - UI_FreezeThreshold);
                // degradation
                output_color.rgb -=(output_color.rgb - b.rgb) * (1 / UI_Precision * (1 - E2));
            }
            else
            {
                output_color.r = (o.r < s.r) ? o.r + (1 / UI_Precision * (1 - E2)) * abs(s.r - o.r) : o.r - (1 / UI_Precision * (1 - E2)) * abs(s.r - o.r);
                output_color.g = (o.g < s.g) ? o.g + (1 / UI_Precision * (1 - E2)) * abs(s.g - o.g) : o.g - (1 / UI_Precision * (1 - E2)) * abs(s.g - o.g);
                output_color.b = (o.b < s.b) ? o.b + (1 / UI_Precision * (1 - E2)) * abs(s.b - o.b) : o.b - (1 / UI_Precision * (1 - E2)) * abs(s.b - o.b);
            }
        }
        output_color.a = 1.0;
        return output_color;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void PS_LongExposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        float4 sample_color  = tex2D(ReShade::BackBuffer, texcoord);
        float4 current_color = tex2D(SAM_ExposureCopy, texcoord);
        float4 base_color    = tex2D(SAM_Freeze, texcoord);
        current_color        = mix_color(base_color, current_color, sample_color);
        fragment            = current_color;
    }
    
    void PS_CopyExposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = tex2D(SAM_Exposure, texcoord);
    }

    void PS_Freeze(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = UI_Freeze ? tex2D(SAM_FreezeCopy, texcoord) : tex2D(ReShade::BackBuffer, texcoord);
    }

    void PS_CopyFreeze(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = tex2D(SAM_Freeze, texcoord);
    }

    void PS_DownsampleColor(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = tex2D(SAM_Exposure, texcoord);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_LongExposure <
        ui_label     = "Long-Exposure";
        ui_tooltip   = "------About-------\n"
                       "OUTDATED: This shader is outdated. Visit the repository for its successor: RealLongExposure.fx\n"
                       "LongExposure.fx enables you to capture visual changes over time.\n"
                       "There are two modes: Filter by brightness or all colors. If you filter by brightness,\n"
                       "brighter pixels will stay longer in the frame. If you do not filter by brightness,\n"
                       "every change will have an impact.\n"
                       "To preserve every change on a static scenery, it is recommended to freeze the current\n"
                       "image and not move the camera. It will give the shader an expectation of the original image,\n"
                       "so it can better keep track of changes.\n"
                       "Exposure duration and precision will let you decide how long the effect should stay.\n\n"
                       "Version:    0.1.1\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass Freeze
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_Freeze;
            RenderTarget = TEX_Freeze;
        }
        pass CopyFreeze
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_CopyFreeze;
            RenderTarget = TEX_FreezeCopy;
        }
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
        pass DownsampleColor
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_DownsampleColor;
        }
    }

}
