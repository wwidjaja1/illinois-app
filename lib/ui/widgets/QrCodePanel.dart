
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:illinois/service/Analytics.dart';
import 'package:illinois/service/Config.dart';
import 'package:illinois/service/NativeCommunicator.dart';
import 'package:illinois/ui/events2/Event2HomePanel.dart';
import 'package:illinois/ui/widgets/HeaderBar.dart';
import 'package:illinois/utils/AppUtils.dart';
import 'package:intl/intl.dart';
import 'package:rokwire_plugin/model/event2.dart';
import 'package:rokwire_plugin/model/group.dart';
import 'package:rokwire_plugin/service/events2.dart';
import 'package:rokwire_plugin/service/groups.dart';
import 'package:rokwire_plugin/service/localization.dart';
import 'package:rokwire_plugin/service/styles.dart';
import 'package:rokwire_plugin/ui/widgets/rounded_button.dart';
import 'package:rokwire_plugin/utils/image_utils.dart';
import 'package:rokwire_plugin/utils/utils.dart';
import 'package:share/share.dart';

class QrCodePanel extends StatefulWidget { //TBD localize
  //final Event2? event;
  //const Event2QrCodePanel({required this.event});

  final String deepLinkUrl;

  final String saveFileName;
  final String? saveWatermarkText;
  final TextStyle? saveWatermarkStyle;

  final String? title;
  final String? description;

  const QrCodePanel({Key? key,
    required this.deepLinkUrl,

    required this.saveFileName,
    this.saveWatermarkText,
    this.saveWatermarkStyle,

    this.title,
    this.description,
  });

  factory QrCodePanel.fromEvent(Event2? event, {Key? key}) => QrCodePanel(
    key: key,
    deepLinkUrl: Events2.eventDetailUrl(event),
      saveFileName: 'event - ${event?.name}',
      saveWatermarkText: event?.name,
      saveWatermarkStyle: TextStyle(fontFamily: Styles().fontFamilies.bold, fontSize: 64, color: Styles().colors.textSurface),
    title: Localization().getStringEx('panel.qr_code.event.title', 'Share this event'),
    description: Localization().getStringEx('panel.qr_code.event.description', 'Invite others to view this event by sharing a link or the QR code after saving it to your photo library.'),
  );

  factory QrCodePanel.fromEventFilterParam(Event2FilterParam filterParam, {Key? key}) => QrCodePanel(
    key: key,
    deepLinkUrl: Events2.eventsQueryUrl(filterParam.toUriParams()),
      saveFileName: "events ${DateFormat('yyyy-MM-dd HH.mm.ss').format(DateTime.now())}",
      saveWatermarkText: filterParam.buildDescription().map((span) => span.toPlainText()).join(),
      saveWatermarkStyle: TextStyle(fontFamily: Styles().fontFamilies.regular, fontSize: 32, color: Styles().colors.textSurface),
    title: Localization().getStringEx('panel.qr_code.event_query.title', 'Share this event set'),
    description: Localization().getStringEx('panel.qr_code.event_query.description', 'Invite others to view this set of filtered events by sharing a link or the QR code after saving it to your photo library.'),
  );

  factory QrCodePanel.fromGroup(Group? group, {Key? key}) => QrCodePanel(
    key: key,
    deepLinkUrl: '${Groups().groupDetailUrl}?group_id=${group?.id}',
      saveFileName: 'group - ${group?.title}',
      saveWatermarkText: group?.title,
      saveWatermarkStyle: TextStyle(fontFamily: Styles().fontFamilies.bold, fontSize: 64, color: Styles().colors.textSurface),
    title: Localization().getStringEx('panel.qr_code.group.title', 'Share this group'),
    description: Localization().getStringEx('panel.qr_code.group.description.label', 'Invite others to join this group by sharing a link or the QR code after saving it to your photo library.'),
  );

  factory QrCodePanel.skillsSelfEvaluation({Key? key}) => QrCodePanel(
    key: key,
    deepLinkUrl: 'TBD:_implement',//TBD: DD - implement
    saveFileName: 'skills self-evaluation',
    saveWatermarkText: 'Skills Self-Evaluation',
    saveWatermarkStyle: TextStyle(fontFamily: Styles().fontFamilies.bold, fontSize: 64, color: Styles().colors.textSurface),
    title: Localization().getStringEx('panel.qr_code.skills_self-evaluation.title', 'Share this feature'),
    description: Localization().getStringEx('panel.qr_code.skills_self-evaluation.description.label', 'Invite others to view this feature by sharing a link or the QR code after saving it to your photo library.'),
  );

  @override
  State<StatefulWidget> createState() => _QrCodePanelState();
}

