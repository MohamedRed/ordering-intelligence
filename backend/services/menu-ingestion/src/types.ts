export interface IngestStartRequest {
  restaurantId: string;
  pageCount: number;
  currency?: string;
}

export interface IngestJob {
  jobId: string;
  restaurantId: string;
  status: 'uploading' | 'queued' | 'processing' | 'ready' | 'error';
  files: string[];
  issues?: string[];
  createdAt: number;
  updatedAt: number;
  draftRef?: string;
  processedAt?: number;
  processingExpiresAt?: number;
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
  ocrLines: OcrLine[];
  issues?: string[];
  compositeUrls?: string[];
  detectedItemCount?: number;
  createdAt: number;
  updatedAt: number;
}
