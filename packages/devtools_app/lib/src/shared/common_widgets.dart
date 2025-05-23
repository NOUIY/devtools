// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart';

import '../screens/debugger/debugger_controller.dart';
import 'analytics/analytics.dart' as ga;
import 'config_specific/launch_url/launch_url.dart';
import 'console/widgets/expandable_variable.dart';
import 'dialogs.dart';
import 'globals.dart';
import 'object_tree.dart';
import 'primitives/auto_dispose.dart';
import 'primitives/flutter_widgets/linked_scroll_controller.dart';
import 'primitives/utils.dart';
import 'theme.dart';
import 'ui/icons.dart';
import 'ui/label.dart';
import 'utils.dart';

const tooltipWait = Duration(milliseconds: 500);
const tooltipWaitLong = Duration(milliseconds: 1000);

/// The width of the package:flutter_test debugger device.
const debuggerDeviceWidth = 800.0;

const defaultDialogRadius = 20.0;
double get areaPaneHeaderHeight => scaleByFontFactor(36.0);
double get assumedMonospaceCharacterWidth => scaleByFontFactor(9.0);

/// Convenience [Divider] with [Padding] that provides a good divider in forms.
class PaddedDivider extends StatelessWidget {
  const PaddedDivider({
    Key? key,
    this.padding = const EdgeInsets.only(bottom: 10.0),
  }) : super(key: key);

  const PaddedDivider.thin({Key? key})
      : padding = const EdgeInsets.only(bottom: 4.0);

  PaddedDivider.vertical({Key? key, double padding = densePadding})
      : padding = EdgeInsets.symmetric(vertical: padding);

  /// The padding to place around the divider.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: const Divider(thickness: 1.0),
    );
  }
}

/// Creates a semibold version of [style].
TextStyle semibold(TextStyle style) =>
    style.copyWith(fontWeight: FontWeight.w600);

/// Creates a version of [style] that uses the primary color of [context].
///
/// When the app is in dark mode, it instead uses the accent color.
TextStyle primaryColor(TextStyle style, BuildContext context) {
  final theme = Theme.of(context);
  return style.copyWith(
    color: (theme.brightness == Brightness.light)
        ? theme.primaryColor
        : theme.colorScheme.secondary,
    fontWeight: FontWeight.w400,
  );
}

/// Creates a version of [style] that uses the lighter primary color of
/// [context].
///
/// In dark mode, the light primary color still has enough contrast to be
/// visible, so we continue to use it.
TextStyle primaryColorLight(TextStyle style, BuildContext context) {
  final theme = Theme.of(context);
  return style.copyWith(
    color: theme.primaryColorLight,
    fontWeight: FontWeight.w300,
  );
}

class OutlinedIconButton extends IconLabelButton {
  const OutlinedIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    String? tooltip,
    Key? key,
  }) : super(
          key: key,
          icon: icon,
          label: '',
          tooltip: tooltip,
          onPressed: onPressed,
          // TODO(jacobr): consider a more conservative min-width. To minimize the
          // impact on the existing UI and deal with the fact that some of the
          // existing label names are fairly verbose, we set a width that will
          // never be hit.
          minScreenWidthForTextBeforeScaling: 20000,
        );
}

/// A button with an icon and a label.
///
/// * `onPressed`: The callback to be called upon pressing the button.
/// * `minScreenWidthForTextBeforeScaling`: The minimum width the button can be before the text is
///    omitted.
class IconLabelButton extends StatelessWidget {
  const IconLabelButton({
    Key? key,
    this.icon,
    this.imageIcon,
    required this.label,
    required this.onPressed,
    this.color,
    this.minScreenWidthForTextBeforeScaling,
    this.elevatedButton = false,
    this.tooltip,
    this.tooltipPadding,
    this.outlined = true,
  })  : assert((icon == null) != (imageIcon == null)),
        super(key: key);

  final IconData? icon;

  final ThemedImageIcon? imageIcon;

  final String label;

  final double? minScreenWidthForTextBeforeScaling;

  final VoidCallback? onPressed;

  final Color? color;

  /// Whether this icon label button should use an elevated button style.
  final bool elevatedButton;

  final String? tooltip;

  final EdgeInsetsGeometry? tooltipPadding;

  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final iconLabel = MaterialIconLabel(
      label: label,
      iconData: icon,
      imageIcon: imageIcon,
      minScreenWidthForTextBeforeScaling: minScreenWidthForTextBeforeScaling,
      color: color,
    );
    if (elevatedButton) {
      return maybeWrapWithTooltip(
        tooltip: tooltip,
        tooltipPadding: tooltipPadding,
        child: ElevatedButton(
          onPressed: onPressed,
          child: iconLabel,
        ),
      );
    }
    // TODO(kenz): this SizedBox wrapper should be unnecessary once
    // https://github.com/flutter/flutter/issues/79894 is fixed.
    return maybeWrapWithTooltip(
      tooltip: tooltip,
      tooltipPadding: tooltipPadding,
      child: SizedBox(
        height: defaultButtonHeight,
        width: !includeText(context, minScreenWidthForTextBeforeScaling)
            ? buttonMinWidth
            : null,
        child: outlined
            ? OutlinedButton(
                style: denseAwareOutlinedButtonStyle(
                  context,
                  minScreenWidthForTextBeforeScaling,
                ),
                onPressed: onPressed,
                child: iconLabel,
              )
            : TextButton(
                onPressed: onPressed,
                style: denseAwareTextButtonStyle(
                  context,
                  minScreenWidthForTextBeforeScaling,
                ),
                child: iconLabel,
              ),
      ),
    );
  }
}

class PauseButton extends StatelessWidget {
  const PauseButton({
    super.key,
    this.iconOnly = false,
    required this.tooltip,
    required this.onPressed,
    this.minScreenWidthForTextBeforeScaling,
  });

  final bool iconOnly;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double? minScreenWidthForTextBeforeScaling;

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return OutlinedIconButton(
        icon: Icons.pause,
        onPressed: onPressed,
        tooltip: tooltip,
      );
    }

    return IconLabelButton(
      key: key,
      icon: Icons.pause,
      label: 'Pause',
      tooltip: tooltip,
      minScreenWidthForTextBeforeScaling: minScreenWidthForTextBeforeScaling,
      onPressed: onPressed,
    );
  }
}

class ResumeButton extends StatelessWidget {
  const ResumeButton({
    super.key,
    this.iconOnly = false,
    required this.tooltip,
    required this.onPressed,
    this.minScreenWidthForTextBeforeScaling,
  });

  final bool iconOnly;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double? minScreenWidthForTextBeforeScaling;

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return OutlinedIconButton(
        icon: Icons.play_arrow,
        onPressed: onPressed,
        tooltip: tooltip,
      );
    }

    return IconLabelButton(
      key: key,
      icon: Icons.pause,
      label: 'Resume',
      tooltip: tooltip,
      minScreenWidthForTextBeforeScaling: minScreenWidthForTextBeforeScaling,
      onPressed: onPressed,
    );
  }
}

