#ifndef LIGHTING_INCLUDED
#define LIGHTING_INCLUDED

#include "UnityLightingCommon.cginc"
#include "UnityGlobalIllumination.cginc"

struct SurfaceOutput {
	fixed3 Albedo; //反射光颜色
	fixed3 Normal; //法线
	fixed3 Emission; //自发光，用于增强物体自身的亮度，使之看起来好像可以自己发光
	half Specular; //镜面高光 
	fixed Gloss;//光泽度
	fixed Alpha;//透明度
};

#ifndef USING_DIRECTIONAL_LIGHT
#if defined (DIRECTIONAL_COOKIE) || defined (DIRECTIONAL)
#define USING_DIRECTIONAL_LIGHT
#endif
#endif

#if defined(UNITY_SHOULD_SAMPLE_SH) || defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
#define UNITY_LIGHT_FUNCTION_APPLY_INDIRECT
#endif

inline fixed4 UnityLambertLight (SurfaceOutput s, UnityLight light)
{
	fixed diff = max (0, dot (s.Normal, light.dir));
	
	fixed4 c;
	c.rgb = s.Albedo * light.color * diff;
	c.a = s.Alpha;
	return c;
}

inline fixed4 LightingLambert (SurfaceOutput s, UnityGI gi)
{
	fixed4 c;
	c = UnityLambertLight (s, gi.light);

	#if defined(DIRLIGHTMAP_SEPARATE)
	#ifdef LIGHTMAP_ON
	c += UnityLambertLight (s, gi.light2);
	#endif
	#ifdef DYNAMICLIGHTMAP_ON
	c += UnityLambertLight (s, gi.light3);
	#endif
	#endif

	#ifdef UNITY_LIGHT_FUNCTION_APPLY_INDIRECT
	c.rgb += s.Albedo * gi.indirect.diffuse;
	#endif

	return c;
}

inline half4 LightingLambert_Deferred (SurfaceOutput s, UnityGI gi, out half4 outDiffuseOcclusion, out half4 outSpecSmoothness, out half4 outNormal)
{
	outDiffuseOcclusion = half4(s.Albedo, 1);
	outSpecSmoothness = 0.0;
	outNormal = half4(s.Normal * 0.5 + 0.5, 1);
	half4 emission = half4(s.Emission, 1);

	#ifdef UNITY_LIGHT_FUNCTION_APPLY_INDIRECT
	emission.rgb += s.Albedo * gi.indirect.diffuse;
	#endif

	return emission;
}

inline void LightingLambert_GI (
	SurfaceOutput s,
	UnityGIInput data,
	inout UnityGI gi)
{
	gi = UnityGlobalIllumination (data, 1.0, s.Normal);
}

inline fixed4 LightingLambert_PrePass (SurfaceOutput s, half4 light)
{
	fixed4 c;
	c.rgb = s.Albedo * light.rgb;
	c.a = s.Alpha;
	return c;
}

// NOTE: some intricacy in shader compiler on some GLES2.0 platforms (iOS) needs 'viewDir' & 'h'
// to be mediump instead of lowp, otherwise specular highlight becomes too bright.
//h是半角向量。半角向量就是平分两个向量之间夹角的单位向量。
//两个向量相加，结果是两个向量构成的平行四边形的对角线，所以半角向量是两个向量相加。
//BlinnPhone的改进就是不用反射向量去计算镜面反射，
//而是用入射光向量和观察向量的半角向量来代替计算。这一方法也是没有物理依据的，只是这样计算计算量更少而且效果差不多甚至更好。如今的着色器十有八九会使用它。
inline fixed4 UnityBlinnPhongLight (SurfaceOutput s, half3 viewDir, UnityLight light)
{
	// 1.半角向量：求（点到光源+点到摄像机）的单位向量，他们的中间平均值
	half3 h = normalize (light.dir + viewDir);
	// 2.漫反射系数【点到光源单位向量与法线向量的余弦值】
	fixed diff = max (0, dot (s.Normal, light.dir));
	// 3.高光底数【半角向量与法线向量的余弦值】
	float nh = max (0, dot (s.Normal, h));
	// 4.高光系数：根据高光低数和高光指数求得
	float spec = pow (nh, s.Specular*128.0) * s.Gloss;
	
	fixed4 c;
	c.rgb = s.Albedo * light.color * diff + light.color * _SpecColor.rgb * spec;
	c.a = s.Alpha;

	return c;
}

inline fixed4 LightingBlinnPhong (SurfaceOutput s, half3 viewDir, UnityGI gi)
{
	fixed4 c;
	c = UnityBlinnPhongLight (s, viewDir, gi.light);

	#if defined(DIRLIGHTMAP_SEPARATE)
	#ifdef LIGHTMAP_ON
	c += UnityBlinnPhongLight (s, viewDir, gi.light2);
	#endif
	#ifdef DYNAMICLIGHTMAP_ON
	c += UnityBlinnPhongLight (s, viewDir, gi.light3);
	#endif
	#endif

	#ifdef UNITY_LIGHT_FUNCTION_APPLY_INDIRECT
	c.rgb += s.Albedo * gi.indirect.diffuse;
	#endif

	return c;
}

inline half4 LightingBlinnPhong_Deferred (SurfaceOutput s, half3 viewDir, UnityGI gi, out half4 outDiffuseOcclusion, out half4 outSpecSmoothness, out half4 outNormal)
{
	outDiffuseOcclusion = half4(s.Albedo, 1);
	outSpecSmoothness = half4(_SpecColor.rgb, s.Specular);
	//GBuffer  [-1,1]  -- ranform to (0,1) f(x) = 0.5x+0.5
	outNormal = half4(s.Normal * 0.5 + 0.5, 1);
	half4 emission = half4(s.Emission, 1);

	#ifdef UNITY_LIGHT_FUNCTION_APPLY_INDIRECT
	emission.rgb += s.Albedo * gi.indirect.diffuse;
	#endif
	
	return emission;
}

inline void LightingBlinnPhong_GI (
	SurfaceOutput s,
	UnityGIInput data,
	inout UnityGI gi)
{
	gi = UnityGlobalIllumination (data, 1.0, s.Normal);
}

//deferred lighting final pass:
inline fixed4 LightingBlinnPhong_PrePass (SurfaceOutput s, half4 light)
{
	fixed spec = light.a * s.Gloss;
	
	fixed4 c;
	c.rgb = (s.Albedo * light.rgb + light.rgb * _SpecColor.rgb * spec);
	c.a = s.Alpha;
	return c;
}

#ifdef UNITY_CAN_COMPILE_TESSELLATION
struct UnityTessellationFactors {
	float edge[3] : SV_TessFactor;
	float inside : SV_InsideTessFactor;
};
#endif // UNITY_CAN_COMPILE_TESSELLATION

// Deprecated, kept around for existing user shaders.
#define UNITY_DIRBASIS \
const half3x3 unity_DirBasis = half3x3( \
	half3( 0.81649658,  0.0,        0.57735027), \
	half3(-0.40824830,  0.70710678, 0.57735027), \
	half3(-0.40824830, -0.70710678, 0.57735027) \
	);

// Deprecated, kept around for existing user shaders. Only sampling the flat lightmap now.
half3 DirLightmapDiffuse(in half3x3 dirBasis, fixed4 color, fixed4 scale, half3 normal, bool surfFuncWritesNormal, out half3 scalePerBasisVector)
{
	return DecodeLightmap (color);
}

#endif
