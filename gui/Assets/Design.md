# App 图标

由内置 imagegen 工具生成。设计主题为地图折页、珊瑚红定位标记和象征全景探索的环形视野，采用蓝绿底色与透明外缘，无文字。

生成提示词：

> Use case: logo-brand. Asset: production macOS application icon for TuxunSafari, a street-view geography exploration helper. Generate ONE square 1024x1024 icon asset, not a mockup or icon sheet. A beautifully crafted native macOS rounded-square tile in ocean blue and teal, with a simple ivory folded map and a vivid coral-red location pin rising at its center. A subtle elliptical panoramic orbit integrated around the map implies 360-degree street-view exploration. Restrained dimensional depth, soft bevels, tactile satin material, soft top-left lighting, crisp silhouette and strong contrast at small Dock sizes. Tile centered with about 8% transparent margin outside its rounded corners, fully transparent outer background, no external cast shadow beyond tile. No text, letters, numbers, compass tick marks, brand logos, watermark or extra objects. Icon fills frame generously. Clean, sophisticated, visually balanced, designed for a real desktop app.

`AppIcon.png` 为生成的原始图像；构建时按 macOS 图标尺寸生成 `.iconset`，再转换成 `.icns`。
