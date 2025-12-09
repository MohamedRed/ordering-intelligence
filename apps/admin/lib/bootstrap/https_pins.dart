import 'https_pins_stub.dart' if (dart.library.io) 'https_pins_io.dart' as impl;

void enforcePinnedCertificates() => impl.enforcePinnedCertificates();
