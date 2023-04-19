/*
 * Copyright 2022 Board of Trustees of the University of Illinois.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:illinois/model/wellness/Appointment.dart';
import 'package:illinois/service/Analytics.dart';
import 'package:illinois/ui/wellness/appointments/AppointmentSchedulePanel.dart';
import 'package:illinois/ui/widgets/HeaderBar.dart';
import 'package:illinois/utils/AppUtils.dart';
import 'package:rokwire_plugin/service/localization.dart';
import 'package:rokwire_plugin/service/styles.dart';
//import 'package:illinois/ui/widgets/TabBar.dart' as uiuc;
import 'package:rokwire_plugin/ui/widgets/rounded_button.dart';

class AppointmentScheduleQuesionsPanel extends StatefulWidget {
  final AppointmentScheduleParam scheduleParam;
  final Appointment? sourceAppointment;
  final void Function(BuildContext context, Appointment? appointment)? onFinish;

  AppointmentScheduleQuesionsPanel({Key? key, required this.scheduleParam, this.sourceAppointment, this.onFinish}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AppointmentScheduleQuestionsPanelState();
}

class _AppointmentScheduleQuestionsPanelState extends State<AppointmentScheduleQuesionsPanel> {

  final double _hPadding = 24;

  Map<String, LinkedHashSet<String>> _selection = <String, LinkedHashSet<String>>{};
  Map<String, TextEditingController> _textControllers = <String, TextEditingController>{};
  Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

  @override
  void initState() {
    _initSelection();
    super.initState();
  }

  void _initSelection() {
    List<AppointmentQuestion>? questions = widget.scheduleParam.questions;
    if (questions != null) {
      for (AppointmentQuestion question in questions) {
        String? questionId = question.id;
        if (questionId != null) {
          String? answer = question.answer;
          if (question.type == AppointmentQuestionType.edit) {
            _textControllers[questionId] = TextEditingController(text: answer);
            _focusNodes[questionId] = FocusNode();
          }

          List<String>? answers = (question.type == AppointmentQuestionType.multiList) ? answer?.split('\n') : null;
          if (answers != null) {
            _selection[questionId] = LinkedHashSet<String>.from(answers.reversed);
          }
          else if (answer != null) {
            _selection[questionId] = LinkedHashSet<String>.from(<String>[answer]);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    for (TextEditingController textController in _textControllers.values) {
      textController.dispose();
    }
    _textControllers.clear();

    for (FocusNode focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _focusNodes.clear();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HeaderBar(title: (widget.sourceAppointment == null) ?
        Localization().getStringEx('panel.appointment.schedule.time.header.title', 'Schedule Appointment') :
        Localization().getStringEx('panel.appointment.reschedule.time.header.title', 'Reschedule Appointment')
      ),
      body: _buildContent(),
      backgroundColor: Styles().colors!.background,
      //bottomNavigationBar: uiuc.TabBar()
    );
  }

  Widget _buildContent() {
    return Column(children: [
      Padding(padding: EdgeInsets.symmetric(vertical: 16, horizontal: _hPadding), child:
        Text(Localization().getStringEx('panel.appointment.schedule.quesions.label.heading', 'Appointment Quesions'),
          
          style: Styles().textStyles?.getTextStyle('widget.title.large.fat'),
        ),
      ),
      Expanded(child:
        SingleChildScrollView(child:
          Padding(padding: EdgeInsets.symmetric(vertical: 12), child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: _buildQuestions(),),
          )
        ),
      ),
      SafeArea(child:
        _buildCommandBar(),
      ),
    ],);
  }

  List<Widget> _buildQuestions() {
    List<Widget> contentList = <Widget>[];
    List<AppointmentQuestion>? questions = widget.scheduleParam.questions;
    if (questions != null) {
      for (int index = 0; index < questions.length; index++) {
        contentList.add(_buildQuestion(questions[index], index: index + 1));
      }
    }
    return contentList;
  }

  Widget _buildQuestion(AppointmentQuestion question, { int? index }) {
    List<Widget> contentList = <Widget>[];

    String title = _displayQuestionTitle(question, index: index);
    if (title.isNotEmpty) {
      contentList.add(Padding(padding: EdgeInsets.symmetric(horizontal: _hPadding), child:
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child:
            RichText(text:
              TextSpan(text: title, style: Styles().textStyles?.getTextStyle("widget.title.large.fat"),
                children: [
                  TextSpan(text: (question.required == true) ?  " *" : "", style: Styles().textStyles?.getTextStyle("widget.title.large.extra_fat"),
                )
              ],),
            ),
          )
        ])      
      ));
    }

    contentList.add(Padding(padding: EdgeInsets.only(top: title.isNotEmpty ? 8 : 0), child:
      _buildQuestionBody(question),
    ));

    contentList.add(Padding(padding: EdgeInsets.only(bottom: 16), child:
      Container()
    ));

    return Column(children: contentList,);
  }

  Widget _buildQuestionBody(AppointmentQuestion question) {
    if (question.type == AppointmentQuestionType.edit) {
      return _buildQuestionEdit(question);
    }
    else if (question.type == AppointmentQuestionType.list) {
      return _buildQuestionAnswersList(question);
    }
    else if (question.type == AppointmentQuestionType.multiList) {
      return _buildQuestionAnswersList(question);
    }
    else if (question.type == AppointmentQuestionType.checkbox) {
      return _buildQuestionCheckbox(question);
    }
    else {
      return Container();
    }
  }

  Widget _buildQuestionEdit(AppointmentQuestion question) {
    TextEditingController? textController = _textControllers[question.id];
    FocusNode? focusNode = _focusNodes[question.id];
    return Padding(padding: EdgeInsets.symmetric(horizontal: _hPadding), child:
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Styles().colors!.fillColorPrimary!, width: 1),
          color: Styles().colors!.white),
        child: Semantics(textField: true, excludeSemantics: true, value: textController?.text,
          label: Localization().getStringEx('panel.appointment.schedule.notes.field', 'NOTES FIELD'),
          hint: Localization().getStringEx('panel.appointment.schedule.notes.field.hint', ''),
          child: TextField(controller: textController, focusNode: focusNode, maxLines: 10,
            decoration: InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            style: Styles().textStyles?.getTextStyle('widget.item.regular.thin'),
            onChanged: (String value) => _onEditChanged(question, value),
          )
        ),
      ),
    );
  }

  void _onEditChanged(AppointmentQuestion question, String value) {
    String? questionId = question.id;
    if (questionId != null) {
      LinkedHashSet<String>? selection = _selection[questionId];
      bool wasEmpty = (selection == null) || selection.isEmpty || selection.first.isEmpty;
      bool isEmpty = value.isEmpty;
      if (wasEmpty != isEmpty) {
        setState(() {
          _selection[questionId] = LinkedHashSet.from(<String>[value]);
        });
      }
      else {
        _selection[questionId] = LinkedHashSet.from(<String>[value]);
      }
    }
  }

  Widget _buildQuestionAnswersList(AppointmentQuestion question) {
    List<Widget> answersList = <Widget>[];
    List<String>? answers = question.values;
    if (answers != null) {
      for (String answer in answers) {
        answersList.add(_buildQuestionAnswer(answer, question: question));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: answersList,);
  }

  Widget _buildQuestionAnswer(String answer, { required AppointmentQuestion question }) {
    LinkedHashSet<String>? selectedAnswers = _selection[question.id];
    bool selected = selectedAnswers?.contains(answer) ?? false;
    String semanticsValue = selected ? Localization().getStringEx("toggle_button.status.checked", "checked",) : Localization().getStringEx("toggle_button.status.unchecked", "unchecked");
    String imageKey = (question.type == AppointmentQuestionType.multiList) ?
      (selected ? "check-box-filled" : "box-outline-gray") :
      (selected ? "check-circle-filled" : "circle-outline");
    return Semantics(label: answer, value: semanticsValue, button: true, child:
      Padding(padding: EdgeInsets.only(left: _hPadding - 12, right: _hPadding), child:
        Row(children: [
          InkWell(onTap: (){ _onAnswer(answer, question: question); AppSemantics.announceCheckBoxStateChange(context,  /*reversed value*/!(selected == true), answer); }, child:
            Padding(padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8, ), child:
              Styles().images?.getImage(imageKey, excludeFromSemantics: true),
            ),
          ),
          Expanded(child:
            Padding(padding: EdgeInsets.only(top: 8, bottom: 8,), child:
              Text(answer, style: Styles().textStyles?.getTextStyle("widget.detail.regular"), textAlign: TextAlign.left,)
            ),
          ),
        ]),
      )
    );
}

  void _onAnswer(String answer, { required AppointmentQuestion question }) {

    Analytics().logSelect(target: '${question.title} => $answer');

    String? questionId = question.id;
    setState(() {
      LinkedHashSet<String>? selectedAnswers = (questionId != null) ? _selection[questionId] : null;
      if ((selectedAnswers != null) && selectedAnswers.contains(answer)) {
        selectedAnswers.remove(answer);
        if (selectedAnswers.isEmpty) {
          _selection.remove(questionId);
        }
      }
      else if (questionId != null) {
        selectedAnswers ??= (_selection[questionId] = LinkedHashSet<String>());
        if (question.type == AppointmentQuestionType.list) {
          selectedAnswers.clear();
        }
        selectedAnswers.add(answer);
      }
    });
  }

  Widget _buildQuestionCheckbox(AppointmentQuestion question) {
    bool? value;
    LinkedHashSet<String>? selectedAnswers = _selection[question.id];
    if ((selectedAnswers != null) && selectedAnswers.isNotEmpty) {
      if (selectedAnswers.first == true.toString()) {
        value = true;
      }
      else if (selectedAnswers.first == false.toString()) {
        value = false;
      }
    }

    String imageKey;
    switch (value) {
      case true:  imageKey = "check-box-filled"; break;
      case false: imageKey = "box-outline-gray"; break;
      default:    imageKey = "box-inside-light-gray"; break;
    }
    
    return Padding(padding: EdgeInsets.symmetric(horizontal: _hPadding), child:
      Container (
        decoration: BoxDecoration(
          color: Styles().colors!.white,
          border: Border.all(color: Styles().colors!.surfaceAccent!, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(4))
        ),
        //padding: const EdgeInsets.only(left: 12, right: 8),
        child: InkWell(onTap: () => _onCheckbox(question: question),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child:
              Padding(padding: EdgeInsets.only(left: 12, top: 16, bottom: 16), child:
                Text(question.title ?? '', style:
                  Styles().textStyles?.getTextStyle('widget.group.dropdown_button.value'),
                )
              ),
            ),
            Padding(padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16), child:
              Styles().images?.getImage(imageKey, excludeFromSemantics: true,) ?? Container(),
            ),
          ]),
        ),
      ),
    );
  }

  void _onCheckbox({ required AppointmentQuestion question }) {
    String? questionId = question.id;
    if (questionId != null) {
      bool? value;
      LinkedHashSet<String>? selectedAnswers = _selection[questionId];
      if ((selectedAnswers != null) && selectedAnswers.isNotEmpty) {
        if (selectedAnswers.first == true.toString()) {
          value = true;
        }
        else if (selectedAnswers.first == false.toString()) {
          value = false;
        }
      }
      // value = (value != true);
      if (value == null) {
        value = true;
      }
      else if (value == true) {
        value = false;
      }
      else {
        value = null;
      }
      setState(() {
        if (value != null)
          _selection[questionId] = LinkedHashSet<String>.from(<String>[value.toString()]);
        else
          _selection.remove(questionId);
      });
    }
  }

  String _displayQuestionTitle(AppointmentQuestion question, { int? index }) {
    if (question.type != AppointmentQuestionType.checkbox) {
      String title = question.title ?? '';
      return ((index != null) && title.isNotEmpty) ? "$index. $title" : title;
    }
    else {
      return '';
    }
  }

  Widget _buildCommandBar() {
    bool canContinue = _canContinue();
    return Padding(padding: EdgeInsets.all(16), child:
      Semantics(explicitChildNodes: true, child: 
        RoundedButton(
          label: Localization().getStringEx("panel.appointment.schedule.time.button.continue.title", "Next"),
          hint: Localization().getStringEx("panel.appointment.schedule.time.button.continue.hint", ""),
          backgroundColor: Styles().colors!.surface,
          textColor: canContinue ? Styles().colors!.fillColorPrimary : Styles().colors?.surfaceAccent,
          borderColor: canContinue ? Styles().colors!.fillColorSecondary : Styles().colors?.surfaceAccent,
          onTap: ()=> _onContinue(),
        ),
      ),
    );
  }

  bool _canContinue() => _invalidQuesion() == null;

  AppointmentQuestion? _invalidQuesion() {
    List<AppointmentQuestion>? questions = widget.scheduleParam.questions;
    if (questions != null) {
      for (AppointmentQuestion question in questions) {
        if (question.required == true) {
          LinkedHashSet<String>? selection = _selection[question.id];
          if ((selection == null) || selection.isEmpty || selection.first.isEmpty) {
            return question;
          }
        }
      }
    }
    return null;
  }

  List<AppointmentQuestion> get _answeredQuesions {
    List<AppointmentQuestion> result = <AppointmentQuestion>[];
    List<AppointmentQuestion>? questions = widget.scheduleParam.questions;
    if (questions != null) {
      for (AppointmentQuestion question in questions) {
        LinkedHashSet<String>? answersList = _selection[question.id];
        String? answer = ((answersList != null) && answersList.isNotEmpty) ?
          answersList.toList().join('\n') : null;
        result.add(AppointmentQuestion.fromOther(question, answer: answer));
      }
    }
    return result;
  }

  void _onContinue() {
    if (_canContinue()) {
      Navigator.push(context, CupertinoPageRoute(builder: (context) => AppointmentSchedulePanel(
        scheduleParam: AppointmentScheduleParam.fromOther(widget.scheduleParam, questions: _answeredQuesions),
        sourceAppointment: widget.sourceAppointment,
        onFinish: widget.onFinish,
      ),));
    }
    else {
      SystemSound.play(SystemSoundType.click);
    }
  }

}