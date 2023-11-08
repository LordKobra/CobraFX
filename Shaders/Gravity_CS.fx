////////////////////////////////////////////////////////////////////////////////////////////////////////
// Gravity CS (Gravity_CS.fx) by SirCobra
// Version 0.2.1
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// Gravity_CS.fx lets pixels gravitate towards the bottom of the screen in the game's 3D environment.
// You can filter the affected pixels by depth and by color.
// It uses a custom seed (currently the Mandelbrot set) to determine the intensity of each pixel.
// Make sure to also test out the texture-RNG variant with the picture "gravityrng.png" provided
// in the Textures folder. You can replace the texture with your own picture, as long as it
// is 1920x1080, RGBA8 and has the same name. Only the red-intensity is taken. So either use red
// images or greyscale images.
// The effect is quite resource consuming. On small resolutions, Gravity.fx may be faster. Lower
// the integer value of GRAVITY_HEIGHT to increase performance at cost of visual fidelity.
// ----------Credits-----------
// The effect can be applied to a specific area like a DoF shader. The basic methods for this were taken
// with permission from https://github.com/FransBouma/OtisFX/blob/master/Shaders/Emphasize.fx
// Code basis for the Mandelbrot set: http://nuclear.mutantstargoat.com/articles/sdr_fract/
// Thanks to kingeric1992 for optimizing the code!
// Thanks to FransBouma, Lord of Lunacy and Annihlator for advice on my first shader :)
////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//                                            Defines & UI
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// Defines

#define COBRA_XGRV_VERSION "0.2.1"
#define COBRA_XGRV_UI_GENERAL "\n / General Options /\n"
#define COBRA_XGRV_UI_DEPTH "\n /  Depth Options  /\n"
#define COBRA_XGRV_UI_COLOR "\n /  Color Options  /\n"

#ifndef M_PI
    #define M_PI 3.1415927
#endif

#ifndef GRAVITY_HEIGHT
    #define GRAVITY_HEIGHT 768
#endif

#define COBRA_XGRV_RES_Y float(BUFFER_HEIGHT) / GRAVITY_HEIGHT
#define COBRA_XGRV_RES_X 1
#define GRAVITY_WIDTH float(BUFFER_WIDTH) / COBRA_XGRV_RES_X

// We need Compute Shader Support
#if (((__RENDERER__ >= 0xb000 && __RENDERER__ < 0x10000) || (__RENDERER__ >= 0x14300)) && __RESHADE__ >= 40800)
    #define COBRA_XGRV_COMPUTE 1
#else
    #define COBRA_XGRV_COMPUTE 0
    #warning "Gravity_CS.fx does only work with ReShade 4.8 or newer, DirectX 11 or newer, OpenGL 4.3 or newer and Vulkan."
#endif

// Includes

#include "Reshade.fxh"

// Shader Start

#if COBRA_XGRV_COMPUTE != 0

// Namespace Everything!

namespace COBRA_XGRV
{
    // UI

    uniform float UI_GravityIntensity <
        ui_label     = " Gravity Intensity";
        ui_type      = "slider";
        ui_spacing   = 2;
        ui_min       = 0.00;
        ui_max       = 1.00;
        ui_step      = 0.01;
        ui_tooltip   = "Gravity strength. Higher values look cooler but increase the computation time by a lot!";
        ui_category  = COBRA_XGRV_UI_GENERAL;
    >                = 0.50;

    uniform float UI_GravityRNG <
        ui_label     = " Gravity RNG";
        ui_type      = "slider";
        ui_min       = 0.01;
        ui_max       = 0.99;
        ui_step      = 0.02;
        ui_tooltip   = "Changes the random intensity of each pixel.";
        ui_category  = COBRA_XGRV_UI_GENERAL;
    >                = 0.75;

