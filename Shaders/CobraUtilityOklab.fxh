// converted to reshade from https://bottosson.github.io/misc/ok_color.h

// toe function for L_r
float toe(float l)
{
    const float K1 = 0.206;
    const float K2 = 0.03;
    const float K3 = (1.0 + K1) / (1.0 + K2);
    return 0.5 * (K3 * l - K1 + sqrt((K3 * l - K1) * (K3 * l - K1) + 4.0 * K2 * K3 * l));
}

// from https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab
float oklab_l_to_lr(float l)
{
    /* const float K1 = 0.206;
    const float K2 = 0.03;
    const float K3 = (1.0 + K1) / (1.0 + K2);
    float lr = (K3 * l - K1 + sqrt((K3 * l - K1) * (K3 * l - K1) + 4.0 * K2 * K3 * l)) / 2.0; */
    return toe(l);
}

// inverse toe function for L_r
float toe_inv(float l)
{
    const float K1 = 0.206;
    const float K2 = 0.03;
    const float K3 = (1.0 + K1) / (1.0 + K2);
    return (l * l + K1 * l) / (K3 * (l + K2));
}

float2 to_ST(float2 cusp)
{
    return float2(cusp.y / cusp.x, cusp.y / (1.0 - cusp.x));
}

float2 get_ST_mid(float2 ab_)
{
    float a_ = ab_.x;
    float b_ = ab_.y;
    float s = 0.11516993 + 1.0 / (
        +7.44778970 + 4.15901240 * b_
        + a_ * (-2.19557347 + 1.75198401 * b_
            + a_ * (-2.13704948 - 10.02301043 * b_
                + a_ * (-4.24894561 + 5.38770819 * b_ + 4.69891013 * a_
                    )))
        );

    float t = 0.11239642 + 1.0 / (
        +1.61320320 - 0.68124379 * b_
        + a_ * (+0.40370612 + 0.90148123 * b_
            + a_ * (-0.27087943 + 0.61223990 * b_
                + a_ * (+0.00299215 - 0.45399568 * b_ - 0.14661872 * a_
                    )))
        );

    return float2(s, t);
}

// Finds the maximum saturation possible for a given hue that fits in sRGB
// Saturation here is defined as S = C/L
// a and b must be normalized so a^2 + b^2 == 1
float compute_max_saturation(float2 ab)
{
    float a = ab.x;
    float b = ab.y;
	// Max saturation will be when one of r, g or b goes below zero.

	// Select different coefficients depending on which component goes below zero first
	float k0, k1, k2, k3, k4, wl, wm, ws;

	if (-1.88170328f * a - 0.80936493f * b > 1.0)
	{
		// Red component
		k0 = +1.19086277f; k1 = +1.76576728f; k2 = +0.59662641f; k3 = +0.75515197f; k4 = +0.56771245f;
		wl = +4.0767416621f; wm = -3.3077115913f; ws = +0.2309699292f;
	}
	else if (1.81444104f * a - 1.19445276f * b > 1.0)
	{
		// Green component
		k0 = +0.73956515f; k1 = -0.45954404f; k2 = +0.08285427f; k3 = +0.12541070f; k4 = +0.14503204f;
		wl = -1.2684380046f; wm = +2.6097574011f; ws = -0.3413193965f;
	}
	else
	{
		// Blue component
		k0 = +1.35733652f; k1 = -0.00915799f; k2 = -1.15130210f; k3 = -0.50559606f; k4 = +0.00692167f;
		wl = -0.0041960863f; wm = -0.7034186147f; ws = +1.7076147010f;
	}

	// Approximate max saturation using a polynomial:
	float S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b;

	// Do one step Halley's method to get closer
	// this gives an error less than 10e6, except for some blue hues where the dS/dh is close to infinite
	// this should be sufficient for most applications, otherwise do two/three steps 

	float k_l = +0.3963377774f * a + 0.2158037573f * b;
	float k_m = -0.1055613458f * a - 0.0638541728f * b;
	float k_s = -0.0894841775f * a - 1.2914855480f * b;

	{
		float l_ = 1.f + S * k_l;
		float m_ = 1.f + S * k_m;
		float s_ = 1.f + S * k_s;

		float l = l_ * l_ * l_;
		float m = m_ * m_ * m_;
		float s = s_ * s_ * s_;

		float l_dS = 3.f * k_l * l_ * l_;
		float m_dS = 3.f * k_m * m_ * m_;
		float s_dS = 3.f * k_s * s_ * s_;

		float l_dS2 = 6.f * k_l * k_l * l_;
		float m_dS2 = 6.f * k_m * k_m * m_;
		float s_dS2 = 6.f * k_s * k_s * s_;

		float f = wl * l + wm * m + ws * s;
		float f1 = wl * l_dS + wm * m_dS + ws * s_dS;
		float f2 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2;

		S = S - f * f1 / (f1 * f1 - 0.5f * f * f2);
	}

	return S;
}

