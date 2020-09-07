/////////////////////////////////////////////////////////
// LongExposure.fx by SirCobra
// Version 0.1
/////////////////////////////////////////////////////////

//
// UI
//
uniform float ExposureDuration <
	ui_type = "drag";
ui_min = 0.000; ui_max = 1.000;
ui_step = 0.001;
ui_tooltip = "Exposure Duration. 0 means";
> = 0.5;
uniform bool byBrightness <
ui_tooltip = "Turn off to capture all colors. Turn on to go by brightness only.\n";
> = false;
uniform bool Freeze <
ui_tooltip = "Freezes the scene.\n";
> = false;
#include "Reshade.fxh"
#ifndef M_PI
#define M_PI 3.1415927
#endif
namespace LongExposure {
	texture texExposure{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16; };
	texture texExposureCopy{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16; };
	sampler2D samplerExposure{ Texture = texExposure; };
	sampler2D samplerExposureCopy{ Texture = texExposureCopy; };
	storage storageExposure{ Texture = texExposure; };


	float4 mix_color(float4 originalColor, float4 sampleColor)
	{
		float ExposureDuration2 = saturate(tan(1.471*(ExposureDuration - 1)) / 10 + 1);
		float4 outputColor;
		if (byBrightness) 
		{
			outputColor.r = ((originalColor.r + originalColor.g + originalColor.b) < (sampleColor.r + sampleColor.g + sampleColor.b)) ? sampleColor.r : originalColor.r - (0.5*(1 - ExposureDuration2))*abs(sampleColor.r - originalColor.r);
			outputColor.g = ((originalColor.r + originalColor.g + originalColor.b) < (sampleColor.r + sampleColor.g + sampleColor.b)) ? sampleColor.g : originalColor.g - (0.5*(1 - ExposureDuration2))*abs(sampleColor.g - originalColor.g);
			outputColor.b = ((originalColor.r + originalColor.g + originalColor.b) < (sampleColor.r + sampleColor.g + sampleColor.b)) ? sampleColor.b : originalColor.b - (0.5*(1 - ExposureDuration2))*abs(sampleColor.b - originalColor.b);
		}
		else 
		{
			outputColor.r = (originalColor.r < sampleColor.r) ? originalColor.r + (0.5*(1 - ExposureDuration2)*(1 - Freeze))*abs(sampleColor.r - originalColor.r) : originalColor.r - (0.5*(1 - ExposureDuration2)*(1 - Freeze))*abs(sampleColor.r - originalColor.r);
			outputColor.g = (originalColor.g < sampleColor.g) ? originalColor.g + (0.5*(1 - ExposureDuration2)*(1 - Freeze))*abs(sampleColor.g - originalColor.g) : originalColor.g - (0.5*(1 - ExposureDuration2)*(1 - Freeze))*abs(sampleColor.g - originalColor.g);
			outputColor.b = (originalColor.b < sampleColor.b) ? originalColor.b + (0.5*(1 - ExposureDuration2)*(1 - Freeze))*abs(sampleColor.b - originalColor.b) : originalColor.b - (0.5*(1 - ExposureDuration2)*(1 - Freeze))*abs(sampleColor.b - originalColor.b);
		}
		outputColor.a = 1.0;
		return outputColor;
	}
	void long_exposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		float4 sampleColor = tex2D(ReShade::BackBuffer, texcoord);
		float4 originalColor = tex2D(samplerExposureCopy, texcoord);
		originalColor = mix_color(originalColor, sampleColor);
		fragment = originalColor;
	}
	void copy_exposure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(samplerExposure, texcoord);
	}
	void downsample_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(samplerExposure, texcoord);
	}
	technique LongExposure
	{
		pass longExposure { VertexShader = PostProcessVS; PixelShader = long_exposure; RenderTarget = texExposure; }
		pass copyExposure { VertexShader = PostProcessVS; PixelShader = copy_exposure; RenderTarget = texExposureCopy; }
		pass downsampleColor { VertexShader = PostProcessVS; PixelShader = downsample_color; }
	}
}
