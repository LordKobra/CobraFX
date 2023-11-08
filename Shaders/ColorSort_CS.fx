////////////////////////////////////////////////////////////////////////////////////////////////////////
// Color Sort (Colorsort_CS.fx) by SirCobra
// Version 0.5.1
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// ColorSort_CS.fx can sort the image pixels by brightness along a user-specified axis.
// You can filter the affected pixels by depth and by color.
// The shader consumes a lot of resources. To balance between quality and performance,
// adjust the preprocessor parameter COLOR_HEIGHT. Check the tooltip for further info.
// ----------Credits-----------
// The effect can be applied to a specific area like a DoF shader. The basic methods for this were taken with permission
// from https://github.com/FransBouma/OtisFX/blob/master/Shaders/Emphasize.fx
// Thanks to kingeric1992 & Lord of Lunacy for tips on how to construct the algorithm. :)
// The merge_sort function is adapted from this website: https://www.techiedelight.com/iterative-merge-sort-algorithm-bottom-up/
// The multithreaded merge sort is constructed as described here: https://www.nvidia.in/docs/IO/67073/nvr-2008-001.pdf
////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//                                            Defines & UI
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// Defines

#define COBRA_XCOL_VERSION "0.5.1"
#define COBRA_XCOL_UI_GENERAL "\n / General Options /\n"
#define COBRA_XCOL_UI_DEPTH "\n /  Depth Masking  /\n"
#define COBRA_XCOL_UI_COLOR "\n /  Color Masking  /\n"

#ifndef M_PI
    #define M_PI 3.1415927
#endif

#ifndef COLOR_HEIGHT
    #define COLOR_HEIGHT 10 // maybe needs multiple of 64 :/
#endif

#define COBRA_XCOL_THREADS ((uint)16) // 2^n
#define COBRA_XCOL_HEIGHT (COLOR_HEIGHT % 15) * 64
#define COBRA_XCOL_NOISE_WIDTH 4096
#define COBRA_XCOL_NOISE_HEIGHT 1024

// We need Compute Shader Support
#if (((__RENDERER__ >= 0xb000 && __RENDERER__ < 0x10000) || (__RENDERER__ >= 0x14300)) && __RESHADE__ >= 40800)
    #define COBRA_XCOL_COMPUTE 1
#else
    #define COBRA_XCOL_COMPUTE 0
    #warning "ColorSort_CS.fx does only work with ReShade 4.8 or newer, DirectX 11 or newer, OpenGL 4.3 or newer and Vulkan."
#endif

// Includes

#include "Reshade.fxh"

// Shader Start

#if COBRA_XCOL_COMPUTE != 0

// Namespace everything!

namespace COBRA_XCOL
{
    // UI

    uniform uint UI_RotationAngle <
        ui_label     = " Angle of Rotation";
        ui_type      = "slider";
        ui_spacing   = 2;
        ui_min       = 0;
        ui_max       = 360;
        ui_units     = "°";
        ui_step      = 1;
        ui_tooltip   = "Rotation of the sorting axis.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = 0;

    uniform float UI_BrightnessThresholdStart <
        ui_label     = " Brightness Threshold: Start";
        ui_type      = "slider";
        ui_min       = -0.050;
        ui_max       = 1.050;
        ui_step      = 0.001;
        ui_tooltip   = "Pixels with brightness close to this parameter serve as starting threshold for the sorting algorithm and\nfragment the area. Set both sliders to their maximum value to disable them.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = 1.050;

    uniform float UI_BrightnessThresholdEnd <
        ui_label     = " Brightness Threshold: End";
        ui_type      = "slider";
        ui_min       = -0.050;
        ui_max       = 1.050;
        ui_step      = 0.001;
        ui_tooltip   = "Pixels with brightness close to this parameter serve as finishing threshold for the sorting algorithm and\nfragment the area. Set both sliders to their maximum value to disable them.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = 1.050;

    uniform float UI_GradientStrength <
        ui_label     = " Gradient Strength";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "Strength of the noise applied to the masked area. More noise results in more brightness variance.\nOnly recommended in monotone environments. For color gradients on the sorted area, better apply\nother effects between Masking and Main effect order.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = 0.000;

    uniform float UI_MaskingNoise <
        ui_label     = " Masking Noise";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.001;
        ui_step      = 0.001;
        ui_tooltip   = "Strength of the noise applied to mask itself.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = 0.000;

    uniform float UI_NoiseSize <
        ui_label     = " Noise Size";
        ui_type      = "slider";
        ui_min       = 0.001;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "Size of the noise texture. A lower value means larger noise pixels.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = 1.000;

