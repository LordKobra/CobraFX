////////////////////////////////////////////////////////////////////////////////////////////////////////
// Cobra Utility (CobraUtility.fxh) by SirCobra
// Version 0.1.0
// You can find info and all my shaders here: https://github.com/LordKobra/CobraFX
//
// --------Description---------
// This header file contains useful functions and definitions for other shaders to use.
// ----------Credits-----------
// The credits are written above the functions.
////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef COBRA_UTL_COLOR
    #error "COBRA_UTL_COLOR not defined"
#endif

#ifndef M_PI
    #define M_PI 3.1415927
#endif

#ifndef M_E
    #define M_E 2.71828183
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//                                           Helper Functions
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

// vector mod and normal fmod
#define fmod(x, y) (frac((x)*rcp(y)) * (y))

struct vs2ps
{
    float4 vpos : SV_Position;
    float4 uv : TEXCOORD0;
};

vs2ps vs_basic(const uint id, float2 extras)
{
    vs2ps o;
    o.uv.x  = (id == 2) ? 2.0 : 0.0;
    o.uv.y  = (id == 1) ? 2.0 : 0.0;
    o.uv.zw = extras;
    o.vpos  = float4(o.uv.xy * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return o;
}

// return value [-M_PI, M_PI]
float atan2_approx(float y, float x)
{
    return acos(x * rsqrt(y * y + x * x)) * (y < 0 ? -1 : 1);
}

#if COBRA_UTL_COLOR

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

#endif
