#ifndef UNITY_STANDARD_CORE_INCLUDED
#define UNITY_STANDARD_CORE_INCLUDED

#include "UnityCG.cginc"
#include "UnityShaderVariables.cginc"
#include "UnityStandardConfig.cginc"
#include "UnityStandardInput.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityStandardBRDF.cginc"

#include "AutoLight.cginc"


//-------------------------------------------------------------------------------------
// counterpart for NormalizePerPixelNormal
// skips normalization per-vertex and expects normalization to happen per-pixel
//--------------------------【函数NormalizePerVertexNormal】-----------------------------  
// 用途：归一化每顶点法线  
// 说明：若满足特定条件，便归一化每顶点法线并返回，否则，直接返回原始值  
// 输入：half3类型的法线坐标  
// 输出：若满足判断条件，返回half3类型的、经过归一化后的法线坐标，否则返回输入的值  
//-----------------------------------------------------------------------------------------------   
half3 NormalizePerVertexNormal (float3 n) // takes float to avoid overflow
{
	//满足着色目标模型的版本小于Shader Model 3.0，或者定义了UNITY_STANDARD_SIMPLE宏，返回归一化后的值 
	#if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE || defined(SHADER_API_MOBILE)
	return normalize(n); // on SHADER_API_MOBILE also normalize in vertex shader to avoid big numbers that might cause precision problems in fragment shader
	#else
	return n; // will normalize per-pixel instead
	#endif
}
//逐像素
half3 NormalizePerPixelNormal (half3 n)
{
	#if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
	return n;
	#else
	return normalize(n);
	#endif
}

//  用途：该函数为主光照函数  (全局光是用的是平行光)
//  说明：实例化一个UnityLight结构体对象，并进行相应的填充  
//-------------------------------------------------------------------------------------
UnityLight MainLight (half3 normalWorld)
{
	UnityLight l;
	#ifdef LIGHTMAP_OFF  //若光照贴图选项为关,使用Unity内置变量赋值 

	l.color = _LightColor0.rgb;
	l.dir = _WorldSpaceLightPos0.xyz;
	l.ndotl = LambertTerm (normalWorld, l.dir);
	#else
	// no light specified by the engine
	// analytical light might be extracted from Lightmap data later on in the shader depending on the Lightmap type
	 //光照贴图选项为开，将各项值设为0  
	l.color = half3(0.f, 0.f, 0.f);
	l.ndotl  = 0.f;
	l.dir = half3(0.f, 0.f, 0.f);
	#endif

	return l;
}

UnityLight AdditiveLight (half3 normalWorld, half3 lightDir, half atten)
{
	UnityLight l;

	l.color = _LightColor0.rgb;
	l.dir = lightDir;
	#ifndef USING_DIRECTIONAL_LIGHT
	l.dir = NormalizePerPixelNormal(l.dir);
	#endif
	l.ndotl = LambertTerm (normalWorld, l.dir);

	// shadow the light
	l.color *= atten;
	return l;
}

UnityLight DummyLight (half3 normalWorld)
{
	UnityLight l;
	l.color = 0;
	l.dir = half3 (0,1,0);
	l.ndotl = LambertTerm (normalWorld, l.dir);
	return l;
}

UnityIndirect ZeroIndirect ()
{
	UnityIndirect ind;
	ind.diffuse = 0;
	ind.specular = 0;
	return ind;
}

//-------------------------------------------------------------------------------------
// Common fragment setup

// deprecated
half3 WorldNormal(half4 tan2world[3])
{
	return normalize(tan2world[2].xyz);
}

// deprecated
#ifdef _TANGENT_TO_WORLD
half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
{
	half3 t = tan2world[0].xyz;
	half3 b = tan2world[1].xyz;
	half3 n = tan2world[2].xyz;

	#if UNITY_TANGENT_ORTHONORMALIZE
	n = NormalizePerPixelNormal(n);

	// ortho-normalize Tangent
	t = normalize (t - n * dot(t, n));

	// recalculate Binormal
	half3 newB = cross(n, t);
	b = newB * sign (dot (newB, b));
	#endif

	return half3x3(t, b, n);
}
#else
half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
{
	return half3x3(0,0,0,0,0,0,0,0,0);
}
#endif

