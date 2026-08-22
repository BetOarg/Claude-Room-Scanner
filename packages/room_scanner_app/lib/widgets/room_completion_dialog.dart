import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

enum RoomCompletionAction {
  addAnotherSpace,
  viewFullPlan,
}

Future<RoomCompletionAction?> showRoomCompletionDialog(
  BuildContext context,
) {
  final l10n = AppLocalizations.of(context)!;

  return showDialog<RoomCompletionAction>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.spaceSaved),
      content: Text(l10n.whatWouldYouLikeToDo),
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(
            dialogContext,
            RoomCompletionAction.addAnotherSpace,
          ),
          icon: const Icon(Icons.add_home_work_outlined),
          label: Text(l10n.addAnotherSpace),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            dialogContext,
            RoomCompletionAction.viewFullPlan,
          ),
          icon: const Icon(Icons.map_outlined),
          label: Text(l10n.viewFullPlan),
        ),
      ],
    ),
  );
}