Shader "AlexMalyutinDev/SSR"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "IgnoreProjector" = "True"
            "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100

        Pass
        {

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest Off

            Name "SSR Tracing"

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 3.0

            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            TEXTURE2D(_SpecularReflectivityBuffer);
            SAMPLER(sampler_SpecularReflectivityBuffer);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 viewDirectionWS : TEXCOORD1;
                float3 viewDirectionVS : TEXCOORD2;
                float4 positionNDC : TEXCOORD3;
                float4 positionCS : SV_POSITION;
            };

            Varyings Vertex(Attributes input)
            {
                Varyings output = (Varyings)0;

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.uv = input.uv;

                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.viewDirectionWS = -GetWorldSpaceViewDir(positionWS.xyz);
                output.viewDirectionVS = TransformWorldToViewDir(output.viewDirectionWS);

                float4 ndc = output.positionCS * 0.5f;
                output.positionNDC.xy = float2(ndc.x, ndc.y * _ProjectionParams.x) + ndc.w;
                output.positionNDC.zw = output.positionCS.zw;

                return output;
            }

            half3 GetNormals(float3 positionWS, float2 uv)
            {
                #if 0
                // TODO: Reconstruct normals from depth, if NormalsBuffer is not turned on
                {
                    float2 uv1 = uv + float2(_ScreenSize.z, 0);
                    float2 uv2 = uv + float2(0, _ScreenSize.w);
                    half depthR = SampleSceneDepth(uv1);
                    half depthU = SampleSceneDepth(uv2);

                    half3 p1 = ComputeWorldSpacePosition(uv1, depthR, _InvCameraViewProj);
                    half3 p2 = ComputeWorldSpacePosition(uv2, depthU, _InvCameraViewProj);

                    return normalize(cross(p2 - positionWS, p1 - positionWS));
                }
                #else
                return SampleSceneNormals(uv);
                #endif
            }

            TEXTURE2D(_BlueNoise_Texture);
            SAMPLER(sampler_BlueNoise_Texture);
            float4 _Dithering_Params;
            #define DitheringScale          _Dithering_Params.xy
            #define DitheringOffset         _Dithering_Params.zw

            half4 Fragment(Varyings input) : SV_Target
            {
                float2 uv = input.positionNDC.xy;
                half4 specularReflectivity = SAMPLE_TEXTURE2D_X(
                    _SpecularReflectivityBuffer,
                    sampler_SpecularReflectivityBuffer,
                    uv
                );

                half3 specular = specularReflectivity.rgb;
                half reflectivity = specularReflectivity.a;

                // TODO: Involve stencil buffer to early test
                if (reflectivity < 0.01)
                {
                    return 0;
                }

                half depth = SampleSceneDepth(uv);
                if (depth == UNITY_RAW_FAR_CLIP_VALUE)
                    return 0;

                half3 positionWS = ComputeWorldSpacePosition(uv, depth, _InvCameraViewProj);

                // TODO: Randomize normals
                float3 normalWS = GetNormals(positionWS, uv);

                half NdotV = dot(normalWS, -normalize(input.viewDirectionWS));
                reflectivity *= (saturate(1 - NdotV));

                if (reflectivity < 0.001)
                {
                    return 0;
                }

                half noise = SAMPLE_TEXTURE2D(
                    _BlueNoise_Texture,
                    sampler_BlueNoise_Texture,
                    uv * DitheringScale + DitheringOffset
                ).a;

                half3 noise3 = sin(half3(noise, 2 * noise + 4.235, 5 * noise + 11.35235) * 2 * PI) * 0.05;
                half3 reflectWS = normalize(reflect(input.viewDirectionWS, normalWS) + noise3 * (1 - reflectivity));

                half3 reflectVS = TransformWorldToViewDir(reflectWS);
                half3 positionVS = TransformWorldToView(positionWS);

                float2 reflectUV = uv;
                float alpha = reflectivity;

                int i = 0;
                half4 hitVS = 0;
                half thickness = 0.5h;
                half bounceRayLength = 0.001h + noise;
                UNITY_LOOP
                while (i < 5)
                {
                    // TODO: Use ViewSpace
                    half3 ray = positionVS + reflectVS * bounceRayLength;
                    half4 positionCS = TransformWViewToHClip(ray);
                    reflectUV = positionCS.xy / positionCS.w * half2(0.5, -0.5) + 0.5;

                    if (any(reflectUV > float2(1.0f, 1.0f) || reflectUV < float2(0.0f, 0.0f)))
                    {
                        break;
                    }

                    depth = SampleSceneDepth(reflectUV);
                    half behindDepthBuffer =
                        LinearEyeDepth(positionCS.z / positionCS.w, _ZBufferParams) >
                        LinearEyeDepth(depth, _ZBufferParams) + thickness;
                    alpha *= 1 - behindDepthBuffer;

                    hitVS = mul(unity_MatrixInvP, ComputeClipSpacePosition(reflectUV, depth));
                    bounceRayLength = length(positionVS - hitVS.xyz / hitVS.w);
                    i++;
                }

                half uvAttenuation = saturate(1 - length(reflectUV * 2 - 1));
                float3 sceneColor = SampleSceneColor(reflectUV);

                alpha *= uvAttenuation * (1 / (1 + bounceRayLength * 0.2));

                return half4(sceneColor, alpha);
            }
            ENDHLSL
        }
    }
}