//像素着色器 获取 世界坐标系下的法线
half3 PerPixelWorldNormal(float4 i_tex, half4 tangentToWorld[3])
{
	#ifdef _NORMALMAP //凹凸纹理映射
	half3 tangent = tangentToWorld[0].xyz;
	half3 binormal = tangentToWorld[1].xyz;
	half3 normal = tangentToWorld[2].xyz;

	#if UNITY_TANGENT_ORTHONORMALIZE
	normal = NormalizePerPixelNormal(normal); //归一化

	// ortho-normalize Tangent
	// T在N上的投影 p = （T . N）N   tangent = T - p  就是垂直N的向量了
	// 因为在插值以后T N 向量可能不在互相垂直了，这个代码的作用是 通过从T中减去偏向N的部分，使T 重新垂直于N
	tangent = normalize (tangent - normal * dot(tangent, normal)); //切线归一化

	// recalculate Binormal
	half3 newB = cross(normal, tangent);
	binormal = newB * sign (dot (newB, binormal));//sign 返回符号 -1 0 1
	#endif

	half3 normalTangent = NormalInTangentSpace(i_tex);//获得到切线空间下的法线
	half3 normalWorld = NormalizePerPixelNormal(tangent * normalTangent.x + binormal * normalTangent.y + normal * normalTangent.z); // @TODO: see if we can squeeze this normalize on SM2.0 as well
	#else
	half3 normalWorld = normalize(tangentToWorld[2].xyz);
	#endif
	return normalWorld;
}

#ifdef _PARALLAXMAP
#define IN_VIEWDIR4PARALLAX(i) NormalizePerPixelNormal(half3(i.tangentToWorldAndParallax[0].w,i.tangentToWorldAndParallax[1].w,i.tangentToWorldAndParallax[2].w))
#define IN_VIEWDIR4PARALLAX_FWDADD(i) NormalizePerPixelNormal(i.viewDirForParallax.xyz)
#else
#define IN_VIEWDIR4PARALLAX(i) half3(0,0,0)
#define IN_VIEWDIR4PARALLAX_FWDADD(i) half3(0,0,0)
#endif

#if UNITY_SPECCUBE_BOX_PROJECTION
#define IN_WORLDPOS(i) i.posWorld
#else
#define IN_WORLDPOS(i) half3(0,0,0)
#endif

#define IN_LIGHTDIR_FWDADD(i) half3(i.tangentToWorldAndLightDir[0].w, i.tangentToWorldAndLightDir[1].w, i.tangentToWorldAndLightDir[2].w)

#define FRAGMENT_SETUP(x) FragmentCommonData x = \
FragmentSetup(i.tex, i.eyeVec, IN_VIEWDIR4PARALLAX(i), i.tangentToWorldAndParallax, IN_WORLDPOS(i));

#define FRAGMENT_SETUP_FWDADD(x) FragmentCommonData x = \
FragmentSetup(i.tex, i.eyeVec, IN_VIEWDIR4PARALLAX_FWDADD(i), i.tangentToWorldAndLightDir, half3(0,0,0));

struct FragmentCommonData
{
	half3 diffColor, specColor;//漫反射颜色；镜面反射颜色  
	// Note: oneMinusRoughness & oneMinusReflectivity for optimization purposes, mostly for DX9 SM2.0 level.
	// Most of the math is being done on these (1-x) values, and that saves a few precious ALU slots.
	half oneMinusReflectivity, oneMinusRoughness;//1减去反射率；1减去粗糙度  
	half3 normalWorld, eyeVec, posWorld;//世界空间中的法线向量坐标；视角向量坐标；在世界坐标中的位置坐标  
	half alpha;//透明度 