/// A button that groups pause and resume controls and automatically manages
/// the button enabled states depending on the value of [paused].
class PauseResumeButtonGroup extends StatelessWidget {
  const PauseResumeButtonGroup({
    super.key,
    required this.paused,
    required this.onPause,
    required this.onResume,
    this.pauseTooltip = 'Pause',
    this.resumeTooltip = 'Resume',
  });

  final bool paused;

  final VoidCallback onPause;

  final VoidCallback onResume;

  final String pauseTooltip;

  final String resumeTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PauseButton(
          iconOnly: true,
          onPressed: paused ? null : onPause,
          tooltip: pauseTooltip,
        ),
        const SizedBox(width: denseSpacing),
        ResumeButton(
          iconOnly: true,
          onPressed: paused ? onResume : null,
          tooltip: resumeTooltip,
        ),
      ],
    );
  }
}

class ClearButton extends IconLabelButton {
  const ClearButton({
    Key? key,
    double? minScreenWidthForTextBeforeScaling,
    String tooltip = 'Clear',
    bool outlined = true,
    required VoidCallback? onPressed,
  }) : super(
          key: key,
          icon: Icons.block,
          label: 'Clear',
          tooltip: tooltip,
          outlined: outlined,
          minScreenWidthForTextBeforeScaling:
              minScreenWidthForTextBeforeScaling,
          onPressed: onPressed,
        );
}

class RefreshButton extends IconLabelButton {
  const RefreshButton({
    Key? key,
    String label = 'Refresh',
    double? minScreenWidthForTextBeforeScaling,
    String? tooltip,
    required VoidCallback? onPressed,
  })  : isIconButton = false,
        super(
          key: key,
          icon: Icons.refresh,
          label: label,
          minScreenWidthForTextBeforeScaling:
              minScreenWidthForTextBeforeScaling,
          tooltip: tooltip,
          onPressed: onPressed,
        );

  const RefreshButton.icon({
    Key? key,
    String? tooltip,
    required VoidCallback? onPressed,
    bool outlined = true,
  })  : isIconButton = true,
        super(
          key: key,
          icon: Icons.refresh,
          label: '',
          tooltip: tooltip,
          onPressed: onPressed,
          outlined: outlined,
          minScreenWidthForTextBeforeScaling: 20000,
        );

  final bool isIconButton;

  @override
  Widget build(BuildContext context) {
    if (!isIconButton || !outlined) {
      return super.build(context);
    }
    return OutlinedIconButton(
      onPressed: onPressed,
      icon: icon!,
    );
  }
}

/// A Refresh ToolbarAction button.
class ToolbarRefresh extends ToolbarAction {
  const ToolbarRefresh({
    super.icon = Icons.refresh,
    required super.onPressed,
    super.tooltip = 'Refresh',
  });
}

/// Button to start recording data.
///
/// * `recording`: Whether recording is in progress.
/// * `minScreenWidthForTextBeforeScaling`: The minimum width the button can be before the text is
///    omitted.
/// * `labelOverride`: Optional alternative text to use for the button.
/// * `onPressed`: The callback to be called upon pressing the button.
class RecordButton extends IconLabelButton {
  const RecordButton({
    Key? key,
    required bool recording,
    required VoidCallback onPressed,
    double? minScreenWidthForTextBeforeScaling,
    String? labelOverride,
    String tooltip = 'Start recording',
  }) : super(
          key: key,
          onPressed: recording ? null : onPressed,
          icon: Icons.fiber_manual_record,
          label: labelOverride ?? 'Record',
          tooltip: tooltip,
          minScreenWidthForTextBeforeScaling:
              minScreenWidthForTextBeforeScaling,
        );
}

/// Button to stop recording data.
///
/// * `recording`: Whether recording is in progress.
/// * `minScreenWidthForTextBeforeScaling`: The minimum width the button can be before the text is
///    omitted.
/// * `onPressed`: The callback to be called upon pressing the button.
class StopRecordingButton extends IconLabelButton {
  const StopRecordingButton({
    Key? key,
    required bool recording,
    required VoidCallback onPressed,
    double? minScreenWidthForTextBeforeScaling,
    String tooltip = 'Stop recording',
  }) : super(
          key: key,
          onPressed: !recording ? null : onPressed,
          icon: Icons.stop,
          label: 'Stop',
          tooltip: tooltip,
          minScreenWidthForTextBeforeScaling:
              minScreenWidthForTextBeforeScaling,
        );
}

class SettingsOutlinedButton extends OutlinedIconButton {
  const SettingsOutlinedButton({
    required VoidCallback onPressed,
    String? tooltip,
  }) : super(
          onPressed: onPressed,
          icon: Icons.settings,
          tooltip: tooltip,
        );
}

class HelpButton extends StatelessWidget {
  const HelpButton({
    required this.onPressed,
    required this.gaScreen,
    required this.gaSelection,
  });

  final VoidCallback onPressed;

  final String gaScreen;

  final String gaSelection;

  @override
  Widget build(BuildContext context) {
    return DevToolsIconButton(
      iconData: Icons.help_outline,
      onPressed: onPressed,
      tooltip: 'Help',
      gaScreen: gaScreen,
      gaSelection: gaSelection,
    );
  }
}

class ExpandAllButton extends StatelessWidget {
  const ExpandAllButton({Key? key, required this.onPressed}) : super(key: key);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: const Text('Expand All'),
    );
  }
}

class CollapseAllButton extends StatelessWidget {
  const CollapseAllButton({Key? key, required this.onPressed})
      : super(key: key);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: const Text('Collapse All'),
    );
  }
}

/// Button that should be used to control showing or hiding a chart.
///
/// The button automatically toggles the icon and the tooltip to indicate the
/// shown or hidden state.
class VisibilityButton extends StatelessWidget {
  const VisibilityButton({
    required this.show,
    required this.onPressed,
    this.minScreenWidthForTextBeforeScaling,
    required this.label,
    required this.tooltip,
  });

  final ValueListenable<bool> show;

  final void Function(bool) onPressed;

  final double? minScreenWidthForTextBeforeScaling;

  final String label;

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: show,
      builder: (_, show, __) {
        return IconLabelButton(
          key: key,
          tooltip: tooltip,
          icon: show ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          label: label,
          minScreenWidthForTextBeforeScaling:
              minScreenWidthForTextBeforeScaling,
          onPressed: () => onPressed(!show),
        );
      },
    );
  }
}

class RecordingInfo extends StatelessWidget {
  const RecordingInfo({
    this.instructionsKey,
    this.recordingStatusKey,
    this.processingStatusKey,
    required this.recording,
    required this.recordedObject,
    required this.processing,
    this.progressValue,
    this.isPause = false,
  });

  final Key? instructionsKey;

  final Key? recordingStatusKey;

  final Key? processingStatusKey;

  final bool recording;

  final String recordedObject;

  final bool processing;

  final double? progressValue;

