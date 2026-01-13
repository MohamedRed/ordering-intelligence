
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'flyer_attachment.dart';

class FlyerTile extends StatelessWidget {
  const FlyerTile({super.key, required this.flyer, required this.onRemove});
  final FlyerAttachment flyer;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = flyer.mime?.startsWith('image/') ?? false;
    return SizedBox(
      width: 120,
      height: 120,
      child: ShadCard(
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Center(
              child: isImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: flyer.bytes != null
                          ? Image.memory(
                              flyer.bytes!,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            )
                          : (flyer.uploadedUrl != null
                              ? Image.network(
                                  flyer.uploadedUrl!,
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.image_outlined, size: 36)),
                    )
                  : const Icon(Icons.picture_as_pdf, size: 36, color: Colors.red),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                padding: const EdgeInsets.all(4),
                onPressed: onRemove,
                child: const Icon(Icons.close, size: 12),
              ),
            ),
            if (flyer.uploading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (flyer.error != null)
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: Text(
                  'Error',
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else if (flyer.uploadedUrl != null)
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: Text(
                  'Uploaded',
                  style: TextStyle(
                      color: ShadTheme.of(context).colorScheme.primary,
                      fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AddFlyerTile extends StatelessWidget {
  const AddFlyerTile({super.key, required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SizedBox(
      width: 120,
      height: 120,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cs.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPick,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add, size: 20),
            SizedBox(height: 6),
            Text('Add flyer', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