    uniform bool UI_ReverseSort <
        ui_label     = " Reverse Sorting";
        ui_tooltip   = "While active, it sorts from dark to bright. Otherwise it will sort from bright to dark.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = false;

    uniform bool UI_InvertMask <
        ui_label     = " Invert Mask";
        ui_tooltip   = "Invert the mask.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = false;

    uniform bool UI_ShowMask <
        ui_label     = " Show Mask";
        ui_tooltip   = "Show the masked pixels. White areas will be preserved, black/grey areas can be affected by the shaders\nencompassed. Dark grey pixels show the noise pattern. Light grey pixels show brightness thresholds.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = false;

    uniform bool UI_HotsamplingMode <
        ui_label     = " Hotsampling Mode";
        ui_tooltip   = "The noise will be the same at all resolutions. Activate this, then adjust your options\nand it will stay the same at all resolutions. Turn this off when you do not intend\nto hotsample.";
        ui_category  = COBRA_XCOL_UI_GENERAL;
    >                = false;

    uniform bool UI_FilterColor <
        ui_label     = " Filter by Color";
        ui_spacing   = 2;
        ui_tooltip   = "Activates the color masking option.";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = true;

    uniform bool UI_ShowSelectedHue <
        ui_label     = " Show Selected Hue";
        ui_tooltip   = "Display the currently selected hue range at the top of the image.";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = false;

    uniform float UI_Value <
        ui_label     = " Value";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.001;
        ui_step      = 0.001;
        ui_tooltip   = "The value describes the brightness of the hue. 0 is black/no hue and 1 is maximum hue (e.g. pure red).";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = 1.001;

    uniform float UI_ValueRange <
        ui_label     = " Value Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.001;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the value.";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = 1.001;

    uniform float UI_Hue <
        ui_label     = " Hue";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The hue describes the color category. It can be red, green, blue or a mix of them.";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = 1.000;

    uniform float UI_HueRange <
        ui_label     = " Hue Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 0.500;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the hue.";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = 0.500;

    uniform float UI_Saturation <
        ui_label     = " Saturation";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The saturation determines the colorfulness. 0 is greyscale and 1 pure colors.";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = 1.000;

    uniform float UI_SaturationRange <
        ui_label     = " Saturation Range";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The tolerance around the saturation.";
        ui_category  = COBRA_XCOL_UI_COLOR;
    >                = 1.000;

    uniform bool UI_FilterDepth <
        ui_label     = " Filter By Depth";
        ui_spacing   = 2;
        ui_tooltip   = "Activates the depth masking option.";
        ui_category  = COBRA_XCOL_UI_DEPTH;
    >                = false;

    uniform float UI_FocusDepth <
        ui_label     = " Focus Depth";
        ui_type      = "slider";
        ui_min       = 0.000;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "Manual focus depth of the point which has the focus. Ranges from 0.0, which means camera is the focus plane,\ntill 1.0 which means the horizon is the focus plane.";
        ui_category  = COBRA_XCOL_UI_DEPTH;
    >                = 0.030;

    uniform float UI_FocusRangeDepth <
        ui_label     = " Focus Range";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.000;
        ui_step      = 0.001;
        ui_tooltip   = "The range of the depth around the manual focus which should still be in focus.";
        ui_category  = COBRA_XCOL_UI_DEPTH;
    >                = 0.020;

    uniform bool UI_Spherical <
        ui_label     = " Spherical Focus";
        ui_tooltip   = "Enables the mask in a sphere around the focus-point instead of a 2D plane.";
        ui_category  = COBRA_XCOL_UI_DEPTH;
    >                = false;

    uniform int UI_SphereFieldOfView <
        ui_label     = " Spherical Field of View";
        ui_type      = "slider";
        ui_min       = 1;
        ui_max       = 180;
        ui_units     = "°";
        ui_tooltip   = "Specifies the estimated Field of View you are currently playing with. Range from 1°,\ntill 180° (half the scene). Normal games tend to use values between 60° and 90°.";
        ui_category  = COBRA_XCOL_UI_DEPTH;
    >                = 75;

    uniform float UI_SphereFocusHorizontal <
        ui_label     = " Spherical Horizontal Focus";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_tooltip   = "Specifies the location of the focuspoint on the horizontal axis. Range from 0, which means left\nscreen border, till 1 which means right screen border.";
        ui_category  = COBRA_XCOL_UI_DEPTH;
    >                = 0.5;

