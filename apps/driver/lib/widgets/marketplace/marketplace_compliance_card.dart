import 'package:flutter/material.dart';

import '../../models/delivery_partner_compliance.dart';

const _vehicleLabels = {
  'bike': 'Bike',
  'ebike': 'E-bike',
  'scooter': 'Scooter',
  'car': 'Car',
  'van': 'Van',
};

const _docLabels = {
  'transport_capacity': 'Transport capacity certificate',
  'driver_license': 'Driver license',
  'vehicle_registration': 'Vehicle registration (carte grise)',
  'vehicle_insurance': 'Vehicle insurance',
  'vehicle_photo': 'Vehicle photo',
};

class MarketplaceComplianceCard extends StatelessWidget {
  const MarketplaceComplianceCard({
    super.key,
    required this.compliance,
    required this.busy,
    required this.selectedVehicleType,
    required this.onVehicleTypeChanged,
    required this.onStart,
    required this.onUpload,
    required this.onRefresh,
  });

  final DeliveryPartnerCompliance? compliance;
  final bool busy;
  final String selectedVehicleType;
  final ValueChanged<String> onVehicleTypeChanged;
  final VoidCallback onStart;
  final Future<void> Function(String docType) onUpload;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final compliance = this.compliance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compliance documents',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Required for France: transport capacity + vehicle docs for motorized vehicles.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (compliance == null) ...[
              DropdownButtonFormField<String>(
                value: _vehicleLabels.containsKey(selectedVehicleType)
                    ? selectedVehicleType
                    : null,
                items: _vehicleLabels.entries
                    .map((entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) onVehicleTypeChanged(value);
                      },
                decoration: const InputDecoration(
                  labelText: 'Vehicle type',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: busy || selectedVehicleType.isEmpty ? null : onStart,
                child: const Text('Start compliance'),
              ),
            ] else ...[
              Text('Vehicle: ${_vehicleLabels[compliance.vehicleType] ?? compliance.vehicleType}'),
              const SizedBox(height: 6),
              Text('Status: ${compliance.status}'),
              const SizedBox(height: 8),
              _buildDocList(context, compliance),
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : onRefresh,
                child: const Text('Refresh status'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocList(BuildContext context, DeliveryPartnerCompliance compliance) {
    final requiredDocs = compliance.requiredDocs;
    if (requiredDocs.isEmpty) {
      return const Text('No additional documents required for this vehicle type.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Required documents'),
        const SizedBox(height: 6),
        ...requiredDocs.map((docType) {
          final label = _docLabels[docType] ?? docType;
          final doc = compliance.documents[docType];
          final status = doc?.status ?? 'missing';
          final missing = compliance.missingRequiredDocs().contains(docType);
          final statusText = missing ? 'missing' : status;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            subtitle: Text('Status: $statusText'),
            trailing: doc?.isUploaded == true
                ? const Icon(Icons.check_circle, color: Colors.green)
                : OutlinedButton(
                    onPressed: busy ? null : () => onUpload(docType),
                    child: const Text('Upload'),
                  ),
          );
        }),
      ],
    );
  }
}
