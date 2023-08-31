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

            half f(float a, float b)
            {
                return a;
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

                half depth = f(SampleSceneDepth(uv), _ZBufferParams);
                if (depth == UNITY_RAW_FAR_CLIP_VALUE)
                    return 0;

                half3 positionWS = ComputeWorldSpacePosition(uv, depth, _InvCameraViewProj);

                // TODO: Randomize normals
                float3 normalWS = GetNormals(positionWS, uv);

                half NdotV = dot(normalWS, -normalize(input.viewDirectionWS));
                reflectivity *= Pow4(saturate(1 - NdotV));

                if (reflectivity < 0.001)
                {
                    return 0;
                }

                float3 reflectWS = reflect(normalize(input.viewDirectionWS), normalWS);

                half noise = InterleavedGradientNoise(uv * _ScreenSize.xy, floor(_TimeParameters.x * 60));

                float2 reflectUV = uv;

                int i = 0;
                half travelDistance = 0.2h + noise * 0.1f;
                UNITY_LOOP
                while (i < 5)
                {
                    float3 ray = positionWS + reflectWS * travelDistance;
                    float4 positionCS = TransformWorldToHClip(ray);
                    reflectUV = positionCS.xy / positionCS.w * half2(0.5, -0.5) + 0.5;

                    if (any(reflectUV > float2(1.0f, 1.0f) || reflectUV < float2(0.0f, 0.0f)))
                    {
                        break;
                    }

                    depth = SampleSceneDepth(reflectUV);
                    travelDistance = length(ray - ComputeWorldSpacePosition(reflectUV, depth, _InvCameraViewProj)) +
                        noise * 0.3h;
                    i++;
                }


                float3 originalSceneColor = SampleSceneColor(uv);
                float3 sceneColor = SampleSceneColor(reflectUV);

                return half4(sceneColor * originalSceneColor, reflectivity);

                float3 positionVS = input.viewDirectionVS * LinearEyeDepth(depth, _ZBufferParams);
                return half4(positionVS, 1);

                return half4(input.uv, 0, 1);
            }
            ENDHLSL
        }
    }
}