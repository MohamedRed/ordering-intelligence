import { writeFile } from 'node:fs/promises';
import path from 'node:path';

import { ARTIFACT_DIR } from './ui_smoke_constants.mjs';

export const captureDomDiagnostics = async (page, appName) => {
  const snapshot = await page.evaluate(() => {
    const resolveRoots = () => {
      const roots = [document];
      const flutterView = document.querySelector('flutter-view');
      if (flutterView) roots.push(flutterView);
      const glassPane = document.querySelector('flt-glass-pane');
      if (glassPane?.shadowRoot) roots.push(glassPane.shadowRoot);
      const semanticsHost = document.querySelector('flt-semantics-host');
      if (semanticsHost) roots.push(semanticsHost);
      return roots;
    };
    const findNode = (selector) => {
      const roots = resolveRoots();
      for (const root of roots) {
        const node = root.querySelector(selector);
        if (node) return node;
      }
      return null;
    };
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
    const glassPane = document.querySelector('flt-glass-pane');
    const shadowRoot = glassPane?.shadowRoot ?? null;

    const placeholder = findNode('flt-semantics-placeholder');
    const semantics = findNode('flt-semantics');
    const semanticsHost = findNode('flt-semantics-host');
    const flutterCanvas = findNode('flt-canvas');
    const probeCanvas = document.createElement('canvas');
    const webglSupport = Boolean(probeCanvas.getContext('webgl'));
    const webgl2Support = Boolean(probeCanvas.getContext('webgl2'));
    const resourceEntries = performance
      .getEntriesByType('resource')
      .filter((entry) =>
        /flutter_bootstrap\\.js|main\\.dart\\.js|canvaskit|skwasm|flutter_service_worker/.test(
          entry.name,
        ),
      )
      .slice(-25)
      .map((entry) => ({
        name: entry.name,
        duration: Math.round(entry.duration),
        initiatorType: entry.initiatorType,
      }));
    const scripts = Array.from(document.scripts || [])
      .map((script) => script.src)
      .filter(Boolean)
      .slice(-25);

    return {
      url: window.location.href,
      readyState: document.readyState,
      hasFlutterView: Boolean(flutterView),
      hasShadowRoot: Boolean(shadowRoot),
      userAgent: navigator.userAgent,
      flutterConfig: window._flutter?.buildConfig ?? null,
      flutterLoaderPresent: Boolean(window._flutter?.loader),
      webglSupport,
      webgl2Support,
      placeholder: describe(placeholder),
      semantics: describe(semantics),
      semanticsHost: describe(semanticsHost),
      glassPane: describe(glassPane),
      flutterCanvas: describe(flutterCanvas),
      flutterView: describe(flutterView),
      scripts,
      resourceEntries,
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
