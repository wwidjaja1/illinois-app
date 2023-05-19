import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:illinois/model/Assistant.dart';
import 'package:illinois/model/Dining.dart';
import 'package:illinois/model/Explore.dart';
import 'package:illinois/model/Laundry.dart';
import 'package:illinois/model/News.dart';
import 'package:illinois/model/Video.dart';
import 'package:illinois/model/sport/Game.dart';
import 'package:illinois/service/Analytics.dart';
import 'package:illinois/service/Auth2.dart';
import 'package:illinois/service/CheckList.dart';
import 'package:illinois/service/Config.dart';
import 'package:illinois/service/DeepLink.dart';
import 'package:illinois/service/FlexUI.dart';
import 'package:illinois/service/Guide.dart';
import 'package:illinois/service/Storage.dart';
import 'package:illinois/ui/SavedPanel.dart';
import 'package:illinois/ui/WebPanel.dart';
import 'package:illinois/ui/academics/AcademicsAppointmentsContentWidget.dart';
import 'package:illinois/ui/academics/AcademicsHomePanel.dart';
import 'package:illinois/ui/academics/StudentCourses.dart';
import 'package:illinois/ui/athletics/AthleticsHomePanel.dart';
import 'package:illinois/ui/athletics/AthleticsNewsListPanel.dart';
import 'package:illinois/ui/canvas/CanvasCoursesListPanel.dart';
import 'package:illinois/ui/explore/ExplorePanel.dart';
import 'package:illinois/ui/gies/CheckListPanel.dart';
import 'package:illinois/ui/groups/GroupsHomePanel.dart';
import 'package:illinois/ui/guide/CampusGuidePanel.dart';
import 'package:illinois/ui/guide/GuideListPanel.dart';
import 'package:illinois/ui/home/HomeCampusResourcesWidget.dart';
import 'package:illinois/ui/home/HomeDailyIlliniWidget.dart';
import 'package:illinois/ui/home/HomePanel.dart';
import 'package:illinois/ui/home/HomeRecentItemsWidget.dart';
import 'package:illinois/ui/home/HomeSaferTestLocationsPanel.dart';
import 'package:illinois/ui/home/HomeSaferWellnessAnswerCenterPanel.dart';
import 'package:illinois/ui/home/HomeTwitterWidget.dart';
import 'package:illinois/ui/home/HomeWPGUFMRadioWidget.dart';
import 'package:illinois/ui/home/HomeWidgets.dart';
import 'package:illinois/ui/laundry/LaundryHomePanel.dart';
import 'package:illinois/ui/mtd/MTDStopsHomePanel.dart';
import 'package:illinois/ui/parking/ParkingEventsPanel.dart';
import 'package:illinois/ui/polls/CreatePollPanel.dart';
import 'package:illinois/ui/polls/CreateStadiumPollPanel.dart';
import 'package:illinois/ui/polls/PollsHomePanel.dart';
import 'package:illinois/ui/research/ResearchProjectsHomePanel.dart';
import 'package:illinois/ui/settings/SettingsAddIlliniCashPanel.dart';
import 'package:illinois/ui/settings/SettingsIlliniCashPanel.dart';
import 'package:illinois/ui/settings/SettingsMealPlanPanel.dart';
import 'package:illinois/ui/settings/SettingsNotificationsContentPanel.dart';
import 'package:illinois/ui/settings/SettingsVideoTutorialListPanel.dart';
import 'package:illinois/ui/settings/SettingsVideoTutorialPanel.dart';
import 'package:illinois/ui/wallet/IDCardPanel.dart';
import 'package:illinois/ui/wallet/MTDBusPassPanel.dart';
import 'package:illinois/ui/wellness/WellnessHomePanel.dart';
import 'package:illinois/ui/widgets/FavoriteButton.dart';
import 'package:illinois/ui/widgets/HeaderBar.dart';
import 'package:illinois/utils/AppUtils.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:rokwire_plugin/model/auth2.dart';
import 'package:rokwire_plugin/model/event.dart';
import 'package:rokwire_plugin/service/app_livecycle.dart';
import 'package:rokwire_plugin/service/assets.dart';
import 'package:rokwire_plugin/service/connectivity.dart';
import 'package:rokwire_plugin/service/groups.dart';
import 'package:rokwire_plugin/service/localization.dart';
import 'package:rokwire_plugin/service/notification_service.dart';
import 'package:rokwire_plugin/service/styles.dart';
import 'package:rokwire_plugin/ui/panels/modal_image_holder.dart';
import 'package:rokwire_plugin/ui/widgets/triangle_painter.dart';
import 'package:rokwire_plugin/utils/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class AssistantPanel extends StatefulWidget {

  static const String notifyRefresh      = "edu.illinois.rokwire.assistant.refresh";

  AssistantPanel();

  @override
  _AssistantPanelState createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> with AutomaticKeepAliveClientMixin<AssistantPanel> implements NotificationsListener {

  List<String>? _contentCodes;
  StreamController<String> _updateController = StreamController.broadcast();
  TextEditingController _inputController = TextEditingController();

  List<Message> _messages = [];

  @override
  void initState() {
    NotificationService().subscribe(this, [
      FlexUI.notifyChanged,
      Auth2UserPrefs.notifyFavoritesChanged,
      Localization.notifyStringsUpdated,
      Styles.notifyChanged,
    ]);

    _messages.add(Message(content: Localization().getStringEx('',
        "Hey there! I'm the Illinois Assistant. "
            "You can ask me anything about the University. "
            "Type a question below to get started."),
        user: false));

    _messages.add(Message(content: Localization().getStringEx('',
        "Where can I find out more about the resources available on campus?"),
        user: true,
    ));

    _messages.add(Message(content: Localization().getStringEx('',
        "There are many resources available for students on campus. "
            "Try checking out the Campus Guide for more information."),
        user: false,
        link: Link(name: "Campus Guide", link: '${DeepLink().appUrl}/guide',
            iconKey: 'guide')));

    _messages.add(Message(content: Localization().getStringEx('',
        "What's for dinner at my dining hall today?"),
      user: true,
      example: true
    ));
    
    _contentCodes = buildContentCodes();
    super.initState();
  }

  @override
  void dispose() {
    NotificationService().unsubscribe(this);
    _updateController.close();
    super.dispose();
  }

  // AutomaticKeepAliveClientMixin
  @override
  bool get wantKeepAlive => true;


  // NotificationsListener
  @override
  void onNotification(String name, dynamic param) {
    if (name == FlexUI.notifyChanged) {
      _updateContentCodes();
      if (mounted) {
        setState(() { });
      }
    }
    else if((name == Auth2UserPrefs.notifyFavoritesChanged) ||
      (name == Localization.notifyStringsUpdated) ||
      (name == Styles.notifyChanged)) {
      if (mounted) {
        setState(() { });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: RootHeaderBar(title: Localization().getStringEx('panel.assistant.label.title', 'Assistant')),
      body: RefreshIndicator(onRefresh: _onPullToRefresh, child:
        Column(children: [
          _buildDisclaimer(),
          Expanded(child:
            SingleChildScrollView(reverse: true, child:
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(children: _buildContentList(),),
              )
            )
          ),
          _buildChatBar(),
        ]),
      ),
      backgroundColor: Styles().colors!.background,
      bottomNavigationBar: null,
    );
  }

  List<Widget> _buildContentList() {
    List<Widget> contentList = <Widget>[];

    for (Message message in _messages) {
      contentList.add(_buildChatBubble(message));
      contentList.add(SizedBox(height: 16.0));
    }

    return contentList;
  }

  Widget _buildDisclaimer() {
    return Container(
      color: Styles().colors?.fillColorPrimary,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Flexible(child: Text(Localization().getStringEx('',
            'This is an experimental feature which may present inaccurate results. '
                'Please verify all information with official University sources. '
                'Your input will be recorded to improve the quality of results.'),
          style: Styles().textStyles?.getTextStyle('widget.title.light.regular')
        )),
      ),
    );
  }

  Widget _buildChatBubble(Message message) {
    EdgeInsets bubblePadding = message.user ? const EdgeInsets.only(left: 32.0) :
      const EdgeInsets.only(right: 0);
    Link? link = message.link;
    return Align(
      alignment: message.user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: bubblePadding,
            child: Row(mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Opacity(
                    opacity: message.example ? 0.5 : 1.0,
                    child: Material(
                      color: message.user ? message.example ? Styles().colors?.background : Styles().colors?.surface : Styles().colors?.fillColorPrimary,
                      borderRadius: BorderRadius.circular(16.0),
                      child: InkWell(
                        onTap: message.example ? () {
                          setState(() {
                            _messages.remove(message);
                            _messages.add(Message(content: message.content, user: true));
                          });
                        } : null,
                        child: Container(
                          decoration: message.example ? BoxDecoration(borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(color: Styles().colors?.fillColorPrimary ?? Colors.black)) : null,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: message.example ?
                              Text(message.content,
                                  style: message.user ? Styles().textStyles?.getTextStyle('widget.title.regular') :
                                  Styles().textStyles?.getTextStyle('widget.title.light.regular'))
                              : SelectableText(message.content,
                              style: message.user ? Styles().textStyles?.getTextStyle('widget.title.regular') :
                                Styles().textStyles?.getTextStyle('widget.title.light.regular')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Visibility(
                  visible: !message.user,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.center,
                    children: [// TODO: Handle material icons in styles images
                      IconButton(onPressed: () {
                        setState(() {
                          if (message.feedback == MessageFeedback.good) {
                            message.feedback = null;
                          } else {
                            message.feedback = MessageFeedback.good;
                          }
                        });
                      },
                        icon: Icon(message.feedback == MessageFeedback.good ? Icons.thumb_up : Icons.thumb_up_outlined,
                            size: 24, color: Styles().colors?.fillColorPrimary),
                        iconSize: 24,
                        splashRadius: 24),
                      IconButton(onPressed: () {
                        setState(() {
                          if (message.feedback == MessageFeedback.bad) {
                            message.feedback = null;
                          } else {
                            message.feedback = MessageFeedback.bad;
                          }
                        });
                      },
                        icon: Icon(message.feedback == MessageFeedback.bad ? Icons.thumb_down :Icons.thumb_down_outlined,
                            size: 24, color: Styles().colors?.fillColorPrimary),
                        iconSize: 24,
                        splashRadius: 24),
                    ],
                  ),
                )
              ],
            ),
          ),
          Visibility(visible: link != null, child: Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 24.0, right: 32.0),
            child: _buildLinkWidget(link),
          ))
        ],
      ),
    );
  }

  Widget _buildLinkWidget(Link? link) {
    if (link == null) {
      return Container();
    }
    EdgeInsets padding = const EdgeInsets.only(right: 32.0);
    return Padding(
      padding: padding,
      child: Material(
        color: Styles().colors?.fillColorPrimary,
        borderRadius: BorderRadius.circular(8.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: () {
            if (DeepLink().isAppUrl(link.link)) {
              DeepLink().launchUrl(link.link);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Visibility(visible: link.iconKey != null, child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Styles().images?.getImage(link.iconKey ?? '') ?? Container(),
                )),
                Text(link.name, style: Styles().textStyles?.getTextStyle('widget.title.light.regular')),
                Expanded(child: Container()),
                Styles().images?.getImage('chevron-right-white') ?? Container(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatBar() {
    return Material(
      color: Styles().colors?.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Row(mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Material(
                color: Styles().colors?.background,
                borderRadius: BorderRadius.circular(16.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: Localization().getStringEx('', 'Type your question here...'),
                      ),
                      style: Styles().textStyles?.getTextStyle('widget.title.regular')
                    ),
                  ),
                ),
              ),
            ),
            IconButton(//TODO: Enable support for material icons in styles images
              splashRadius: 24,
              icon: Icon(Icons.send, color: Styles().colors?.fillColorSecondary),
              onPressed: () {
                setState(() {
                  String message = _inputController.text;
                  if (message.isNotEmpty) {
                    _messages.add(Message(content: message, user: true));
                  }
                  _inputController.text = '';
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _updateContentCodes() {
    List<String>?  contentCodes = buildContentCodes();
    if ((contentCodes != null) && !DeepCollectionEquality().equals(_contentCodes, contentCodes)) {
      if (mounted) {
        setState(() {
          _contentCodes = contentCodes;
        });
      }
      else {
        _contentCodes = contentCodes;
      }
    }
  }
  
  Future<void> _onPullToRefresh() async {
    _updateController.add(AssistantPanel.notifyRefresh);
    if (mounted) {
      setState(() {});
    }
  }

  static List<String>? buildContentCodes() {
    List<String>? codes = JsonUtils.listStringsValue(FlexUI()['assistant']);
    // codes?.sort((String code1, String code2) {
    //   String title1 = _BrowseSection.title(sectionId: code1);
    //   String title2 = _BrowseSection.title(sectionId: code2);
    //   return title1.toLowerCase().compareTo(title2.toLowerCase());
    // });
    return codes;
  }
}