	#if UNITY_OPTIMIZE_TEXCUBELOD || UNITY_STANDARD_SIMPLE
	half3 reflUVW;//反射率的UVW
	#endif

	#if UNITY_STANDARD_SIMPLE
	half3 tangentSpaceNormal;//切线空间中的法线向量  
	#endif
};

#ifndef UNITY_SETUP_BRDF_INPUT
#define UNITY_SETUP_BRDF_INPUT SpecularSetup
#endif

inline FragmentCommonData SpecularSetup (float4 i_tex)
{
	half4 specGloss = SpecularGloss(i_tex.xy);
	half3 specColor = specGloss.rgb;
	half oneMinusRoughness = specGloss.a;

	half oneMinusReflectivity;
	half3 diffColor = EnergyConservationBetweenDiffuseAndSpecular (Albedo(i_tex), specColor, /*out*/ oneMinusReflectivity);
	
	FragmentCommonData o = (FragmentCommonData)0;
	o.diffColor = diffColor;
	o.specColor = specColor;
	o.oneMinusReflectivity = oneMinusReflectivity;
	o.oneMinusRoughness = oneMinusRoughness;
	return o;
}

inline FragmentCommonData MetallicSetup (float4 i_tex)
{
	half2 metallicGloss = MetallicGloss(i_tex.xy);
	half metallic = metallicGloss.x;
	half oneMinusRoughness = metallicGloss.y;		// this is 1 minus the square root of real roughness m.

	half oneMinusReflectivity;
	half3 specColor;
	half3 diffColor = DiffuseAndSpecularFromMetallic (Albedo(i_tex), metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

	FragmentCommonData o = (FragmentCommonData)0;
	o.diffColor = diffColor;
	o.specColor = specColor;
	o.oneMinusReflectivity = oneMinusReflectivity;
	o.oneMinusRoughness = oneMinusRoughness;
	return o;
} 

inline FragmentCommonData FragmentSetup (float4 i_tex, half3 i_eyeVec, half3 i_viewDirForParallax, half4 tangentToWorld[3], half3 i_posWorld)
{
	i_tex = Parallax(i_tex, i_viewDirForParallax);

	half alpha = Alpha(i_tex.xy);
	#if defined(_ALPHATEST_ON)
	clip (alpha - _Cutoff);
	#endif

	FragmentCommonData o = UNITY_SETUP_BRDF_INPUT (i_tex);
	o.normalWorld = PerPixelWorldNormal(i_tex, tangentToWorld);
	o.eyeVec = NormalizePerPixelNormal(i_eyeVec);
	o.posWorld = i_posWorld;

	// NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
	o.diffColor = PreMultiplyAlpha (o.diffColor, alpha, o.oneMinusReflectivity, /*out*/ o.alpha);
	return o;
}
//函数：片段着色部分全局光照的处理函数  
inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light, bool reflections)
{
	UnityGIInput d;
	d.light = light;
	d.worldPos = s.posWorld;
	d.worldViewDir = -s.eyeVec;
	d.atten = atten;
	#if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
	d.ambient = 0;
	d.lightmapUV = i_ambientOrLightmapUV;
	#else
	d.ambient = i_ambientOrLightmapUV.rgb;
	d.lightmapUV = 0;
	#endif
	d.boxMax[0] = unity_SpecCube0_BoxMax;
	d.boxMin[0] = unity_SpecCube0_BoxMin;
	d.probePosition[0] = unity_SpecCube0_ProbePosition;
	d.probeHDR[0] = unity_SpecCube0_HDR;

	d.boxMax[1] = unity_SpecCube1_BoxMax;
	d.boxMin[1] = unity_SpecCube1_BoxMin;
	d.probePosition[1] = unity_SpecCube1_ProbePosition;
	d.probeHDR[1] = unity_SpecCube1_HDR;

	if(reflections)
	{
		Unity_GlossyEnvironmentData g;
		g.roughness		= 1 - s.oneMinusRoughness;
		#if UNITY_OPTIMIZE_TEXCUBELOD || UNITY_STANDARD_SIMPLE
		g.reflUVW 		= s.reflUVW;
		#else
		g.reflUVW		= reflect(s.eyeVec, s.normalWorld);
		#endif

		return UnityGlobalIllumination (d, occlusion, s.normalWorld, g);
	}
	else
	{
		return UnityGlobalIllumination (d, occlusion, s.normalWorld);
	}
}

inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light)
{
	return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, true);
}

//-----------------------------【函数OutputForward】----------------------------------------------  
// 用途：正向渲染通道输出函数  
//  输入参数：一个half4类型的一个颜色值output，一个half型的透明度值alphaFromSurface  
// 返回值：经过透明处理的half4型的输出颜色值  
//-------------------------------------------------------------------------------------
half4 OutputForward (half4 output, half alphaFromSurface)
{
	#if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
	output.a = alphaFromSurface;
	#else
	UNITY_OPAQUE_ALPHA(output.a);
	#endif
	return output;
}

//顶点正向全局光照函数  
inline half4 VertexGIForward(VertexInput v, float3 posWorld, half3 normalWorld)
{
	//【1】定义一个half4型的ambientOrLightmapUV变量，并将四个分量都置为0  
	half4 ambientOrLightmapUV = 0;
	// Static lightmaps
	//【2】对ambientOrLightmapUV变量的四个分量赋值  
	// 【2-1】若没有定义LIGHTMAP_OFF（关闭光照贴图）宏，也就是此情况下启用静态的光照贴图，则计算对应的光照贴图坐标  
	#ifndef LIGHTMAP_OFF
	ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
	ambientOrLightmapUV.zw = 0;
	// Sample light probe for Dynamic objects only (no static or dynamic lightmaps)
	//【2-2】若定义了UNITY_SHOULD_SAMPLE_SH宏，则表示对动态的对象采样（不对静态或者动态的光照贴图采样）  
	#elif UNITY_SHOULD_SAMPLE_SH
	#ifdef VERTEXLIGHT_ON
	// Approximated illumination from non-important point lights
	ambientOrLightmapUV.rgb = Shade4PointLights (
		unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
		unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
		unity_4LightAtten0, posWorld, normalWorld);
	#endif

	ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, ambientOrLightmapUV.rgb);		
	#endif

	//【2-3】若定义了如下的VERTEXLIGHT_ONDYNAMICLIGHTMAP_ON宏（即开启动态光照贴图），则给变量的zw分量赋值  
	#ifdef DYNAMICLIGHTMAP_ON
	ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
	#endif

	return ambientOrLightmapUV;
}

//-------------------------------------------------------------------------------------
// Input functions 定义在input 
/*
struct VertexInput
{
	float4 vertex	: POSITION;
	half3 normal	: NORMAL;
	float2 uv0		: TEXCOORD0;
	float2 uv1		: TEXCOORD1;
#if defined(DYNAMICLIGHTMAP_ON) || defined(UNITY_PASS_META)
	float2 uv2		: TEXCOORD2;
#endif
#ifdef _TANGENT_TO_WORLD
	half4 tangent	: TANGENT;
#endif
};
*/


// ------------------------------------------------------------------
//  Base forward pass (directional light, emission, lightmaps, ...)

struct VertexOutputForwardBase
{
	float4 pos							: SV_POSITION;//像素坐标  
	float4 tex							: TEXCOORD0;
	half3 eyeVec 						: TEXCOORD1;
	half4 tangentToWorldAndParallax[3]	: TEXCOORD2;	// [3x3:tangentToWorld | 1x3:viewDirForParallax] //3x3为切线到世界矩阵的值，1x3为视差方向的值 
	half4 ambientOrLightmapUV			: TEXCOORD5;	// SH or Lightmap UV // 球谐函数（Spherical harmonics）或光照贴图的UV坐标 
	SHADOW_COORDS(6)//阴影坐标  
	UNITY_FOG_COORDS(7)//雾效坐标 