    uniform float UI_SphereFocusVertical <
        ui_label     = " Spherical Vertical Focus";
        ui_type      = "slider";
        ui_min       = 0.0;
        ui_max       = 1.0;
        ui_tooltip   = "Specifies the location of the focuspoint on the vertical axis. Range from 0, which means upper\nscreen border, till 1 which means bottom screen border.";
        ui_category  = COBRA_XCOL_UI_DEPTH;
    >                = 0.5;

    uniform int UI_BufferEnd <
        ui_type     = "radio";
        ui_spacing  = 2;
        ui_text     = " Preprocessor Options:\n * COLOR_HEIGHT (default value: 10) multiplied by 64 defines the resolution of the effect along the sorting axis. The value needs to be integer. Smaller values give performance at cost of visual fidelity. 8: Performance, 10: Default, 12: Good, 14: High\n\n"
                      " Shader Version: " COBRA_XCOL_VERSION;
        ui_label    = " ";
    > ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                             Textures & Samplers & Storage & Shared Memory
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Texture

    texture TEX_HalfRes
    {
        Width  = BUFFER_WIDTH;
        Height = COBRA_XCOL_HEIGHT;
        Format = RGBA16F;
    };

    texture TEX_Noise < source = "uniform_noise.png";
    >
    {
        Width  = COBRA_XCOL_NOISE_WIDTH;
        Height = COBRA_XCOL_NOISE_HEIGHT;
        Format = R8;
    };

    texture TEX_Mask
    {
        Width  = BUFFER_WIDTH;
        Height = COBRA_XCOL_HEIGHT;
        Format = R16F;
    };

    texture TEX_Background
    {
        Width  = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };

    texture TEX_ColorSort
    {
        Width  = BUFFER_WIDTH;
        Height = COBRA_XCOL_HEIGHT;
        Format = RGBA16F;
    };

    // Sampler

    sampler2D SAM_HalfRes { Texture = TEX_HalfRes; };
    sampler2D SAM_Background { Texture = TEX_Background; };
    sampler2D SAM_ColorSort { Texture = TEX_ColorSort; };