  final bool isPause;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (processing) {
      child = ProcessingInfo(
        key: processingStatusKey,
        progressValue: progressValue,
        processedObject: recordedObject,
      );
    } else if (recording) {
      child = RecordingStatus(
        key: recordingStatusKey,
        recordedObject: recordedObject,
      );
    } else {
      child = RecordingInstructions(
        key: instructionsKey,
        recordedObject: recordedObject,
        isPause: isPause,
      );
    }
    return Center(
      child: child,
    );
  }
}

class RecordingStatus extends StatelessWidget {
  const RecordingStatus({
    Key? key,
    required this.recordedObject,
  }) : super(key: key);

  final String recordedObject;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Recording $recordedObject',
          style: Theme.of(context).subtleTextStyle,
        ),
        const SizedBox(height: defaultSpacing),
        const CircularProgressIndicator(),
      ],
    );
  }
}

class RecordingInstructions extends StatelessWidget {
  const RecordingInstructions({
    Key? key,
    required this.isPause,
    required this.recordedObject,
  }) : super(key: key);

  final String recordedObject;

  final bool isPause;

  @override
  Widget build(BuildContext context) {
    final stopOrPauseRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: isPause
          ? const [
              Text('Click the pause button '),
              Icon(Icons.pause),
              Text(' to pause the recording.'),
            ]
          : const [
              Text('Click the stop button '),
              Icon(Icons.stop),
              Text(' to end the recording.'),
            ],
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Click the record button '),
            const Icon(Icons.fiber_manual_record),
            Text(' to start recording $recordedObject.'),
          ],
        ),
        stopOrPauseRow,
      ],
    );
  }
}

class ProcessingInfo extends StatelessWidget {
  const ProcessingInfo({
    Key? key,
    required this.progressValue,
    required this.processedObject,
  }) : super(key: key);

  final double? progressValue;

  final String processedObject;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Processing $processedObject',
            style: Theme.of(context).subtleTextStyle,
          ),
          const SizedBox(height: defaultSpacing),
          SizedBox(
            width: 200.0,
            height: defaultSpacing,
            child: LinearProgressIndicator(
              value: progressValue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Common button for exiting offline mode.
///
/// Consumers of this widget will be responsible for including the following in
/// onPressed:
///
/// setState(() {
///   offlineController.exitOfflineMode();
/// }
class ExitOfflineButton extends IconLabelButton {
  const ExitOfflineButton({required VoidCallback onPressed})
      : super(
          key: const Key('exit offline button'),
          onPressed: onPressed,
          label: 'Exit offline mode',
          icon: Icons.clear,
        );
}

/// A small element containing some accessory information, often a numeric
/// value.
class Badge extends StatelessWidget {
  const Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // These constants are sized to give 1 digit badges a circular look.
    const badgeCornerRadius = 12.0;
    const badgePadding = 6.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(badgeCornerRadius),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: borderPadding,
        horizontal: badgePadding,
      ),
      child: Text(
        text,
        // Use a slightly smaller font for the badge.
        style: (theme.primaryTextTheme.bodyMedium ?? const TextStyle())
            .apply(fontSizeDelta: -1),
      ),
    );
  }
}

/// A widget, commonly used for icon buttons, that provides a tooltip with a
/// common delay before the tooltip is shown.
class DevToolsTooltip extends StatelessWidget {
  const DevToolsTooltip({
    Key? key,
    this.message,
    this.richMessage,
    required this.child,
    this.waitDuration = tooltipWait,
    this.preferBelow = false,
    this.padding = const EdgeInsets.all(defaultSpacing),
    this.decoration,
    this.textStyle,
  })  : assert((message == null) != (richMessage == null)),
        super(key: key);

  final String? message;
  final InlineSpan? richMessage;
  final Widget child;
  final Duration waitDuration;
  final bool preferBelow;
  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    TextStyle? style = textStyle;
    if (richMessage == null) {
      style ??= TextStyle(
        color: Theme.of(context).colorScheme.tooltipTextColor,
        fontSize: defaultFontSize,
      );
    }
    return Tooltip(
      message: message,
      richMessage: richMessage,
      waitDuration: waitDuration,
      preferBelow: preferBelow,
      padding: padding,
      textStyle: style,
      decoration: decoration,
      child: child,
    );
  }
}

class DevToolsIconButton extends StatelessWidget {
  const DevToolsIconButton({
    Key? key,
    this.iconData,
    this.iconWidget,
    required this.onPressed,
    required this.tooltip,
    required this.gaScreen,
    required this.gaSelection,
  })  : assert((iconData == null) != (iconWidget == null)),
        super(key: key);

  final IconData? iconData;

  final Widget? iconWidget;

  final VoidCallback onPressed;

  final String tooltip;

  final String gaScreen;

  final String gaSelection;

  @override
  Widget build(BuildContext context) {
    final icon = iconData != null
        ? Icon(
            iconData,
            size: defaultIconSize,
          )
        : iconWidget;
    return SizedBox(
      // This is required to force the button height.
      height: defaultButtonHeight,
      child: DevToolsTooltip(
        message: tooltip,
        child: TextButton(
          onPressed: () {
            ga.select(gaScreen, gaSelection);
            onPressed();
          },
          child: SizedBox(
            height: defaultButtonHeight,
            width: defaultButtonHeight,
            child: icon,
          ),
        ),
      ),
    );
  }
}

/// A wrapper around a TextButton, an Icon, and an optional Tooltip; used for
/// small toolbar actions.
class ToolbarAction extends StatelessWidget {
  const ToolbarAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    Key? key,
    this.size,
    this.style,
  }) : super(key: key);

  final TextStyle? style;
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: style,
      ),
      onPressed: onPressed,
      child: Icon(
        icon,
        size: size ?? actionsIconSize,
        color: style?.color,
      ),
    );

    return tooltip == null
        ? button
        : DevToolsTooltip(
            message: tooltip,
            child: button,
          );
  }
}

/// A blank, drop-in replacement for [AreaPaneHeader].
///
/// Acts as an empty header widget with zero size that is compatible with
/// interfaces that expect a [PreferredSizeWidget].
class BlankHeader extends StatelessWidget implements PreferredSizeWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }

  @override
  Size get preferredSize => Size.zero;
}

/// Create a bordered, fixed-height header area with a title and optional child
/// on the right-hand side.
///
/// This is typically used as a title for a logical area of the screen.
class AreaPaneHeader extends StatelessWidget implements PreferredSizeWidget {
  const AreaPaneHeader({
    Key? key,
    required this.title,
    this.maxLines = 1,
    this.needsTopBorder = true,
    this.needsBottomBorder = true,
    this.needsLeftBorder = false,
    this.actions = const [],
    this.leftPadding = defaultSpacing,
    this.rightPadding = densePadding,
    this.tall = false,
    this.backgroundColor,
  }) : super(key: key);

