// Copyright 2024 Board of Trustees of the University of Illinois.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:illinois/model/Assistant.dart';
import 'package:illinois/service/Assistant.dart';
import 'package:illinois/service/Auth2.dart';
import 'package:illinois/service/FirebaseMessaging.dart';
import 'package:illinois/service/FlexUI.dart';
import 'package:illinois/service/IlliniCash.dart';
import 'package:illinois/service/SpeechToText.dart';
import 'package:illinois/ui/widgets/AccessWidgets.dart';
import 'package:illinois/ui/widgets/TypingIndicator.dart';
import 'package:illinois/utils/AppUtils.dart';
import 'package:rokwire_plugin/model/auth2.dart';
import 'package:rokwire_plugin/service/localization.dart';
import 'package:rokwire_plugin/service/notification_service.dart';
import 'package:rokwire_plugin/service/styles.dart';
import 'package:rokwire_plugin/ui/widgets/rounded_button.dart';
import 'package:rokwire_plugin/utils/utils.dart';

class AssistantConversationContentWidget extends StatefulWidget {
  final Stream shouldClearAllMessages;
  AssistantConversationContentWidget({required this.shouldClearAllMessages});

  @override
  State<AssistantConversationContentWidget> createState() => _AssistantConversationContentWidgetState();
}

