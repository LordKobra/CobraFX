//
// UI
//

uniform float3 Color1 <
	ui_type = "color";
ui_tooltip = "Specifies the blend color to blend with the greyscale. in (Red, Green, Blue). Use dark colors to darken further away objects";
> = float3(0.0, 0.0, 0.0);
uniform float3 Color2 <
	ui_type = "color";
ui_tooltip = "Specifies the blend color to blend with the greyscale. in (Red, Green, Blue). Use dark colors to darken further away objects";
> = float3(1.0, 1.0, 1.0);

#include "Reshade.fxh"
namespace primitiveColor
{
#ifndef COLOR_HEIGHT
#define COLOR_HEIGHT	BUFFER_HEIGHT/8
#endif
	//
	// textures
	//
	texture texHalfRes{ Width = BUFFER_WIDTH; Height = COLOR_HEIGHT; Format = RGBA16F; };
	texture texColorSort{ Width = BUFFER_WIDTH; Height = COLOR_HEIGHT; Format = RGBA16F; };
	storage texColorSortStorage{ Texture = texColorSort; };
	//
	// samplers
	//
	sampler2D SamplerHalfRes{ Texture = texHalfRes; };
	sampler2D SamplerColorSort{ Texture = texColorSort; };
	//
	// code
	//
	bool min_color(float4 a, float4 b)
	{
		float val = (a.r + a.g + a.b) - (b.r + b.g + b.b);
		val = (abs(val) > 0.001) ? val : (2 * a.r - 2 * b.r + a.g - b.g + a.b / 2 - b.b / 2);
		return (val < 0) ? false : true; // a <= b
	}

	void merge_sort(inout float4 A[COLOR_HEIGHT]) //credit source pls
	{
		float4 temp[COLOR_HEIGHT] = A;
		//alt
		int n = COLOR_HEIGHT;
		int high = n - 1;
		int low = 0;
		for (int m = 1; m <= high - low; m = 2 * m)
		{
			for (int i = low; i < high; i += 2 * m)
			{
				int from = i;
				int mid = i + m - 1;
				int to = min(i + 2 * m - 1, high);

				//inside func ////////////////////////////////////////////////
				int k = from, i_2 = from, j = mid + 1;
				// loop till there are elements in the left and right runs
				while (i_2 <= mid && j <= to)
				{
					if (min_color(A[i_2], A[j])) {
						temp[k++] = A[i_2++];
					}
					else {
						temp[k++] = A[j++];
					}
				}
				// Copy remaining elements
				while (i_2 < COLOR_HEIGHT && i_2 <= mid)
					temp[k++] = A[i_2++];
				// copy back to the original array to reflect sorted order
				for (i_2 = from; i_2 <= to; i_2++)
					A[i_2] = temp[i_2];
			}
		}
	}
	// passes
	void half_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(ReShade::BackBuffer, texcoord);
	}
	void sort_color(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
	{
		float column = id.x;
		float colNorm = column * BUFFER_RCP_WIDTH;
		float4 colortable[COLOR_HEIGHT];
		//int interval_start = 0;
		//int interval_end = 0;
		//bool past_active = false, current_active;
		//float3 current_color, d1, d2;
		int i;
		for (i = 0; i < COLOR_HEIGHT; i++) //color1 = area of peace, color2 = area of sorting
		{
			//current
			colortable[i] = tex2Dfetch(SamplerHalfRes, int4(id.x, i, 0, 0)); //replace with COLOR_HEIGHT_DEPENDANCY IN FUTURE
		}
		/*[fastopt] for (i = 0; i < COLOR_HEIGHT; i++) //color1 = area of peace, color2 = area of sorting
		{
			current_color = colortable[i];;
			d1 = distance(Color1.rgb, current_color);
			d2 = distance(Color2.rgb, current_color);
			current_active = (d1 < d2) ? true : false;
			[flatten] if (!past_active && current_active) // the start of a great adventure
			{
				interval_start = i;
				past_active = true; // change state
				//continue;
			}
			[branch] if (past_active && !current_active)
			{
				interval_end = i - 1;
				past_active = false; //change state
				//barrier();
				//merge_sort(colortable);
				//continue;
			}

		}*/
		//float3 copy[COLOR_HEIGHT] = colortable;
		//barrier();
		merge_sort(colortable);
		for (i = 0; i < COLOR_HEIGHT; i++) {
			tex2Dstore(texColorSortStorage, float2(id.x, i), float4(colortable[i]));
		}
	}
	void downsample_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		float4 colFragment = tex2D(SamplerColorSort, texcoord);
		fragment = colFragment;
	}
	//Pipeline
	technique ColorSort
	{
		pass halfColor { VertexShader = PostProcessVS; PixelShader = half_color; RenderTarget = texHalfRes; }
		pass sortColor { ComputeShader = sort_color<64, 1>; DispatchSizeX = BUFFER_WIDTH / 64; DispatchSizeY = 1; }
		pass downsampleColor { VertexShader = PostProcessVS; PixelShader = downsample_color; }
	}
}