  final Widget title;
  final int maxLines;
  final bool needsTopBorder;
  final bool needsBottomBorder;
  final bool needsLeftBorder;
  final List<Widget> actions;
  final double leftPadding;
  final double rightPadding;
  final bool tall;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderSide = defaultBorderSide(theme);
    return SizedBox.fromSize(
      size: preferredSize,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: needsTopBorder ? borderSide : BorderSide.none,
            bottom: needsBottomBorder ? borderSide : BorderSide.none,
            left: needsLeftBorder ? borderSide : BorderSide.none,
          ),
          color: backgroundColor ?? theme.titleSolidBackgroundColor,
        ),
        padding: EdgeInsets.only(left: leftPadding, right: rightPadding),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: DefaultTextStyle(
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall!,
                child: title,
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize {
    return Size.fromHeight(
      tall ? areaPaneHeaderHeight + 2 * densePadding : areaPaneHeaderHeight,
    );
  }
}

BorderSide defaultBorderSide(ThemeData theme) {
  return BorderSide(color: theme.focusColor);
}

class DevToolsToggleButtonGroup extends StatelessWidget {
  const DevToolsToggleButtonGroup({
    Key? key,
    required this.children,
    required this.selectedStates,
    required this.onPressed,
  }) : super(key: key);

  final List<Widget> children;

  final List<bool> selectedStates;

  final void Function(int)? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: defaultButtonHeight,
      child: ToggleButtons(
        borderRadius:
            const BorderRadius.all(Radius.circular(defaultBorderRadius)),
        color: theme.colorScheme.toggleButtonsTitle,
        selectedColor: theme.colorScheme.toggleButtonsTitleSelected,
        fillColor: theme.colorScheme.toggleButtonsFillSelected,
        textStyle: theme.textTheme.bodyLarge,
        constraints: BoxConstraints(
          minWidth: defaultButtonHeight,
          minHeight: defaultButtonHeight,
        ),
        isSelected: selectedStates,
        onPressed: onPressed,
        children: children,
      ),
    );
  }
}

/// Button to export data.
///
/// * `minScreenWidthForTextBeforeScaling`: The minimum width the button can be before the text is
///    omitted.
/// * `onPressed`: The callback to be called upon pressing the button.
class ExportButton extends IconLabelButton {
  const ExportButton({
    Key? key,
    required VoidCallback? onPressed,
    required double minScreenWidthForTextBeforeScaling,
    String tooltip = 'Export data',
  }) : super(
          key: key,
          onPressed: onPressed,
          icon: Icons.file_download,
          label: 'Export',
          tooltip: tooltip,
          minScreenWidthForTextBeforeScaling:
              minScreenWidthForTextBeforeScaling,
        );
}

/// Button to open related information / documentation.
///
/// [tooltip] specifies the hover text for the button.
/// [link] is the link that should be opened when the button is clicked.
class InformationButton extends StatelessWidget {
  const InformationButton({
    Key? key,
    required this.tooltip,
    required this.link,
  }) : super(key: key);

  final String tooltip;

  final String link;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: const Icon(Icons.help_outline),
        onPressed: () async => await launchUrl(link),
      ),
    );
  }
}

class ToggleButton extends StatelessWidget {
  const ToggleButton({
    Key? key,
    required this.onPressed,
    required this.isSelected,
    required this.message,
    required this.icon,
    this.outlined = true,
    this.label,
    this.shape,
  }) : super(key: key);

  final String message;

  final VoidCallback onPressed;

  final bool isSelected;

  final IconData icon;

  final String? label;

  final OutlinedBorder? shape;

  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DevToolsTooltip(
      message: message,
      // TODO(kenz): this SizedBox wrapper should be unnecessary once
      // https://github.com/flutter/flutter/issues/79894 is fixed.
      child: SizedBox(
        height: defaultButtonHeight,
        child: OutlinedButton(
          key: key,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            side: outlined ? null : BorderSide.none,
            backgroundColor: isSelected
                ? theme.colorScheme.toggleButtonsFillSelected
                : Colors.transparent,
            shape: shape,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: defaultIconSize,
                color: isSelected
                    ? theme.colorScheme.toggleButtonsTitleSelected
                    : theme.colorScheme.toggleButtonsTitle,
              ),
              if (label != null) ...[
                const SizedBox(width: denseSpacing),
                Text(
                  style: theme.textTheme.bodyLarge!.apply(
                    color: isSelected
                        ? theme.colorScheme.toggleButtonsTitleSelected
                        : theme.colorScheme.toggleButtonsTitle,
                  ),
                  label!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FilterButton extends StatelessWidget {
  const FilterButton({
    Key? key,
    required this.onPressed,
    required this.isFilterActive,
    this.message = 'Filter',
  }) : super(key: key);

  final VoidCallback onPressed;
  final bool isFilterActive;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ToggleButton(
      onPressed: onPressed,
      isSelected: isFilterActive,
      message: message,
      icon: Icons.filter_list,
    );
  }
}

class RoundedDropDownButton<T> extends StatelessWidget {
  const RoundedDropDownButton({
    Key? key,
    this.value,
    this.onChanged,
    this.isDense = false,
    this.style,
    this.selectedItemBuilder,
    this.items,
  }) : super(key: key);

  final T? value;

  final ValueChanged<T?>? onChanged;

  final bool isDense;

  final TextStyle? style;

  final DropdownButtonBuilder? selectedItemBuilder;

  final List<DropdownMenuItem<T>>? items;

  @override
  Widget build(BuildContext context) {
    return RoundedOutlinedBorder(
      child: Center(
        child: Container(
          padding: const EdgeInsets.only(
            left: defaultSpacing,
            right: borderPadding,
          ),
          height: defaultButtonHeight - 2.0, // subtract 2.0 for width of border
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              onChanged: onChanged,
              isDense: isDense,
              style: style,
              selectedItemBuilder: selectedItemBuilder,
              items: items,
            ),
          ),
        ),
      ),
    );
  }
}

class DevToolsClearableTextField extends StatelessWidget {
  DevToolsClearableTextField({
    Key? key,
    required this.labelText,
    TextEditingController? controller,
    this.hintText,
    this.onChanged,
    this.autofocus = false,
  })  : controller = controller ?? TextEditingController(),
        super(key: key);

  final TextEditingController controller;
  final String? hintText;
  final String labelText;
  final Function(String)? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      autofocus: autofocus,
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(denseSpacing),
        constraints: BoxConstraints(
          minHeight: defaultTextFieldHeight,
          maxHeight: defaultTextFieldHeight,
        ),
        border: const OutlineInputBorder(),
        labelText: labelText,
        hintText: hintText,
        suffixIcon: IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.clear),
          onPressed: () {
            controller.clear();
            onChanged?.call('');
          },
        ),
        isDense: true,
      ),
    );
  }
}

Widget clearInputButton(VoidCallback onPressed) {
  return inputDecorationSuffixButton(Icons.clear, onPressed);
}

Widget closeSearchDropdownButton(VoidCallback? onPressed) {
  return inputDecorationSuffixButton(Icons.close, onPressed);
}

