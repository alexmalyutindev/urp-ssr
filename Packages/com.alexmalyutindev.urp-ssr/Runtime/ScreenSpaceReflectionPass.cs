using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class ScreenSpaceReflectionPass : ScriptableRenderPass
    {
        private readonly Material _tracingMaterial;
        private readonly PostProcessData _postProcessData;
        private int ditheringIndex = 0;

        public ScreenSpaceReflectionPass(Material tracingMaterial, PostProcessData postProcessData)
        {
            _tracingMaterial = tracingMaterial;
            _postProcessData = postProcessData;
            profilingSampler = new ProfilingSampler(nameof(ScreenSpaceReflectionPass));
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }
        
        private class PassData
        {
            public TextureHandle ColorTarget;
            public Matrix4x4 CameraTransform;
            public Material Material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();
            var frameDesc = cameraData.cameraTargetDescriptor;

            ditheringIndex = PostProcessUtils.ConfigureDithering(
                _postProcessData,
                ditheringIndex,
                frameDesc.width,
                frameDesc.height,
                _tracingMaterial
            );
            
            using var builder = renderGraph.AddUnsafePass<PassData>("Tracing", out var passData);
            passData.ColorTarget = resourceData.activeColorTexture;

            passData.Material = _tracingMaterial;
            var transform = cameraData.camera.transform;
            passData.CameraTransform = Matrix4x4.TRS(
                transform.position + transform.forward,
                transform.rotation,
                Vector3.one * 2
            );
            
            builder.AllowPassCulling(false);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                cmd.SetRenderTarget(data.ColorTarget);
                cmd.DrawMesh(RenderingUtils.fullscreenMesh, data.CameraTransform, data.Material);
            });
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();

            var camera = renderingData.cameraData.camera;
            ditheringIndex = PostProcessUtils.ConfigureDithering(
                _postProcessData,
                ditheringIndex,
                camera.pixelWidth,
                camera.pixelHeight,
                _tracingMaterial
            );
            
            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                var transform = camera.transform;
                Matrix4x4 quad = Matrix4x4.TRS(
                    transform.position + transform.forward,
                    transform.rotation,
                    Vector3.one * 2
                );
                cmd.DrawMesh(RenderingUtils.fullscreenMesh, quad, _tracingMaterial);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                // Blitter.BlitTexture(
                //     cmd,
                //     colorAttachmentHandle.nameID,
                //     renderingData.cameraData.renderer.cameraColorTargetHandle.nameID,
                //     _tracingMaterial,
                //     0
                // );
            }

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            CommandBufferPool.Release(cmd);
        }
    }
}