using SSR.InternalBridge;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class SpecularReflectivityPass : ScriptableRenderPass
    {
        private const string BufferName = "_SpecularReflectivityBuffer";
        private static int BufferNameId = Shader.PropertyToID(BufferName);

        private const string SpecularReflectivityPassName = "SpecularReflectivity";
        private RTHandle _specularBuffer;
        private UniversalRenderer _renderer;
        private FilteringSettings _filteringSettings;
        private ShaderTagId _shaderTagId;

        public SpecularReflectivityPass()
        {
            profilingSampler = new ProfilingSampler(nameof(SpecularReflectivityPass));

            _filteringSettings = FilteringSettings.defaultValue;
            _filteringSettings.renderQueueRange = RenderQueueRange.opaque;

            _shaderTagId = new ShaderTagId(SpecularReflectivityPassName);
        }

        private class PassData
        {
            public RendererListHandle ReflectiveObjects;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var renderingData = frameData.Get<UniversalRenderingData>();
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();

            var frameDescriptor = cameraData.cameraTargetDescriptor;

            using var builder = renderGraph.AddRasterRenderPass<PassData>(nameof(SpecularReflectivityPass), out var passData);
            var desc = new RendererListDesc(_shaderTagId, renderingData.cullResults, cameraData.camera)
            {
                renderQueueRange = RenderQueueRange.opaque,
            };
            passData.ReflectiveObjects = renderGraph.CreateRendererList(desc);
            builder.UseRendererList(passData.ReflectiveObjects);

            var targetDesc = new TextureDesc(frameDescriptor.width, frameDescriptor.height)
            {
                name = BufferName,
                filterMode = FilterMode.Bilinear,
                format = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.ARGB32, true),
            };
            var target = renderGraph.CreateTexture(in targetDesc);

            builder.AllowPassCulling(false);
            builder.SetRenderAttachment(target, 0);
            builder.SetGlobalTextureAfterPass(target, BufferNameId);
            builder.SetRenderFunc<PassData>(static (data, context) =>
            {
                context.cmd.DrawRendererList(data.ReflectiveObjects);
            });
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            _renderer = renderingData.cameraData.renderer as UniversalRenderer;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            var desc = new RenderTextureDescriptor(
                cameraTextureDescriptor.width,
                cameraTextureDescriptor.height,
                RenderTextureFormat.ARGB32
            );

            RenderingUtils.ReAllocateIfNeeded(ref _specularBuffer, desc, filterMode: FilterMode.Bilinear, name: BufferName);

            ConfigureTarget(_specularBuffer, _renderer.GetDepthTexture());
            ConfigureClear(ClearFlag.Color, Color.clear);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();

            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var drawingSettings = CreateDrawingSettings(
                    _shaderTagId,
                    ref renderingData,
                    SortingCriteria.CommonOpaque
                );

                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref _filteringSettings);
            }

            cmd.SetGlobalTexture(BufferName, _specularBuffer);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }
}