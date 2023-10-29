using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class ScreenSpaceReflectionFeature : ScriptableRendererFeature
    {
        public Material TracingMaterial;
        public PostProcessData PostProcessData;

        private SpecularReflectivityPass _pass;
        private ScreenSpaceReflectionPass _tracingPass;

        /// <inheritdoc/>
        public override void Create()
        {
            _pass = new SpecularReflectivityPass
            {
                renderPassEvent = RenderPassEvent.AfterRenderingOpaques
            };

            _tracingPass = new ScreenSpaceReflectionPass(TracingMaterial, PostProcessData)
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingTransparents
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_pass);
            renderer.EnqueuePass(_tracingPass);
        }
    }
}