Widget inputDecorationSuffixButton(IconData icon, VoidCallback? onPressed) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: densePadding),
    width: defaultIconSize + denseSpacing,
    child: IconButton(
      padding: const EdgeInsets.all(0.0),
      onPressed: onPressed,
      iconSize: defaultIconSize,
      splashRadius: defaultIconSize,
      icon: Icon(icon),
    ),
  );
}

class OutlinedRowGroup extends StatelessWidget {
  const OutlinedRowGroup({required this.children, this.borderColor});

  final List<Widget> children;

  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final color = borderColor ?? Theme.of(context).focusColor;
    final childrenWithOutlines = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      childrenWithOutlines.addAll([
        Container(
          decoration: BoxDecoration(
            border: Border(
              left: i == 0 ? BorderSide(color: color) : BorderSide.none,
              right: BorderSide(color: color),
              top: BorderSide(color: color),
              bottom: BorderSide(color: color),
            ),
          ),
          child: children[i],
        ),
      ]);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: childrenWithOutlines,
    );
  }
}

class OutlineDecoration extends StatelessWidget {
  const OutlineDecoration({
    Key? key,
    this.child,
    this.showTop = true,
    this.showBottom = true,
    this.showLeft = true,
    this.showRight = true,
  }) : super(key: key);

  factory OutlineDecoration.onlyBottom({required Widget? child}) =>
      OutlineDecoration(
        showTop: false,
        showLeft: false,
        showRight: false,
        child: child,
      );

  factory OutlineDecoration.onlyTop({required Widget? child}) =>
      OutlineDecoration(
        showBottom: false,
        showLeft: false,
        showRight: false,
        child: child,
      );

  factory OutlineDecoration.onlyLeft({required Widget? child}) =>
      OutlineDecoration(
        showBottom: false,
        showTop: false,
        showRight: false,
        child: child,
      );

  factory OutlineDecoration.onlyRight({required Widget? child}) =>
      OutlineDecoration(
        showBottom: false,
        showTop: false,
        showLeft: false,
        child: child,
      );

  final bool showTop;
  final bool showBottom;
  final bool showLeft;
  final bool showRight;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).focusColor;
    final border = BorderSide(color: color);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: showLeft ? border : BorderSide.none,
          right: showRight ? border : BorderSide.none,
          top: showTop ? border : BorderSide.none,
          bottom: showBottom ? border : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

class RoundedOutlinedBorder extends StatelessWidget {
  const RoundedOutlinedBorder({Key? key, this.child}) : super(key: key);

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: roundedBorderDecoration(context),
      child: child,
    );
  }
}

BoxDecoration roundedBorderDecoration(BuildContext context) => BoxDecoration(
      border: Border.all(color: Theme.of(context).focusColor),
      borderRadius: BorderRadius.circular(defaultBorderRadius),
    );

class LeftBorder extends StatelessWidget {
  const LeftBorder({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final leftBorder =
        Border(left: BorderSide(color: Theme.of(context).focusColor));

    return Container(
      decoration: BoxDecoration(border: leftBorder),
      child: child,
    );
  }
}

/// The golden ratio.
///
/// Makes for nice-looking rectangles.
final goldenRatio = 1 + sqrt(5) / 2;

class CenteredMessage extends StatelessWidget {
  const CenteredMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}

class CenteredCircularProgressIndicator extends StatelessWidget {
  const CenteredCircularProgressIndicator({this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    const indicator = Center(
      child: CircularProgressIndicator(),
    );

    if (size == null) return indicator;

    return SizedBox(
      width: size,
      height: size,
      child: indicator,
    );
  }
}

class CircularIconButton extends StatelessWidget {
  const CircularIconButton({
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return RawMaterialButton(
      fillColor: backgroundColor,
      hoverColor: Theme.of(context).hoverColor,
      elevation: 0.0,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      constraints: BoxConstraints.tightFor(
        width: actionsIconSize,
        height: actionsIconSize,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
        side: BorderSide(
          width: 2.0,
          color: foregroundColor,
        ),
      ),
      onPressed: onPressed,
      child: Icon(
        icon,
        size: defaultIconSize,
        color: foregroundColor,
      ),
    );
  }
}

/// An extension on [ScrollController] to facilitate having the scrolling widget
/// auto scroll to the bottom on new content.
extension ScrollControllerAutoScroll on ScrollController {
// TODO(devoncarew): We lose dock-to-bottom when we receive content when we're
// off screen.

  /// Return whether the view is currently scrolled to the bottom.
  bool get atScrollBottom {
    final pos = position;
    return pos.pixels == pos.maxScrollExtent;
  }

  /// Scroll the content to the bottom using the app's default animation
  /// duration and curve..
  Future<void> autoScrollToBottom() async {
    await animateTo(
      position.maxScrollExtent,
      duration: rapidDuration,
      curve: defaultCurve,
    );

    // Scroll again if we've received new content in the interim.
    if (hasClients) {
      final pos = position;
      if (pos.pixels != pos.maxScrollExtent) {
        jumpTo(pos.maxScrollExtent);
      }
    }
  }
}

/// An extension on [LinkedScrollControllerGroup] to facilitate having the
/// scrolling widgets auto scroll to the bottom on new content.
///
/// This extension serves the same function as the [ScrollControllerAutoScroll]
/// extension above, but we need to implement these methods again as an
/// extension on [LinkedScrollControllerGroup] because individual
/// [ScrollController]s are intentionally inaccessible from
/// [LinkedScrollControllerGroup].
extension LinkedScrollControllerGroupExtension on LinkedScrollControllerGroup {
  bool get atScrollBottom {
    final pos = position;
    return pos.pixels == pos.maxScrollExtent;
  }

  /// Scroll the content to the bottom using the app's default animation
  /// duration and curve..
  void autoScrollToBottom() async {
    await animateTo(
      position.maxScrollExtent,
      duration: rapidDuration,
      curve: defaultCurve,
    );

    // Scroll again if we've received new content in the interim.
    if (hasAttachedControllers) {
      final pos = position;
      if (pos.pixels != pos.maxScrollExtent) {
        jumpTo(pos.maxScrollExtent);
      }
    }
  }
}

/// Utility extension methods to the [Color] class.
extension ColorExtension on Color {
  /// Return a slightly darker color than the current color.
  Color darken([double percent = 0.05]) {
    assert(0.0 <= percent && percent <= 1.0);
    percent = 1.0 - percent;

    final c = this;
    return Color.fromARGB(
      c.alpha,
      (c.red * percent).round(),
      (c.green * percent).round(),
      (c.blue * percent).round(),
    );
  }

  /// Return a slightly brighter color than the current color.
  Color brighten([double percent = 0.05]) {
    assert(0.0 <= percent && percent <= 1.0);

    final c = this;
    return Color.fromARGB(
      c.alpha,
      c.red + ((255 - c.red) * percent).round(),
      c.green + ((255 - c.green) * percent).round(),
      c.blue + ((255 - c.blue) * percent).round(),
    );
  }
}

/// Gets an alternating color to use for indexed UI elements.
Color alternatingColorForIndex(int index, ColorScheme colorScheme) {
  return index % 2 == 1
      ? colorScheme.defaultBackgroundColor
      : colorScheme.alternatingBackgroundColor;
}

class BreadcrumbNavigator extends StatelessWidget {
  const BreadcrumbNavigator.builder({
    required this.itemCount,
    required this.builder,
  });

