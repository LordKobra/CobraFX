/////////////////////////////////////////////////////////
// MirrorScreen.fx by SirCobra
// Version 0.1
// Did this shader exist already? We will never know
/////////////////////////////////////////////////////////

#include "ReShade.fxh"

void mirror_screen(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
{
	float2 p = float2(0.5 - abs(texcoord.x - 0.5), texcoord.y);
	fragment = tex2D(ReShade::BackBuffer, p);
}

technique MirrorScreen
{
	pass mirrorScreen { VertexShader = PostProcessVS; PixelShader = mirror_screen; }
}
