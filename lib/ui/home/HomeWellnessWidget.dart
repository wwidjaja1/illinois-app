import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:illinois/model/wellness/ToDo.dart';
import 'package:illinois/model/wellness/WellnessRing.dart';
import 'package:illinois/service/Analytics.dart';
import 'package:illinois/service/DeepLink.dart';
import 'package:illinois/service/Transportation.dart';
import 'package:illinois/service/Wellness.dart';
import 'package:illinois/service/WellnessRings.dart';
import 'package:illinois/ui/WebPanel.dart';
import 'package:illinois/ui/home/HomePanel.dart';
import 'package:illinois/ui/home/HomeWidgets.dart';
import 'package:illinois/ui/wellness/WellnessHomePanel.dart';
import 'package:illinois/ui/wellness/rings/WellnessRingWidgets.dart';
import 'package:illinois/ui/wellness/todo/WellnessToDoItemDetailPanel.dart';
import 'package:illinois/ui/widgets/FavoriteButton.dart';
import 'package:illinois/ui/widgets/LinkButton.dart';
import 'package:illinois/utils/AppUtils.dart';
import 'package:rokwire_plugin/service/localization.dart';
import 'package:rokwire_plugin/service/notification_service.dart';
import 'package:rokwire_plugin/service/styles.dart';
import 'package:rokwire_plugin/ui/widgets/rounded_button.dart';
import 'package:rokwire_plugin/utils/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeWellnessWidget extends StatefulWidget {
  
  final String? favoriteId;
  final StreamController<String>? updateController;

  HomeWellnessWidget({Key? key, this.favoriteId, this.updateController}) : super(key: key);

  static Widget handle({String? favoriteId, HomeDragAndDropHost? dragAndDropHost, int? position}) =>
    HomeHandleWidget(favoriteId: favoriteId, dragAndDropHost: dragAndDropHost, position: position,
      title: title,
    );

  static String get title => Localization().getStringEx('widget.home.wellness.label.title', 'Wellness');

  @override
  State<HomeWellnessWidget> createState() => _HomeWellnessWidgetState();
}

class _HomeWellnessWidgetState extends HomeCompoundWidgetState<HomeWellnessWidget> {

  //_HomeWellnessWidgetState() : super(direction: Axis.horizontal);

  @override String? get favoriteId => widget.favoriteId;
  @override String? get title => HomeWellnessWidget.title;
  @override String? get emptyMessage => Localization().getStringEx("widget.home.wellness.text.empty.description", "Tap the \u2606 on items in Wellness so you can quickly find them here.");

  @override
  Widget? widgetFromCode(String code) {
    if (code == 'todo') {
      return HomeToDoWellnessWidget(favorite: HomeFavorite(code, category: widget.favoriteId), updateController: widget.updateController,);
    }
    else if (code == 'rings') {
      return HomeRingsWellnessWidget(favorite: HomeFavorite(code, category: widget.favoriteId), updateController: widget.updateController,);
    }
    else if (code == 'tips') {
      return HomeDailyTipsWellnessWidget(favorite: HomeFavorite(code, category: widget.favoriteId), updateController: widget.updateController,);
    }
    else {
      return null;
    }
  }
}

// HomeToDoWellnessWidget

class HomeToDoWellnessWidget extends StatefulWidget {
  final HomeFavorite? favorite;
  final StreamController<String>? updateController;

  HomeToDoWellnessWidget({Key? key, this.favorite, this.updateController}) : super(key: key);

  @override
  State<HomeToDoWellnessWidget> createState() => _HomeToDoWellnessWidgetState();
}

class _HomeToDoWellnessWidgetState extends State<HomeToDoWellnessWidget> implements NotificationsListener {
  List<ToDoItem>? _toDoItems;
  bool _loading = false;

  @override
  void initState() {
    NotificationService().subscribe(this, [
      Wellness.notifyToDoItemCreated,
      Wellness.notifyToDoItemUpdated,
      Wellness.notifyToDoItemsDeleted,
    ]);
    _loadToDoItems();
    super.initState();
  }

