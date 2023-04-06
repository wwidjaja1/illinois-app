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

import 'package:flutter/material.dart';
import 'package:illinois/model/wellness/Appointment.dart';
import 'package:illinois/ui/widgets/HeaderBar.dart';
import 'package:rokwire_plugin/service/localization.dart';
import 'package:rokwire_plugin/service/styles.dart';
import 'package:illinois/ui/widgets/TabBar.dart' as uiuc;

class AppointmentSchedulePanel extends StatefulWidget {

  final AppointmentScheduleParam scheduleParam;

  AppointmentSchedulePanel({ Key? key, required this.scheduleParam }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AppointmentSchedulePanelState();
}

class _AppointmentSchedulePanelState extends State<AppointmentSchedulePanel> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HeaderBar(title: Localization().getStringEx('panel.appointment.schedule.header.title', 'Schedule Appointment')),
      body: Container(),
      backgroundColor: Styles().colors!.background,
      bottomNavigationBar: uiuc.TabBar()
    );
  }
}

class AppointmentScheduleParam {
  final List<AppointmentProvider>? providers;
  final AppointmentProvider? provider;

  final List<AppointmentUnit>? units;
  final AppointmentUnit? unit;

  final AppointmentTimeSlot? timeSlot;

  AppointmentScheduleParam({
    this.providers, this.provider,
    this.units, this.unit,
    this.timeSlot,
  });

  factory AppointmentScheduleParam.fromOther(AppointmentScheduleParam? other, {
    List<AppointmentProvider>? providers,
    AppointmentProvider? provider,

    List<AppointmentUnit>? units,
    AppointmentUnit? unit,

    AppointmentTimeSlot? timeSlot,
  }) => AppointmentScheduleParam(
    providers: other?.providers ?? providers,
    provider: other?.provider ?? provider,

    units: other?.units ?? units,
    unit: other?.unit ?? unit,

    timeSlot: other?.timeSlot ?? timeSlot
  );

}