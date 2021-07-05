/////////////////////////////////////////////////////////
// cGravity.fx by SirCobra
// Version 0.1
// currently VERY resource-intensive
// This effect lets pixels gravitate towards the bottom in a 3D environment.
// It uses a custom seed (currently the Mandelbrot set) to determine the intensity of each pixel.
// Make sure to also test out the texture-RNG variant with the picture "gravityrng.png" provided in Textures.
// You can replace the texture with your own picture, as long as it is 1920x1080, RGBA8 and has the same name. 
// Only the red-intensity is taken. So either use red images or greyscale images.
// The effect can be applied to a specific area like a DoF shader. The basic methods for this were taken with permission
// from https://github.com/FransBouma/OtisFX/blob/master/Shaders/Emphasize.fx
/////////////////////////////////////////////////////////

//
// UI
//

uniform float GravityIntensity <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.01;
ui_tooltip = "Gravity strength. Higher values look cooler but increase the computation time by a lot!";
> = 0.2;
uniform float GravityRNG <
	ui_type = "drag";
ui_min = 0.01; ui_max = 0.99;
ui_step = 0.02;
ui_tooltip = "Changes the RNG for each pixel.";
> = 0.97;
uniform bool useImage <
	ui_tooltip = "Changes the RNG to the input image called gravityrng.png located in Textures. You can change the image for your own seed as long as the name and resolution stay the same.";
> = false;
uniform bool invertGravity <
	ui_tooltip = "Pixels now move upwards.";
> = false;
uniform bool allowOverlapping <
	ui_tooltip = "This way the effect does not get hidden behind other objects.";
> = false;
uniform bool performanceMode <
	ui_tooltip = "The effect only checks every second pixel.";
> = true;
uniform bool FilterDepth <
	ui_tooltip = "Activates the depth filter option.";
> = false;
uniform float FocusDepth <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "Manual focus depth of the point which has the focus. Range from 0.0, which means camera is the focus plane, till 1.0 which means the horizon is focus plane.";
> = 0.026;
uniform float FocusRangeDepth <
	ui_type = "drag";
ui_min = 0.0; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "The depth of the range around the manual focus depth which should be emphasized. Outside this range, de-emphasizing takes place";
> = 0.001;
uniform float FocusEdgeDepth <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_tooltip = "The depth of the edge of the focus range. Range from 0.00, which means no depth, so at the edge of the focus range, the effect kicks in at full force,\ntill 1.00, which means the effect is smoothly applied over the range focusRangeEdge-horizon.";
ui_step = 0.001;
> = 0.050;
uniform bool Spherical <
	ui_tooltip = "Enables Emphasize in a sphere around the focus-point instead of a 2D plane";
> = false;
uniform int Sphere_FieldOfView <
	ui_type = "drag";
ui_min = 1; ui_max = 180;
ui_tooltip = "Specifies the estimated Field of View you are currently playing with. Range from 1, which means 1 Degree, till 180 which means 180 Degree (half the scene).\nNormal games tend to use values between 60 and 90.";
> = 75;
uniform float Sphere_FocusHorizontal <
	ui_type = "drag";
ui_min = 0; ui_max = 1;
ui_tooltip = "Specifies the location of the focuspoint on the horizontal axis. Range from 0, which means left screen border, till 1 which means right screen border.";
> = 0.5;
uniform float Sphere_FocusVertical <
	ui_type = "drag";
ui_min = 0; ui_max = 1;
ui_tooltip = "Specifies the location of the focuspoint on the vertical axis. Range from 0, which means upper screen border, till 1 which means bottom screen border.";
> = 0.5;
uniform float3 BlendColor <
	ui_type = "color";
ui_tooltip = "Specifies the blend color to blend with the greyscale. in (Red, Green, Blue). Use dark colors to darken further away objects";
> = float3(0.55, 1.0, 0.95);

uniform float EffectFactor <
	ui_type = "drag";
ui_min = 0.0; ui_max = 1.0;
ui_tooltip = "Specifies the factor the desaturation is applied. Range from 0.0, which means the effect is off (normal image), till 1.0 which means the desaturated parts are\nfull greyscale (or color blending if that's enabled)";
> = 1.0;
uniform bool FilterColor <
	ui_tooltip = "Activates the color filter option.";