    uniform bool UI_UseImage <
        ui_label     = " Use Image";
        ui_tooltip   = "Changes the RNG to the input image called gravityrng.png located in the Textures folder.\nYou can change the image for your own RNG as long as the name and resolution stay the same.";
        ui_category  = COBRA_XGRV_UI_GENERAL;
    >                = false;

    uniform bool UI_InvertGravity <
        ui_label     = " Invert Gravity";
        ui_tooltip   = "Pixels will gravitate upwards.";
        ui_category  = COBRA_XGRV_UI_GENERAL;
    >                = false;

    uniform bool UI_AllowOverlapping <
        ui_label     = " Allow Overlapping";
        ui_tooltip   = "This way, the effect does not get hidden behind other objects.";
        ui_category  = COBRA_XGRV_UI_GENERAL;
    >                = false;

    uniform float3 UI_EffectTint <
        ui_label     = " Effect Tint";
        ui_type      = "color";
        ui_tooltip   = "Specifies the tint of the gravitating pixels, the further they move away from their origin.";
        ui_category  = COBRA_XGRV_UI_GENERAL;
    >                = float3(0.50, 0.50, 0.50);

    uniform float UI_TintIntensity <
        ui_label     = " Tint Intensity";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_tooltip   = "Specifies intensity of the tint applied to the gravitating pixels. Range from 0.0, which\nmeans no tint, till 1.0 which means fully tinted.";
        ui_category  = COBRA_XGRV_UI_GENERAL;
    >                = 0.0;

    uniform bool UI_FilterDepth <
        ui_label     = " Filter by Depth";
        ui_spacing   = 2;
        ui_tooltip   = "Activates the depth filter option.";
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >                = false;

    uniform float UI_FocusDepth <
        ui_label     = " Focus Depth";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "Manual depth of the focus center. Ranges from 0.0, which means the camera position\nis the focus plane, till 1.0 which means the horizon is the focus plane.";
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >                = 0.030;

    uniform float UI_FocusRangeDepth <
        ui_label     = " Focus Range";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The depth range around the manual focus which should still be in focus.";
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >                = 1.000;

    uniform float UI_FocusEdgeDepth <
        ui_label     = " Focus Fade";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_tooltip   = "The smoothness of the edge of the focus range. Range from 0.0, which means sudden\ntransition, till 1.0, which means the effect is smoothly fading towards camera and horizon.";
        ui_step      = 0.001;
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >                = 0.020;

    uniform bool UI_Spherical <
        ui_label     = " Spherical Focus";
        ui_tooltip   = "Enables the effect in a sphere around the focus-point instead of a 2D plane.";
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >                = false;

    uniform int UI_SphereFieldOfView <
        ui_label     = " Spherical Field of View";
        ui_type      = "slider";
        ui_min       = 1;
        ui_max       = 180;
        ui_units     = "°";
        ui_tooltip   = "Specifies the estimated Field of View you are currently playing with. Range from 1,\nwhich means 1 Degree, till 180 which means 180 Degree (half the scene).\nNormal games tend to use values between 60 and 90.";
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >                = 75;

    uniform float UI_SphereFocusHorizontal <
        ui_label = " Spherical Horizontal Focus";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_tooltip   = "Specifies the location of the focuspoint on the horizontal axis. Range from 0, which\nmeans left screen border, till 1 which means right screen border.";
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >            = 0.5;

    uniform float UI_SphereFocusVertical <
        ui_label = " Spherical Vertical Focus";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_tooltip   = "Specifies the location of the focuspoint on the vertical axis. Range from 0, which\nmeans upper screen border, till 1 which means bottom screen border.";
        ui_category  = COBRA_XGRV_UI_DEPTH;
    >            = 0.5;

    uniform bool UI_FilterColor <
        ui_label     = " Filter by Color";
        ui_spacing   = 2;
        ui_tooltip   = "Activates the color filter option.";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = false;

    uniform bool UI_ShowSelectedHue <
        ui_label     = " Show Selected Hue";
        ui_tooltip   = "Display the currently selected hue range at the top of the image.";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = false;