	// next ones would not fit into SM2.0 limits, but they are always for SM3.0+
	//若定义了镜面立方体投影宏，定义一个posWorld   
	#if UNITY_SPECCUBE_BOX_PROJECTION
	float3 posWorld					: TEXCOORD8;
	#endif
	//若定义了优化纹理的立方体LOD宏，还将定义如下的参数reflUVW  
	#if UNITY_OPTIMIZE_TEXCUBELOD
	#if UNITY_SPECCUBE_BOX_PROJECTION
	half3 reflUVW				: TEXCOORD9;
	#else
	half3 reflUVW				: TEXCOORD8;
	#endif
	#endif
};

//-----------------------------------【vertForwardBase函数】----------------------------------------  
//  用途：正向渲染基础通道的顶点着色函数  
//  说明：实例化一个VertexOutputForwardBase结构体对象，并进行相应的填充  
//  输入：VertexInput结构体  
//  输出：VertexOutputForwardBase结构体  
//  附：VertexInput结构体原型：  


VertexOutputForwardBase vertForwardBase (VertexInput v)
{
	//【1】实例化一个VertexOutputForwardBase结构体对象  
	VertexOutputForwardBase o;
	// //用Unity内置的宏初始化参数 
	UNITY_INITIALIZE_OUTPUT(VertexOutputForwardBase, o);

	//【2】通过物体坐标系到世界坐标系的变换矩阵乘以物体的顶点位置,得到对象在世界坐标系中的位置  
	float4 posWorld = mul(_Object2World, v.vertex); //转换到世界坐标

	//【3】若定义了镜面立方体投影宏，将计算得到的世界坐标系的xyz坐标作为输出参数的世界坐标值  
	#if UNITY_SPECCUBE_BOX_PROJECTION
	o.posWorld = posWorld.xyz;
	#endif

	//【4】输出的顶点位置（像素位置）为模型视图投影矩阵乘以顶点位置，也就是将三维空间中的坐标投影到了二维窗口  
	o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
	//【5】计算纹理坐标，使用UnityStandardInput.cginc头文件中的辅助函数。  
	o.tex = TexCoords(v);
	//【6】视线的方向= 对象在世界坐标系中的位置减去摄像机的世界空间位置，并进行逐顶点归一化  
	o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
	
	//【7】计算物体在世界空间中的法线坐标  
	float3 normalWorld = UnityObjectToWorldNormal(v.normal);

	//【8】进行世界空间中的切线相关参数的计算与赋值  
	//若定义了_TANGENT_TO_WORLD  
	#ifdef _TANGENT_TO_WORLD
	//世界空间中的物体的法线值 
	float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
	//在世界空间中为每个顶点创建切线  
	float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
	//分别为3个分量赋值  
	o.tangentToWorldAndParallax[0].xyz = tangentToWorld[0];
	o.tangentToWorldAndParallax[1].xyz = tangentToWorld[1];
	o.tangentToWorldAndParallax[2].xyz = tangentToWorld[2];
	#else
	//否则，三个分量直接取为0，0和上面计算得到的normalW
	o.tangentToWorldAndParallax[0].xyz = 0;
	o.tangentToWorldAndParallax[1].xyz = 0;
	o.tangentToWorldAndParallax[2].xyz = normalWorld;
	#endif
	//【9】阴影的获取  
	//We need this for shadow receving
	TRANSFER_SHADOW(o);
	//【10】进行顶点正向相关的全局光照操作  
	o.ambientOrLightmapUV = VertexGIForward(v, posWorld, normalWorld);
	
	//【11】若定义了_PARALLAXMAP宏，则计算视差的视角方向并赋值
	#ifdef _PARALLAXMAP
	//声明一个由切线空间的基组成的3x3矩阵“rotation”   定义在cg.cginc
	TANGENT_SPACE_ROTATION;
	//计算视差的视角方向  
	half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
	//分别将三个分量赋值给VertexOutputForwardBase结构体对象o的tangentToWorldAndParallax的三个分量  
	o.tangentToWorldAndParallax[0].w = viewDirForParallax.x;
	o.tangentToWorldAndParallax[1].w = viewDirForParallax.y;
	o.tangentToWorldAndParallax[2].w = viewDirForParallax.z;
	#endif
	//【12】若定义了UNITY_OPTIMIZE_TEXCUBELOD，便计算反射光方向向量并赋值  
	#if UNITY_OPTIMIZE_TEXCUBELOD
	//使用CG语言内置函数reflect计算反射光方向向量  
	o.reflUVW 		= reflect(o.eyeVec, normalWorld);
	#endif
	//【13】从顶点中输出雾数据  
	UNITY_TRANSFER_FOG(o,o.pos);
	//【14】返回已经附好值的VertexOutputForwardBase类型的对象  
	return o;
}