// finds L_cusp and C_cusp for a given hue
// a and b must be normalized so a^2 + b^2 == 1
float2 find_cusp(float2 ab)
{
    // First, find the maximum saturation (saturation S = C/L)
    float s_cusp = compute_max_saturation(ab);

    // Convert to linear sRGB to find the first point where at least one of r,g or b >= 1:
    float3 rgb_at_max = oklab_to_srgb(float3(1.0, s_cusp * ab.x, s_cusp * ab.y));
    float l_cusp = pow(1.0 / max(max(rgb_at_max.r, rgb_at_max.g), rgb_at_max.b), 1.0 / 3.0);
    float c_cusp = l_cusp * s_cusp;

    return float2(l_cusp , c_cusp);
}

// Finds intersection of the line defined by 
// L = L0 * (1 - t) + t * L1;
// C = t * C1;
// a and b must be normalized so a^2 + b^2 == 1
float find_gamut_intersection(float a, float b, float L1, float C1, float L0, float2 cusp)
{
	// Find the intersection for upper and lower half seprately
	float t;
	if (((L1 - L0) * cusp.y - (cusp.x - L0) * C1) <= 0.0)
	{
		// Lower half

		t = cusp.y * L0 / (C1 * cusp.x + cusp.y * (L0 - L1));
	}
	else
	{
		// Upper half

		// First intersect with triangle
		t = cusp.y * (L0 - 1.0) / (C1 * (cusp.x - 1.0) + cusp.y * (L0 - L1));

		// Then one step Halley's method
		{
			float dL = L1 - L0;
			float dC = C1;
            const float3x2 M1 = float3x2(  0.3963377774,  0.2158037573,
                                          -0.1055613458, -0.0638541728,
                                          -0.0894841775, -1.2914855480  );
            float3 k_lms = mul(M1, float2(a,b));

            float3 lms_dt = dL + dC * k_lms;

			// If higher accuracy is required, 2 or 3 iterations of the following block can be used:
			{
				float L = L0 * (1.0 - t) + t * L1;
				float C = t * C1;

                float3 lms_ = L + C * k_lms;
                float3 lms  = pow(lms_, 3.0);
                float3 lmsdt = 3.0 * lms_dt * lms_ * lms_;
                float3 lmsdt2 = 6.0 * lms_dt * lms_dt * lms_;
                const float3x3 M2 = float3x3(  4.0767416621, -3.3077115913,  0.2309699292,
                                              -1.2684380046,  2.6097574011, -0.3413193965,
                                              -0.0041960863, -0.7034186147,  1.7076147010  );
                
                float3 rgb = mul(M2, lms) - 1.0;
                float3 rgb1 = mul(M2, lmsdt);
                float3 rgb2 = mul(M2, lmsdt2);
                float3 u_rgb = rgb1 / (rgb1 * rgb1 - 0.5 * rgb * rgb2);
                float3 t_rgb = -rgb * u_rgb;
                t_rgb = u_rgb >= 0.0 ? t_rgb : float(0x7f7fffff);

				t += min(t_rgb.r, min(t_rgb.g, t_rgb.b));
			}
		}
	}

	return t;
}

