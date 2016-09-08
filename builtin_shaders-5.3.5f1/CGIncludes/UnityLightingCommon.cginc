#ifndef UNITY_LIGHTING_COMMON_INCLUDED
#define UNITY_LIGHTING_COMMON_INCLUDED

fixed4 _LightColor0;
fixed4 _SpecColor;
//Unity中光源参数的结构体  
struct UnityLight
{
	half3 color;//光源颜色  
	half3 dir;//光源方向  
	half  ndotl;//光源方向和当前表面法线方向的点积  
};
//Unity中间接光源参数的结构体  
struct UnityIndirect
{
	half3 diffuse;//漫反射颜色  
	half3 specular;//镜面反射颜色  
};
//全局光照结构体 
//里面的light是UnityLight类型，并不表示光源，而是用来表示当前像素受光源影响的量。
struct UnityGI
{
	UnityLight light; //定义第一个光源参数结构体，表示第一个光源  
	//若定义了DIRLIGHTMAP_SEPARATE（单独的方向光源光照贴图） 
	#ifdef DIRLIGHTMAP_SEPARATE     //当烘培GI启用高光后，才会调用。
		#ifdef LIGHTMAP_ON
		 //若定义了LIGHTMAP_ON（打开光照贴图）  
			UnityLight light2; //定义第二个光源参数结构体，表示第二个光源  
		#endif
		#ifdef DYNAMICLIGHTMAP_ON // 预计算GI启用高光后，才会调用。
		//若定义了DYNAMICLIGHTMAP_ON（打开动态光照贴图）  
			UnityLight light3;//定义第三个光源参数结构体，表示第三个光源  
		#endif
	#endif
	UnityIndirect indirect;//Unity中间接光源参数的结构体
};

//全局光照的输入参数结构体  
struct UnityGIInput 
{
	UnityLight light; // pixel light, sent from the engine// 像素光源，由引擎准备并传输过来 || pixel light, sent from the engine  

	float3 worldPos;//世界空间中的位置坐标 
	half3 worldViewDir;//世界空间中的视角方向向量坐标  
	half atten;//衰减值  
	half3 ambient;//环境光颜色  
	half4 lightmapUV; // .xy = static lightmap UV, .zw = dynamic lightmap UV   //光照贴图的UV坐标，其中 取.xy = static lightmapUV（静态光照贴图的UV）  zw = dynamic lightmap UV（动态光照贴图的UV）  

	float4 boxMax[2];//box最大值
	float4 boxMin[2];//box最小值 
	float4 probePosition[2];//光照探针的位置  
	float4 probeHDR[2];//光照探针的高动态范围图像（High-Dynamic Range）  
};

#endif