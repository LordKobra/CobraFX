////////////////////////////////////////////////////////////////////////////////////////////////////////
// Cobra Mask (CobraMask.fx) by SirCobra
// Version 0.2.2
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// CobraMask.fx allows to apply ReShade shaders exclusively to a selected part of the screen.
// The mask can be defined through color and scene-depth parameters. The parameters are
// specifically designed to work in accordance with the color and depth selection of other
// CobraFX shaders. This shader works the following way: In the effect window, you put
// "Cobra Mask: Start" above, and "Cobra Mask: Finish" below the shaders you want to be
// affected by the mask. When you turn it on, the effects in between will only affect the
// part of the screen with the correct color and depth.
//
// ----------Credits-----------
// 1) The effect can be applied to a specific area like a DoF shader. The basic methods for this were
// taken with permission from: https://github.com/FransBouma/OtisFX/blob/master/Shaders/Emphasize.fx
// 2) HSV conversions by Sam Hocevar: http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//                                            Defines & UI
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// Shader Start
// Defines

#define COBRA_MSK_VERSION "0.2.2"
#define COBRA_MSK_UI_GENERAL "\n / General Options /\n"
#define COBRA_MSK_UI_COLOR "\n /  Color Masking  /\n"
#define COBRA_MSK_UI_DEPTH "\n /  Depth Masking  /\n"

// Includes

#include "Reshade.fxh"

// Namespace Everything!

namespace COBRA_MSK
{
    // UI

    uniform bool UI_InvertMask <
        ui_label     = " Invert Mask";
        ui_spacing   = 2;
        ui_tooltip   = "Invert the mask.";
        ui_category  = COBRA_MSK_UI_GENERAL;
    >                = false;

    uniform bool UI_ShowMask <
        ui_label     = " Show Mask";
        ui_tooltip   = "Show the masked pixels. Black areas will be preserved, white areas can be affected by the shaders encompassed.";
        ui_category  = COBRA_MSK_UI_GENERAL;
    >                = false;

    uniform bool UI_FilterColor <
        ui_label     = " Filter by Color";
        ui_spacing   = 2;
        ui_tooltip   = "Activates the color masking option.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = true;

    uniform bool UI_ShowSelectedHue <
        ui_label     = " Show Selected Hue";
        ui_tooltip   = "Display the currently selected hue range at the top of the image.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = false;

    uniform float UI_Value <
        ui_label     = " Value";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The value describes the brightness of the hue. 0 is black/no hue and 1 is maximum hue (e.g. pure red).";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = 1.000;

    uniform float UI_ValueRange <
        ui_label     = " Value Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.001;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the value.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = 1.001;

    uniform float UI_ValueEdge <
        ui_label     = " Value Fade";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The smoothness beyond the value range.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = 0.000;

    uniform float UI_Hue <
        ui_label     = " Hue";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The hue describes the color category. It can be red, green, blue or a mix of them.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = 1.000;

    uniform float UI_HueRange <
        ui_label     = " Hue Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 0.500;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the hue.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = 0.500;

    uniform float UI_Saturation <
        ui_label     = " Saturation";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The saturation determines the colorfulness. 0 is greyscale and 1 pure colors.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = 1.000;

    uniform float UI_SaturationRange <
        ui_label     = " Saturation Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the saturation.";
        ui_category  = COBRA_MSK_UI_COLOR;
    >                = 1.000;

    uniform bool UI_FilterDepth <
        ui_label     = " Filter By Depth";
        ui_spacing   = 2;
        ui_tooltip   = "Activates the depth masking option.";
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = false;

    uniform float UI_FocusDepth <
        ui_label     = " Focus Depth";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "Manual focus depth of the point which has the focus. Ranges from 0.0, which means camera is the focus plane,\ntill 1.0 which means the horizon is the focus plane.";
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = 0.030;

    uniform float UI_FocusRangeDepth <
        ui_label     = " Focus Range";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The range of the depth around the manual focus which should still be in focus.";
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = 0.020;

    uniform float UI_FocusEdgeDepth <
        ui_label     = " Focus Fade";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_tooltip   = "The smoothness of the edge of the focus range. Range from 0.0, which means sudden transition, till 1.0,\nwhich means the effect is smoothly fading towards camera and horizon.";
        ui_step      = 0.001;
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = 0.020;

    uniform bool UI_Spherical <
        ui_label     = " Spherical Focus";
        ui_tooltip   = "Enables the mask in a sphere around the focus-point instead of a 2D plane.";
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = false;

    uniform int UI_SphereFieldOfView <
        ui_label     = " Spherical Field of View";
        ui_type      = "slider";
        ui_min       = 1;
        ui_max       = 180;
        ui_units     = "°";
        ui_tooltip   = "Specifies the estimated Field of View you are currently playing with. Range from 1, which means 1 Degree,\ntill 180 which means 180 Degree (half the scene). Normal games tend to use values between 60 and 90.";
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = 75;

    uniform float UI_SphereFocusHorizontal <
        ui_label     = " Spherical Horizontal Focus";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_tooltip   = "Specifies the location of the focuspoint on the horizontal axis. Range from 0, which means left\nscreen border, till 1 which means right screen border.";
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = 0.5;