  @override
  void dispose() {
    NotificationService().unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(child:
      Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color.fromRGBO(19, 41, 75, 0.3), spreadRadius: 2.0, blurRadius: 8.0, offset: Offset(0, 2))]), child:
        ClipRRect(borderRadius: BorderRadius.all(Radius.circular(6)), child:
          Row(children: <Widget>[
            Expanded(child:
              Column(children: <Widget>[
                Container(color: Styles().colors!.backgroundVariant, child:
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child:
                      Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child:
                        Text(Localization().getStringEx('widget.home.wellness.todo.title', 'MY TO-DO LIST'), style: TextStyle(color: Styles().colors!.fillColorPrimary, fontFamily: Styles().fontFamilies!.bold, fontSize: 14))),
                      ),
                    HomeFavoriteButton(favorite: widget.favorite, style: FavoriteIconStyle.Button, padding: EdgeInsets.all(12), prompt: true)
                  ])
                ),
                Container(color: Styles().colors!.backgroundVariant, height: 1,),
                Container(color: Styles().colors!.white, child:
                  Padding(padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8), child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Expanded(child: Text(Localization().getStringEx('widget.home.wellness.todo.items.today.label', 'TODAY\'S ITEMS'), textAlign: TextAlign.start, overflow: TextOverflow.ellipsis, style: TextStyle(color: Styles().colors!.fillColorSecondary, fontSize: 12, fontFamily: Styles().fontFamilies!.bold)))]),
                      Stack(alignment: Alignment.center, children: [
                        Visibility(visible: !_loading, child: _buildTodayItemsWidget()),
                        _buildLoadingIndicator()
                      ]),
                      Padding(padding: EdgeInsets.only(top: 15), child: Row(children: [Expanded(child: Text(Localization().getStringEx('widget.home.wellness.todo.items.unassigned.label', 'UNASSIGNED ITEMS'), textAlign: TextAlign.start, overflow: TextOverflow.ellipsis, style: TextStyle(color: Styles().colors!.fillColorSecondary, fontSize: 12, fontFamily: Styles().fontFamilies!.bold)))])),
                      Stack(alignment: Alignment.center, children: [
                        Visibility(visible: !_loading, child: _buildUnAssignedItemsWidget()),
                        _buildLoadingIndicator()
                      ]),
                      Padding(padding: EdgeInsets.only(top: 20), child: Row(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        RoundedButton(
                          label: Localization().getStringEx('widget.home.wellness.todo.items.add.button', 'Add Item'), borderColor: Styles().colors!.fillColorSecondary,
                          textColor: Styles().colors!.fillColorPrimary,
                          leftIcon: Image.asset('images/icon-add-14x14.png', color: Styles().colors!.fillColorPrimary),
                          iconPadding: 8, rightIconPadding: EdgeInsets.only(right: 8), fontSize: 14, contentWeight: 0, 
                          fontFamily: Styles().fontFamilies!.regular, padding: EdgeInsets.zero, onTap: _onTapAddItem),
                        LinkButton(
                          title: Localization().getStringEx('widget.home.wellness.todo.items.view_all.label', 'View All'),
                          hint: Localization().getStringEx('widget.home.wellness.todo.items.view_all.hint', 'Tap to view all To Do items'),
                          fontSize: 14,
                          onTap: _onTapViewAll,
                        ),
                      ]))
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Visibility(visible: _loading, child: SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Styles().colors!.fillColorSecondary, strokeWidth: 2)));
  }

  Widget _buildTodayItemsWidget() {
    List<ToDoItem>? todayItems = _buildTodayItems();
    List<Widget> widgetList = <Widget>[];
    if (CollectionUtils.isNotEmpty(todayItems)) {
      for (ToDoItem item in todayItems!) {
        widgetList.add(_buildToDoItemWidget(item));
      }
    } else {
      widgetList.add(Text(Localization().getStringEx('widget.home.wellness.todo.items.today.empty.msg', 'You have no to-do items for today.'), style: TextStyle(color: Styles().colors!.textSurface, fontSize: 14, fontFamily: Styles().fontFamilies!.regular)));
    }
    return Padding(padding: EdgeInsets.only(top: 2), child: Column(children: widgetList));
  }

  Widget _buildUnAssignedItemsWidget() {
    List<ToDoItem>? unAssignedItems = _buildUnAssignedItems();
    List<Widget> widgetList = <Widget>[];
    if (CollectionUtils.isNotEmpty(unAssignedItems)) {
      for (ToDoItem item in unAssignedItems!) {
        widgetList.add(_buildToDoItemWidget(item));
      }
    } else {
      widgetList.add(Text(Localization().getStringEx('widget.home.wellness.todo.items.unassigned.empty.msg', 'You have no unassigned to-do items.'), style: TextStyle(color: Styles().colors!.textSurface, fontSize: 14, fontFamily: Styles().fontFamilies!.regular)));
    }
    return Padding(padding: EdgeInsets.only(top: 2), child: Column(children: widgetList));
  }

  Widget _buildToDoItemWidget(ToDoItem item) {
    final double completedWidgetSize = 20;
    Widget completedWidget = item.isCompleted ? Image.asset('images/example.png', color: Styles().colors!.textSurface, height: completedWidgetSize, width: completedWidgetSize, fit: BoxFit.fill) : Container(
            decoration: BoxDecoration(color: Colors.transparent, shape: BoxShape.circle, border: Border.all(color: Styles().colors!.textSurface!, width: 1)), height: completedWidgetSize, width: completedWidgetSize);
    return GestureDetector(onTap: () => _onTapToDoItem(item), child: Padding(padding: EdgeInsets.only(top: 10), child: Container(color: Colors.transparent, child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
      Padding(padding: EdgeInsets.only(right: 10), child: completedWidget),
      Expanded(child: Text(StringUtils.ensureNotEmpty(item.name), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.start, style: TextStyle(color: Styles().colors!.textSurface, fontSize: 14, fontFamily: Styles().fontFamilies!.regular)))
    ]))));
  }

  void _onTapToDoItem(ToDoItem item) {
    Analytics().logWellnessToDo(
      action: item.isCompleted ? Analytics.LogWellnessActionUncomplete : Analytics.LogWellnessActionComplete,
      source: widget.runtimeType.toString(),
      item: item);
    item.isCompleted = !item.isCompleted;
    Wellness().updateToDoItem(item).then((success) {
      if (!success) {
        AppAlert.showDialogResult(context, Localization().getStringEx('widget.home.wellness.todo.items.completed.failed.msg', 'Failed to update To-Do item.'));
      }
    });
  }

  void _onTapAddItem() {
    Analytics().logSelect(target: "Add Item", source: widget.runtimeType.toString());
    Navigator.push(context, CupertinoPageRoute(builder: (context) => WellnessToDoItemDetailPanel()));
  }

  void _onTapViewAll() {
    Analytics().logSelect(target: "View All", source: widget.runtimeType.toString());
    Navigator.push(context, CupertinoPageRoute(builder: (context) => WellnessHomePanel(content: WellnessContent.todo)));
  }

  void _loadToDoItems() {
    _setLoading(true);
    Wellness().loadToDoItems().then((items) {
      _toDoItems = items;
      _setLoading(false);
    });
  }

  void _refreshItems() {
    Wellness().loadToDoItems().then((items) {
      _toDoItems = items;
      _updateState();
    });
  }

  void _setLoading(bool loading) {
    _loading = loading;
    _updateState();
  }

  void _updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  List<ToDoItem>? _buildTodayItems() {
    List<ToDoItem>? todayItems;
    if (CollectionUtils.isNotEmpty(_toDoItems)) {
      DateTime now = DateTime.now();
      todayItems = <ToDoItem>[];
      for (ToDoItem item in _toDoItems!) {
        DateTime? dueDate = item.dueDateTime;
        if (dueDate != null) {
          if ((dueDate.year == now.year) && (dueDate.month == now.month) && (dueDate.day == now.day)) {
            todayItems.add(item);
            if (todayItems.length == 3) { // return max 3 items
              break;
            }
          }
        }
      }
    }
    return todayItems;
  }

  List<ToDoItem>? _buildUnAssignedItems() {
    List<ToDoItem>? unAssignedItems;
    if (CollectionUtils.isNotEmpty(_toDoItems)) {
      unAssignedItems = <ToDoItem>[];
      for (ToDoItem item in _toDoItems!) {
        if (item.category == null) {
            unAssignedItems.add(item);
            if (unAssignedItems.length == 3) { // return max 3 items
              break;
            }
        }
      }
    }
    return unAssignedItems;
  }

  // NotificationsListener

  void onNotification(String name, dynamic param) {
    if (name == Wellness.notifyToDoItemCreated) {
      _refreshItems();
    } else if (name == Wellness.notifyToDoItemUpdated) {
      _refreshItems();
    } else if (name == Wellness.notifyToDoItemsDeleted) {
      _refreshItems();
    }
  }
}