half4 fragForwardBaseInternal (VertexOutputForwardBase i)
{
	//定义并初始化类型为FragmentCommonData的变量s  
	FRAGMENT_SETUP(s)
	//若定义了UNITY_OPTIMIZE_TEXCUBELOD，则由输入的顶点参数来设置反射光方向向量  
	#if UNITY_OPTIMIZE_TEXCUBELOD
	s.reflUVW		= i.reflUVW;
	#endif
  //设置主光照  
	UnityLight mainLight = MainLight (s.normalWorld);
	//设置阴影的衰减系数  
	half atten = SHADOW_ATTENUATION(i);

 	//计算全局光照
	half occlusion = Occlusion(i.tex.xy);
	UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, mainLight);

	//加上BRDF-基于物理的光照
	half4 c = UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.oneMinusRoughness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect);
	//加上BRDF-全局光照
	c.rgb += UNITY_BRDF_GI (s.diffColor, s.specColor, s.oneMinusReflectivity, s.oneMinusRoughness, s.normalWorld, -s.eyeVec, occlusion, gi);
	//加上自发光 
	c.rgb += Emission(i.tex.xy);
  	//设置雾效
	UNITY_APPLY_FOG(i.fogCoord, c.rgb);
	return OutputForward (c, s.alpha);
}

half4 fragForwardBase (VertexOutputForwardBase i) : SV_Target	// backward compatibility (this used to be the fragment entry function)
{
	return fragForwardBaseInternal(i);
}

// ------------------------------------------------------------------
//  Additive forward pass (one light per pass)

struct VertexOutputForwardAdd
{
	float4 pos							: SV_POSITION;
	float4 tex							: TEXCOORD0;
	half3 eyeVec 						: TEXCOORD1;
	half4 tangentToWorldAndLightDir[3]	: TEXCOORD2;	// [3x3:tangentToWorld | 1x3:lightDir]
	LIGHTING_COORDS(5,6)
	UNITY_FOG_COORDS(7)

	// next ones would not fit into SM2.0 limits, but they are always for SM3.0+
	#if defined(_PARALLAXMAP)
	half3 viewDirForParallax			: TEXCOORD8;
	#endif
};

