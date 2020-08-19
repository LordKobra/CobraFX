/////////////////////////////////////////////////////////
// Gravity.fx by SirCobra
// Version 0.1
// currently VERY resource-intensive
// This effect lets pixels gravitate towards the bottom in a 3D environment.
// It uses a custom seed (currently the Mandelbrot set) to determine the intensity of each pixel.
// The effect can be applied to a specific area like a DoF shader. The basic methods for this were taken with permission
// from https://github.com/FransBouma/OtisFX/blob/master/Shaders/Emphasize.fx
/////////////////////////////////////////////////////////

//
// UI
//

uniform float GravityIntensity <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "Gravity strength. Higher values look cooler but increase the computation time by a lot!";
> = 0.5;
uniform float GravityRNG <
	ui_type = "drag";
ui_min = 0.01; ui_max = 1;
ui_step = 0.01;
ui_tooltip = "Changes the RNG for each pixel.";
> = 75;
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
/*uniform float BlendFactor <
	ui_type = "drag";
ui_min = 0.0; ui_max = 1.0;
ui_tooltip = "Specifies the factor BlendColor is blended. Range from 0.0, which means full greyscale, till 1.0 which means full blend of the BlendColor";
> = 1.0;*/
uniform float EffectFactor <
	ui_type = "drag";
ui_min = 0.0; ui_max = 1.0;
ui_tooltip = "Specifies the factor the desaturation is applied. Range from 0.0, which means the effect is off (normal image), till 1.0 which means the desaturated parts are\nfull greyscale (or color blending if that's enabled)";
> = 1.0;

#include "Reshade.fxh"

#ifndef M_PI
	#define M_PI 3.1415927
#endif

//
// textures
//

texture texGravitySeedMap { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F;};
texture texGravitySeedMapCopy{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
texture texGravityCurrentSeed{ Width = 1; Height = 1; Format = R16F; };

//
// samplers
//

sampler2D SamplerGravitySeedMap{ Texture = texGravitySeedMap; };
sampler2D SamplerGravitySeedMapCopy{ Texture = texGravitySeedMapCopy; };
sampler2D SamplerGravityCurrentSeed{ Texture = texGravityCurrentSeed; };

//
// code
//

// Calculate Pixel Depth
float CalculateDepth(float2 texcoord : TEXCOORD)
{
	const float scenedepth = ReShade::GetLinearizedDepth(texcoord);
	return scenedepth;
}

// Calculate Focus Intensity
float CalculateDepthDiffCoC(float2 texcoord : TEXCOORD)
{
	const float scenedepth = ReShade::GetLinearizedDepth(texcoord);
	const float scenefocus = FocusDepth;
	const float desaturateFullRange = FocusRangeDepth + FocusEdgeDepth;
	float depthdiff;

	if (Spherical == true)
	{
		texcoord.x = (texcoord.x - Sphere_FocusHorizontal)*ReShade::ScreenSize.x;
		texcoord.y = (texcoord.y - Sphere_FocusVertical)*ReShade::ScreenSize.y;
		const float degreePerPixel = Sphere_FieldOfView / ReShade::ScreenSize.x;
		const float fovDifference = sqrt((texcoord.x*texcoord.x) + (texcoord.y*texcoord.y))*degreePerPixel;
		depthdiff = sqrt((scenedepth*scenedepth) + (scenefocus*scenefocus) - (2 * scenedepth*scenefocus*cos(fovDifference*(2 * M_PI / 360))));
	}
	else
	{
		depthdiff = abs(scenedepth - scenefocus);
	}

	return (1-saturate((depthdiff > desaturateFullRange) ? 1.0 : smoothstep(0, desaturateFullRange, depthdiff)));
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
		float y = 2*z.x*z.y + c.y;
		if ((x*x + y*y) > 4.0) break;
		z.x = x;
		z.y = y;
	}

	float intensity = 1.0;
	return saturate(((intensity * (i == 100 ? 0.0 : float(i)) / 100)-0.8)/0.22);
}

// Applies Gravity to the Pixels recursively
float4 Gravity_main(float2 texcoord : TEXCOORD) 
{
	float2 tex2 = texcoord;
	float tex2_distance = 0;	
	if (GravityIntensity < 0.01) return tex2D(ReShade::BackBuffer, texcoord); // 1. check grav - global
	// continue with local procedure
	float depth_threshold = CalculateDepth(texcoord); //get base threshold
	float pixelHeight = 1 / ReShade::ScreenSize.y; //get pixel size
	float2 offset = float2(0.0, pixelHeight);
	int iterations = round(GravityIntensity / pixelHeight);
	int j;

	for (j = 1; j <= iterations; j++) 
	{
		// 2. check depth
		float curr_depth = ReShade::GetLinearizedDepth(texcoord- j*offset);
		if (curr_depth > depth_threshold) continue;
		// 3. check focus
		float focus = CalculateDepthDiffCoC(texcoord - j * offset);
		if (focus < 0.01) continue;
		// 4. mandelbrotRNG
		float mandelbrot = tex2Dlod(SamplerGravitySeedMap, float4(texcoord-j*offset,0,1)).r;
		if (mandelbrot < 0.05) continue;
		float tex_distance_max = GravityIntensity*focus*mandelbrot; 

		if ((tex_distance_max) > (j * offset.y)) 
		{
			depth_threshold = curr_depth;
			tex2 = texcoord - j * offset;
			tex2_distance = j * offset.y/tex_distance_max; //we want 0 close to 1 max distance
		}
	}

	float4 colFragment = tex2D(ReShade::BackBuffer, tex2);
	return lerp(colFragment, float4(BlendColor, 1.0),tex2_distance * tex2_distance*EffectFactor);
	//return lerp(colFragment, float4(BlendColor,1.0), ((tex2_distance > 0) ? ((1-tex2_distance*tex2_distance)*EffectFactor) : 0));
}


void rng_generate(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{
	float old_rng = tex2D(SamplerGravityCurrentSeed, float2(0, 0)).r;
	fragment = (abs(old_rng - GravityRNG) > 0.001) ? mandelbrotRNG(texcoord) : tex2D(SamplerGravitySeedMapCopy, texcoord).r;
}
void rng_update_map(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{
	fragment = tex2D(SamplerGravitySeedMap, texcoord).r;
}
void rng_update_seed(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float fragment : SV_Target)
{
	fragment = GravityRNG;
}
void gravity_func(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 outFragment : SV_Target)
{
	outFragment = Gravity_main(texcoord);
	return;
}


technique Gravity
{
	pass GenerateRNG { VertexShader = PostProcessVS; PixelShader = rng_generate; RenderTarget = texGravitySeedMap; }
	pass UpdateRNGMap { VertexShader = PostProcessVS; PixelShader = rng_update_map; RenderTarget = texGravitySeedMapCopy; }
	pass UpdateRNGSeed { VertexShader = PostProcessVS; PixelShader = rng_update_seed; RenderTarget = texGravityCurrentSeed; }
	pass ApplyGravity { VertexShader = PostProcessVS; PixelShader = gravity_func; }
}



