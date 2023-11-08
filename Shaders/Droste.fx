////////////////////////////////////////////////////////////////////////////////////////////////////////
// Droste Effect (Droste.fx) by SirCobra
// Version 0.4.1
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// The Droste effect warps the image-space to recursively appear within itself.
////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//                                            Defines & UI
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// Shader Start
// Defines

#define COBRA_DRO_VERSION "0.4.1"
#define COBRA_DRO_UI_GENERAL "\n / General Options /\n"

#ifndef M_PI
    #define M_PI 3.1415927
#endif

#ifndef M_E
    #define M_E 2.71828183
#endif

// Includes

#include "Reshade.fxh"

// Namespace Everything!

namespace COBRA_DRO
{
    // UI

    uniform int UI_EffectType <
        ui_label     = " Effect Type";
        ui_type      = "radio";
        ui_spacing   = 2;
        ui_items     = "Circular\0Rectangular\0";
        ui_tooltip   = "Shape of the recursive appearance.";
        ui_category  = COBRA_DRO_UI_GENERAL;
    >                = 0;

    uniform bool UI_Spiral <
        ui_label     = " Spiral";
        ui_spacing   = 2;
        ui_tooltip   = "Warp space into a spiral.";
        ui_category  = COBRA_DRO_UI_GENERAL;
    >                = true;

    uniform float UI_OuterRing <
        ui_label     = " Outer Ring Size";
        ui_type      = "slider";
        ui_min       = 0.00;
        ui_max       = 1.00;
        ui_step      = 0.01;
        ui_tooltip   = "The outer ring defines the texture border towards the edge of the screen.";
        ui_category  = COBRA_DRO_UI_GENERAL;
    >                = 1.00;

    uniform float UI_Zoom <
        ui_label     = " Zoom";
        ui_type      = "slider";
        ui_min       = 0.00;
        ui_max       = 9.90;
        ui_step      = 0.01;
        ui_tooltip   = "Zoom into the output.";
        ui_category  = COBRA_DRO_UI_GENERAL;
    >                = 1.00;

    uniform float UI_Frequency <
        ui_label     = " Frequency";
        ui_type      = "slider";
        ui_min       = 0.10;
        ui_max       = 5.00;
        ui_step      = 0.01;
        ui_tooltip   = "Defines the frequency of the recursion.";
        ui_category  = COBRA_DRO_UI_GENERAL;
    >                = 1.00;

    uniform float UI_X_Offset <
        ui_label     = " Center Horizontal Offset";
        ui_type      = "slider";
        ui_min       = -0.50;
        ui_max       = 0.50;
        ui_step      = 0.01;
        ui_tooltip   = "Change the horizontal position of the center. Keep it at 0 to get the best results.";
        ui_category  = COBRA_DRO_UI_GENERAL;
    >                = 0.00;

    uniform float UI_Y_Offset <
        ui_label     = " Center Vertical Offset";
        ui_type      = "slider";
        ui_min       = -0.50;
        ui_max       = 0.50;
        ui_step      = 0.01;
        ui_tooltip   = "Change the Y position of the center. Keep it at 0 to get the best results.";
        ui_category  = COBRA_DRO_UI_GENERAL;
    >                = 0.00;

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " Shader Version: " COBRA_DRO_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // normal fmod
    float mod(float x, float y)
    {
        return x - y * floor(x / y);
    }

    // return value -M_PI ~ M_PI
    float atan2_approx(float y, float x)
    {
        return acos(x * rsqrt(y * y + x * x)) * (y < 0 ? -1 : 1);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void PS_Droste(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        // transform coordinate system
        const float2 AR     = UI_EffectType == 0 ? float2(float(BUFFER_WIDTH) / BUFFER_HEIGHT, 1.0) : float2(1.0, 1.0);
        const float2 OFFSET = float2(UI_X_Offset, UI_Y_Offset);
        float2 new_pos      = (texcoord - 0.5 + OFFSET) * AR;

        // calculate orientation of center and pixel
        const float NEW_CENTER_DISTANCE = 2.0 * (0.5 - max(abs(OFFSET.x), abs(OFFSET.y)));
        const float NEW_CENTER_ANGLE    = abs(OFFSET.x) + abs(OFFSET.y) < 0.01 ? 1 : (atan2_approx(-OFFSET.x * AR.x, -OFFSET.y) + M_PI) / (2 * M_PI);
        float angle                     = (atan2_approx(new_pos.x, new_pos.y) + M_PI) / (2 * M_PI);
        angle                           = 1 - mod(abs(abs(angle - NEW_CENTER_ANGLE) - 0.5), 0.5) * 2;

        //smooth off-center projection
        float angle_smooth = (1 - cos(angle * angle * M_PI)) / 2;
        float intensity    = angle_smooth + (1 - angle_smooth) * NEW_CENTER_DISTANCE;

        // calculate and normalize angle
        float val = atan2_approx(new_pos.x, new_pos.y) + M_PI;
        val      /= 2 * M_PI;
        val       = UI_Spiral ? val : 0;

        // calculate distance from center
        float cicle_dist = val + log(sqrt(new_pos.x * new_pos.x + new_pos.y * new_pos.y) / intensity * (10 - UI_Zoom)) * UI_Frequency;
        float rect_dist  = val + log(max(abs(new_pos.x), abs(new_pos.y)) * (10 - UI_Zoom)) * UI_Frequency;
        val              = UI_EffectType == 0 ? cicle_dist : rect_dist;
        val              = (exp(mod(val, 1) / UI_Frequency) - 1) / (exp(1 / UI_Frequency) - 1);

        // normalized vector
        float vector_length     = sqrt(new_pos.x * new_pos.x + new_pos.y * new_pos.y);
        float unit_circle_ratio = UI_EffectType == 0 ? 0.5 / vector_length : 0.5 / max(abs(new_pos.x), abs(new_pos.y));
        float2 normalized       = new_pos * unit_circle_ratio;

        // calculate relative position towards outer and inner ring and interpolate
        const float INNER_RING = 1 / exp(1 / (UI_Frequency)) * UI_OuterRing;
        float real_scale       = (1 - val) * INNER_RING + val * UI_OuterRing;
        real_scale            *= intensity;
        float2 adjusted        = normalized * real_scale / AR + 0.5 - OFFSET;
        fragment               = tex2D(ReShade::BackBuffer, adjusted);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_Droste <
        ui_label     = "Droste Effect";
        ui_tooltip   = "------About-------\n"
                       "Droste.fx warps the image-space to recursively appear within itself.\n\n"
                       "Version:    " COBRA_DRO_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass Droste
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_Droste;
        }
    }
}
