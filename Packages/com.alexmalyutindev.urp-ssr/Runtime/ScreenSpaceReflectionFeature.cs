using UnityEngine.Rendering.Universal;

namespace SSR.Runtime
{
    public class ScreenSpaceReflectionFeature : ScriptableRendererFeature
    {
        SpecularReflectivityPass _pass;

        /// <inheritdoc/>
        public override void Create()
        {
            _pass = new SpecularReflectivityPass
            {
                renderPassEvent = RenderPassEvent.AfterRenderingOpaques
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_pass);
        }
    }
}