> = false;
uniform float Value <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "The Value describes the brightness of the hue. 0 is black/no hue and 1 is maximum hue(e.g. pure red).";
> = 1.0;
uniform float ValueRange <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "The tolerance around the value.";
> = 1.0;
uniform float Hue <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "The hue describes the color category. It can be red, green, blue or a mix of them.";
> = 1.0;
uniform float HueRange <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "The tolerance around the hue.";
> = 1.0;
uniform float Saturation <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "The saturation determins the colorfulness. 0 is greyscale and 1 pure colors.";
> = 1.0;
uniform float SaturationRange <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "The tolerance around the saturation.";
> = 1.0;

#include "Reshade.fxh"
#ifndef M_PI
#define M_PI 3.1415927
#endif
#ifndef DPTH
#define DPTH 256
#endif
#ifndef GRAVITY_RES
#define GRAVITY_RES 4
#endif
#ifndef GRAVITY_HEIGHT
#define GRAVITY_HEIGHT BUFFER_HEIGHT/GRAVITY_RES
#endif
#ifndef GRAVITY_WIDTH
#define GRAVITY_WIDTH BUFFER_WIDTH/GRAVITY_RES
#endif
//
// textures
//

texture texGravitySeedMap{ Width = GRAVITY_WIDTH; Height = GRAVITY_HEIGHT; Format = R16F; };
texture texGravitySeedMapCopy{ Width = GRAVITY_WIDTH; Height = GRAVITY_HEIGHT; Format = R16F; };
texture texGravitySeedMap2 < source = "gravityrng.png"; > { Width = 1920; Height = 1080; Format = RGBA8; };
texture texGravityCurrentSettings{ Width = 1; Height = 2; Format = R16F; };
texture texGravityMain{ Width = GRAVITY_WIDTH; Height = GRAVITY_HEIGHT; Format = RGBA8; };
//
// samplers
//

sampler2D SamplerGravitySeedMap{ Texture = texGravitySeedMap; };
sampler2D SamplerGravitySeedMapCopy{ Texture = texGravitySeedMapCopy; };
sampler2D SamplerGravitySeedMap2{ Texture = texGravitySeedMap2; };
sampler2D SamplerGravityCurrentSeed{ Texture = texGravityCurrentSettings; };
sampler2D SamplerGravityMain{ Texture = texGravityMain; MagFilter = POINT; MinFilter = POINT;	MipFilter = POINT; };
storage storageGravityMain{ Texture = texGravityMain; };
//
// code
//

float3 mod(float3 x, float y) //x - y * floor(x/y).
{
	return x - y * floor(x / y);
}
//From Sam Hocevar: http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
float4 rgb2hsv(float4 c)
{
	float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
	float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return float4(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x, 1.0);
}
float inFocus(float4 rgbval, float scenedepth, float2 texcoord)
{
	//colorfilter
	float4 hsvval = rgb2hsv(rgbval);
	bool d1 = abs(hsvval.b - Value) < ValueRange;
	bool d2 = abs(hsvval.r - Hue) < (HueRange + pow(2.71828, -(hsvval.g*hsvval.g) / 0.005)) || (1 - abs(hsvval.r - Hue)) < (HueRange + pow(2.71828, -(hsvval.g*hsvval.g) / 0.01));
	bool d3 = abs(hsvval.g - Saturation) <= SaturationRange;
	bool is_color_focus = (d3 && d2 && d1) || FilterColor == 0; // color threshold
	//depthfilter
	float3 col_val = rgbval.rgb;
	const float scenefocus = FocusDepth;
	const float desaturateFullRange = FocusRangeDepth + FocusEdgeDepth;
	float depthdiff;
	texcoord.x = (texcoord.x - Sphere_FocusHorizontal)*ReShade::ScreenSize.x;
	texcoord.y = (texcoord.y - Sphere_FocusVertical)*ReShade::ScreenSize.y;
	const float degreePerPixel = Sphere_FieldOfView / ReShade::ScreenSize.x;
	const float fovDifference = sqrt((texcoord.x*texcoord.x) + (texcoord.y*texcoord.y))*degreePerPixel;
	depthdiff = Spherical ? sqrt((scenedepth*scenedepth) + (scenefocus*scenefocus) - (2 * scenedepth*scenefocus*cos(fovDifference*(2 * M_PI / 360)))) : depthdiff = abs(scenedepth - scenefocus);
	float coc_val = (1-FilterDepth)+(1 - saturate((depthdiff > desaturateFullRange) ? 1.0 : smoothstep(FocusRangeDepth, desaturateFullRange, depthdiff)));
	return saturate(coc_val)*is_color_focus;
}

