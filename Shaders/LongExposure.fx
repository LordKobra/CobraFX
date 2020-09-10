/////////////////////////////////////////////////////////
// LongExposure.fx by SirCobra
// Version 0.1
//
// --------Description---------
// There are two modes: Filter by brightness or all colors.
// If you filter by brightness, brighter pixels will stay longer in the frame.
//
// If you do not filter by brightness, every change will have an impact.
// To preserve every change on a static scenery, it is recommended to freeze the current image and not move the camera.
// It will give the shader an expectation of the original image, so it can better keep track of changes.
// Exposure Duration and Precision will let you decide how long the effect should stay.
/////////////////////////////////////////////////////////

//
// UI
//
uniform float ExposureDuration <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "Exposure Duration. 0 means no duration, 1 means infinite duration.";
> = 0.5;
uniform float Precision <
	ui_type = "drag";
ui_min = 1; ui_max = 10;
ui_step = 1;
ui_tooltip = "Scaling Precision for longer Exposures. 1 means high precision on low exposures, 10 high precision on high exposures.";
> = 1;
uniform bool byBrightness <
ui_tooltip = "Turn off to capture all colors. Turn on to go by brightness only.\n";
> = false;
uniform bool Freeze <
ui_tooltip = "Freezes the scene. Do this on a static scene without moving the camera, so the shader can better preserve changes.\n";
> = false;
uniform float FreezeThreshold <
	ui_type = "drag";
ui_min = 0.00; ui_max = 1;
ui_step = 0.01;
ui_tooltip = "This determins the minimum difference in color necessary to overwrite the Freeze Image.";
> = 0.01;
#include "Reshade.fxh"
#ifndef M_PI
#define M_PI 3.1415927
#endif

//
// Code
//
namespace LongExposure {
	texture texExposure{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16; };
	texture texExposureCopy{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16; };
	texture texFreeze{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
	texture texFreezeCopy{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
	sampler2D samplerExposure{ Texture = texExposure; };
	sampler2D samplerExposureCopy{ Texture = texExposureCopy; };
	sampler2D samplerFreeze{ Texture = texFreeze; };
	sampler2D samplerFreezeCopy{ Texture = texFreezeCopy; };


	float4 mix_color(float4 base, float4 originalColor, float4 sampleColor)
	{
		float ExposureDuration2 = sqrt(saturate(1 - (ExposureDuration - 1)*(ExposureDuration - 1)));//saturate(tan(1.471*(ExposureDuration - 1)) / 10 + 1);
		float4 outputColor;
		if (byBrightness) 
		{
			outputColor.r = ((originalColor.r + originalColor.g + originalColor.b) < (sampleColor.r + sampleColor.g + sampleColor.b)) ? sampleColor.r : originalColor.r - (1/ Precision *(1 - ExposureDuration2))*abs(sampleColor.r - originalColor.r);
			outputColor.g = ((originalColor.r + originalColor.g + originalColor.b) < (sampleColor.r + sampleColor.g + sampleColor.b)) ? sampleColor.g : originalColor.g - (1/ Precision *(1 - ExposureDuration2))*abs(sampleColor.g - originalColor.g);
			outputColor.b = ((originalColor.r + originalColor.g + originalColor.b) < (sampleColor.r + sampleColor.g + sampleColor.b)) ? sampleColor.b : originalColor.b - (1/ Precision *(1 - ExposureDuration2))*abs(sampleColor.b - originalColor.b);
		}
		else 
		{
			if(Freeze) // base.r check diff originalColor sampleColor to r d(base,sample) d(base, original) if d_bs < d_bo, keep, else increase by d_bo+q*(d_bs-d_bo or fixed)
			{
				float d_bs = abs(base.r - sampleColor.r) + abs(base.g - sampleColor.g) + abs(base.b - sampleColor.b);
				float d_bo = abs(base.r - originalColor.r) + abs(base.g - originalColor.g) + abs(base.b - originalColor.b);
				float d_os = abs(sampleColor.r + sampleColor.g + sampleColor.b - originalColor.r - originalColor.g - originalColor.b);

				outputColor.r = originalColor.r + (sampleColor.r - originalColor.r)*0.33*saturate(d_bs / 3 - FreezeThreshold);
				outputColor.g = originalColor.g + (sampleColor.g - originalColor.g)*0.33*saturate(d_bs / 3 - FreezeThreshold);
				outputColor.b = originalColor.b + (sampleColor.b - originalColor.b)*0.33*saturate(d_bs / 3 - FreezeThreshold);
				//degradation
				outputColor.r -= (outputColor.r - base.r) * (1 / Precision * (1 - ExposureDuration2));
				outputColor.g -= (outputColor.g - base.g) * (1 / Precision * (1 - ExposureDuration2));
				outputColor.b -= (outputColor.b - base.b) * (1 / Precision * (1 - ExposureDuration2));
			}
			else
			{
				outputColor.r = (originalColor.r < sampleColor.r) ? originalColor.r + (1 / Precision * (1 - ExposureDuration2))*abs(sampleColor.r - originalColor.r) : originalColor.r - (1 / Precision * (1 - ExposureDuration2))*abs(sampleColor.r - originalColor.r);
				outputColor.g = (originalColor.g < sampleColor.g) ? originalColor.g + (1 / Precision * (1 - ExposureDuration2))*abs(sampleColor.g - originalColor.g) : originalColor.g - (1 / Precision * (1 - ExposureDuration2))*abs(sampleColor.g - originalColor.g);
				outputColor.b = (originalColor.b < sampleColor.b) ? originalColor.b + (1 / Precision * (1 - ExposureDuration2))*abs(sampleColor.b - originalColor.b) : originalColor.b - (1 / Precision * (1 - ExposureDuration2))*abs(sampleColor.b - originalColor.b);
			}
		}
		outputColor.a = 1.0;
		return outputColor;
	}
	void long_exposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		float4 sampleColor = tex2D(ReShade::BackBuffer, texcoord);
		float4 currentColor = tex2D(samplerExposureCopy, texcoord);
		float4 baseColor = tex2D(samplerFreeze, texcoord);
		currentColor = mix_color(baseColor, currentColor, sampleColor);
		fragment = currentColor;
	}
	void copy_exposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(samplerExposure, texcoord);
	}
	void freeze(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = Freeze ? tex2D(samplerFreezeCopy, texcoord) : tex2D(ReShade::BackBuffer, texcoord);
	}
	void copy_freeze(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(samplerFreeze, texcoord);
	}
	void downsample_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(samplerExposure, texcoord);
	}
	technique LongExposure
	{
		pass Freeze { VertexShader = PostProcessVS; PixelShader = freeze; RenderTarget = texFreeze; }
		pass copyFreeze { VertexShader = PostProcessVS; PixelShader = copy_freeze; RenderTarget = texFreezeCopy; }
		pass longExposure { VertexShader = PostProcessVS; PixelShader = long_exposure; RenderTarget = texExposure; }
		pass copyExposure { VertexShader = PostProcessVS; PixelShader = copy_exposure; RenderTarget = texExposureCopy; }
		pass downsampleColor { VertexShader = PostProcessVS; PixelShader = downsample_color; }
	}
}