class _QrCodePanelState extends State<QrCodePanel> {
  static final int _imageSize = 1024;
  Uint8List? _qrCodeBytes;

  @override
  void initState() {
    super.initState();
    _loadQrImageBytes().then((imageBytes) {
      setState(() {
        _qrCodeBytes = imageBytes;
      });
    });
  }

  Future<Uint8List?> _loadQrImageBytes() async {
    return await NativeCommunicator().getBarcodeImageData({
      'content': _promotionUrl,
      'format': 'qrCode',
      'width': _imageSize,
      'height': _imageSize,
    });
  }

  Future<void> _saveQrCode() async {
    Analytics().logSelect(target: "Save Event QR Code");

    if (_qrCodeBytes == null) {
      AppAlert.showDialogResult(context, Localization().getStringEx("panel.qr_code.alert.no_qr_code.msg", "There is no QR Code"));
    } else {
      Uint8List? updatedImageBytes = await ImageUtils.applyLabelOverImage(_qrCodeBytes, widget.saveWatermarkText,
        width: _imageSize.toDouble(),
        height: _imageSize.toDouble(),
        textStyle: widget.saveWatermarkStyle,
      );
      bool result = (updatedImageBytes != null);
      if (result) {
        result = await ImageUtils.saveToFs(updatedImageBytes, widget.saveFileName) ?? false;
      }

      const String destinationMacro = '{{Destination}}';
      String messageSource = (result
          ? (Localization().getStringEx("panel.qr_code.alert.save.success.msg", "Successfully saved qr code in $destinationMacro"))
          : Localization().getStringEx("panel.qr_code.alert.save.fail.msg", "Failed to save qr code in $destinationMacro"));
      String destinationTargetText = (defaultTargetPlatform == TargetPlatform.android)
          ? Localization().getStringEx("panel.qr_code.alert.save.success.pictures", "Pictures")
          : Localization().getStringEx("panel.qr_code.alert.save.success.gallery", "Gallery");
      String message = messageSource.replaceAll(destinationMacro, destinationTargetText);
      AppAlert.showDialogResult(context, message).then((value) {
        if(result) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HeaderBar(
        title: widget.title,
        textAlign: TextAlign.center,
      ),
      body: SingleChildScrollView(
        child: Container(
          color: Styles().colors.background,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                    widget.description ?? '',
                    style: Styles().textStyles.getTextStyle("widget.title.regular.fat")
                ),
                Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: ((_qrCodeBytes != null)
                      ? Semantics(
                    label: Localization().getStringEx('panel.qr_code.code.hint', "QR code image"),
                    child: Container(
                      decoration: BoxDecoration(color: Styles().colors.white, borderRadius: BorderRadius.all(Radius.circular(5))),
                      padding: EdgeInsets.all(5),
                      child: Image.memory(
                        _qrCodeBytes!,
                        fit: BoxFit.fitWidth,
                        semanticLabel: Localization().getStringEx("panel.qr_code.primary.heading.title", "Promotion Key"),
                      ),
                    ),
                  )
                      : Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width - 10,
                    child: Align(
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color?>(Styles().colors.fillColorSecondary),
                        strokeWidth: 2,
                      ),
                    ),
                  )),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 12),
                  child: RoundedButton(
                    label: Localization().getStringEx('panel.qr_code.button.save.title', 'Save QR Code'),
                    hint: '',
                    textStyle: Styles().textStyles.getTextStyle("widget.title.regular.fat"),
                    backgroundColor: Styles().colors.background,
                    borderColor: Styles().colors.fillColorSecondary,
                    onTap: _onTapSave,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: RoundedButton(
                    label: Localization().getStringEx('panel.qr_code.button.share.title', 'Share Link'),
                    hint: '',
                    textStyle: Styles().textStyles.getTextStyle("widget.button.title.medium.fat"),
                    backgroundColor: Styles().colors.background,
                    borderColor: Styles().colors.fillColorSecondary,
                    onTap: _onTapShare,
                  ),
                )
              ],
            ),
          ),
        ),
      ),
      backgroundColor: Styles().colors.background,
    );
  }

  void _onTapSave() {
    Analytics().logSelect(target: 'Save Event Qr Code');
    _saveQrCode();
  }

  void _onTapShare() {
    Analytics().logSelect(target: 'Share Event Qr Code');
    Share.share(_promotionUrl);
  }

  String get _promotionUrl {
    String? redirectUrl = Config().deepLinkRedirectUrl;
    return ((redirectUrl != null) && redirectUrl.isNotEmpty) ? UrlUtils.buildWithQueryParameters(redirectUrl, <String, String>{
      'target': widget.deepLinkUrl
    }) : widget.deepLinkUrl;
  }
}