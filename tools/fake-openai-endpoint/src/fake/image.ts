import { ImageGenerationOptions } from '../types';

/**
 * 1x1 transparent PNG encoded in base64 as a tiny fallback fixture.
 */
export const SAMPLE_BASE64_PNG =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

/**
 * Procedural SVG image generated from prompt.
 */
export function generateSvgDataUrl(prompt: string, size: string = '1024x1024'): string {
  const [width, height] = size.split('x').map((s) => parseInt(s, 10) || 512);
  const cleanPrompt = prompt.replace(/["<>]/g, '').slice(0, 80);

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#4f46e5" />
      <stop offset="100%" stop-color="#06b6d4" />
    </linearGradient>
  </defs>
  <rect width="100%" height="100%" fill="url(#grad)" />
  <circle cx="${width / 2}" cy="${height / 2 - 40}" r="${Math.min(width, height) / 4}" fill="#ffffff" opacity="0.15" />
  <text x="50%" y="${height / 2 - 10}" text-anchor="middle" fill="#ffffff" font-family="sans-serif" font-size="${Math.max(16, width / 28)}px" font-weight="bold">Fake AI Simulator Image</text>
  <text x="50%" y="${height / 2 + 25}" text-anchor="middle" fill="#e0e7ff" font-family="sans-serif" font-size="${Math.max(12, width / 40)}px">${cleanPrompt}</text>
  <text x="50%" y="${height - 20}" text-anchor="middle" fill="#ffffff" opacity="0.6" font-family="sans-serif" font-size="12px">${width}x${height}</text>
</svg>`;

  const base64 = Buffer.from(svg).toString('base64');
  return `data:image/svg+xml;base64,${base64}`;
}

/**
 * Generates an image response matching OpenAI images format.
 */
export function generateImages(options: ImageGenerationOptions) {
  const count = options.n || 1;
  const format = options.response_format || 'url';
  const size = options.size || '1024x1024';

  const data = [];
  for (let i = 0; i < count; i++) {
    if (format === 'b64_json') {
      data.push({
        b64_json: SAMPLE_BASE64_PNG,
        revised_prompt: `Simulated realistic visualization of: "${options.prompt}"`,
      });
    } else {
      data.push({
        url: generateSvgDataUrl(options.prompt, size),
        revised_prompt: `Simulated realistic visualization of: "${options.prompt}"`,
      });
    }
  }

  return {
    created: Math.floor(Date.now() / 1000),
    data,
  };
}
