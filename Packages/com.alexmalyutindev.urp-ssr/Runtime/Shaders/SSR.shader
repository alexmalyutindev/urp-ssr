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
            //            Blend DstColor Zero
            ZWrite Off
            ZTest Off

            Name "SSR Tracing"

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 3.0

            #pragma vertex Vertex
            #pragma fragment Fragment

            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"

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


            float remap_tri(float v)
            {
                float orig = v * 2.0f - 1.0f;
                v = max(-1.0f, orig / sqrt(abs(orig)));
                return v - sign(orig) + 0.5f;
            }

            float SampleSceneDepthLOD0(float2 uv)
            {
                return SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(uv), 0).r;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                const half thickness = 1.0h;
                const half4 clearColor = half4(0.0h, 0.0h, 0.0h, 0.0h);

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
                    return clearColor;
                }

                half depth = SampleSceneDepthLOD0(uv);
                if (depth == UNITY_RAW_FAR_CLIP_VALUE)
                {
                    return clearColor;
                }

                half3 positionWS = ComputeWorldSpacePosition(uv, depth, _InvCameraViewProj);

                // TODO: Randomize normals
                float3 normalWS = GetNormals(positionWS, uv);

                // NOTE: Redundant
                half NdotV = dot(normalWS, -input.viewDirectionWS);
                // reflectivity *= Pow4(saturate(1 - NdotV));
                reflectivity *= saturate((1.0 - NdotV) / 0.1);

                if (reflectivity < 0.001)
                {
                    return clearColor;
                }

                half noise = SAMPLE_TEXTURE2D(
                    _BlueNoise_Texture,
                    sampler_BlueNoise_Texture,
                    uv * DitheringScale
                ).a;

                half3 noise3 = sin(half3(noise, 2 * noise + 4.235, 5 * noise + 11.35235) * 2 * PI) * 0.05;
                half3 reflectWS = normalize(reflect(input.viewDirectionWS, normalWS) + noise3 * (1 - reflectivity));

                half3 reflectVS = TransformWorldToViewDir(reflectWS);
                half3 positionVS = TransformWorldToView(positionWS);

                float2 reflectUV = uv;
                float alpha = reflectivity;

                int i = 0;
                half4 hitVS = 0;
                half bounceRayLength = 0.1h + noise;
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

                    depth = SampleSceneDepthLOD0(reflectUV);
                    half travelZ =
                        LinearEyeDepth(positionCS.z / positionCS.w, _ZBufferParams) -
                        LinearEyeDepth(depth, _ZBufferParams);
                    half inFrontOfDepthBuffer = travelZ < thickness;
                    alpha *= inFrontOfDepthBuffer;

                    hitVS = mul(unity_MatrixInvP, ComputeClipSpacePosition(reflectUV, depth));
                    bounceRayLength = length(positionVS - hitVS.xyz / hitVS.w);
                    i++;
                }


                half guv = length(reflectUV * 2 - 1);
                half uvAttenuation = saturate(1 - guv * guv);
                float3 sceneColor = SampleSceneColor(reflectUV);

                AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(uv);
                sceneColor *= aoFactor.directAmbientOcclusion;

                alpha *= uvAttenuation / (1 + bounceRayLength * 0.1);

                return half4(saturate(sceneColor) * specular, alpha);
            }
            ENDHLSL
        }
    }
}