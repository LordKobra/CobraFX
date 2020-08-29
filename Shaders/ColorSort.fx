//
// UI
//

uniform float3 Color1 <
	ui_type = "color";
ui_tooltip = "desc";
> = float3(0.0, 0.0, 0.0);
uniform float3 Color2 <
	ui_type = "color";
ui_tooltip = "desc";
> = float3(1.0, 1.0, 1.0);
#include "Reshade.fxh"
namespace primitiveColor
{
#ifndef COLOR_HEIGHT
#define COLOR_HEIGHT	768 //maybe needs multiple of 64 :/
#endif
#ifndef THREAD_HEIGHT
#define THREAD_HEIGHT	32
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
		return (val < 0) ? false : true; // a <= b Returns False if a smaller
	}
	
	groupshared float4 colortable[COLOR_HEIGHT];

	//groupshared float4 temp[COLOR_HEIGHT];
	void merge_sort(int low, int high, int em) //credit source pls
	{
		float4 temp[COLOR_HEIGHT/ THREAD_HEIGHT];
		for (int i = 0; i < COLOR_HEIGHT/THREAD_HEIGHT; i++) 
		{
			temp[i] = colortable[low+i];
		}
		for (int m = em; m <= high - low; m = 2 * m)
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
					if (min_color(colortable[i_2], colortable[j])) {	
						temp[k++-low] = colortable[i_2++];
					}
					else {
						temp[k++-low] = colortable[j++];
					}
				}
				// Copy remaining elements
				while (i_2 < high && i_2 <= mid)
				{
					temp[k++-low] = colortable[i_2++];
				}	
				// copy back to the original array to reflect sorted order
				for (i_2 = from; i_2 <= to; i_2++) 
				{
					colortable[i_2] = temp[i_2-low];
				}		
			}
		}
	}
	// passes
	groupshared int evenblock[THREAD_HEIGHT];
	groupshared int oddblock[THREAD_HEIGHT];
	void sort_color(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
	{
		int row = tid.y*COLOR_HEIGHT / THREAD_HEIGHT;
		int interval_start = row;
		int interval_end = row - 1 + COLOR_HEIGHT / THREAD_HEIGHT;
		int i;
		// fill everything with content
		for (i = 0; i < COLOR_HEIGHT / THREAD_HEIGHT; i++)
		{
			colortable[row + i] = tex2Dfetch(SamplerHalfRes, int4(id.x, row + i, 0, 0));
		}
		// sort the small arrays
		merge_sort(interval_start, interval_end,1);
		//combine
		float4 key[THREAD_HEIGHT];
		float4 key_sorted[THREAD_HEIGHT];
		float4 sorted_array[2 * COLOR_HEIGHT / THREAD_HEIGHT];
		for (i = 1; i < THREAD_HEIGHT; i = 2 * i) // the amount of merges, just like a normal merge sort
		{ 
			barrier();
			int groupsize = 2 * i; // mistake corrected
			//keylist
			for (int j = 0; j < groupsize; j++)
			{
				int curr = tid.y - (tid.y % groupsize) + j;
				key[curr] = colortable[curr * COLOR_HEIGHT / THREAD_HEIGHT];
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
			
			// calculate the real distance // CHECK FOR CORRECTNESS
			// original pos of key[id.y] = id.y % groupsize/2
			// sorted pos of key[id.y] = idy_sorted
			//barrier();
			int diff_sorted = (idy_sorted%groupsize) - (tid.y%(groupsize/2));
			int pos1 = tid.y *COLOR_HEIGHT / THREAD_HEIGHT; //original position
			bool is_even = (tid.y%groupsize) < groupsize / 2;
			if (is_even)
			{
				evenblock[idy_sorted] = pos1;
				if (diff_sorted == 0)
				{
					oddblock[idy_sorted] = (tid.y - (tid.y%groupsize) + groupsize / 2)*COLOR_HEIGHT / THREAD_HEIGHT;
				}
				else
				{
					int odd_block_search_start = (tid.y - (tid.y%groupsize) + groupsize / 2 + diff_sorted - 1)*COLOR_HEIGHT / THREAD_HEIGHT;
					for (int i2 = 0; i2 < COLOR_HEIGHT / THREAD_HEIGHT; i2++) 
					{ // n pls make logn in future
						oddblock[idy_sorted] = odd_block_search_start + i2;
						if (min_color(key_sorted[idy_sorted], colortable[odd_block_search_start + i2]))
						{
							break;
						}
						else
						{
							oddblock[idy_sorted] = odd_block_search_start + i2 + 1;
						}
					}
				}
			}
			else
			{
				oddblock[idy_sorted] = pos1;
				if (diff_sorted == 0)
				{
					evenblock[idy_sorted] = (tid.y - (tid.y%groupsize))*COLOR_HEIGHT / THREAD_HEIGHT;
				}
				else
				{
					int even_block_search_start = (tid.y - (tid.y%groupsize) + diff_sorted - 1)*COLOR_HEIGHT / THREAD_HEIGHT;
					for (int i2 = 0; i2 < COLOR_HEIGHT / THREAD_HEIGHT; i2++) {
						evenblock[idy_sorted] = even_block_search_start + i2;
						if (min_color(key_sorted[idy_sorted], colortable[even_block_search_start + i2]))
						{
							break;
						}
						else
						{
							evenblock[idy_sorted] = even_block_search_start + i2 + 1;
						}
					}
				}
			}
			
			/// find the corresponding block
			barrier();
			int even_start, even_end, odd_start, odd_end;
			/*even_end = evenblock[tid.y];
			odd_end = oddblock[tid.y];
			if (tid.y%groupsize == 0) 
			{
				even_start = (tid.y - (tid.y%groupsize)) *COLOR_HEIGHT / THREAD_HEIGHT;
				odd_start = (tid.y - (tid.y%groupsize) + groupsize / 2) * COLOR_HEIGHT / THREAD_HEIGHT;

			}
			else
			{
				even_start = evenblock[tid.y-1];
				odd_start = oddblock[tid.y-1];
			}*/
			even_start = evenblock[tid.y];
			odd_start = oddblock[tid.y];

			if ((tid.y + 1) % groupsize == 0)
			{
				even_end = (tid.y - (tid.y%groupsize) + groupsize / 2) *COLOR_HEIGHT / THREAD_HEIGHT;
				odd_end = (tid.y - (tid.y%groupsize) + groupsize) * COLOR_HEIGHT / THREAD_HEIGHT;
			}
			else
			{
				even_end = evenblock[tid.y + 1];
				odd_end = oddblock[tid.y + 1];
			}
			//do the job
			int even_counter = even_start;
			int odd_counter = odd_start;
			int cc = 0;
			while (even_counter < even_end && odd_counter < odd_end)
			{
				if (min_color(colortable[even_counter], colortable[odd_counter])) {
					sorted_array[cc++] = colortable[even_counter++];
				}
				else {
					sorted_array[cc++] = colortable[odd_counter++];
				}
			}
			while (even_counter < even_end)
			{
				sorted_array[cc++] = colortable[even_counter++];
			}
			while (odd_counter < odd_end)
			{
				sorted_array[cc++] = colortable[odd_counter++];
			}
			//replace
			barrier();
			int sorted_array_size = cc;
			//thisevenstart-globalevenstart + thisoddstart - globaloddstart + globalevenstart
			int global_position = odd_start + even_start - (tid.y - (tid.y%groupsize) + groupsize / 2) *COLOR_HEIGHT / THREAD_HEIGHT;
			for (int w = 0; w < cc; w++)
			{
				colortable[global_position + w] = sorted_array[w];
			}			
			//barrier();
			
		}
		barrier();
		for (i = 0; i < COLOR_HEIGHT / THREAD_HEIGHT; i++) 
		{
				tex2Dstore(texColorSortStorage, float2(id.x, row+i), float4(colortable[row+i]));
		}
	}

	void half_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(ReShade::BackBuffer, texcoord);
	}
	void switch_1(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(SamplerColorSort, texcoord);
	}
	void downsample_color(float4 vpos : SV_Position, float2 texcoord : TEXCOORD, out float4 fragment : SV_Target)
	{
		fragment = tex2D(SamplerColorSort, texcoord);
	}
	//Pipeline
	technique ColorSort
	{
		pass halfColor { VertexShader = PostProcessVS; PixelShader = half_color; RenderTarget = texHalfRes; }
		pass sortColor { ComputeShader = sort_color<1, THREAD_HEIGHT>; DispatchSizeX = BUFFER_WIDTH; DispatchSizeY = 1; }
		//pass switch1 { VertexShader = PostProcessVS; PixelShader = switch_1; RenderTarget = texHalfRes; }
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
find each key in the other array										logn	parallel
then make an odd even list for both arrays and the keys
*/