// HomeRingsWellnessWidget

class HomeRingsWellnessWidget extends StatefulWidget {
  final HomeFavorite? favorite;
  final StreamController<String>? updateController;

  HomeRingsWellnessWidget({Key? key, this.favorite, this.updateController}) : super(key: key);

  @override
  State<HomeRingsWellnessWidget> createState() => _HomeRingsWellnessWidgetState();
}

class _HomeRingsWellnessWidgetState extends State<HomeRingsWellnessWidget> implements NotificationsListener {
  @override
  void initState() {
    NotificationService().subscribe(this, [
      WellnessRings.notifyUserRingsUpdated
    ]);
    WellnessRings().loadWellnessRings();
    super.initState();
  }

  @override
  void dispose() {
    NotificationService().unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return 
      Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color.fromRGBO(19, 41, 75, 0.3), spreadRadius: 2.0, blurRadius: 8.0, offset: Offset(0, 2))]), child:
        ClipRRect(borderRadius: BorderRadius.all(Radius.circular(6)), child:
          Row(children: <Widget>[
            Expanded(child:
              Column(children: <Widget>[
                Container(color: Styles().colors!.backgroundVariant, child:
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child:
                      Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child:
                        Text(Localization().getStringEx('widget.home.wellness.rings.title', 'DAILY WELLNESS RINGS'), style: TextStyle(color: Styles().colors!.fillColorPrimary, fontFamily: Styles().fontFamilies!.bold, fontSize: 14))),
                      ),
                    HomeFavoriteButton(favorite: widget.favorite, style: FavoriteIconStyle.Button, padding: EdgeInsets.all(12), prompt: true)
                  ])
                ),
                Container(color: Styles().colors!.backgroundVariant, height: 1,),
                Container(color: Styles().colors!.white, child:
                  Padding(padding: EdgeInsets.only(top: 20, right: 13, bottom: 0, left: 2), child:
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child:
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                            // Expanded( child:
                            Container(width: 13,),
                            Container(
                              child: WellnessRing(backgroundColor: Colors.white, size: 130, strokeSize: 15, borderWidth: 2,accomplishmentDialogEnabled: false,),
                            ),
                            // ),
                            Container(width: 18,),
                            Expanded(
                                child: Container(
                                    child: _buildButtons()
                                )
                            )
                          ],)
                          ),
                        ]),
                        LinkButton(
                          title: Localization().getStringEx('widget.home.wellness.rings.view_all.label', 'View All'),
                          hint: Localization().getStringEx('widget.home.wellness.rings.view_all.hint', 'Tap to view all rings'),
                          fontSize: 14,
                          onTap: _onTapViewAll,
                        ),
                      ],
                    )
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
  }

  Widget _buildButtons(){
    List<Widget> content = [];
    List<WellnessRingDefinition>? activeRings = WellnessRings().wellnessRings;
    if(activeRings?.isNotEmpty ?? false){
      for(WellnessRingDefinition data in activeRings!) {
        content.add(SmallWellnessRingButton(
            label: data.name!,
            description: "${WellnessRings().getRingDailyValue(data.id).toInt()}/${data.goal.toInt()}",
            color: data.color,
            onTapWidget: (context)  =>  _onTapIncrease(data)
        ));
        content.add(Container(height: 5,));
      }
    }

    return Container(child:Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content,
    ));
  }

  void _onTapViewAll(){
    Analytics().logSelect(target: "View All", source: widget.runtimeType.toString());
    Navigator.push(context, CupertinoPageRoute(builder: (context) => WellnessHomePanel(content: WellnessContent.rings)));
  }

  Future<void> _onTapIncrease(WellnessRingDefinition data) async{
    Analytics().logWellnessRing(
      action: Analytics.LogWellnessActionComplete,
      source: widget.runtimeType.toString(),
      item: data,
    );
    await WellnessRings().addRecord(WellnessRingRecord(value: 1, dateCreatedUtc: DateTime.now(), wellnessRingId: data.id));
  }
  // NotificationsListener

  void onNotification(String name, dynamic param) {
    if(name == WellnessRings.notifyUserRingsUpdated){
      if(mounted){
        setState(() {});
      }
    }
  }
}