float3 get_Cs(float3 lab_)
{
    float L  = lab_.x;
    float a_ = lab_.y;
    float b_ = lab_.z;
    float2 cusp = find_cusp(lab_.yz);

    float C_max = find_gamut_intersection(a_, b_, L, 1.0, L, cusp);
    float2 ST_max = to_ST(cusp);
    
    // Scale factor to compensate for the curved part of gamut shape:
    float k = C_max / min((L * ST_max.x), (1.0 - L) * ST_max.y);

    float C_mid;
    {
        float2 ST_mid = get_ST_mid(lab_.yz);

        // Use a soft minimum function, instead of a sharp triangle shape to get a smooth value for chroma.
        float C_a = L * ST_mid.x;
        float C_b = (1.0 - L) * ST_mid.y;
        C_mid = 0.9 * k * sqrt(sqrt(1.0 / (1.0 / (C_a * C_a * C_a * C_a) + 1.0 / (C_b * C_b * C_b * C_b))));
    }

    float C_0;
    {
        // for C_0, the shape is independent of hue, so ST are constant. Values picked to roughly be the average values of ST.
        float C_a = L * 0.4;
        float C_b = (1.0 - L) * 0.8;

        // Use a soft minimum function, instead of a sharp triangle shape to get a smooth value for chroma.
        C_0 = sqrt(1.0 / (1.0 / (C_a * C_a) + 1.0 / (C_b * C_b)));
    }

    return float3(C_0, C_mid, C_max);
}

// https://bottosson.github.io/misc/ok_color.h
float3 okhsl_to_srgb(float3 okhsl)
{
    float h = okhsl.x;
    float s = okhsl.y;
    float l = okhsl.z;

    if (l == 1.0)
    {
        return float3(1.0, 1.0, 1.0);
    }

    else if (l == 0.0)
    {
        return float3(0.0, 0.0, 0.0);
    }

    float a_ = cos(2.0 * M_PI * h);
    float b_ = sin(2.0 * M_PI * h);
    float L = toe_inv(l);
    float3 Lab_ = float3(L, a_, b_);
    float3 cs = get_Cs(Lab_);
    float C_0 = cs.x;
    float C_mid = cs.y;
    float C_max = cs.z;

    // Interpolate the three values for C so that:
    // At s=0: dC/ds = C_0, C=0
    // At s=0.8: C=C_mid
    // At s=1.0: C=C_max

    float mid = 0.8;
    float mid_inv = 1.25;

    float C, t, k_0, k_1, k_2;

    if (s < mid)
    {
        t = mid_inv * s;

        k_1 = mid * C_0;
        k_2 = (1.0 - k_1 / C_mid);

        C = t * k_1 / (1.0 - k_2 * t);
    }
    else
    {
        t = (s - mid) / (1.0 - mid);

        k_0 = C_mid;
        k_1 = (1.0 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0;
        k_2 = (1.0 - (k_1) / (C_max - C_mid));

        C = k_0 + t * k_1 / (1.0 - k_2 * t);
    }

    float3 srgb = oklab_to_srgb(float3(L, C * a_, C * b_));
    return srgb;
}

float3 srgb_to_okhsl(float3 srgb)
{
    float3 lab = srgb_to_oklab(srgb);

    float C = sqrt(lab.y * lab.y + lab.z * lab.z);
    float a_ = lab.y / C;
    float b_ = lab.z / C;

    float L = lab.x;
    float3 Lab_ = float3(L, a_, b_);
    float h = 0.5 + 0.5 * atan2_approx(-lab.z, -lab.y) / M_PI;

    float3 cs = get_Cs(Lab_);
    float C_0 = cs.x;
    float C_mid = cs.y;
    float C_max = cs.z;

    // Inverse of the interpolation in okhsl_to_srgb:

    float mid = 0.8;
    float mid_inv = 1.25;

    float s;
    if (C < C_mid)
    {
        float k_1 = mid * C_0;
        float k_2 = (1.0 - k_1 / C_mid);

        float t = C / (k_1 + k_2 * C);
        s = t * mid;
    }
    else
    {
        float k_0 = C_mid;
        float k_1 = (1.0 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0;
        float k_2 = (1.0 - (k_1) / (C_max - C_mid));

        float t = (C - k_0) / (k_1 + k_2 * (C - k_0));
        s = mid + (1.0 - mid) * t;
    }

    float l = toe(L);
    return float3(h, s, l);
}