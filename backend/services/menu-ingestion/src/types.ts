export interface IngestStartRequest {
  restaurantId: string;
  pageCount: number;
  currency?: string;
}

export interface IngestJob {
  jobId: string;
  restaurantId: string;
  status: 'uploading' | 'queued' | 'processing' | 'ready' | 'error' | 'canceled';
  pipelineMode?: 'menu_only' | 'full';
  resumeRequestedAt?: number;
  readyKind?: 'menu_only' | 'full';
  files: string[];
  issues?: string[];
  createdAt: number;
  updatedAt: number;
  draftRef?: string;
  processedAt?: number;
  processingExpiresAt?: number;
  processingStartedAt?: number;
  progressPercent?: number; // 0..100
  progressStage?: string; // e.g. queued|analyze|composites|extract|assign|write|done|error
  cancelRequestedAt?: number;
}

export interface ModifierOption {
  id: string;
  name: string;
  priceCents: number;
}

export interface ModifierGroup {
  id: string;
  name: string;
  required: boolean;
  minSelections: number;
  maxSelections: number;
  options: ModifierOption[];
}

export interface BundleComponent {
  role: string;
  itemIds?: string[];
  category?: string;
  requiredGroupIds?: string[];
}

export interface BundleRule {
  bundleId: string;
  displayName: string;
  triggerItemId?: string;
  triggerCategory?: string;
  components: BundleComponent[];
  promptHintsFr?: string;
}

export interface OcrLine {
  page: number;
  text: string;
  bbox: [number, number, number, number];
  line?: number;
  column?: number;
  lineId: string; // unique per line, used to map items back to image crops
}

export interface MenuItem {
  id: string;
  name: string;
  category?: string;
  price?: number;
  currency?: string;
  sizes?: string[];
  description?: string;
  modifiers?: string[];
  modifierGroups?: ModifierGroup[];
  available?: boolean;
  allergens?: string[];
  lineIds?: string[]; // OCR lines that belong to this item (for cropping)
  imageUrl?: string; // signed URL to cropped image (if available)
  photoUrl?: string; // signed URL to detected dish photo (if available)
}

export interface DraftMenu {
  jobId: string;
  restaurantId: string;
  items: MenuItem[];
  bundleRules?: BundleRule[];
  ocrLines: OcrLine[];
  issues?: string[];
  compositeUrls?: string[];
  detectedItemCount?: number;
  createdAt: number;
  updatedAt: number;
}