VertexOutputForwardAdd vertForwardAdd (VertexInput v)
{
	VertexOutputForwardAdd o;
	UNITY_INITIALIZE_OUTPUT(VertexOutputForwardAdd, o);

	float4 posWorld = mul(_Object2World, v.vertex);
	o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
	o.tex = TexCoords(v);
	o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
	float3 normalWorld = UnityObjectToWorldNormal(v.normal);
	#ifdef _TANGENT_TO_WORLD
	float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

	float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
	o.tangentToWorldAndLightDir[0].xyz = tangentToWorld[0];
	o.tangentToWorldAndLightDir[1].xyz = tangentToWorld[1];
	o.tangentToWorldAndLightDir[2].xyz = tangentToWorld[2];
	#else
	o.tangentToWorldAndLightDir[0].xyz = 0;
	o.tangentToWorldAndLightDir[1].xyz = 0;
	o.tangentToWorldAndLightDir[2].xyz = normalWorld;
	#endif
	//We need this for shadow receiving
	TRANSFER_VERTEX_TO_FRAGMENT(o);

	float3 lightDir = _WorldSpaceLightPos0.xyz - posWorld.xyz * _WorldSpaceLightPos0.w;
	#ifndef USING_DIRECTIONAL_LIGHT
	lightDir = NormalizePerVertexNormal(lightDir);
	#endif
	o.tangentToWorldAndLightDir[0].w = lightDir.x;
	o.tangentToWorldAndLightDir[1].w = lightDir.y;
	o.tangentToWorldAndLightDir[2].w = lightDir.z;

	#ifdef _PARALLAXMAP
	TANGENT_SPACE_ROTATION;
	o.viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
	#endif
	
	UNITY_TRANSFER_FOG(o,o.pos);
	return o;
}

half4 fragForwardAddInternal (VertexOutputForwardAdd i)
{
	FRAGMENT_SETUP_FWDADD(s)

	UnityLight light = AdditiveLight (s.normalWorld, IN_LIGHTDIR_FWDADD(i), LIGHT_ATTENUATION(i));
	UnityIndirect noIndirect = ZeroIndirect ();

	half4 c = UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.oneMinusRoughness, s.normalWorld, -s.eyeVec, light, noIndirect);
	
	UNITY_APPLY_FOG_COLOR(i.fogCoord, c.rgb, half4(0,0,0,0)); // fog towards black in additive pass
	return OutputForward (c, s.alpha);
}

half4 fragForwardAdd (VertexOutputForwardAdd i) : SV_Target		// backward compatibility (this used to be the fragment entry function)
{
	return fragForwardAddInternal(i);
}

// ------------------------------------------------------------------
//  Deferred pass

struct VertexOutputDeferred
{
	float4 pos							: SV_POSITION;
	float4 tex							: TEXCOORD0;
	half3 eyeVec 						: TEXCOORD1;
	half4 tangentToWorldAndParallax[3]	: TEXCOORD2;	// [3x3:tangentToWorld | 1x3:viewDirForParallax]
	half4 ambientOrLightmapUV			: TEXCOORD5;	// SH or Lightmap UVs			
	#if UNITY_SPECCUBE_BOX_PROJECTION
	float3 posWorld						: TEXCOORD6;
	#endif
	#if UNITY_OPTIMIZE_TEXCUBELOD
	#if UNITY_SPECCUBE_BOX_PROJECTION
	half3 reflUVW				: TEXCOORD7;
	#else
	half3 reflUVW				: TEXCOORD6;
	#endif
	#endif

};


VertexOutputDeferred vertDeferred (VertexInput v)
{
	VertexOutputDeferred o;
	UNITY_INITIALIZE_OUTPUT(VertexOutputDeferred, o);

	float4 posWorld = mul(_Object2World, v.vertex);
	#if UNITY_SPECCUBE_BOX_PROJECTION
	o.posWorld = posWorld;
	#endif
	o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
	o.tex = TexCoords(v);
	o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
	float3 normalWorld = UnityObjectToWorldNormal(v.normal);
	#ifdef _TANGENT_TO_WORLD
	float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

	float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
	o.tangentToWorldAndParallax[0].xyz = tangentToWorld[0];
	o.tangentToWorldAndParallax[1].xyz = tangentToWorld[1];
	o.tangentToWorldAndParallax[2].xyz = tangentToWorld[2];
	#else
	o.tangentToWorldAndParallax[0].xyz = 0;
	o.tangentToWorldAndParallax[1].xyz = 0;
	o.tangentToWorldAndParallax[2].xyz = normalWorld;
	#endif

	o.ambientOrLightmapUV = 0;
	#ifndef LIGHTMAP_OFF
	o.ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
	#elif UNITY_SHOULD_SAMPLE_SH
	o.ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, o.ambientOrLightmapUV.rgb);
	#endif
	#ifdef DYNAMICLIGHTMAP_ON
	o.ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
	#endif
	
	#ifdef _PARALLAXMAP
	TANGENT_SPACE_ROTATION;
	half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
	o.tangentToWorldAndParallax[0].w = viewDirForParallax.x;
	o.tangentToWorldAndParallax[1].w = viewDirForParallax.y;
	o.tangentToWorldAndParallax[2].w = viewDirForParallax.z;
	#endif

	#if UNITY_OPTIMIZE_TEXCUBELOD
	o.reflUVW		= reflect(o.eyeVec, normalWorld);
	#endif

	return o;
}

