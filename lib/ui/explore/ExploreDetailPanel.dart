/*
 * Copyright 2020 Board of Trustees of the University of Illinois.
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
import 'package:geolocator/geolocator.dart';
import 'package:illinois/model/Analytics.dart';
import 'package:illinois/model/Laundry.dart';
import 'package:illinois/model/MTD.dart';
import 'package:illinois/model/StudentCourse.dart';
import 'package:illinois/model/sport/Game.dart';
import 'package:illinois/model/Appointment.dart';
import 'package:illinois/ui/academics/StudentCourses.dart';
import 'package:illinois/ui/athletics/AthleticsGameDetailPanel.dart';
import 'package:illinois/ui/explore/ExploreBuildingDetailPanel.dart';
import 'package:illinois/ui/laundry/LaundryRoomDetailPanel.dart';
import 'package:illinois/ui/mtd/MTDStopDeparturesPanel.dart';
import 'package:illinois/ui/appointments/AppointmentDetailPanel.dart';
import 'package:illinois/ui/explore/ExploreDiningDetailPanel.dart';

import 'package:rokwire_plugin/model/explore.dart';
import 'package:illinois/model/Dining.dart';
import 'package:illinois/ui/widgets/HeaderBar.dart';
import 'package:illinois/ext/Explore.dart';
import 'package:rokwire_plugin/model/group.dart';

class ExploreDetailPanel extends StatelessWidget with AnalyticsInfo {
  final Explore? explore;
  final Position? initialLocationData;
  final AnalyticsFeature? _analyticsFeature;
  final Group? browseGroup;

  ExploreDetailPanel({this.explore, this.initialLocationData, this.browseGroup, AnalyticsFeature? analyticsFeature}) :
    _analyticsFeature = analyticsFeature;

  static Widget? contentPanel({Explore? explore, Position? initialLocationData, AnalyticsFeature? analyticsFeature, Group? browseGroup}) {
    if (explore is Dining) {
      return ExploreDiningDetailPanel(dining: explore, initialLocationData: initialLocationData, analyticsFeature: analyticsFeature);
    }
    else if (explore is LaundryRoom) {
      return LaundryRoomDetailPanel(room: explore, analyticsFeature: analyticsFeature);
    }
    else if (explore is Game) {
      return AthleticsGameDetailPanel(game: explore, analyticsFeature: analyticsFeature);
    }
    else if (explore is Building) {
      return ExploreBuildingDetailPanel(building: explore, analyticsFeature: analyticsFeature);
    }
    else if (explore is MTDStop) {
      return MTDStopDeparturesPanel(stop: explore, analyticsFeature: analyticsFeature);
    }
    else if (explore is StudentCourse) {
      return StudentCourseDetailPanel(course: explore, analyticsFeature: analyticsFeature);
    }
    else if (explore is Appointment) {
      return AppointmentDetailPanel(appointment: explore, analyticsFeature: analyticsFeature);
    }
    else { // Default for unexpected type
      return null;
    }
  }

  @override
  AnalyticsFeature? get analyticsFeature => _analyticsFeature ?? explore?.analyticsFeature;

  @override
  Map<String, dynamic>? get analyticsPageAttributes => explore?.analyticsAttributes;

  @override
  Widget build(BuildContext context) {
    return contentPanel(explore: explore, initialLocationData: initialLocationData, analyticsFeature: analyticsFeature, browseGroup: browseGroup) ?? Scaffold(
      appBar: HeaderBar(),
    );
  }
}