  final int itemCount;

  final IndexedWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Breadcrumb.height + 2 * borderPadding,
      alignment: Alignment.centerLeft,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        itemBuilder: builder,
      ),
    );
  }
}

class Breadcrumb extends StatelessWidget {
  const Breadcrumb({
    required this.text,
    required this.isRoot,
    required this.onPressed,
  });

  static const height = 28.0;

  static const caretWidth = 4.0;

  final String text;

  final bool isRoot;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Create the text painter here so that we can calculate `breadcrumbWidth`.
    // We need the width for the wrapping Container that gives the CustomPaint
    // a bounded width.
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: theme.colorScheme.chartTextColor,
          decoration: TextDecoration.underline,
        ),
      ),
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    )..layout();

    final caretWidth =
        isRoot ? Breadcrumb.caretWidth : Breadcrumb.caretWidth * 2;
    final breadcrumbWidth = textPainter.width + caretWidth + densePadding * 2;

    return InkWell(
      onTap: onPressed,
      child: Container(
        width: breadcrumbWidth,
        padding: const EdgeInsets.all(borderPadding),
        child: CustomPaint(
          painter: _BreadcrumbPainter(
            textPainter: textPainter,
            isRoot: isRoot,
            breadcrumbWidth: breadcrumbWidth,
            colorScheme: theme.colorScheme,
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbPainter extends CustomPainter {
  _BreadcrumbPainter({
    required this.textPainter,
    required this.isRoot,
    required this.breadcrumbWidth,
    required this.colorScheme,
  });

  final TextPainter textPainter;

  final bool isRoot;

  final double breadcrumbWidth;

  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colorScheme.chartAccentColor;
    final path = Path()..moveTo(0, 0);

    if (isRoot) {
      path.lineTo(0, Breadcrumb.height);
    } else {
      path
        ..lineTo(Breadcrumb.caretWidth, Breadcrumb.height / 2)
        ..lineTo(0, Breadcrumb.height);
    }

    path
      ..lineTo(breadcrumbWidth - Breadcrumb.caretWidth, Breadcrumb.height)
      ..lineTo(breadcrumbWidth, Breadcrumb.height / 2)
      ..lineTo(breadcrumbWidth - Breadcrumb.caretWidth, 0);

    canvas.drawPath(path, paint);

    final textXOffset =
        isRoot ? densePadding : Breadcrumb.caretWidth + densePadding;
    textPainter.paint(
      canvas,
      Offset(textXOffset, (Breadcrumb.height - textPainter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _BreadcrumbPainter oldDelegate) {
    return textPainter != oldDelegate.textPainter ||
        isRoot != oldDelegate.isRoot ||
        breadcrumbWidth != oldDelegate.breadcrumbWidth ||
        colorScheme != oldDelegate.colorScheme;
  }
}

// TODO(bkonyi): replace uses of this class with `JsonViewer`.
class FormattedJson extends StatelessWidget {
  const FormattedJson({
    this.json,
    this.formattedString,
    this.useSubtleStyle = false,
  }) : assert((json == null) != (formattedString == null));

  static const encoder = JsonEncoder.withIndent('  ');

  final Map<String, dynamic>? json;

  final String? formattedString;

  final bool useSubtleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // TODO(kenz): we could consider using a prettier format like YAML.
    return SelectableText(
      json != null ? encoder.convert(json) : formattedString!,
      style: useSubtleStyle ? theme.subtleFixedFontStyle : theme.fixedFontStyle,
    );
  }
}

class JsonViewer extends StatefulWidget {
  const JsonViewer({
    required this.encodedJson,
  });

  final String encodedJson;

  @override
  State<JsonViewer> createState() => _JsonViewerState();
}

class _JsonViewerState extends State<JsonViewer>
    with ProvidedControllerMixin<DebuggerController, JsonViewer> {
  late Future<void> _initializeTree;
  late DartObjectNode variable;

  @override
  void initState() {
    super.initState();
    assert(widget.encodedJson.isNotEmpty);
    final responseJson = json.decode(widget.encodedJson);
    // Insert the JSON data into the fake service cache so we can use it with
    // the `ExpandableVariable` widget.
    final root =
        serviceManager.service!.fakeServiceCache.insertJsonObject(responseJson);
    variable = DartObjectNode.fromValue(
      name: '[root]',
      value: root,
      artificialName: true,
      isolateRef: IsolateRef(
        id: 'fake-isolate',
        number: 'fake-isolate',
        name: 'local-cache',
        isSystemIsolate: true,
      ),
    );
    // Intended to be unawaited.
    // ignore: discarded_futures
    _initializeTree = buildVariablesTree(variable);
  }

  @override
  void dispose() {
    super.dispose();
    // Remove the JSON object from the fake service cache to avoid holding on
    // to large objects indefinitely.
    serviceManager.service!.fakeServiceCache
        .removeJsonObject(variable.value as Instance);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Currently a redundant check, but adding it anyway to prevent future
    // bugs being introduced.
    if (!initController()) {
      return;
    }
    // Any additional initialization code should be added after this line.
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(denseSpacing),
      child: SingleChildScrollView(
        child: FutureBuilder(
          future: _initializeTree,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return Container();
            return ExpandableVariable(
              variable: variable,
            );
          },
        ),
      ),
    );
  }
}

class MoreInfoLink extends StatelessWidget {
  const MoreInfoLink({
    Key? key,
    required this.url,
    required this.gaScreenName,
    required this.gaSelectedItemDescription,
    this.padding,
  }) : super(key: key);

  final String url;

  final String gaScreenName;

  final String gaSelectedItemDescription;

  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _onLinkTap,
      borderRadius: BorderRadius.circular(defaultBorderRadius),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(denseSpacing),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'More info',
              style: theme.linkTextStyle,
            ),
            const SizedBox(width: densePadding),
            Icon(
              Icons.launch,
              size: tooltipIconSize,
              color: theme.colorScheme.toggleButtonsTitle,
            ),
          ],
        ),
      ),
    );
  }

  void _onLinkTap() {
    unawaited(launchUrl(url));
    ga.select(gaScreenName, gaSelectedItemDescription);
  }
}

class LinkTextSpan extends TextSpan {
  LinkTextSpan({
    required Link link,
    required BuildContext context,
    TextStyle? style,
  }) : super(
          text: link.display,
          style: style ?? Theme.of(context).linkTextStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              ga.select(
                link.gaScreenName,
                link.gaSelectedItemDescription,
              );
              await launchUrl(link.url);
            },
        );
}

class Link {
  const Link({
    required this.display,
    required this.url,
    required this.gaScreenName,
    required this.gaSelectedItemDescription,
  });

  final String display;

  final String url;

