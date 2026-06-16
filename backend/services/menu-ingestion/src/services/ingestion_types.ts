export type GeneratedComposite = { generatedFiles: string[] };

export type GeminiItemImage = {
  name: string;
  url: string;
  storagePath: string;
};

export type ExtractedItems = {
  images: GeminiItemImage[];
  count: number;
};

export type GradioResult = {
  text?: string;
  inlineData?: string;
  url?: string;
};
