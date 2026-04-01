import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/order_model.dart';
import '../screens/reverify_face_screen.dart';
import '../utils/app_logger.dart';
import '../widgets/traka_bottom_sheet.dart';
import '../widgets/traka_l10n_scope.dart';
import 'passenger_receipt_pdf_service.dart';
import 'public_receipt_proof_service.dart';
import 'verification_service.dart';

/// Alur terbitkan bukti online + PDF + sheet buka/bagikan (penumpang/penerima atau driver).
class OrderReceiptPdfFlow {
  OrderReceiptPdfFlow._();

  static bool canPassengerIssue(OrderModel order) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !order.isCompleted) return false;
    if (order.passengerUid == uid) return true;
    if (order.isKirimBarang && order.receiverUid == uid) return true;
    return false;
  }

  static bool canDriverIssue(OrderModel order) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !order.isCompleted) return false;
    return order.driverUid == uid;
  }

  static Future<void> issueAsPassenger({
    required State<StatefulWidget> host,
    required OrderModel order,
    required void Function(String?) setLoadingOrderId,
  }) =>
      _issue(
        host: host,
        order: order,
        issuerIsDriver: false,
        setLoadingOrderId: setLoadingOrderId,
      );

  static Future<void> issueAsDriver({
    required State<StatefulWidget> host,
    required OrderModel order,
    required void Function(String?) setLoadingOrderId,
  }) =>
      _issue(
        host: host,
        order: order,
        issuerIsDriver: true,
        setLoadingOrderId: setLoadingOrderId,
      );

  static Future<void> _issue({
    required State<StatefulWidget> host,
    required OrderModel order,
    required bool issuerIsDriver,
    required void Function(String?) setLoadingOrderId,
  }) async {
    final context = host.context;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userData = snap.data();
    if (!context.mounted) return;
    final l10n = TrakaL10n.of(context);

    if (userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountDataNotFound)),
      );
      return;
    }
    if (VerificationService.isAdminVerificationBlockingFeatures(userData)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.receiptAdminVerificationBlocking)),
      );
      return;
    }
    if (issuerIsDriver) {
      if (!VerificationService.isDriverVerified(userData)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.receiptDriverVerificationRequired)),
        );
        return;
      }
    } else {
      if (!VerificationService.isPenumpangVerified(userData)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.receiptPassengerVerificationRequired)),
        );
        return;
      }
    }
    if (VerificationService.needsFaceReverify(userData)) {
      final role = issuerIsDriver ? 'driver' : 'penumpang';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.receiptFaceReverifyRequiredSchedule),
          action: SnackBarAction(
            label: l10n.verify,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (reverifyCtx) => ReverifyFaceScreen(
                    role: role,
                    onSuccess: () => Navigator.of(reverifyCtx).pop(),
                  ),
                ),
              );
            },
          ),
        ),
      );
      return;
    }

    setLoadingOrderId(order.id);

    try {
      final proof = await PublicReceiptProofService.issueProof(order.id);
      final doc = await PassengerReceiptPdfService.buildDocument(
        order: order,
        verifyUrl: proof.verifyUrl,
        issuerIsDriver: issuerIsDriver,
      );
      final name = issuerIsDriver
          ? 'bukti_traka_driver_${order.orderNumber ?? order.id}.pdf'
          : 'bukti_traka_${order.orderNumber ?? order.id}.pdf';
      final file =
          await PassengerReceiptPdfService.savePdfToFile(doc, name: name);
      if (!context.mounted) return;
      await showTrakaModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.pdfReportReadyTitle,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.pdfReportReadyHint,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final r = await PassengerReceiptPdfService.openPdfFile(file);
                    if (!context.mounted) return;
                    if (r.type != ResultType.done) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.failedToOpenPdf(r.message)),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.viewPdf),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    if (issuerIsDriver) {
                      await PassengerReceiptPdfService.sharePdfFile(
                        file,
                        subject: l10n.receiptPdfShareSubjectDriver,
                        text: l10n.receiptPdfShareBodyDriver,
                      );
                    } else {
                      await PassengerReceiptPdfService.sharePdfFile(
                        file,
                        subject: l10n.receiptPdfShareSubjectPassenger,
                        text: l10n.receiptPdfShareBodyPassenger,
                      );
                    }
                  },
                  icon: const Icon(Icons.share),
                  label: Text(l10n.share),
                ),
              ],
            ),
          ),
        ),
      );
    } on PublicReceiptProofException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e, st) {
      logError(
        'OrderReceiptPdfFlow._issue(${issuerIsDriver ? "driver" : "passenger"})',
        e,
        st,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToCreatePdf(e))),
        );
      }
    } finally {
      if (context.mounted) {
        setLoadingOrderId(null);
      }
    }
  }
}