    uniform float UI_Value <
        ui_label     = " Value";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.001;
        ui_step      = 0.001;
        ui_tooltip   = "The value describes the brightness of the hue. 0 is black/no hue and 1 is maximum hue (e.g. pure red).";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = 1.001;

    uniform float UI_ValueRange <
        ui_label     = " Value Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.001;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the value.";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = 1.001;

    uniform float UI_Hue <
        ui_label     = " Hue";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The hue describes the color category. It can be red, green, blue or a mix of them.";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = 1.000;

    uniform float UI_HueRange <
        ui_label     = " Hue Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 0.500;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the hue.";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = 0.500;

    uniform float UI_Saturation <
        ui_label     = " Saturation";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The saturation determines the colorfulness. 0 is greyscale and 1 pure colors.";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = 1.000;

    uniform float UI_SaturationRange <
        ui_label     = " Saturation Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the saturation.";
        ui_category  = COBRA_XGRV_UI_COLOR;
    >                = 1.000;

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " Preprocessor Options:\n * GRAVITY_HEIGHT (default value: 768) defines the resolution of the effect along the gravitational axis. The value needs to be integer. Smaller values give performance at cost of visual fidelity.\n\n"
        " Shader Version: " COBRA_XGRV_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                         Textures & Samplers
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture TEX_GravitySeedMap
    {
        Width  = GRAVITY_WIDTH;
        Height = GRAVITY_HEIGHT;
        Format = R16F;
    };

    texture TEX_GravitySeedMapCopy
    {
        Width  = GRAVITY_WIDTH;
        Height = GRAVITY_HEIGHT;
        Format = R16F;
    };

    texture TEX_GravitySeedMap2 < source = "gravityrng.png";
    > //@TODO reduce to one map, see gravity.fx eric solution
    {
        Width  = 1920;
        Height = 1080;
        Format = RGBA8;
    };

    texture TEX_GravityCurrentSettings
    {
        Width  = 1;
        Height = 2;
        Format = R16F;
    };

    texture TEX_GravityMain
    {
        Width  = GRAVITY_WIDTH;
        Height = GRAVITY_HEIGHT;
        Format = RGBA8;
    };

    texture TEX_GravityDepth
    {
        Width  = GRAVITY_WIDTH;
        Height = GRAVITY_HEIGHT;
        Format = R32F;
    };

    // Sampler

    sampler2D SAM_GravitySeedMap { Texture = TEX_GravitySeedMap; };
    sampler2D SAM_GravitySeedMapCopy { Texture = TEX_GravitySeedMapCopy; };
    sampler2D SAM_GravitySeedMap2 { Texture = TEX_GravitySeedMap2; };
    sampler2D SAM_GravityCurrentSeed { Texture = TEX_GravityCurrentSettings; };