  final String gaScreenName;

  final String gaSelectedItemDescription;
}

Widget maybeWrapWithTooltip({
  required String? tooltip,
  EdgeInsetsGeometry? tooltipPadding,
  required Widget child,
}) {
  if (tooltip != null) {
    return DevToolsTooltip(
      message: tooltip,
      padding: tooltipPadding,
      child: child,
    );
  }
  return child;
}

class Legend extends StatelessWidget {
  const Legend({
    Key? key,
    required this.entries,
    this.dense = false,
  }) : super(key: key);

  double get legendSquareSize =>
      dense ? scaleByFontFactor(12.0) : scaleByFontFactor(16.0);

  final List<LegendEntry> entries;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final textStyle = dense ? Theme.of(context).legendTextStyle : null;
    final List<Widget> legendItems = entries
        .map(
          (entry) => _legendItem(
            entry.description,
            entry.color,
            textStyle,
          ),
        )
        .toList()
        .joinWith(const SizedBox(height: denseRowSpacing));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: legendItems,
    );
  }

  Widget _legendItem(String description, Color? color, TextStyle? style) {
    return Row(
      children: [
        Container(
          height: legendSquareSize,
          width: legendSquareSize,
          color: color,
        ),
        const SizedBox(width: denseSpacing),
        Text(
          description,
          style: style,
        ),
      ],
    );
  }
}

class LegendEntry {
  const LegendEntry(this.description, this.color);

  final String description;

  final Color? color;
}

/// The type of data provider function used by the CopyToClipboard Control.
typedef ClipboardDataProvider = String? Function();

/// Control that copies `data` to the clipboard.
///
/// If it succeeds, it displays a notification with `successMessage`.
class CopyToClipboardControl extends StatelessWidget {
  const CopyToClipboardControl({
    this.dataProvider,
    this.successMessage = 'Copied to clipboard.',
    this.tooltip = 'Copy to clipboard',
    this.buttonKey,
    this.size,
    this.gaScreen,
    this.gaItem,
    this.style,
  });

  final TextStyle? style;
  final ClipboardDataProvider? dataProvider;
  final String? successMessage;
  final String tooltip;
  final Key? buttonKey;
  final double? size;
  final String? gaScreen;
  final String? gaItem;

  @override
  Widget build(BuildContext context) {
    final onPressed = dataProvider == null
        ? null
        : () {
            if (gaScreen != null && gaItem != null) {
              ga.select(gaScreen!, gaItem!);
            }
            unawaited(
              copyToClipboard(dataProvider!() ?? '', successMessage),
            );
          };

    return ToolbarAction(
      icon: Icons.content_copy,
      tooltip: tooltip,
      onPressed: onPressed,
      key: buttonKey,
      size: size,
      style: style,
    );
  }
}

/// Checkbox Widget class that listens to and manages a [ValueNotifier].
///
/// Used to create a Checkbox widget who's boolean value is attached
/// to a [ValueNotifier<bool>]. This allows for the pattern:
///
/// Create the [NotifierCheckbox] widget in build e.g.,
///
///   myCheckboxWidget = NotifierCheckbox(notifier: controller.myCheckbox);
///
/// The checkbox and the value notifier are now linked with clicks updating the
/// [ValueNotifier] and changes to the [ValueNotifier] updating the checkbox.
class NotifierCheckbox extends StatelessWidget {
  const NotifierCheckbox({
    Key? key,
    required this.notifier,
    this.onChanged,
    this.enabled = true,
    this.checkboxKey,
  }) : super(key: key);

  /// The notifier this [NotifierCheckbox] is responsible for listening to and
  /// updating.
  final ValueNotifier<bool?> notifier;

  /// The callback to be called on change in addition to the notifier changes
  /// handled by this class.
  final void Function(bool? newValue)? onChanged;

  /// Whether this checkbox should be enabled for interaction.
  final bool enabled;

  /// Key to assign to the checkbox, for testing purposes.
  final Key? checkboxKey;

  void _updateValue(bool? value) {
    if (notifier.value != value) {
      notifier.value = value;
      if (onChanged != null) {
        onChanged!(value);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: notifier,
      builder: (context, bool? value, _) {
        return SizedBox(
          height: defaultButtonHeight,
          child: Checkbox(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            value: value,
            onChanged: enabled ? _updateValue : null,
            key: checkboxKey,
          ),
        );
      },
    );
  }
}

class CheckboxSetting extends StatelessWidget {
  const CheckboxSetting({
    Key? key,
    required this.notifier,
    required this.title,
    this.description,
    this.tooltip,
    this.onChanged,
    this.enabled = true,
    this.gaScreenName,
    this.gaItem,
    this.checkboxKey,
  }) : super(key: key);

  final ValueNotifier<bool?> notifier;

  final String title;

  final String? description;

  final String? tooltip;

  final void Function(bool? newValue)? onChanged;

  /// Whether this checkbox setting should be enabled for interaction.
  final bool enabled;

  final String? gaScreenName;

  final String? gaItem;

  final Key? checkboxKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget textContent = RichText(
      overflow: TextOverflow.visible,
      text: TextSpan(
        text: title,
        style: enabled ? theme.regularTextStyle : theme.subtleTextStyle,
      ),
    );

    if (description != null) {
      textContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          textContent,
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                text: ' • $description',
                style: theme.subtleTextStyle,
              ),
            ),
          ),
        ],
      );
    }
    final content = Row(
      children: [
        NotifierCheckbox(
          notifier: notifier,
          onChanged: (bool? value) {
            final gaScreenName = this.gaScreenName;
            final gaItem = this.gaItem;
            if (gaScreenName != null && gaItem != null) {
              ga.select(gaScreenName, gaItem);
            }
            final onChanged = this.onChanged;
            if (onChanged != null) {
              onChanged(value);
            }
          },
          enabled: enabled,
          checkboxKey: checkboxKey,
        ),
        Flexible(
          child: textContent,
        ),
      ],
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return DevToolsTooltip(
        message: tooltip,
        child: content,
      );
    }
    return content;
  }
}

class PubWarningText extends StatelessWidget {
  const PubWarningText({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFlutterApp = serviceManager.connectedApp!.isFlutterAppNow == true;
    final sdkName = isFlutterApp ? 'Flutter' : 'Dart';
    final minSdkVersion = isFlutterApp ? '2.8.0' : '2.15.0';
    return SelectableText.rich(
      TextSpan(
        text: 'Warning: you should no longer be launching DevTools from'
            ' pub.\n\n',
        style: theme.subtleTextStyle
            .copyWith(color: theme.colorScheme.errorTextColor),
        children: [
          TextSpan(
            text: 'DevTools version 2.8.0 will be the last version to '
                'be shipped on pub. As of $sdkName\nversion >= '
                '$minSdkVersion, DevTools should be launched by running '
                'the ',
            style: theme.subtleTextStyle,
          ),
          TextSpan(
            text: '`dart devtools`',
            style: theme.subtleFixedFontStyle,
          ),
          TextSpan(
            text: '\ncommand.',
            style: theme.subtleTextStyle,
          ),
        ],
      ),
    );
  }
}

class BlinkingIcon extends StatefulWidget {
  const BlinkingIcon({
    Key? key,
    required this.icon,
    required this.color,
    required this.size,
  }) : super(key: key);

