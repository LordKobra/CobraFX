/////////////////////////////////////////////////////////
// ColorSort.fx by SirCobra
// Version 0.1
// currently resource-intensive
// This compute shader only runs on the ReShade 4.8 Beta and DX11 or newer.
// This effect does sort all colors on a vertical line by brightness.
// The effect can be applied to a specific area like a DoF shader. The basic methods for this were taken with permission
// from https://github.com/FransBouma/OtisFX/blob/master/Shaders/Emphasize.fx
// Thanks to kingeric1992 & Lord of Lunacy for tips on how to construct the algorithm. :)
// The merge_sort function is adapted from this website: https://www.techiedelight.com/iterative-merge-sort-algorithm-bottom-up/
// The multithreaded merge sort is constructed as described here: https://www.nvidia.in/docs/IO/67073/nvr-2008-001.pdf
/////////////////////////////////////////////////////////

//
// UI
//
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
#include "Reshade.fxh"
namespace primitiveColor
{
#ifndef COLOR_HEIGHT
#define COLOR_HEIGHT	640 //maybe needs multiple of 64 :/
#endif
#ifndef THREAD_HEIGHT
#define THREAD_HEIGHT	16 // 2^n
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
		float val = b.a - a.a; // val > 0 for a smaller
		val = (abs(val) < 0.1) ? ((a.r + a.g + a.b) - (b.r + b.g + b.b)) : val;
		return (val < 0) ? false : true; // Returns False if a smaller, yes its weird
	}
	float3 mod(float3 x, float y) //x - y * floor(x/y).
	{
		return x - y * floor(x / y);
	}
	//HSV functions from iq (https://www.shadertoy.com/view/MsS3Wc)
	float4 hsv2rgb(float4 c)
	{
		float3 rgb = clamp(abs(mod(float3(c.x*6.0, c.x*6.0+4.0, c.x*6.0+2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);

		rgb = rgb * rgb*(3.0 - 2.0*rgb); // cubic smoothing	

		return float4(c.z * lerp(float3(1.0,1.0,1.0), rgb, c.y),1.0);
	}
	//From Sam Hocevar: http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
	float4 rgb2hsv(float4 c)
	{
		float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
		float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
		float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

		float d = q.x - min(q.w, q.y);
		float e = 1.0e-10;
		return float4(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x,1.0);
	}
	bool inFocus(float4 rgbval, float scenedepth)
	{
		//colorfilter
		float4 hsvval = rgb2hsv(rgbval);
		bool d1 = abs(hsvval.b - Value) < ValueRange;
		bool d2 = abs(hsvval.r - Hue) < (HueRange + pow(2.71828, -(hsvval.g*hsvval.g) / 0.005)) || (1-abs(hsvval.r - Hue)) < (HueRange+pow(2.71828,-(hsvval.g*hsvval.g)/0.01));
		bool d3 = abs(hsvval.g - Saturation) <= SaturationRange;
		bool is_color_focus = (d3 && d2 && d1) || FilterColor == 0; // color threshold
		//depthfilter
		bool is_depth_focus = (abs(scenedepth - FocusDepth) < FocusRangeDepth) || FilterDepth == 0;
		return is_color_focus && is_depth_focus;

	}
	groupshared float4 colortable[2 * COLOR_HEIGHT];
	void merge_sort(int low, int high, int em)
	{
		float4 temp[COLOR_HEIGHT / THREAD_HEIGHT];
		for (int i = 0; i < COLOR_HEIGHT / THREAD_HEIGHT; i++)
		{
			temp[i] = colortable[low + i];
		}
		for (int m = em; m <= high - low; m = 2 * m)
		{
			for (int i = low; i < high; i += 2 * m)
			{
				int from = i;
				int mid = i + m - 1;
				int to = min(i + 2 * m - 1, high);
				//inside function //////////////////////////////////
				int k = from, i_2 = from, j = mid + 1;
				while (i_2 <= mid && j <= to)
				{
					if (min_color(colortable[i_2], colortable[j])) {
						temp[k++ - low] = colortable[i_2++];
					}
					else {
						temp[k++ - low] = colortable[j++];
					}
				}
				while (i_2 < high && i_2 <= mid)
				{
					temp[k++ - low] = colortable[i_2++];
				}
				for (i_2 = from; i_2 <= to; i_2++)
				{
					colortable[i_2] = temp[i_2 - low];
				}
			}
		}
	}
	// passes
	groupshared int evenblock[2 * THREAD_HEIGHT];
	groupshared int oddblock[2 * THREAD_HEIGHT];
	void sort_color(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
	{
		int row = tid.y*COLOR_HEIGHT / THREAD_HEIGHT;
		int interval_start = row + tid.x*COLOR_HEIGHT;
		int interval_end = row - 1 + COLOR_HEIGHT / THREAD_HEIGHT + tid.x*COLOR_HEIGHT;
		int i;
		//masking
		if (tid.y == 0)
		{
			bool was_focus = false;
			bool is_focus = false;
			int maskval = 0;
			for (i = 0; i < COLOR_HEIGHT; i++)
			{
				colortable[i + tid.x*COLOR_HEIGHT] = tex2Dfetch(SamplerHalfRes, int4(id.x, i, 0, 0));
				float scenedepth = ReShade::GetLinearizedDepth(float2(float(id.x) / BUFFER_WIDTH, float(i) / COLOR_HEIGHT));
				is_focus = inFocus(colortable[i + tid.x*COLOR_HEIGHT], scenedepth);

				if (!(is_focus && was_focus))
					maskval++;
				was_focus = is_focus;
				colortable[i + tid.x*COLOR_HEIGHT].a = (float)maskval+0.5*is_focus;

			}
		}
		barrier();
		// sort the small arrays
		merge_sort(interval_start, interval_end, 1);
		//combine
		float4 key[THREAD_HEIGHT];
		float4 key_sorted[THREAD_HEIGHT];
		float4 sorted_array[2 * COLOR_HEIGHT / THREAD_HEIGHT];
		for (i = 1; i < THREAD_HEIGHT; i = 2 * i) // the amount of merges, just like a normal merge sort
		{
			barrier();
			int groupsize = 2 * i;
			//keylist
			for (int j = 0; j < groupsize; j++) //probably redundancy between threads. optimzable
			{
				int curr = tid.y - (tid.y % groupsize) + j;
				key[curr] = colortable[curr * COLOR_HEIGHT / THREAD_HEIGHT + tid.x*COLOR_HEIGHT];
			}
			//sort keys
			int idy_sorted;
			int even = tid.y - (tid.y % groupsize);
			int k = even;
			int mid = even + groupsize / 2 - 1;
			int odd = mid + 1;
			int to = even + groupsize - 1;
			while (even <= mid && odd <= to)
			{
				if (min_color(key[even], key[odd]))
				{
					if (tid.y == even) idy_sorted = k;
					key_sorted[k++] = key[even++];
				}
				else
				{
					if (tid.y == odd) idy_sorted = k;
					key_sorted[k++] = key[odd++];
				}
			}
			// Copy remaining elements
			while (even <= mid)
			{
				if (tid.y == even) idy_sorted = k;
				key_sorted[k++] = key[even++];
			}
			while (odd <= to)
			{
				if (tid.y == odd) idy_sorted = k;
				key_sorted[k++] = key[odd++];
			}
			// calculate the real distance
			int diff_sorted = (idy_sorted%groupsize) - (tid.y % (groupsize / 2));
			int pos1 = tid.y *COLOR_HEIGHT / THREAD_HEIGHT;
			bool is_even = (tid.y%groupsize) < groupsize / 2;
			if (is_even)
			{
				evenblock[idy_sorted + tid.x*THREAD_HEIGHT] = pos1;
				if (diff_sorted == 0)
				{
					oddblock[idy_sorted + tid.x*THREAD_HEIGHT] = (tid.y - (tid.y%groupsize) + groupsize / 2)*COLOR_HEIGHT / THREAD_HEIGHT;
				}
				else
				{
					int odd_block_search_start = (tid.y - (tid.y%groupsize) + groupsize / 2 + diff_sorted - 1)*COLOR_HEIGHT / THREAD_HEIGHT;
					for (int i2 = 0; i2 < COLOR_HEIGHT / THREAD_HEIGHT; i2++)
					{ // n pls make logn in future
						oddblock[idy_sorted + tid.x*THREAD_HEIGHT] = odd_block_search_start + i2;
						if (min_color(key_sorted[idy_sorted], colortable[odd_block_search_start + i2 + tid.x*COLOR_HEIGHT]))
						{
							break;
						}
						else
						{
							oddblock[idy_sorted + tid.x*THREAD_HEIGHT] = odd_block_search_start + i2 + 1;
						}
					}
				}
			}
			else
			{
				oddblock[idy_sorted + tid.x*THREAD_HEIGHT] = pos1;
				if (diff_sorted == 0)
				{
					evenblock[idy_sorted + tid.x*THREAD_HEIGHT] = (tid.y - (tid.y%groupsize))*COLOR_HEIGHT / THREAD_HEIGHT;
				}
				else
				{
					int even_block_search_start = (tid.y - (tid.y%groupsize) + diff_sorted - 1)*COLOR_HEIGHT / THREAD_HEIGHT;
					for (int i2 = 0; i2 < COLOR_HEIGHT / THREAD_HEIGHT; i2++) {
						evenblock[idy_sorted + tid.x*THREAD_HEIGHT] = even_block_search_start + i2;
						if (min_color(key_sorted[idy_sorted], colortable[even_block_search_start + i2 + tid.x*COLOR_HEIGHT]))
						{
							break;
						}
						else
						{
							evenblock[idy_sorted + tid.x*THREAD_HEIGHT] = even_block_search_start + i2 + 1;
						}
					}
				}
			}
			// find the corresponding block
			barrier();
			int even_start, even_end, odd_start, odd_end;
			even_start = evenblock[tid.y + tid.x*THREAD_HEIGHT];
			odd_start = oddblock[tid.y + tid.x*THREAD_HEIGHT];
			if ((tid.y + 1) % groupsize == 0)
			{
				even_end = (tid.y - (tid.y%groupsize) + groupsize / 2) *COLOR_HEIGHT / THREAD_HEIGHT;
				odd_end = (tid.y - (tid.y%groupsize) + groupsize) * COLOR_HEIGHT / THREAD_HEIGHT;
			}
			else
			{
				even_end = evenblock[tid.y + 1 + tid.x*THREAD_HEIGHT];
				odd_end = oddblock[tid.y + 1 + tid.x*THREAD_HEIGHT];
			}
			//sort the block
			int even_counter = even_start;
			int odd_counter = odd_start;
			int cc = 0;
			while (even_counter < even_end && odd_counter < odd_end)
			{
				if (min_color(colortable[even_counter + tid.x*COLOR_HEIGHT], colortable[odd_counter + tid.x*COLOR_HEIGHT])) {
					sorted_array[cc++] = colortable[even_counter++ + tid.x*COLOR_HEIGHT];
				}
				else {
					sorted_array[cc++] = colortable[odd_counter++ + tid.x*COLOR_HEIGHT];
				}
			}
			while (even_counter < even_end)
			{
				sorted_array[cc++] = colortable[even_counter++ + tid.x*COLOR_HEIGHT];
			}
			while (odd_counter < odd_end)
			{
				sorted_array[cc++] = colortable[odd_counter++ + tid.x*COLOR_HEIGHT];
			}
			//replace
			barrier();
			int sorted_array_size = cc;
			int global_position = odd_start + even_start - (tid.y - (tid.y%groupsize) + groupsize / 2) *COLOR_HEIGHT / THREAD_HEIGHT;
			for (int w = 0; w < cc; w++)
			{
				colortable[global_position + w + tid.x*COLOR_HEIGHT] = sorted_array[w];
			}
		}
		barrier();
		for (i = 0; i < COLOR_HEIGHT / THREAD_HEIGHT; i++)
		{
			colortable[row + i + tid.x*COLOR_HEIGHT].a = colortable[row + i + tid.x*COLOR_HEIGHT].a % 1;
			tex2Dstore(texColorSortStorage, float2(id.x, row + i), float4(colortable[row + i + tid.x*COLOR_HEIGHT]));
		}
	}
	void half_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(ReShade::BackBuffer, texcoord);
	}
	void downsample_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(ReShade::BackBuffer, texcoord);
		float fragment_depth = ReShade::GetLinearizedDepth(texcoord);
		fragment = inFocus(fragment, fragment_depth) ? tex2D(SamplerColorSort, texcoord) : fragment;
	}
	//Pipeline
	technique ColorSort
	{
		pass halfColor { VertexShader = PostProcessVS; PixelShader = half_color; RenderTarget = texHalfRes; }
		pass sortColor { ComputeShader = sort_color<2, THREAD_HEIGHT>; DispatchSizeX = BUFFER_WIDTH / 2; DispatchSizeY = 1; }
		pass downsampleColor { VertexShader = PostProcessVS; PixelShader = downsample_color; }
	}
}


//sampling:
/*
64 threads normal merge sort											n*logn	parallel
now normal merge sort on 2 arrays the following way:
currently n<=32 arrays e.g. 32
split in 64/n e.g. 2 per array											n
take two arrays and compute key for each split Array a b e.g.a1a2b1b2	n
sort keys eg a1b1...													n		non-parallel
compute difference rank between each key and sorted						n		parallel
find each key in the other array										logn	parallel  currently n
then make an odd even list for both arrays and the keys
*/