// HomeDailyTipsWellnessWidget

class HomeDailyTipsWellnessWidget extends StatefulWidget {
  final HomeFavorite? favorite;
  final StreamController<String>? updateController;

  HomeDailyTipsWellnessWidget({Key? key, this.favorite, this.updateController}) : super(key: key);

  @override
  State<HomeDailyTipsWellnessWidget> createState() => _HomeDailyTipsWellnessWidgetState();
}

class _HomeDailyTipsWellnessWidgetState extends State<HomeDailyTipsWellnessWidget> implements NotificationsListener {

  Color? _tipColor;
  bool _loadingTipColor = false;
  
  @override
  void initState() {
    NotificationService().subscribe(this, [
      Wellness.notifyDailyTipChanged,
    ]);

    if (widget.updateController != null) {
      widget.updateController!.stream.listen((String command) {
        if (command == HomePanel.notifyRefresh) {
          if (mounted) {
            setState(() {
              _loadingTipColor = true;
            });

            Wellness().refreshDailyTip();

            Transportation().loadAlternateColor().then((Color? activeColor) {
              Wellness().refreshDailyTip();
              if (mounted) {
                setState(() {
                  if (activeColor != null) {
                    _tipColor = activeColor;
                  }
                  _loadingTipColor = false;
                });
              }
            });
          }
        }
      });
    }

    _loadingTipColor = true;
    Transportation().loadAlternateColor().then((Color? activeColor) {
      if (mounted) {
        setState(() {
          if (activeColor != null) {
            _tipColor = activeColor;
          }
          _loadingTipColor = false;
        });
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    NotificationService().unsubscribe(this);
    super.dispose();
  }

  // NotificationsListener

  void onNotification(String name, dynamic param) {
    if (name == Wellness.notifyDailyTipChanged) {
      _updateTipColor();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: _onTap, child:
      Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color.fromRGBO(19, 41, 75, 0.3), spreadRadius: 2.0, blurRadius: 8.0, offset: Offset(0, 2))]), child:
        ClipRRect(borderRadius: BorderRadius.all(Radius.circular(6)), child:
          Row(children: <Widget>[
            Expanded(child:
              Column(children: <Widget>[
                Container(color: Styles().colors!.backgroundVariant, child:
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child:
                      Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child:
                        Text(Localization().getStringEx('widget.home.wellness.tips.title', 'DAILY TIPS'), style: TextStyle(color: Styles().colors!.fillColorPrimary, fontFamily: Styles().fontFamilies!.bold, fontSize: 14))),
                      ),
                    HomeFavoriteButton(favorite: widget.favorite, style: FavoriteIconStyle.Button, padding: EdgeInsets.all(12), prompt: true)
                  ])
                ),
                Container(color: Styles().colors!.backgroundVariant, height: 1,),
                _loadingTipColor ? _buildLoading() : _buildTip()
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(color: Styles().colors?.white, child:
      Padding(padding: EdgeInsets.all(32), child:
        Row(children: <Widget>[
          Expanded(child:
            Center(child:
              SizedBox(height: 24, width: 24, child:
                CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color?>(_tipColor ?? Styles().colors?.fillColorSecondary), ),
              )
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTip() {
    Color? textColor = Styles().colors?.fillColorPrimary;
    Color? backColor = Styles().colors?.white; // _tipColor ?? Styles().colors?.accentColor3;
    return Container(color: backColor, child:
      Padding(padding: EdgeInsets.all(16), child:
        Row(children: <Widget>[
          Expanded(child:
            Html(data: Wellness().dailyTip ?? '',
              onLinkTap: (url, context, attributes, element) => _launchUrl(url),
              style: { "body": Style(color: textColor, fontFamily: Styles().fontFamilies?.bold, fontSize: FontSize(16), padding: EdgeInsets.zero, margin: EdgeInsets.zero), },
            ),
          ),
        ]),
      ),
    );
  }

  void _onTap() {
    Analytics().logSelect(target: "View", source: widget.runtimeType.toString());
    Navigator.push(context, CupertinoPageRoute(builder: (context) => WellnessHomePanel(content: WellnessContent.dailyTips,)));
  }

  void _updateTipColor() {
    Transportation().loadAlternateColor().then((Color? activeColor) {
      if (mounted) {
        setState(() {
          if (activeColor != null) {
            _tipColor = activeColor;
          }
        });
      }
    });
  }

  void _launchUrl(String? url) {
    if (StringUtils.isNotEmpty(url)) {
      if (DeepLink().isAppUrl(url)) {
        DeepLink().launchUrl(url);
      }
      else if (UrlUtils.launchInternal(url)){
        Navigator.push(context, CupertinoPageRoute(builder: (context) => WebPanel(url: url)));
      }
      else{
        launch(url!);
      }
    }
  }

}