    sampler2D SAM_Noise
    {
        Texture   = TEX_Noise;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    sampler2D SAM_Mask
    {
        Texture   = TEX_Mask;
        MagFilter = POINT;
        MinFilter = POINT;
        MipFilter = POINT;
    };

    // Storage

    storage STOR_ColorSort { Texture = TEX_ColorSort; };

    // Groupshared Memory

    groupshared float4 color_table[2 * COBRA_XCOL_HEIGHT];
    groupshared int even_block[2 * COBRA_XCOL_THREADS];
    groupshared int odd_block[2 * COBRA_XCOL_THREADS];

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                           Helper Functions
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    // vector mod and normal fmod
    float3 mod(float3 x, float y)
    {
        return x - y * floor(x / y);
    }

    float fmod(float x, float y)
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

    // rotate the screen
    float2 rotate(float2 texcoord, uint angle, bool revert)
    {
        //@TODO angle is UI_RotationAngle -> gives us a constant evaluation instead of variable
        float2 rotated = texcoord;
        // easy cases to avoid dividing by zero; values 0 & 360 are trivial
        rotated = (angle == 90) ? float2(texcoord.y, texcoord.x) : rotated;
        rotated = (angle == 180) ? float2(1 - texcoord.x, 1 - texcoord.y) : rotated;
        rotated = (angle == 270) ? float2(1 - texcoord.y, 1 - texcoord.x) : rotated;

        // harder cases
        if (!(angle == 0 || angle == 90 || angle == 180 || angle == 270 || angle == 360))
        {
            // neccessary transformations from picture coordinates to normal coordinate system for better visualization of the concept
            angle     = fmod(angle + 180, 360); // we only need to rotate the angle, because although texcoord is inverted applying it twice fixes it.
            float phi = angle * M_PI / 180.0;

            // rotate the borders @TODO can we vectorize please?
            float2 p00 = float2(0.0, 0.0); // 0
            float2 p01 = float2(0.0, 1.0); // 1
            float2 p10 = float2(1.0, 0.0); // 2
            float2 p11 = float2(1.0, 1.0); // 3
            p00        = float2(cos(phi) * p00.x - sin(phi) * p00.y, sin(phi) * p00.x + cos(phi) * p00.y);
            p01        = float2(cos(phi) * p01.x - sin(phi) * p01.y, sin(phi) * p01.x + cos(phi) * p01.y);
            p10        = float2(cos(phi) * p10.x - sin(phi) * p10.y, sin(phi) * p10.x + cos(phi) * p10.y);
            p11        = float2(cos(phi) * p11.x - sin(phi) * p11.y, sin(phi) * p11.x + cos(phi) * p11.y);

            // find min and max values
            uint l, r;
            float lval, rval;
            lval = p00.x;
            rval = p00.y;
            l    = 0;
            r    = 0;
            l    = (p01.x < lval) ? 1 : l;
            lval = (p01.x < lval) ? p01.x : lval;
            r    = (p01.x > rval) ? 1 : r;
            rval = (p01.x > rval) ? p01.x : rval;
            l    = (p10.x < lval) ? 2 : l;
            lval = (p10.x < lval) ? p10.x : lval;
            r    = (p10.x > rval) ? 2 : r;
            rval = (p10.x > rval) ? p10.x : rval;
            l    = (p11.x < lval) ? 3 : l;
            lval = (p11.x < lval) ? p11.x : lval;
            r    = (p11.x > rval) ? 3 : r;
            rval = (p11.x > rval) ? p11.x : rval;

            // REVERT ?
            float current_x     = revert ? float2(cos(phi) * texcoord.x - sin(phi) * texcoord.y, sin(phi) * texcoord.x + cos(phi) * texcoord.y).x : lval + texcoord.x * (rval - lval); //  just rotate x or interpolate between rotation start and end and find correct x: lval - x*lval + x*rval = lval + x(rval-lval)
            float current_x_rel = abs(lval - current_x) / abs(lval - rval);
            float current_y     = float2(cos(phi) * texcoord.x - sin(phi) * texcoord.y, sin(phi) * texcoord.x + cos(phi) * texcoord.y).y;

            // there exist 4 borders, find the intersections
            //  0-1 0-2 1-3 2-3
            float3 ylow  = 1000.0;
            float3 yhigh = -1000.0;
            // 0-1
            float x_rel = abs(p00.x - current_x) / abs(p00.x - p01.x);
            float y_abs = (1.0 - x_rel) * p00.y + x_rel * p01.y;
            ylow        = ((p00.x < current_x && current_x < p01.x) || (p00.x > current_x && current_x > p01.x)) ? float3(0.0, x_rel, y_abs) : ylow;
            yhigh       = ((p00.x < current_x && current_x < p01.x) || (p00.x > current_x && current_x > p01.x)) ? ylow : yhigh;
            // 0-2
            x_rel = abs(p00.x - current_x) / abs(p00.x - p10.x);
            y_abs = (1.0 - x_rel) * p00.y + x_rel * p10.y;
            ylow  = ((p00.x < current_x && current_x < p10.x) || (p00.x > current_x && current_x > p10.x)) && (y_abs < ylow.z) ? float3(x_rel, 0.0, y_abs) : ylow;
            yhigh = ((p00.x < current_x && current_x < p10.x) || (p00.x > current_x && current_x > p10.x)) && (y_abs > yhigh.z) ? float3(x_rel, 0.0, y_abs) : yhigh;
            // 1-3
            x_rel = abs(p01.x - current_x) / abs(p01.x - p11.x);
            y_abs = (1.0 - x_rel) * p01.y + x_rel * p11.y;
            ylow  = ((p01.x < current_x && current_x < p11.x) || (p01.x > current_x && current_x > p11.x)) && (y_abs < ylow.z) ? float3(x_rel, 1.0, y_abs) : ylow;
            yhigh = ((p01.x < current_x && current_x < p11.x) || (p01.x > current_x && current_x > p11.x)) && (y_abs > yhigh.z) ? float3(x_rel, 1.0, y_abs) : yhigh;
            // 2-3
            x_rel = abs(p10.x - current_x) / abs(p10.x - p11.x);
            y_abs = (1.0 - x_rel) * p10.y + x_rel * p11.y;
            ylow  = ((p10.x < current_x && current_x < p11.x) || (p10.x > current_x && current_x > p11.x)) && (y_abs < ylow.z) ? float3(1.0, x_rel, y_abs) : ylow;
            yhigh = ((p10.x < current_x && current_x < p11.x) || (p10.x > current_x && current_x > p11.x)) && (y_abs > yhigh.z) ? float3(1.0, x_rel, y_abs) : yhigh;

            // interpolate and check revert
            rotated = revert ? float2(current_x_rel, abs(yhigh.z - current_y) / abs(ylow.z - yhigh.z)) : (1.0 - texcoord.y) * yhigh.xy + texcoord.y * ylow.xy; // find the y position on the original grid : find the y position on the rotated grid
        }
        return rotated;
    }

    // calculate if pixel is in focus
    bool check_focus(float4 rgb, float scene_depth, float2 texcoord)
    {
        // colorfilter
        float4 hsv          = rgb2hsv(rgb);
        bool d1             = abs(hsv.b - UI_Value) < UI_ValueRange;
        bool d2             = abs(hsv.r - UI_Hue) < (UI_HueRange + pow(2.71828, -(hsv.g * hsv.g) / 0.005)) || (1.0 - abs(hsv.r - UI_Hue)) < (UI_HueRange + pow(2.71828, -(hsv.g * hsv.g) / 0.01));
        bool d3             = abs(hsv.g - UI_Saturation) <= UI_SaturationRange;
        bool is_color_focus = (d3 && d2 && d1) || UI_FilterColor == 0;
        // depthfilter
        texcoord.x                   = (texcoord.x - UI_SphereFocusHorizontal) * ReShade::ScreenSize.x;
        texcoord.y                   = (texcoord.y - UI_SphereFocusVertical) * ReShade::ScreenSize.y;
        const float DEGREE_PER_PIXEL = float(UI_SphereFieldOfView) / ReShade::ScreenSize.x;
        float fov_diff               = sqrt((texcoord.x * texcoord.x) + (texcoord.y * texcoord.y)) * DEGREE_PER_PIXEL;
        float depth_diff             = UI_Spherical ? sqrt((scene_depth * scene_depth) + (UI_FocusDepth * UI_FocusDepth) - (2.0 * scene_depth * UI_FocusDepth * cos(fov_diff * (2.0 * M_PI / 360.0)))) : abs(scene_depth - UI_FocusDepth);
        bool is_depth_focus          = (depth_diff < UI_FocusRangeDepth) || UI_FilterDepth == 0;

        bool in_focus = is_color_focus && is_depth_focus;
        return in_focus + UI_InvertMask - 2 * in_focus * UI_InvertMask; // @TODO Add invert mask as general option in header
    }

    /// Sorting

    // core sorting decider
    bool min_color(float4 a, float4 b)
    {
        float val = b.a - a.a; // val > 0 for a smaller
        val       = (abs(val) < 0.1) ? ((a.r + a.g + a.b) - (b.r + b.g + b.b)) * (1 - UI_ReverseSort - UI_ReverseSort) : val;
        return (val < 0.0) ? false : true; // Returns False if a smaller, yes its weird
    }

    // single thread merge sort
    void merge_sort(int low, int high, int em)
    {
        float4 temp[COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS];
        for (int i = 0; i < COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS; i++)
        {
            temp[i] = color_table[low + i];
        }

        for (int m = em; m <= high - low; m = 2 * m)
        {
            for (int i = low; i < high; i += 2 * m)
            {
                int from = i;
                int mid  = i + m - 1;
                int to   = min(i + 2 * m - 1, high);
                // inside function //////////////////////////////////
                int k = from, i_2 = from, j = mid + 1;
                while (i_2 <= mid && j <= to)
                {
                    if (min_color(color_table[i_2], color_table[j]))
                    {
                        temp[k++ - low] = color_table[i_2++];
                    }
                    else
                    {
                        temp[k++ - low] = color_table[j++];
                    }
                }

                while (i_2 < high && i_2 <= mid)
                {
                    temp[k++ - low] = color_table[i_2++];
                }

                for (i_2 = from; i_2 <= to; i_2++)
                {
                    color_table[i_2] = temp[i_2 - low];
                }
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                              Shaders
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Masking

    void PS_MaskColor(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
    {
        // focus
        float4 color      = tex2D(ReShade::BackBuffer, texcoord);
        float scene_depth = ReShade::GetLinearizedDepth(texcoord);
        float in_focus    = check_focus(color, scene_depth, texcoord);

        // separator
        const uint HS_WIDTH = UI_HotsamplingMode ? 2036 : BUFFER_WIDTH;
        float2 t_noise      = float2(texcoord.x, texcoord.y) * UI_NoiseSize;
        const float PHI     = UI_RotationAngle * M_PI / 180;
        t_noise             = float2(cos(PHI) * t_noise.x - sin(PHI) * t_noise.y, sin(PHI) * t_noise.x + cos(PHI) * t_noise.y);
        t_noise             = float2(fmod(t_noise.x * HS_WIDTH, COBRA_XCOL_NOISE_WIDTH) / (float)COBRA_XCOL_NOISE_WIDTH, fmod(t_noise.y * COBRA_XCOL_HEIGHT, COBRA_XCOL_NOISE_HEIGHT) / (float)COBRA_XCOL_NOISE_HEIGHT);
        float noise_1       = tex2D(SAM_Noise, t_noise).r; // add some point-color.
        // bool is_noisy = UI_MaskingNoise > noise_1;
        bool seperator_1 = abs((color.r + color.g + color.b) / 3 - UI_BrightnessThresholdStart) < 0.04;
        bool seperator_2 = abs((color.r + color.g + color.b) / 3 - UI_BrightnessThresholdEnd) < 0.04;
        // bool seperator = seperator_1 || seperator_2;
        noise_1  = 0.5 * noise_1;
        noise_1  = seperator_1 ? 0.8 : noise_1;
        noise_1  = seperator_2 ? 0.7 : noise_1;
        fragment = saturate(!in_focus + noise_1); // 1 -not in focus 0-0.5 in_focus+noiselevel 0.8:seperator_1 0.7 sep2
    }

    void PS_SaveBackground(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = tex2D(ReShade::BackBuffer, texcoord);
    }

    /// Gradient

    void PS_Gradient(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        fragment = tex2D(ReShade::BackBuffer, texcoord);

        // Gradient Noise
        float2 t_noise = float2(frac(texcoord.x * BUFFER_WIDTH / COBRA_XCOL_NOISE_WIDTH), frac(texcoord.y * COBRA_XCOL_HEIGHT / COBRA_XCOL_NOISE_HEIGHT));
        float noise_1  = tex2D(SAM_Noise, t_noise).r;
        noise_1        = (sin(4.0 * M_PI * noise_1) + 4.0 * M_PI * noise_1) / (4.0 * M_PI);
        noise_1        = UI_GradientStrength * (noise_1 - 0.5); // @TODO Gradient in Saturation, so it's not black/white
        fragment       = saturate(fragment + float4(noise_1.xxx, 0.0));
    }

    /// Main

    void PS_PrepareColorSort(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        // prepare and rotate texture for sorting
        float2 texcoord_new = rotate(texcoord, UI_RotationAngle, false);
        fragment            = tex2D(ReShade::BackBuffer, texcoord_new);
        float mask          = tex2D(SAM_Mask, texcoord_new).r;
        fragment.a          = mask;
    }

    // multithread merge sort
    void CS_ColorSort(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
    {
        int row            = tid.y * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
        int interval_start = row + tid.x * COBRA_XCOL_HEIGHT;
        int interval_end   = row - 1 + COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS + tid.x * COBRA_XCOL_HEIGHT;
        uint i;

        // masking
        for (i = row; i <= row - 1 + COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS; i++)
        {
            color_table[i + tid.x * COBRA_XCOL_HEIGHT] = tex2Dfetch(SAM_HalfRes, int2(id.x, i));
        }

        if (tid.y == 0)
        {
            bool was_focus        = false; // last array element
            bool is_focus         = false; // current array element
            float noise           = 0.0;
            bool is_separate      = false;
            bool was_separate     = false;
            const bool ACTIVE_SEP = UI_BrightnessThresholdStart < 1.02 || UI_BrightnessThresholdEnd < 1.02;
            bool separate_area    = !ACTIVE_SEP;
            int mask_val          = 0;
            for (i = 0; i < COBRA_XCOL_HEIGHT; i++)
            {
                // determine focus mask
                // color_table[i + tid.x * COBRA_XCOL_HEIGHT] = tex2Dfetch(SAM_HalfRes, int2(id.x, i));
                is_focus = color_table[i + tid.x * COBRA_XCOL_HEIGHT].a < 0.9; // 1 -not in focus 0-0.5 in_focus+noiselevel 0.8:seperator_1 0.7 sep2
                // thresholding cells
                noise         = color_table[i + tid.x * COBRA_XCOL_HEIGHT].a < 0.6 ? 2.0 * color_table[i + tid.x * COBRA_XCOL_HEIGHT].a : 0.0;
                is_separate   = is_focus && UI_MaskingNoise > noise;
                separate_area = ACTIVE_SEP && is_focus && color_table[i + tid.x * COBRA_XCOL_HEIGHT].a > 0.75 ? true : separate_area;
                separate_area = ACTIVE_SEP && is_focus && color_table[i + tid.x * COBRA_XCOL_HEIGHT].a > 0.65 && is_focus && color_table[i + tid.x * COBRA_XCOL_HEIGHT].a < 0.75 ? false : separate_area;

                if (!(is_focus && was_focus && separate_area && !(is_separate && !was_separate)))
                    mask_val++;

                was_focus                                    = is_focus;
                was_separate                                 = is_separate;
                color_table[i + tid.x * COBRA_XCOL_HEIGHT].a = (float)mask_val + 0.5 * is_focus; // is the is_focus carryover depreciated? - Yes :)
            }
        }
        barrier();
        // sort the small arrays
        merge_sort(interval_start, interval_end, 1);
        // combine
        float4 key[COBRA_XCOL_THREADS];
        float4 key_sorted[COBRA_XCOL_THREADS];
        float4 sorted_array[2 * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS];
        for (i = 1; i < COBRA_XCOL_THREADS; i = 2 * i) // the amount of merges, just like a normal merge sort
        {
            barrier();
            uint group_size = 2 * i;
            // keylist
            for (int j = 0; j < group_size; j++) // probably redundancy between threads. optimzable
            {
                int curr  = tid.y - (tid.y % group_size) + j;
                key[curr] = color_table[curr * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS + tid.x * COBRA_XCOL_HEIGHT];
            }

            // sort keys
            int idy_sorted;
            int even = tid.y - (tid.y % group_size);
            int k    = even;
            int mid  = even + group_size / 2 - 1;
            int odd  = mid + 1;
            int to   = even + group_size - 1;
            while (even <= mid && odd <= to)
            {
                if (min_color(key[even], key[odd]))
                {
                    if (tid.y == even)
                        idy_sorted = k;
                    key_sorted[k++] = key[even++];
                }
                else
                {
                    if (tid.y == odd)
                        idy_sorted = k;
                    key_sorted[k++] = key[odd++];
                }
            }

            // Copy remaining elements
            while (even <= mid)
            {
                if (tid.y == even)
                    idy_sorted = k;
                key_sorted[k++] = key[even++];
            }

            while (odd <= to)
            {
                if (tid.y == odd)
                    idy_sorted = k;
                key_sorted[k++] = key[odd++];
            }

            // calculate the real distance
            int diff_sorted = (idy_sorted % group_size) - (tid.y % (group_size / 2));
            int pos1        = tid.y * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
            bool is_even    = (tid.y % group_size) < group_size / 2;
            if (is_even)
            {
                even_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = pos1;
                if (diff_sorted == 0)
                {
                    odd_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = (tid.y - (tid.y % group_size) + group_size / 2) * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
                }
                else
                {
                    int odd_block_search_start = (tid.y - (tid.y % group_size) + group_size / 2 + diff_sorted - 1) * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
                    for (int i2 = 0; i2 < COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS; i2++)
                    { // n pls make logn in future
                        odd_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = odd_block_search_start + i2;
                        if (min_color(key_sorted[idy_sorted], color_table[odd_block_search_start + i2 + tid.x * COBRA_XCOL_HEIGHT]))
                        {
                            break;
                        }
                        else
                        {
                            odd_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = odd_block_search_start + i2 + 1;
                        }
                    }
                }
            }
            else
            {
                odd_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = pos1;
                if (diff_sorted == 0)
                {
                    even_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = (tid.y - (tid.y % group_size)) * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
                }
                else
                {
                    int even_block_search_start = (tid.y - (tid.y % group_size) + diff_sorted - 1) * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
                    for (int i2 = 0; i2 < COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS; i2++)
                    {
                        even_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = even_block_search_start + i2;
                        if (min_color(key_sorted[idy_sorted], color_table[even_block_search_start + i2 + tid.x * COBRA_XCOL_HEIGHT]))
                        {
                            break;
                        }
                        else
                        {
                            even_block[idy_sorted + tid.x * COBRA_XCOL_THREADS] = even_block_search_start + i2 + 1;
                        }
                    }
                }
            }

            // find the corresponding block
            barrier();
            int even_start, even_end, odd_start, odd_end;
            even_start = even_block[tid.y + tid.x * COBRA_XCOL_THREADS];
            odd_start  = odd_block[tid.y + tid.x * COBRA_XCOL_THREADS];
            if ((tid.y + 1) % group_size == 0)
            {
                even_end = (tid.y - (tid.y % group_size) + group_size / 2) * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
                odd_end  = (tid.y - (tid.y % group_size) + group_size) * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
            }
            else
            {
                even_end = even_block[tid.y + 1 + tid.x * COBRA_XCOL_THREADS];
                odd_end  = odd_block[tid.y + 1 + tid.x * COBRA_XCOL_THREADS];
            }

            // sort the block
            int even_counter = even_start;
            int odd_counter  = odd_start;
            int cc           = 0;
            while (even_counter < even_end && odd_counter < odd_end)
            {
                if (min_color(color_table[even_counter + tid.x * COBRA_XCOL_HEIGHT], color_table[odd_counter + tid.x * COBRA_XCOL_HEIGHT]))
                {
                    sorted_array[cc++] = color_table[even_counter++ + tid.x * COBRA_XCOL_HEIGHT];
                }
                else
                {
                    sorted_array[cc++] = color_table[odd_counter++ + tid.x * COBRA_XCOL_HEIGHT];
                }
            }

            while (even_counter < even_end)
            {
                sorted_array[cc++] = color_table[even_counter++ + tid.x * COBRA_XCOL_HEIGHT];
            }

            while (odd_counter < odd_end)
            {
                sorted_array[cc++] = color_table[odd_counter++ + tid.x * COBRA_XCOL_HEIGHT];
            }

            // replace
            barrier();
            // int sorted_array_size = cc;
            int global_position = odd_start + even_start - (tid.y - (tid.y % group_size) + group_size / 2) * COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS;
            for (int w = 0; w < cc; w++)
            {
                color_table[global_position + w + tid.x * COBRA_XCOL_HEIGHT] = sorted_array[w];
            }
        }

        barrier();
        for (i = 0; i < COBRA_XCOL_HEIGHT / COBRA_XCOL_THREADS; i++)
        {
            color_table[row + i + tid.x * COBRA_XCOL_HEIGHT].a = color_table[row + i + tid.x * COBRA_XCOL_HEIGHT].a % 1.0;
            tex2Dstore(STOR_ColorSort, float2(id.x, row + i), color_table[row + i + tid.x * COBRA_XCOL_HEIGHT]);
        }
    }

    // reproject to output window
    void PS_PrintColorSort(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
    {
        float2 texcoord_new  = rotate(texcoord, UI_RotationAngle, true);
        fragment             = tex2D(SAM_Background, texcoord);
        float fragment_depth = ReShade::GetLinearizedDepth(texcoord);
        fragment             = check_focus(fragment, fragment_depth, texcoord) ? tex2D(SAM_ColorSort, texcoord_new) : fragment;
        fragment             = UI_ShowMask ? tex2D(SAM_Mask, texcoord).rrrr : fragment;
        fragment             = (UI_ShowSelectedHue * UI_FilterColor) ? show_hue(texcoord, fragment) : fragment;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                             Techniques
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    technique TECH_ColorSortMasking <
        ui_label     = "Color Sort: Masking";
        ui_tooltip   = "This is the masking part of the shader. It has to be placed above ColorSort: Main.\n"
                       "All effects between Masking and Main (e.g. Monochrome) will only apply to the sorted area.\n"
                       "------About-------\n"
                       "ColorSort_CS.fx can sort the image pixels by brightness along a user-specified axis.\n"
                       "You can filter the affected pixels by depth and by color.\n"
                       "The shader consumes a lot of resources. To balance between quality and performance,\n"
                       "adjust the preprocessor parameter COLOR_HEIGHT. Check the tooltip for further info.\n\n"
                       "Version:    " COBRA_XCOL_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass MaskColor
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_MaskColor;
            RenderTarget = TEX_Mask;
        }

        pass SaveBackground
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_SaveBackground;
            RenderTarget = TEX_Background;
        }

        pass Gradient
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_Gradient;
        }
    }

    technique TECH_ColorSortMain <
        ui_label     = "Color Sort: Main";
        ui_tooltip   = "------About-------\n"
                       "ColorSort_CS.fx can sort the image pixels by brightness along a user-specified axis.\n"
                       "You can filter the affected pixels by depth and by color.\n"
                       "The shader consumes a lot of resources. To balance between quality and performance,\n"
                       "adjust the preprocessor parameter COLOR_HEIGHT. Check the tooltip for further info.\n\n"
                       "Version:    " COBRA_XCOL_VERSION "\nAuthor:     SirCobra\nCollection: CobraFX\n"
                       "            https://github.com/LordKobra/CobraFX";
    >
    {
        pass PrepareColorSort
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_PrepareColorSort;
            RenderTarget = TEX_HalfRes;
        }

        pass sortColor
        {
            ComputeShader = CS_ColorSort<2, COBRA_XCOL_THREADS>;
            DispatchSizeX = BUFFER_WIDTH / 2;
            DispatchSizeY = 1;
        }

        pass PrintColorSort
        {
            VertexShader = PostProcessVS;
            PixelShader  = PS_PrintColorSort;
        }
    }
} // Namespace End

#endif // Shader End

/*-------------.
| :: Footer :: |
'--------------/

Performance Notes
* 64 threads normal merge sort											n*logn	parallel
 now normal merge sort on 2 arrays the following way:
 currently n<=32 arrays e.g. 32
* split in 64/n e.g. 2 per array										n
* take two arrays and compute key for each split Array a b e.g.a1a2b1b2	n
* sort keys eg a1b1...													n		non-parallel
* compute difference rank between each key and sorted					n		parallel
* find each key in the other array										logn	parallel  currently n
 then make an odd even list for both arrays and the keys

TODO:
* Edge detection or other ideas, e.g. the triangle grid

*/