//calculate Mandelbrot Seed
//inspired by http://nuclear.mutantstargoat.com/articles/sdr_fract/
float mandelbrotRNG(float2 texcoord: TEXCOORD)
{
	float2 center = float2(0.675, 0.46); // an interesting center at the mandelbrot for our zoom
	float zoom = 0.033*GravityRNG; // smaller numbers increase zoom
	float aspect = ReShade::ScreenSize.x / ReShade::ScreenSize.y; // format to screenspace
	float2 z, c;
	c.x = aspect * (texcoord.x - 0.5) * zoom - center.x;
	c.y = (texcoord.y - 0.5) * zoom - center.y;
	int i;
	z = c;

	for (i = 0; i < 100; i++)
	{
		float x = z.x*z.x - z.y*z.y + c.x;
		float y = 2 * z.x*z.y + c.y;
		if ((x*x + y * y) > 4.0) break;
		z.x = x;
		z.y = y;
	}

	float intensity = 1.0;
	return saturate(((intensity * (i == 100 ? 0.0 : float(i)) / 100) - 0.8) / 0.22);
}
// GRAVITY MAIN
void gravityMain(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
{ //allow overlap: start top always full paint and pointer to lowest painted area O(n)
  //no allow overlap: depth_lookup pointer to highest element. [ID:offset]
	uint2 depth_lookup[DPTH];
	uint top_depth = DPTH - 1;
	uint paintIterator = 0;
	for (uint y = 0; y < GRAVITY_HEIGHT && paintIterator < GRAVITY_HEIGHT; y++) // normal
	{
		uint yi = y + (GRAVITY_HEIGHT - 1 - 2*y)*invertGravity;
		// get your information together
		float4 rgbval = tex2Dfetch(ReShade::BackBuffer, int4(id.x*GRAVITY_RES, yi*GRAVITY_RES, 0, 0)); //access
		float scenedepth = ReShade::GetLinearizedDepth(float2((id.x*GRAVITY_RES +0.5) / BUFFER_WIDTH, (yi*GRAVITY_RES +0.5) / BUFFER_HEIGHT)); //access
		float strength = tex2Dfetch(SamplerGravitySeedMap, int4(id.x, yi, 0, 0)).r; //access
		strength = strength * GravityIntensity * inFocus(rgbval, scenedepth, float2(id.x / GRAVITY_WIDTH, yi / GRAVITY_HEIGHT)); //access
		strength = strength * GRAVITY_HEIGHT;
		// overlap
		if (allowOverlapping) {
			if (paintIterator == y)
				paintIterator++;
			for (uint i = paintIterator; i <= min(y + (uint)strength, GRAVITY_HEIGHT - 1); i++, paintIterator++)
			{
				float4 storeVal = tex2Dfetch(ReShade::BackBuffer, int4(id.x, yi, 0, 0)); //access
				float blendIntensity = smoothstep(y, y + (uint) strength, y);
				storeVal.a = 1;
				storeVal = lerp(storeVal, float4(BlendColor, 1.0), blendIntensity * EffectFactor);
				tex2Dstore(storageGravityMain, float2(id.x, paintIterator + (GRAVITY_HEIGHT - 1 - 2 * paintIterator)*invertGravity), storeVal);
			}
		}
		// update the table
		else {
			uint cur_depth = uint(scenedepth * (DPTH - 1));
			depth_lookup[cur_depth] = float2(y, (uint) strength);
			if (cur_depth < top_depth)
			{
				top_depth = (strength == 0) ? top_depth : cur_depth;
			}
			else {
				// iterate the map
				for (int i = top_depth; i < cur_depth; i++)
				{
					float2 pixel = depth_lookup[top_depth].xy;
					if (pixel.x + pixel.y > y) //|| pixel.x == y)
					{
						float4 storeVal = tex2Dfetch(ReShade::BackBuffer, int4(id.x*GRAVITY_RES, (pixel.x*(1 - invertGravity) + (GRAVITY_HEIGHT - 1 - pixel.x)*invertGravity)* GRAVITY_RES, 0, 0)); //access
						float blendIntensity = smoothstep(pixel.x, pixel.x + pixel.y, y);
						storeVal.a = 1;
						storeVal = lerp(storeVal, float4(BlendColor, 1.0), blendIntensity * EffectFactor);
						tex2Dstore(storageGravityMain, float2(id.x, yi), storeVal); //access (y*(1-invertGravity)+(BUFFER_HEIGHT-1-y)*invertGravity) =y+(BUFFER_HEIGHT-1-2y)*invertGravity
						i = cur_depth + 1;
					}
					else
					{
						depth_lookup[i] = float2(0.0, 0.0);
						top_depth++;
					}
				}
			}
		}
	}
}
//SETUP//////////////////////////////////////////////////////////////////////////////////////////////////////
//RNG MAP
void rng_generateSetup(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{

	float value = tex2D(SamplerGravitySeedMap2, texcoord).r;
	value = saturate((value - 1 + GravityRNG) / GravityRNG);
	fragment = (useImage ? value : mandelbrotRNG(texcoord));
}
void rng_update_mapSetup(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{
	fragment = tex2D(SamplerGravitySeedMap, texcoord).r;
}
//MAIN///////////////////////////////////////////////////////////////////////////////////////////////////////
//RNG MAP
void rng_generate(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{
	float old_rng = tex2D(SamplerGravityCurrentSeed, float2(0, 0.25)).r;
	old_rng += tex2D(SamplerGravityCurrentSeed, float2(0, 0.75)).r;
	float new_rng = GravityRNG + ((useImage) ? 0.01 : 0);
	new_rng += GravityIntensity;
	float value = tex2D(SamplerGravitySeedMap2, texcoord).r;
	value = saturate((value - 1 + GravityRNG) / GravityRNG);
	if (abs(old_rng - new_rng) > 0.001)
	{
		fragment = (useImage ? value : mandelbrotRNG(texcoord));
	}
	else
	{
		fragment = tex2D(SamplerGravitySeedMapCopy, texcoord).r;
	}
}
void rng_update_map(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{
	fragment = tex2D(SamplerGravitySeedMap, texcoord).r;
}

// update current settings - careful with pipeline placement -at the end
void rng_update_settings(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{
	float fragment1 = GravityRNG;
	fragment1 += useImage ? 0.01 : 0;
	float fragment2 = GravityIntensity;
	fragment = ((texcoord.y < 0.5) ? fragment1 : fragment2);
}
// PRINT
void prepare_gravity(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
{
	fragment = float4(tex2D(ReShade::BackBuffer, texcoord).rgb,0);
}
void downsample_gravity(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
{
	fragment = tex2D(SamplerGravityMain, texcoord);
	fragment = fragment.a ? fragment : tex2D(ReShade::BackBuffer, texcoord);
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PIPELINE
//
technique PreGravity < hidden = true; enabled = true; timeout = 1000; >
{
	pass GenerateRNG { VertexShader = PostProcessVS; PixelShader = rng_generateSetup; RenderTarget = texGravitySeedMap; }
	pass UpdateRNGMap { VertexShader = PostProcessVS; PixelShader = rng_update_mapSetup; RenderTarget = texGravitySeedMapCopy; }
}
technique cGravity
{
	pass GenerateRNG { VertexShader = PostProcessVS; PixelShader = rng_generate; RenderTarget = texGravitySeedMap; }
	pass UpdateRNGMap { VertexShader = PostProcessVS; PixelShader = rng_update_map; RenderTarget = texGravitySeedMapCopy; }
	pass prepareGravity { VertexShader = PostProcessVS; PixelShader = prepare_gravity; RenderTarget = texGravityMain; }
	pass GravityMain { ComputeShader = gravityMain<32, 1>; DispatchSizeX = GRAVITY_WIDTH; DispatchSizeY = 1; }
	pass UpdateSettings { VertexShader = PostProcessVS; PixelShader = rng_update_settings; RenderTarget = texGravityCurrentSettings; }
	pass downsampleGravity { VertexShader = PostProcessVS; PixelShader = downsample_gravity; }
}

// Idee Pixelshader: 
// 1. SeedMap erstellen und kopieren für jeden Pixel
// 2. Daraus einen Prefilter DistanceMap und Kopie für jeden Pixel berechnen
// 3. Dann noch Depth+Color Filter als map erstellen um Redundanz zu erspaaren.
// 4. Rekursive für jeden Pixel DistanceMap-mal checken auf Seed*CoC

// Idee Computeshader:
// 1. SeedMap erstellen und kopieren für jeden Pixel
// 2. Computeshader für jede Spalte Radixsort auf Depthvalue
// 3. Ausgabe als Pixelshader

// Fazit: DistanceMap und CocMap fallen weg.

// ToDo: performanceMode, check Performance Difference on 5K