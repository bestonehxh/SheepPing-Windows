/// Web preview stand-in for the ICMP engine: browsers cannot send ICMP, so
/// every request reports a general failure.
library;

import 'dart:io';

import 'icmp_types.dart';

Future<IcmpOutcome> icmpEcho(
  InternetAddress target, {
  required Duration timeout,
  int scopeId = 0,
}) async => const IcmpOutcome(status: ipGeneralFailure);