class _AssistantConversationContentWidgetState extends State<AssistantConversationContentWidget>
    with AutomaticKeepAliveClientMixin<AssistantConversationContentWidget>
    implements NotificationsListener {
  static final String resourceName = 'assistant';

  List<String>? _contentCodes;
  TextEditingController _inputController = TextEditingController();
  ScrollController _scrollController = ScrollController();
  final GlobalKey _chatBarKey = GlobalKey();

  bool _listening = false;

  List<Message> _messages = [];

  bool _loadingResponse = false;
  Message? _feedbackMessage;

  int? _queryLimit = 5;

  Map<String, String>? _userContext;

  late StreamSubscription _streamSubscription;

  @override
  void initState() {
    super.initState();
    NotificationService().subscribe(this, [
      FlexUI.notifyChanged,
      Auth2UserPrefs.notifyFavoritesChanged,
      Localization.notifyStringsUpdated,
      Styles.notifyChanged,
      SpeechToText.notifyError,
    ]);

    _streamSubscription = widget.shouldClearAllMessages.listen((event) {
      _clearAllMessages();
    });

    _initDefaultMessages();

    _contentCodes = buildContentCodes();

    _onPullToRefresh();

    _userContext = _getUserContext();

  }

  @override
  void dispose() {
    NotificationService().unsubscribe(this);
    _inputController.dispose();
    _streamSubscription.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(AssistantConversationContentWidget old) {
    super.didUpdateWidget(old);
    // in case the stream instance changed, subscribe to the new one
    if (widget.shouldClearAllMessages != old.shouldClearAllMessages) {
      _streamSubscription.cancel();
      _streamSubscription = widget.shouldClearAllMessages.listen((_) => _clearAllMessages);
    }
  }

  // AutomaticKeepAliveClientMixin
  @override
  bool get wantKeepAlive => true;

  // NotificationsListener
  @override
  void onNotification(String name, dynamic param) {
    if (name == FlexUI.notifyChanged) {
      _updateContentCodes();
      setStateIfMounted((){});
    } else if ((name == Auth2UserPrefs.notifyFavoritesChanged) ||
        (name == Localization.notifyStringsUpdated) ||
        (name == Styles.notifyChanged)) {
      setStateIfMounted((){});
    } else if (name == SpeechToText.notifyError) {
      setState(() {
        _listening = false;
      });
    }
  }

  // Public APIs

  void _clearAllMessages() {
    setStateIfMounted(() {
      _initDefaultMessages();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Widget? accessWidget = AccessCard.builder(resource: resourceName);

    return accessWidget != null
        ? Column(children: [Padding(padding: EdgeInsets.only(top: 16.0), child: accessWidget)])
        : Positioned.fill(
            child: Stack(children: [
            Padding(padding: EdgeInsets.only(bottom: _chatBarHeight), child: RefreshIndicator(
                onRefresh: _onPullToRefresh,
                child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    controller: _scrollController,
                    child: Padding(padding: EdgeInsets.all(16), child: Column(children: _buildContentList()))))),
            Positioned(bottom: MediaQuery.of(context).viewInsets.bottom, left: 0, right: 0, child: _buildChatBar())
          ]));
  }

  List<Widget> _buildContentList() {
    List<Widget> contentList = <Widget>[];

    for (Message message in _messages) {
      contentList.add(_buildChatBubble(message));
      contentList.add(SizedBox(height: 16.0));
    }

    if (_loadingResponse) {
      contentList.add(_buildTypingChatBubble());
      contentList.add(SizedBox(height: 16.0));
    }

    return contentList;
  }

  Widget _buildChatBubble(Message message) {
    EdgeInsets bubblePadding = message.user ? EdgeInsets.only(left: 100.0) : EdgeInsets.only(right: 100);
    String answer = message.isAnswerUnknown
        ? Localization()
            .getStringEx('panel.assistant.unknown.answer.value', "I wasn’t able to find an answer from an official university source.")
        : message.content;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: bubblePadding,
          child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: message.user ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Flexible(
                    child: Opacity(
                        opacity: message.example ? 0.5 : 1.0,
                        child: Material(
                            color: message.user
                                ? message.example
                                    ? Styles().colors.background
                                    : Styles().colors.blueAccent
                                : Styles().colors.white,
                            borderRadius: BorderRadius.circular(16.0),
                            child: InkWell(
                                onTap: message.example
                                    ? () {
                                        _messages.remove(message);
                                        _submitMessage(message.content);
                                      }
                                    : null,
                                child: Container(
                                    decoration: message.example
                                        ? BoxDecoration(
                                            borderRadius: BorderRadius.circular(16.0),
                                            border: Border.all(color: Styles().colors.fillColorPrimary))
                                        : null,
                                    child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          message.example
                                              ? Text(
                                                  Localization().getStringEx('panel.assistant.label.example.eg.title', "eg. ") +
                                                      message.content,
                                                  style: message.user
                                                      ? Styles().textStyles.getTextStyle('widget.title.regular')
                                                      : Styles().textStyles.getTextStyle('widget.title.light.regular'))
                                              : SelectableText(answer,
                                                  style: message.user
                                                      ? Styles().textStyles.getTextStyle('widget.dialog.message.medium.thin')
                                                      : Styles().textStyles.getTextStyle('widget.message.regular')),
                                          _buildNegativeFeedbackFormWidget(message),
                                          _buildFeedbackResponseDisclaimer(message)
                                        ])))))))
              ])),
      _buildFeedbackAndSourcesExpandedWidget(message)
    ]);
  }

  Widget _buildFeedbackAndSourcesExpandedWidget(Message message) {
    final double feedbackIconSize = 24;
    bool feedbackControlsVisible = (message.acceptsFeedback && !message.isAnswerUnknown);
    bool additionalControlsVisible = !message.user && (_messages.indexOf(message) != 0);
    bool areSourcesLabelsVisible = additionalControlsVisible && ((CollectionUtils.isNotEmpty(message.sources) || CollectionUtils.isNotEmpty(message.links)));
    bool areSourcesValuesVisible = (additionalControlsVisible && areSourcesLabelsVisible && (message.sourcesExpanded == true));
    List<Link>? deepLinks = message.links;
    List<Widget> webLinkWidgets = _buildWebLinkWidgets(message.sources);

    return Visibility(
        visible: additionalControlsVisible,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Visibility(
                visible: feedbackControlsVisible,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      onPressed: message.feedbackExplanation == null
                          ? () {
                              _sendFeedback(message, true);
                            }
                          : null,
                      icon: Icon(message.feedback == MessageFeedback.good ? Icons.thumb_up : Icons.thumb_up_outlined,
                          size: feedbackIconSize,
                          color:
                              message.feedbackExplanation == null ? Styles().colors.fillColorPrimary : Styles().colors.disabledTextColor),
                      iconSize: feedbackIconSize,
                      splashRadius: feedbackIconSize),
                  IconButton(
                      onPressed: message.feedbackExplanation == null
                          ? () {
                              _sendFeedback(message, false);
                            }
                          : null,
                      icon: Icon(message.feedback == MessageFeedback.bad ? Icons.thumb_down : Icons.thumb_down_outlined,
                          size: feedbackIconSize, color: Styles().colors.fillColorPrimary),
                      iconSize: feedbackIconSize,
                      splashRadius: feedbackIconSize)
                ])),
            Visibility(
                visible: areSourcesLabelsVisible,
                child: Padding(padding: EdgeInsets.only(top: (!message.acceptsFeedback ? 10 : 0), left: (!message.acceptsFeedback ? 5 : 0)), child: InkWell(
                    onTap: () => _onTapSourcesAndLinksLabel(message),
                    splashColor: Colors.transparent,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Text(Localization().getStringEx('panel.assistant.sources_links.label', 'Sources and Links'),
                          style: Styles().textStyles.getTextStyle('widget.message.small')),
                      Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: Styles().images.getImage(areSourcesValuesVisible ? 'chevron-up-dark-blue' : 'chevron-down-dark-blue') ??
                              Container())
                    ]))))
          ]),
          Visibility(
              visible: areSourcesValuesVisible,
              child: Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Visibility(
                        visible: CollectionUtils.isNotEmpty(webLinkWidgets),
                        child: Padding(
                            padding: EdgeInsets.only(top: 15),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: webLinkWidgets))),
                    Visibility(
                        visible: CollectionUtils.isNotEmpty(deepLinks),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                              padding: EdgeInsets.only(top: 15, bottom: 5),
                              child: Text(Localization().getStringEx('panel.assistant.related.label', 'Related:'),
                                  style: Styles().textStyles.getTextStyle('widget.title.small.semi_fat'))),
                          _buildDeepLinkWidgets(deepLinks)
                        ]))
                  ])))
        ]));
  }

  void _onTapSourcesAndLinksLabel(Message message) {
    setStateIfMounted(() {
      message.sourcesExpanded = !(message.sourcesExpanded ?? false);
    });
  }

  Widget _buildNegativeFeedbackFormWidget(Message message) {
    bool isNegativeFeedbackForm = (message.feedbackResponseType == FeedbackResponseType.negative);
    return Visibility(visible: isNegativeFeedbackForm, child: Text('Request submit negative feedback'));
  }

  Widget _buildFeedbackResponseDisclaimer(Message message) {
    bool isSystemFeedbackMessage = (message.feedbackResponseType != null);
    return Visibility(
        visible: isSystemFeedbackMessage,
        child: Padding(padding: EdgeInsets.only(top: 10), child: Text(
            Localization().getStringEx('panel.assistant.feedback.disclaimer.description',
                'Your input on this response is anonymous and will be reviewed to improve the quality of the Illinois Assistant.'),
            style: Styles().textStyles.getTextStyle('widget.assistant.bubble.feedback.disclaimer.description.thin'))));
  }

  void _sendFeedback(Message message, bool good) {
    if (message.feedbackExplanation != null) {
      return;
    }

    bool bad = false;

    setState(() {
      if (good) {
        if (message.feedback == MessageFeedback.good) {
          message.feedback = null;
        } else {
          message.feedback = MessageFeedback.good;
          _messages.add(Message(
              content: Localization().getStringEx(
                  'panel.assistant.label.feedback.disclaimer.prompt.title',
                  'Thank you for providing feedback!'),
              user: false, feedbackResponseType: FeedbackResponseType.positive));
        }
      } else {
        if (message.feedback == MessageFeedback.bad) {
          message.feedback = null;
        } else {
          message.feedback = MessageFeedback.bad;
          _messages.add(Message(
              content: Localization().getStringEx(
                  'panel.assistant.label.feedback.negative.prompt.title',
                  "Thank you for providing feedback! Could you please explain "
                      "the issue with my response?"),
              user: false));
          _feedbackMessage = message;
          bad = true;
        }
      }
    });

    if (!bad && _feedbackMessage != null) {
      _messages.removeLast();
      _feedbackMessage = null;
    }

    Assistant().sendFeedback(message);
  }

  Widget _buildTypingChatBubble() {
    return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
            width: 100,
            height: 50,
            child: Material(
                color: Styles().colors.blueAccent,
                borderRadius: BorderRadius.circular(16.0),
                child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TypingIndicator(
                        flashingCircleBrightColor: Styles().colors.surface, flashingCircleDarkColor: Styles().colors.blueAccent)))));
  }

  List<Widget> _buildWebLinkWidgets(List<String> sources) {
    List<Widget> sourceLinks = [];
    for (String source in sources) {
      Uri? uri = Uri.tryParse(source);
      if ((uri != null) && uri.host.isNotEmpty) {
        sourceLinks.add(_buildWebLinkWidget(source));
      }
    }
    return sourceLinks;
  }

  Widget _buildWebLinkWidget(String source) {
    Uri? uri = Uri.tryParse(source);
    return Padding(
        padding: EdgeInsets.only(bottom: 8, right: 140),
        child: Material(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22), side: BorderSide(color: Styles().colors.fillColorSecondary, width: 1)),
            color: Styles().colors.white,
            child: InkWell(
                onTap: () => _onTapSourceLink(source),
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Padding(padding: EdgeInsets.only(right: 8), child: Styles().images.getImage('external-link')),
                      Expanded(
                          child: Text(StringUtils.ensureNotEmpty(uri?.host),
                              overflow: TextOverflow.ellipsis,
                              style: Styles().textStyles.getTextStyle('widget.button.link.source.title.semi_fat')))
                    ])))));
  }

  Widget _buildDeepLinkWidgets(List<Link>? links) {
    List<Widget> linkWidgets = [];
    for (Link link in links ?? []) {
      if (linkWidgets.isNotEmpty) {
        linkWidgets.add(SizedBox(height: 8.0));
      }
      linkWidgets.add(_buildDeepLinkWidget(link));
    }
    return Column(children: linkWidgets);
  }

  Widget _buildDeepLinkWidget(Link? link) {
    if (link == null) {
      return Container();
    }
    EdgeInsets padding = const EdgeInsets.only(right: 160.0);
    return Padding(
        padding: padding,
        child: Material(
            color: Styles().colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10), side: BorderSide(color: Styles().colors.mediumGray2, width: 1)),
            child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () {
                  NotificationService().notify('${FirebaseMessaging.notifyBase}.${link.link}', link.params);
                },
                child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(children: [
                      Visibility(
                          visible: (link.iconKey != null),
                          child: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Styles().images.getImage(link.iconKey ?? '') ?? Container())),
                      Expanded(child: Text(link.name, style: Styles().textStyles.getTextStyle('widget.message.small.semi_fat'))),
                      Styles().images.getImage('chevron-right') ?? Container()
                    ])))));
  }

  Widget _buildChatBar() {
    bool enabled = _feedbackMessage != null || _queryLimit == null || _queryLimit! > 0;
    return Material(
      key: _chatBarKey,
        color: Styles().colors.surface,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Row(mainAxisSize: MainAxisSize.max, children: [
                Expanded(
                    child: Container(
                        decoration: BoxDecoration(
                            border: Border.all(color: Styles().colors.surfaceAccent), borderRadius: BorderRadius.circular(12.0)),
                        child: Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Stack(children: [
                              Padding(padding: EdgeInsets.only(right: 28), child: TextField(
                                  enabled: enabled,
                                  controller: _inputController,
                                  minLines: 1,
                                  maxLines: 3,
                                  textCapitalization: TextCapitalization.sentences,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: _submitMessage,
                                  onChanged: (_) => setStateIfMounted((){}),
                                  decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: _feedbackMessage == null
                                          ? enabled
                                          ? null
                                          : Localization().getStringEx('panel.assistant.label.queries.limit.title',
                                          'Sorry you are out of questions for today. Please check back tomorrow to ask more questions!')
                                          : Localization()
                                          .getStringEx('panel.assistant.field.feedback.title', 'Type your feedback here...')),
                                  style: Styles().textStyles.getTextStyle('widget.title.regular'))),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(padding: EdgeInsets.only(right: 0), child: _buildSendImage(enabled)))
                            ]))))
              ])),
              _buildQueryLimit(),
              Visibility(visible: Auth2().isDebugManager && FlexUI().hasFeature('assistant_personalization'), child: _buildContextButton())
            ])));
  }

  Widget _buildSendImage(bool enabled) {
    if (StringUtils.isNotEmpty(_inputController.text)) {
      return IconButton(
        //TODO: Enable support for material icons in styles images
          splashRadius: 24,
          icon: Icon(Icons.send, color: enabled ? Styles().colors.fillColorSecondary : Styles().colors.disabledTextColor),
          onPressed: enabled
              ? () {
            _submitMessage(_inputController.text);
          }
              : null);
    } else {
      return Visibility(
          visible: enabled && SpeechToText().isEnabled,
          child: IconButton(
            //TODO: Enable support for material icons in styles images
              splashRadius: 24,
              icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic, color: Styles().colors.fillColorSecondary),
              onPressed: enabled
                  ? () {
                if (_listening) {
                  _stopListening();
                } else {
                  _startListening();
                }
              }
                  : null));
    }
  }

  Widget _buildQueryLimit() {
    if (_queryLimit == null) {
      return Container();
    }
    return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                    color: (_queryLimit ?? 0) > 0
                        ? Styles().colors.saferLocationWaitTimeColorGreen
                        : Styles().colors.saferLocationWaitTimeColorRed,
                    shape: BoxShape.circle)),
            SizedBox(width: 8),
            Text(
                Localization()
                    .getStringEx('panel.assistant.label.queries.remaining.title', "{{query_limit}} questions remaining today")
                    .replaceAll('{{query_limit}}', _queryLimit.toString()),
                style: Styles().textStyles.getTextStyle('widget.title.small'))
          ]),
          Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                  Localization().getStringEx('panel.assistant.inaccurate.description.disclaimer',
                      'The Illinois Assistant may display inaccurate information.\nPlease double-check its responses.'),
                  style: Styles().textStyles.getTextStyle('widget.info.tiny'),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 5))
        ]));
  }

  Widget _buildContextButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: RoundedButton(
        label: Localization().getStringEx('panel.assistant.button.context.title', 'Context'),
        onTap: _showContext,
      ),
    );
  }

  Future<void> _showContext() {
    List<String> userContextKeys = _userContext?.keys.toList() ?? [];
    List<String> userContextVals = _userContext?.values.toList() ?? [];
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setStateForDialog) {
          List<Widget> contextFields = [];
          for (int i = 0; i < userContextKeys.length; i++) {
            String key = userContextKeys[i];
            String val = userContextVals[i]; // TextEditingController controller = TextEditingController();
            // controller.text = context;
            contextFields.add(Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: TextFormField(
                      initialValue: key,
                      onChanged: (value) {
                        userContextKeys[i] = value;
                      }),
                ),
                SizedBox(width: 8.0),
                Expanded(
                  child: TextFormField(
                      initialValue: val,
                      onChanged: (value) {
                        userContextVals[i] = value;
                      }),
                ),
              ],
            ));
          }
          return AlertDialog(
            title: Text(Localization().getStringEx('panel.assistant.dialog.context.title', 'User Context')),
            content: SingleChildScrollView(
              child: ListBody(
                children: contextFields,
              ),
            ),
            actions: [
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: RoundedButton(
                      label: Localization().getStringEx('panel.assistant.dialog.context.button.add.title', 'Add'),
                      onTap: () {
                        setStateForDialog(() {
                          userContextKeys.add('');
                          userContextVals.add('');
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 8.0,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: RoundedButton(
                        label: Localization().getStringEx('panel.assistant.dialog.context.button.default.title', 'Default'),
                        onTap: () {
                          _userContext = _getUserContext();
                          Navigator.of(context).pop();
                          _showContext();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: RoundedButton(
                        label: Localization().getStringEx('panel.assistant.dialog.context.button.profile1.title', 'Profile 1'),
                        onTap: () {
                          _userContext = _getUserContext(
                              name: 'John Doe', netID: 'jdoe', college: 'Media', department: 'Journalism', studentLevel: 'Sophomore');
                          Navigator.of(context).pop();
                          _showContext();
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 8.0,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: RoundedButton(
                        label: Localization().getStringEx('panel.assistant.dialog.context.button.profile2.title', 'Profile 2'),
                        onTap: () {
                          _userContext = _getUserContext(
                              name: 'Jane Smith',
                              netID: 'jsmith',
                              college: 'Grainger Engineering',
                              department: 'Electrical and Computer Engineering',
                              studentLevel: 'Senior');
                          Navigator.of(context).pop();
                          _showContext();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: RoundedButton(
                  label: Localization().getStringEx('panel.assistant.dialog.context.button.save.title', 'Save'),
                  onTap: () {
                    _userContext = {};
                    for (int i = 0; i < userContextKeys.length; i++) {
                      String key = userContextKeys[i];
                      String val = userContextVals[i];
                      if (key.isNotEmpty && val.isNotEmpty) {
                        _userContext?[key] = val;
                      }
                    }
                    if (_userContext?.isEmpty ?? false) {
                      _userContext = null;
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _submitMessage(String message) async {
    FocusScope.of(context).requestFocus(FocusNode());
    if (_loadingResponse) {
      return;
    }

    setState(() {
      if (message.isNotEmpty) {
        _messages.add(Message(content: message, user: true));
      }
      _inputController.text = '';
      _loadingResponse = true;
    });

    if (_feedbackMessage != null) {
      _feedbackMessage?.feedbackExplanation = message;
      Message? response = await Assistant().sendFeedback(_feedbackMessage!);
      setState(() {
        if (response != null) {
          _messages.add(response);
        } else {
          _messages.add(Message(
              content: Localization().getStringEx(
                  'panel.assistant.label.feedback.thank_you.title',
                  'Thank you for the explanation! '
                      'Your response has been recorded and will be used to improve results in the future.'),
              user: false));
        }
        _loadingResponse = false;
      });
      _feedbackMessage = null;
      return;
    }

    int? limit = _queryLimit;
    if (limit != null && limit <= 0) {
      setState(() {
        _messages.add(Message(
            content: Localization().getStringEx(
                'panel.assistant.label.queries.limit.title',
                'Sorry you are out of questions for today. '
                    'Please check back tomorrow to ask more questions!'),
            user: false));
      });
      return;
    }

    _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: Duration(seconds: 1),
      curve: Curves.fastOutSlowIn,
    );

    Map<String, String>? userContext = FlexUI().hasFeature('assistant_personalization') ? _userContext : null;

    Message? response = await Assistant().sendQuery(message, context: userContext);
    if (mounted) {
      setState(() {
        if (response != null) {
          _messages.add(response);
          if (_queryLimit != null) {
            if (response.queryLimit != null) {
              _queryLimit = response.queryLimit;
            } else {
              _queryLimit = _queryLimit! - 1;
            }
          }
        } else {
          _messages.add(Message(
              content: Localization()
                  .getStringEx('panel.assistant.label.error.title', 'Sorry, something went wrong. For the best results, please restart the app and try your question again.'),
              user: false));
          _inputController.text = message;
        }
        _loadingResponse = false;
      });
    }
  }

  Map<String, String>? _getUserContext({String? name, String? netID, String? college, String? department, String? studentLevel}) {
    Map<String, String> context = {};

    college ??= IlliniCash().studentClassification?.collegeName;
    department ??= IlliniCash().studentClassification?.departmentName;
    if (college != null && department != null) {
      context['college'] = college;
      context['department'] = department;
    }

    studentLevel ??= IlliniCash().studentClassification?.studentLevelDescription;
    if (studentLevel != null) {
      context['level'] = studentLevel;
    }

    return context.isNotEmpty ? context : null;
  }

  void _onTapSourceLink(String source) {
    UrlUtils.launchExternal(source);
  }

  void _startListening() {
    SpeechToText().listen(onResult: _onSpeechResult);
    setState(() {
      _listening = true;
    });
  }

  void _stopListening() async {
    await SpeechToText().stopListening();
    setState(() {
      _listening = false;
    });
  }

  void _onSpeechResult(String result, bool finalResult) {
    setState(() {
      _inputController.text = result;
      if (finalResult) {
        _listening = false;
      }
    });
  }

  void _updateContentCodes() {
    List<String>? contentCodes = buildContentCodes();
    if ((contentCodes != null) && !DeepCollectionEquality().equals(_contentCodes, contentCodes)) {
      if (mounted) {
        setState(() {
          _contentCodes = contentCodes;
        });
      } else {
        _contentCodes = contentCodes;
      }
    }
  }

  Future<void> _onPullToRefresh() async {
    Assistant().getQueryLimit().then((limit) {
      if (limit != null) {
        setStateIfMounted(() {
          _queryLimit = limit;
        });
      }
    });
  }

  void _initDefaultMessages() {
    if (CollectionUtils.isNotEmpty(_messages)) {
      _messages.clear();
    }
    _messages.add(Message(
        content: Localization().getStringEx('panel.assistant.label.welcome_message.title',
            'The Illinois Assistant is a search feature that brings official university resources to your fingertips. Ask a question below to get started.'),
        user: false));
  }

  double get _chatBarHeight {
    RenderObject? chatBarRenderBox = _chatBarKey.currentContext?.findRenderObject();
    double? chatBarHeight = (chatBarRenderBox is RenderBox) ? chatBarRenderBox.size.height : null;
    return chatBarHeight ?? 0;
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