    uniform float UI_SphereFocusVertical <
        ui_label     = " Spherical Vertical Focus";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_tooltip   = "Specifies the location of the focuspoint on the vertical axis. Range from 0, which means upper\nscreen border, till 1 which means bottom screen border.";
        ui_category  = COBRA_MSK_UI_DEPTH;
    >                = 0.5;

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " Shader Version: " COBRA_MSK_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                         Textures & Samplers
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture TEX_Mask
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };

    // Sampler

    sampler2D SAM_Mask
    {
        Texture   = TEX_Mask;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    #define COBRA_UTL_COLOR 1
    #include ".\CobraUtility.fxh"
    #undef COBRA_UTL_COLOR

    // returns a value between 0 and 1 (1 = in focus)
    float check_focus(float4 rgb, float scene_depth, float2 texcoord)
    {
        // colorfilter
        float4 hsv           = rgb2hsv(rgb);
        float d1_f           = abs(hsv.b - UI_Value) - UI_ValueRange;
        d1_f                 = 1.0 - smoothstep(0.0, UI_ValueEdge, d1_f);
        bool d2              = abs(hsv.r - UI_Hue) < (UI_HueRange + pow(2.71828, -(hsv.g * hsv.g) / 0.005)) || (1.0 - abs(hsv.r - UI_Hue)) < (UI_HueRange + pow(2.71828, -(hsv.g * hsv.g) / 0.01));
        bool d3              = abs(hsv.g - UI_Saturation) <= UI_SaturationRange;
        float is_color_focus = max(d3 * d2 * d1_f, UI_FilterColor == 0); // color threshold

        // depthfilter
        const float DESATURATE_FULL_RANGE = UI_FocusRangeDepth + UI_FocusEdgeDepth;
        texcoord.x                        = (texcoord.x - UI_SphereFocusHorizontal) * ReShade::ScreenSize.x;
        texcoord.y                        = (texcoord.y - UI_SphereFocusVertical) * ReShade::ScreenSize.y;
        const float DEGREE_PER_PIXEL      = float(UI_SphereFieldOfView) / ReShade::ScreenSize.x;
        float fov_diff                    = sqrt((texcoord.x * texcoord.x) + (texcoord.y * texcoord.y)) * DEGREE_PER_PIXEL;
        float depth_diff                  = UI_Spherical ? sqrt((scene_depth * scene_depth) + (UI_FocusDepth * UI_FocusDepth) - (2.0 * scene_depth * UI_FocusDepth * cos(fov_diff * (2.0 * M_PI / 360.0)))) : abs(scene_depth - UI_FocusDepth);
        float depth_val                   = 1.0 - saturate((depth_diff > DESATURATE_FULL_RANGE) ? 1.0 : smoothstep(UI_FocusRangeDepth, DESATURATE_FULL_RANGE, depth_diff));
        depth_val                         = max(depth_val, UI_FilterDepth == 0);
        return is_color_focus * depth_val;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    void PS_MaskStart(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        float4 color   = tex2Dfetch(ReShade::BackBuffer, floor(vpos.xy));
        float depth    = ReShade::GetLinearizedDepth(texcoord);
        float in_focus = check_focus(color, depth, texcoord);
        in_focus       = lerp(in_focus, 1 - in_focus, UI_InvertMask); // in_focus - 2UI*focus + UI
        fragment       = float4(color.rgb, in_focus);
    }

    void PS_MaskEnd(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = tex2Dfetch(SAM_Mask, floor(vpos.xy));
        fragment = UI_ShowMask ? fragment.aaaa : lerp(tex2Dfetch(ReShade::BackBuffer, floor(vpos.xy)), fragment, 1.0 - fragment.a);
        fragment = (UI_ShowSelectedHue * UI_FilterColor) ? show_hue(texcoord, fragment) : fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_CobraMaskStart <
        ui_label     = "Cobra Mask: Start";
        ui_tooltip   = "Place this -above- the shaders you want to mask.\n"
                       "The masked area is copied and stored here, meaning all effects\n"
                       "applied between Start and Finish only affect the unmasked area.\n\n"
                       "------About-------\n"
                       "CobraMask.fx allows to apply ReShade shaders exclusively to a selected part of the screen.\n"
                       "The mask can be defined through color and scene-depth parameters. The parameters are\n"
                       "specifically designed to work in accordance with the color and depth selection of other\n"
                       "CobraFX shaders.\n\n"
                       "Version:    " COBRA_MSK_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass MaskStart
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_MaskStart;
            RenderTarget = TEX_Mask;
        }
    }

    technique TECH_CobraMaskFinish <
        ui_label     = "Cobra Mask: Finish";
        ui_tooltip   = "Place this -below- the shaders you want to mask.\n"
                       "The masked area is applied again onto the screen.\n\n"
                       "------About-------\n"
                       "CobraMask.fx allows to apply ReShade shaders exclusively to a selected part of the screen.\n"
                       "The mask can be defined through color and scene-depth parameters. The parameters are\n"
                       "specifically designed to work in accordance with the color and depth selection of other\n"
                       "CobraFX shaders.\n\n"
                       "Version:    " COBRA_MSK_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass MaskEnd
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_MaskEnd;
        }
    }
}