    sampler2D SAM_GravityMain
    {
        Texture   = TEX_GravityMain;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    sampler2D SAM_GravityDepth
    {
        Texture   = TEX_GravityDepth;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    // Storage

    storage STOR_GravityMain { Texture = TEX_GravityMain; };
    storage STOR_GravityDepth { Texture = TEX_GravityDepth; };

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // vector mod
    float3 mod(float3 x, float y) // x - y * floor(x/y).
    {
        return x - y * floor(x / y);
    }

    // HSV conversions by Sam Hocevar: http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
    float4 rgb2hsv(float4 c)
    {
        const float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p       = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q       = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d        = q.x - min(q.w, q.y);
        const float E  = 1.0e-10;
        return float4(abs(q.z + (q.w - q.y) / (6.0 * d + E)), d / (q.x + E), q.x, 1.0);
    }

    float4 hsv2rgb(float4 c)
    {
        const float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p       = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
        return float4(c.z * lerp(K.xxx, saturate(p - K.xxx), c.y), 1.0);
    }

    // show the color bar. inspired by originalnicodrs design
    float4 show_hue(float2 texcoord, float4 fragment)
    {
        const float RANGE = 0.145;
        const float DEPTH = 0.06;
        if (abs(texcoord.x - 0.5) < RANGE && texcoord.y < DEPTH)
        {
            float4 hsv  = float4(saturate(texcoord.x - 0.5 + RANGE) / (2.0 * RANGE), 1.0, 1.0, 1.0);
            float4 rgb  = hsv2rgb(hsv);
            bool active = min(abs(hsv.r - UI_Hue), (1.0 - abs(hsv.r - UI_Hue))) < UI_HueRange;
            fragment    = active ? rgb : float4(0.5, 0.5, 0.5, 1.0);
        }
        return fragment;
    }

    // calculate if pixel is in focus
    float check_focus(float4 rgb, float scene_depth, float2 texcoord)
    {
        // colorfilter
        float4 hsv          = rgb2hsv(rgb);
        bool d1             = abs(hsv.b - UI_Value) < UI_ValueRange;
        bool d2             = abs(hsv.r - UI_Hue) < (UI_HueRange + pow(2.71828, -(hsv.g * hsv.g) / 0.005)) || (1.0 - abs(hsv.r - UI_Hue)) < (UI_HueRange + pow(2.71828, -(hsv.g * hsv.g) / 0.01));
        bool d3             = abs(hsv.g - UI_Saturation) <= UI_SaturationRange;
        bool is_color_focus = (d3 && d2 && d1) || UI_FilterColor == 0;
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

    // calculate Mandelbrot Seed
    // inspired by http://nuclear.mutantstargoat.com/articles/sdr_fract/
    float mandelbrot_rng(float2 texcoord : TEXCOORD)
    {
        const float2 CENTER = float2(0.675, 0.46);                                  // an interesting center at the mandelbrot for our zoom
        const float ZOOM    = 0.033 * UI_GravityRNG;                                // smaller numbers increase zoom
        const float AR      = float(ReShade::ScreenSize.x) / ReShade::ScreenSize.y; // format to screenspace
        float2 z, c;
        c.x = AR * (texcoord.x - 0.5) * ZOOM - CENTER.x;
        c.y = (texcoord.y - 0.5) * ZOOM - CENTER.y;
        // c = float2(AR,1.0)*(texcoord-0.5) * ZOOM - CENTER; @TODO Performance
        int i;
        z = c;

        for (i = 0; i < 100; i++)
        {
            float x = z.x * z.x - z.y * z.y + c.x;
            float y = 2 * z.x * z.y + c.y;
            if ((x * x + y * y) > 4.0)
                break;
            z.x = x;
            z.y = y;
        }

        const float intensity = 1.0;
        return saturate(((intensity * (i == 100 ? 0.0 : float(i)) / 100.0) - 0.8) / 0.22);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    groupshared uint final_list[GRAVITY_HEIGHT];
    groupshared float depth_list[GRAVITY_HEIGHT];
    groupshared float depth_listU[GRAVITY_HEIGHT];
    groupshared uint strengthen[GRAVITY_HEIGHT];

    void CS_Gravity(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        for (uint y = 0; y < GRAVITY_HEIGHT; y++)
        {
            // strengthskip[y] = 0;
            final_list[y] = y;
            depth_list[y] = depth_listU[y] = ReShade::GetLinearizedDepth(float2((id.x * COBRA_XGRV_RES_X + 0.5) / BUFFER_WIDTH, (y * COBRA_XGRV_RES_Y + 0.5) / BUFFER_HEIGHT));
        }

        uint paint_iterator = 0;

        for (int y = 0; y < GRAVITY_HEIGHT; y++)
        {
            uint yi = y + (GRAVITY_HEIGHT - 1 - 2 * y) * UI_InvertGravity;
            // get your information together
            float4 rgb        = tex2Dfetch(ReShade::BackBuffer, int2(id.x * COBRA_XGRV_RES_X, yi * COBRA_XGRV_RES_Y)); // access
            rgb.a             = 1.0;
            float scene_depth = depth_list[yi];                                                                                                                                                        // access
            float strength    = tex2Dfetch(SAM_GravitySeedMap, int2(id.x, yi)).r;                                                                                                                      // access
            strength          = strength * UI_GravityIntensity * check_focus(rgb, scene_depth, float2((id.x * COBRA_XGRV_RES_X + 0.5) / BUFFER_WIDTH, (yi * COBRA_XGRV_RES_Y + 0.5) / BUFFER_HEIGHT)); // access
            strengthen[yi]    = strength = strength * (GRAVITY_HEIGHT - 2.0);
            if (!UI_AllowOverlapping)
            {
                // normal
                uint yymax = min(y + strength, GRAVITY_HEIGHT);
                for (uint yy = y + 1; yy <= yymax; yy++)
                {
                    uint yyi           = yy + (GRAVITY_HEIGHT - 1 - 2 * yy) * UI_InvertGravity;
                    float target_depth = depth_listU[yyi]; // affected
                    final_list[yyi]    = (target_depth > scene_depth) ? yi : final_list[yyi];
                    depth_listU[yyi]   = (target_depth > scene_depth) ? depth_list[yi] : depth_listU[yyi]; // affected
                    // strengthskip[yyi] = (targetdepth > scenedepth) ? yymax - yyi : strengthskip[yyi];
                    // yyi = (targetdepth > scenedepth) ? yyi : yyi+strengthskip[yyi];
                }
            }
            else
            {
                // version for overlapping
                if (paint_iterator == y)
                    paint_iterator++;
                uint imax = min(y + (uint)strength, GRAVITY_HEIGHT - 1);
                for (uint i = paint_iterator; i <= imax; i++, paint_iterator++)
                {
                    final_list[i + (GRAVITY_HEIGHT - 1 - 2 * i) * UI_InvertGravity]  = yi;
                    depth_listU[i + (GRAVITY_HEIGHT - 1 - 2 * i) * UI_InvertGravity] = 0.0;
                }
            }
        }
        for (uint y = 0; y < GRAVITY_HEIGHT; y++)
        {
            if (y != final_list[y])
            {
                float4 store_val      = tex2Dfetch(ReShade::BackBuffer, int2(id.x, final_list[y] * COBRA_XGRV_RES_Y)); // access
                float blend_intensity = smoothstep(0.0, strengthen[final_list[y]], distance(y, final_list[y]));
                store_val.a           = 1.0;
                store_val             = lerp(store_val, float4(UI_EffectTint, 1.0), blend_intensity * UI_TintIntensity);
                tex2Dstore(STOR_GravityMain, float2(id.x, y), store_val);
                tex2Dstore(STOR_GravityDepth, float2(id.x, y), depth_listU[y]);
            }
        }
    }

    /// SETUP

    // RNG MAP
    void PS_GenerateRNGSetup(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {

        float value = tex2D(SAM_GravitySeedMap2, texcoord).r;
        value       = saturate((value - 1.0 + UI_GravityRNG) / UI_GravityRNG);
        fragment    = (UI_UseImage ? value : mandelbrot_rng(texcoord));
    }

    void PS_UpdateRNGMapSetup(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        fragment = tex2D(SAM_GravitySeedMap, texcoord).r;
    }

    /// MAIN

    // RNG MAP
    void PS_GenerateRNG(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        float old_rng = tex2D(SAM_GravityCurrentSeed, float2(0.0, 0.25)).r;
        old_rng      += tex2D(SAM_GravityCurrentSeed, float2(0.0, 0.75)).r; // @TODO why read twice and add? bug?
        float new_rng = UI_GravityRNG + ((UI_UseImage) ? 0.01 : 0.0);
        new_rng      += UI_GravityIntensity;
        float value   = tex2D(SAM_GravitySeedMap2, texcoord).r;
        value         = saturate((value - 1.0 + UI_GravityRNG) / UI_GravityRNG);
        if (abs(old_rng - new_rng) > 0.001)
        {
            fragment = (UI_UseImage ? value : mandelbrot_rng(texcoord));
        }
        else
        {
            fragment = tex2D(SAM_GravitySeedMapCopy, texcoord).r;
        }
    }

    void PS_UpdateRNGMap(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        fragment = tex2D(SAM_GravitySeedMap, texcoord).r;
    }

    // update current settings - careful with pipeline placement -at the end
    void PS_UpdateRNGSettings(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        float fragment1 = UI_GravityRNG;
        fragment1      += UI_UseImage ? 0.01 : 0.0;
        float fragment2 = UI_GravityIntensity;
        fragment        = ((texcoord.y < 0.5) ? fragment1 : fragment2);
    }

    // PRINT
    void PS_PrepareGravity(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = float4(0.0, 0.0, 0.0, 0.0); // @TODO Do we really need to apply a constant per pixel, faster ways?
    }

    void PS_PrepareDepth(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        fragment = 1.0;
    }

    void PS_PrintGravity(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment            = tex2D(SAM_GravityMain, texcoord);
        float depth_gravity = tex2D(SAM_GravityDepth, texcoord).r;
        float depth_pixel   = ReShade::GetLinearizedDepth(texcoord);
        fragment            = (fragment.a && depth_gravity < depth_pixel) ? fragment : tex2D(ReShade::BackBuffer, texcoord);
        fragment            = (UI_ShowSelectedHue * UI_FilterColor) ? show_hue(texcoord, fragment) : fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_PreGravity <
        hidden     = true;
        enabled    = true;
        timeout    = 1000;
    >
    {
        pass GenerateRNG
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_GenerateRNGSetup;
            RenderTarget = TEX_GravitySeedMap;
        }

        pass UpdateRNGMap
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_UpdateRNGMapSetup;
            RenderTarget = TEX_GravitySeedMapCopy;
        }
    }

    technique TECH_GravityCS <
        ui_label     = "Gravity CS";
        ui_tooltip   = "------About-------\n"
                       "Gravity_CS.fx lets pixels gravitate towards the bottom of the screen in the game's 3D environment.\n"
                       "You can filter the affected pixels by depth and by color.\n"
                       "It uses a custom seed (currently the Mandelbrot set) to determine the intensity of each pixel.\n"
                       "Make sure to also test out the texture-RNG variant with the picture 'gravityrng.png' provided\n"
                       "in the Textures folder. You can replace the texture with your own picture, as long as it\n"
                       "is 1920x1080, RGBA8 and has the same name. Only the red-intensity is taken. So either use red\n"
                       "images or greyscale images.\n"
                       "CS is the compute shader version of Gravity.fx, it works best on resolutions above 1080p.\n"
                       "At lower resolutions, check out Gravity.fx instead. For additional perfomance, read the\n"
                       "preprocessor tooltip of GRAVITY_HEIGHT.\n\n"
                       "Version:    " COBRA_XGRV_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass GenerateRNG
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_GenerateRNG;
            RenderTarget = TEX_GravitySeedMap;
        }

        pass UpdateRNGMap
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_UpdateRNGMap;
            RenderTarget = TEX_GravitySeedMapCopy;
        }

        pass PrepareGravity
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_PrepareGravity;
            RenderTarget = TEX_GravityMain;
        }

        pass PrepareDepth
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_PrepareDepth;
            RenderTarget = TEX_GravityDepth;
        }

        pass GravityMain
        {
            ComputeShader = CS_Gravity<1, 1>;
            DispatchSizeX = GRAVITY_WIDTH;
            DispatchSizeY = 1;
        }

        pass UpdateSettings
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_UpdateRNGSettings;
            RenderTarget = TEX_GravityCurrentSettings;
        }

        pass PrintGravity
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_PrintGravity;
        }
    }
}
#endif // Shader End