void fragDeferred (
	VertexOutputDeferred i,
	out half4 outDiffuse : SV_Target0,			// RT0: diffuse color (rgb), occlusion (a)
	out half4 outSpecSmoothness : SV_Target1,	// RT1: spec color (rgb), smoothness (a)
	out half4 outNormal : SV_Target2,			// RT2: normal (rgb), --unused, very low precision-- (a) 
	out half4 outEmission : SV_Target3			// RT3: emission (rgb), --unused-- (a)
	)
{
	#if (SHADER_TARGET < 30)
	outDiffuse = 1;
	outSpecSmoothness = 1;
	outNormal = 0;
	outEmission = 0;
	return;
	#endif

	FRAGMENT_SETUP(s)
	#if UNITY_OPTIMIZE_TEXCUBELOD
	s.reflUVW		= i.reflUVW;
	#endif

	// no analytic lights in this pass
	UnityLight dummyLight = DummyLight (s.normalWorld);
	half atten = 1;

	// only GI
	half occlusion = Occlusion(i.tex.xy);
	#if UNITY_ENABLE_REFLECTION_BUFFERS
	bool sampleReflectionsInDeferred = false;
	#else
	bool sampleReflectionsInDeferred = true;
	#endif

	UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, dummyLight, sampleReflectionsInDeferred);

	half3 color = UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.oneMinusRoughness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect).rgb;
	color += UNITY_BRDF_GI (s.diffColor, s.specColor, s.oneMinusReflectivity, s.oneMinusRoughness, s.normalWorld, -s.eyeVec, occlusion, gi);

	#ifdef _EMISSION
	color += Emission (i.tex.xy);
	#endif

	#ifndef UNITY_HDR_ON
	color.rgb = exp2(-color.rgb);
	#endif

	outDiffuse = half4(s.diffColor, occlusion);
	outSpecSmoothness = half4(s.specColor, s.oneMinusRoughness);
	outNormal = half4(s.normalWorld*0.5+0.5,1);
	outEmission = half4(color, 1);
}


//
// Old FragmentGI signature. Kept only for backward compatibility and will be removed soon
//

inline UnityGI FragmentGI(
	float3 posWorld,
	half occlusion, half4 i_ambientOrLightmapUV, half atten, half oneMinusRoughness, half3 normalWorld, half3 eyeVec,
	UnityLight light,
	bool reflections)
{
	// we init only fields actually used
	FragmentCommonData s = (FragmentCommonData)0;
	s.oneMinusRoughness = oneMinusRoughness;
	s.normalWorld = normalWorld;
	s.eyeVec = eyeVec;
	s.posWorld = posWorld;
	#if UNITY_OPTIMIZE_TEXCUBELOD
	s.reflUVW = reflect(eyeVec, normalWorld);
	#endif
	return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, reflections);
}
inline UnityGI FragmentGI (
	float3 posWorld,
	half occlusion, half4 i_ambientOrLightmapUV, half atten, half oneMinusRoughness, half3 normalWorld, half3 eyeVec,
	UnityLight light)
{
	return FragmentGI (posWorld, occlusion, i_ambientOrLightmapUV, atten, oneMinusRoughness, normalWorld, eyeVec, light, true);
}

#endif // UNITY_STANDARD_CORE_INCLUDED
