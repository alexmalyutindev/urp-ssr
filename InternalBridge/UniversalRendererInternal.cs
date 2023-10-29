using UnityEngine.Experimental.Rendering.RenderGraphModule;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR.InternalBridge
{
    public static class UniversalRendererInternal
    {
        public static RTHandle GetDepthTexture(this UniversalRenderer renderer)
        {
            return renderer.m_DepthTexture;
        }
        
        /// <summary>
        /// 0: GBufferAlbedo
        /// 1: GBufferSpecularMetallic
        /// 2: GBufferNormalSmoothness
        /// 3: GBufferLighting
        /// </summary>
        /// <param name="renderer"></param>
        /// <returns></returns>
        public static TextureHandle[] GetGBuffer(this UniversalRenderer renderer)
        {
            return renderer.frameResources.gbuffer;
        }
    }
}
