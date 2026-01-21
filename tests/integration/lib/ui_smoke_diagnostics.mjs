import { writeFile } from 'node:fs/promises';
import path from 'node:path';

import { ARTIFACT_DIR } from './ui_smoke_constants.mjs';

export const captureDomDiagnostics = async (page, appName) => {
  const snapshot = await page.evaluate(() => {
    const findNode = (selector) =>
      document.querySelector(selector)
      || document.querySelector('flutter-view')?.shadowRoot?.querySelector(selector);
    const describe = (node) => {
      if (!node) return null;
      const rect = node.getBoundingClientRect();
      const style = getComputedStyle(node);
      return {
        tag: node.tagName,
        id: node.id || null,
        className: node.className || null,
        connected: node.isConnected,
        rect: {
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        },
        style: {
          display: style.display,
          visibility: style.visibility,
          opacity: style.opacity,
          pointerEvents: style.pointerEvents,
          position: style.position,
          left: style.left,
          top: style.top,
          width: style.width,
          height: style.height,
          zIndex: style.zIndex,
        },
      };
    };

    const flutterView = document.querySelector('flutter-view');
    const shadowRoot = flutterView?.shadowRoot ?? null;

    const placeholder = findNode('flt-semantics-placeholder');
    const semantics = findNode('flt-semantics');
    const glassPane = findNode('flt-glass-pane');

    return {
      url: window.location.href,
      readyState: document.readyState,
      hasFlutterView: Boolean(flutterView),
      hasShadowRoot: Boolean(shadowRoot),
      placeholder: describe(placeholder),
      semantics: describe(semantics),
      glassPane: describe(glassPane),
      flutterView: describe(flutterView),
    };
  });

  const payload = {
    capturedAt: new Date().toISOString(),
    ...snapshot,
  };

  await writeFile(
    path.join(ARTIFACT_DIR, `${appName}-dom.json`),
    `${JSON.stringify(payload, null, 2)}\n`,
  );
};