  final IconData icon;

  final Color color;

  final double size;

  @override
  _BlinkingIconState createState() => _BlinkingIconState();
}

class _BlinkingIconState extends State<BlinkingIcon> {
  late Timer timer;

  late bool showFirst;

  @override
  void initState() {
    super.initState();
    showFirst = true;
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        showFirst = !showFirst;
      });
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(seconds: 1),
      firstChild: _icon(),
      secondChild: _icon(color: widget.color),
      crossFadeState:
          showFirst ? CrossFadeState.showFirst : CrossFadeState.showSecond,
    );
  }

  Widget _icon({Color? color}) {
    return Icon(
      widget.icon,
      size: widget.size,
      color: color,
    );
  }
}

// TODO(https://github.com/flutter/devtools/issues/2989): investigate if we can
// modify this widget to be a 'MultiValueListenableBuilder' that can take an
// arbitrary number of listenables.
/// A widget that listens for changes to two different [ValueListenable]s and
/// rebuilds for change notifications to either.
///
/// This widget is preferred over nesting two [ValueListenableBuilder]s in a
/// single build method.
class DualValueListenableBuilder<T, U> extends StatefulWidget {
  const DualValueListenableBuilder({
    Key? key,
    required this.firstListenable,
    required this.secondListenable,
    required this.builder,
    this.child,
  }) : super(key: key);

  final ValueListenable<T> firstListenable;

  final ValueListenable<U> secondListenable;

  final Widget Function(
    BuildContext context,
    T firstValue,
    U secondValue,
    Widget? child,
  ) builder;

  final Widget? child;

  @override
  _DualValueListenableBuilderState createState() =>
      _DualValueListenableBuilderState<T, U>();
}

class _DualValueListenableBuilderState<T, U>
    extends State<DualValueListenableBuilder<T, U>> with AutoDisposeMixin {
  @override
  void initState() {
    super.initState();
    addAutoDisposeListener(widget.firstListenable);
    addAutoDisposeListener(widget.secondListenable);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      widget.firstListenable.value,
      widget.secondListenable.value,
      widget.child,
    );
  }
}

class SmallCircularProgressIndicator extends StatelessWidget {
  const SmallCircularProgressIndicator({
    Key? key,
    required this.valueColor,
  }) : super(key: key);

  final Animation<Color?> valueColor;

  @override
  Widget build(BuildContext context) {
    return CircularProgressIndicator(
      strokeWidth: 2,
      valueColor: valueColor,
    );
  }
}

class ElevatedCard extends StatelessWidget {
  const ElevatedCard({
    Key? key,
    required this.child,
    this.width,
    this.height,
    this.padding,
  }) : super(key: key);

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: defaultElevation,
      color: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(defaultBorderRadius),
      ),
      child: Container(
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.all(denseSpacing),
        child: child,
      ),
    );
  }
}

/// A convenience wrapper for a [StatefulWidget] that uses the
/// [AutomaticKeepAliveClientMixin] on its [State].
///
/// Wrap a widget in this class if you want [child] to stay alive, and avoid
/// rebuilding. This is useful for children of [TabView]s. When wrapped in this
/// wrapper, [child] will not be destroyed and rebuilt when switching tabs.
///
/// See [AutomaticKeepAliveClientMixin] for more information.
class KeepAliveWrapper extends StatefulWidget {
  const KeepAliveWrapper({Key? key, required this.child}) : super(key: key);

  final Widget child;

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool wantKeepAlive = true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Help button, that opens a dialog on click.
class HelpButtonWithDialog extends StatelessWidget {
  const HelpButtonWithDialog({
    required this.gaScreen,
    required this.gaSelection,
    required this.dialogTitle,
    required this.child,
  });

  final String gaScreen;

  final String gaSelection;

  final String dialogTitle;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HelpButton(
      onPressed: () {
        ga.select(gaScreen, gaSelection);
        unawaited(
          showDialog(
            context: context,
            builder: (context) => DevToolsDialog(
              title: DialogTitleText(dialogTitle),
              includeDivider: false,
              content: child,
              actions: const [
                DialogCloseButton(),
              ],
            ),
          ),
        );
      },
      gaScreen: gaScreen,
      gaSelection: gaSelection,
    );
  }
}

/// Display a single bullet character in order to act as a stylized spacer
/// component.
class BulletSpacer extends StatelessWidget {
  const BulletSpacer({this.useAccentColor = false});

  final bool useAccentColor;

  static double get width => actionWidgetSize / 2;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    late TextStyle? textStyle;
    textStyle = useAccentColor
        ? theme.appBarTheme.toolbarTextStyle ??
            theme.primaryTextTheme.bodyMedium
        : theme.textTheme.bodyMedium;

    final mutedColor = textStyle?.color?.withAlpha(0x90);

    return Container(
      width: width,
      height: actionWidgetSize,
      alignment: Alignment.center,
      child: Text(
        '•',
        style: textStyle?.copyWith(color: mutedColor),
      ),
    );
  }
}

class ToCsvButton extends StatelessWidget {
  const ToCsvButton({
    Key? key,
    this.onPressed,
    this.tooltip = 'Download data in CSV format',
    required this.minScreenWidthForTextBeforeScaling,
  }) : super(key: key);

  final VoidCallback? onPressed;
  final String? tooltip;
  final double minScreenWidthForTextBeforeScaling;

  @override
  Widget build(BuildContext context) {
    return IconLabelButton(
      label: 'CSV',
      icon: Icons.file_download,
      tooltip: tooltip,
      onPressed: onPressed,
      minScreenWidthForTextBeforeScaling: minScreenWidthForTextBeforeScaling,
    );
  }
}

class RadioButton<T> extends StatelessWidget {
  const RadioButton({
    super.key,
    required this.label,
    required this.itemValue,
    required this.groupValue,
    this.onChanged,
    this.radioKey,
  });

  final String label;
  final T itemValue;
  final T groupValue;
  final void Function(T?)? onChanged;
  final Key? radioKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Radio<T>(
          value: itemValue,
          groupValue: groupValue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
          key: radioKey,
        ),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class ContextMenuButton extends StatelessWidget {
  const ContextMenuButton({
    this.style,
    this.gaScreen,
    this.gaItem,
    required this.menu,
  });

  static const double width = 14;

  final TextStyle? style;
  final String? gaScreen;
  final String? gaItem;
  final List<Widget> menu;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: menu,
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
        return SizedBox(
          width: width,
          child: TextButton(
            child: Text('⋮', style: style, textAlign: TextAlign.center),
            onPressed: () {
              if (gaScreen != null && gaItem != null) {
                ga.select(gaScreen!, gaItem!);
              }
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          ),
        );
      },
    );
  }
}
