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

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:illinois/model/wellness/Appointment.dart';
import 'package:illinois/service/Storage.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rokwire_plugin/service/app_livecycle.dart';
import 'package:rokwire_plugin/service/deep_link.dart';
import 'package:rokwire_plugin/service/log.dart';
import 'package:rokwire_plugin/service/network.dart';
import 'package:rokwire_plugin/service/notification_service.dart';
import 'package:rokwire_plugin/service/service.dart';
import 'package:rokwire_plugin/utils/utils.dart';
import 'package:illinois/service/Config.dart';
import 'package:http/http.dart' as http;
import 'package:illinois/service/Auth2.dart';
import 'package:uuid/uuid.dart';

enum AppointmentsTimeSource { upcoming, past }

class Appointments with Service implements NotificationsListener {
  static const String notifyAppointmentDetail = "edu.illinois.rokwire.appointments.detail";
  static const String notifyPastAppointmentsChanged = "edu.illinois.rokwire.appointments.past.changed";
  static const String notifyUpcomingAppointmentsChanged = "edu.illinois.rokwire.appointments.upcoming.changed";
  static const String notifyAppointmentsAccountChanged = "edu.illinois.rokwire.appointments.account.changed";
  
  static const String notifyAppointmentsChanged = "edu.illinois.rokwire.appointments.changed";

  static const String _appointmentRemindersNotificationsEnabledKey = 'edu.illinois.rokwire.settings.inbox.notification.appointments.reminders.notifications.enabled';
  
  DateTime? _pausedDateTime;
  late Directory _appDocDir;

  static const String _upcomingAppointmentsCacheDocName = "upcoming_appointments.json";
  static const String _pastAppointmentsCacheDocName = "past_appointments.json";
  static const String _accountCacheDocName = "appointments_account.json";
  
  List<Appointment>? _upcomingAppointments;
  List<Appointment>? _pastAppointments;
  AppointmentsAccount? _account;
  bool? _isLastAccountResponseSuccessful;

  List<Map<String, dynamic>>? _appointmentDetailsCache;

  // Singletone

  static final Appointments _service = Appointments._internal();
  factory Appointments() => _service;
  Appointments._internal();

  // Service

  @override
  void createService() {
    NotificationService().subscribe(this, [
      DeepLink.notifyUri,
      AppLivecycle.notifyStateChanged,
      Auth2.notifyLoginChanged
    ]);
    _appointmentDetailsCache = <Map<String, dynamic>>[];
    super.createService();
  }

  @override
  void destroyService() {
    NotificationService().unsubscribe(this);
    super.destroyService();
  }

  @override
  Future<void> initService() async {
    _appDocDir = await getApplicationDocumentsDirectory();

    await Future.wait([
      _initAppointments(timeSource: AppointmentsTimeSource.upcoming).then((appts) => _upcomingAppointments = appts),
      _initAppointments(timeSource: AppointmentsTimeSource.past).then((appts) => _pastAppointments = appts),
      _initAccount()
    ]);
    
    super.initService();
  }

  @override
  void initServiceUI() {
    _processCachedAppointmentDetails();
  }


  // NotificationsListener

  @override
  void onNotification(String name, dynamic param) {
    if (name == DeepLink.notifyUri) {
      _onDeepLinkUri(param);
    } else if (name == AppLivecycle.notifyStateChanged) {
      _onAppLivecycleStateChanged(param);
    } else if (name == Auth2.notifyLoginChanged) {
      _initAccount();
      _updateAllAppointments();
    }
  }

  void _onAppLivecycleStateChanged(AppLifecycleState? state) {
    if (state == AppLifecycleState.paused) {
      _pausedDateTime = DateTime.now();
    }
    else if (state == AppLifecycleState.resumed) {
      if (_pausedDateTime != null) {
        Duration pausedDuration = DateTime.now().difference(_pausedDateTime!);
        if (Config().refreshTimeout < pausedDuration.inSeconds) {
          _updateAccount();
          _updateAllAppointments();
        }
      }
    }
  }

  // Getters & Setters

  AppointmentsAccount? get account => _account;

  bool get isAccountValid => (account != null) && (_isLastAccountResponseSuccessful == true);

  bool get reminderNotificationsEnabled =>
      isAccountValid &&
      (Auth2().isLoggedIn) &&
      (Auth2().prefs?.getBoolSetting(_appointmentRemindersNotificationsEnabledKey, defaultValue: true) ?? true);

  set reminderNotificationsEnabled(bool value) {
    if (Auth2().isLoggedIn) {
      Auth2().prefs?.applySetting(_appointmentRemindersNotificationsEnabledKey, value);
    }
  }

  Future<Appointment?> loadAppointment(String? appointmentId) async {
    if (StringUtils.isNotEmpty(appointmentId) && StringUtils.isNotEmpty(Config().appointmentsUrl)) {
      if (StringUtils.isNotEmpty(Config().appointmentsUrl)) {
        String? url = "${Config().appointmentsUrl}/services/appointments?_ids=$appointmentId";
        http.Response? response = await Network().get(url, auth: Auth2());
        int? responseCode = response?.statusCode;
        String? responseString = response?.body;
        if (responseCode == 200) {
          return Appointment.listFromJson(JsonUtils.decodeList(responseString))?.first;
        } else {
          debugPrint('Failed to load appointment with id {$appointmentId}. Reason: $responseCode, $responseString');
          return null;
        }
      }
    }
    return null;
  }

  List<Appointment>? getAppointments({required AppointmentsTimeSource timeSource, AppointmentType? type}) {
    List<Appointment>? srcAppts;
    switch (timeSource) {
      case AppointmentsTimeSource.past:
        srcAppts = _pastAppointments;
        break;
      case AppointmentsTimeSource.upcoming:
        srcAppts = _upcomingAppointments;
        break;
    }
    if (CollectionUtils.isNotEmpty(srcAppts)) {
      if (type != null) {
        List<Appointment>? result = <Appointment>[];
        for (Appointment appt in srcAppts!) {
          if (type == appt.type) {
            result.add(appt);
          }
        }
        return result;
      }
    }
    return srcAppts;
  }

  Future<void> refreshAppointments() => _updateAllAppointments();

  File _getAppointmentsCacheFile({required AppointmentsTimeSource timeSource}) {
    late String docName;
    switch (timeSource) {
      case AppointmentsTimeSource.past:
        docName = _pastAppointmentsCacheDocName;
        break;
      case AppointmentsTimeSource.upcoming:
        docName = _upcomingAppointmentsCacheDocName;
        break;
    }
    return File(join(_appDocDir.path, docName));
  }

  Future<String?> _loadAppointmentsStringFromCache({required AppointmentsTimeSource timeSource}) async {
    File appointmentsFile = _getAppointmentsCacheFile(timeSource: timeSource);
    return await appointmentsFile.exists() ? await appointmentsFile.readAsString() : null;
  }

  Future<void> _saveAppointmentsStringToCache(String? value, AppointmentsTimeSource timeSource) async {
    await _getAppointmentsCacheFile(timeSource: timeSource).writeAsString(value ?? '', flush: true);
  }

  Future<List<Appointment>?> _loadAppointmentsFromCache({required AppointmentsTimeSource timeSource}) async {
    return Appointment.listFromJson(JsonUtils.decodeList(await _loadAppointmentsStringFromCache(timeSource: timeSource)));
  }

  Future<String?> _loadAppointmentsStringFromNet({required AppointmentsTimeSource timeSource}) async {
    //TMP: assets shortcut
    //return await AppBundle.loadString('assets/appointments.json');
    if (StringUtils.isNotEmpty(Config().appointmentsUrl) && Auth2().isLoggedIn) {
      String url = "${Config().appointmentsUrl}/services/appointments";
      switch (timeSource) {
        case AppointmentsTimeSource.upcoming:
          url += '?start-date=${DateTime.now().toUtc().millisecondsSinceEpoch}&order=asc';
          break;
        case AppointmentsTimeSource.past:
          url += '?end-date=${DateTime.now().toUtc().millisecondsSinceEpoch}&order=desc';
          break;
      }
      http.Response? response = await Network().get(url, auth: Auth2());
      int? responseCode = response?.statusCode;
      String? responseString = response?.body;
      if (responseCode == 200) {
        return responseString;
      } else {
        debugPrint('Failed to load appointments ($url) from net. Reason: $responseCode, $responseString');
        return null;
      }
    }
    return null;
  }

  Future<List<Appointment>?> _initAppointments({required AppointmentsTimeSource timeSource}) async {
    List<Appointment>? appointments;
    appointments = await _loadAppointmentsFromCache(timeSource: timeSource);
    if (appointments != null) {
      _updateAppointments(timeSource: timeSource);
    } else {
      String? appointmentsJsonString = await _loadAppointmentsStringFromNet(timeSource: timeSource);
      appointments = Appointment.listFromJson(JsonUtils.decodeList(appointmentsJsonString));
      if (appointments != null) {
        _saveAppointmentsStringToCache(appointmentsJsonString, timeSource);
      }
    }
    return appointments;
  }

  Future<void> _updateAllAppointments() async {
    await Future.wait([
      _updateAppointments(timeSource: AppointmentsTimeSource.upcoming),
      _updateAppointments(timeSource: AppointmentsTimeSource.past),
    ]);
  }

  Future<void> _updateAppointments({required AppointmentsTimeSource timeSource}) async {
    String? appointmentsJsonString = await _loadAppointmentsStringFromNet(timeSource: timeSource);
    List<Appointment>? appointments = Appointment.listFromJson(JsonUtils.decodeList(appointmentsJsonString));
    bool apptsChanged = false;
    switch (timeSource) {
      case AppointmentsTimeSource.past:
        if (!DeepCollectionEquality().equals(_pastAppointments, appointments)) {
          _pastAppointments = appointments;
          apptsChanged = true;
        }
        break;
      case AppointmentsTimeSource.upcoming:
        if (!DeepCollectionEquality().equals(_upcomingAppointments, appointments)) {
          _upcomingAppointments = appointments;
          apptsChanged = true;
        }
        break;
    }
    if (apptsChanged) {
      _saveAppointmentsStringToCache(appointmentsJsonString, timeSource);
      _notifyAppointmentsChanged(timeSource: timeSource);
    }
  }

  void _notifyAppointmentsChanged({required AppointmentsTimeSource timeSource}) {
    switch (timeSource) {
      case AppointmentsTimeSource.past:
        NotificationService().notify(notifyPastAppointmentsChanged);
        break;
      case AppointmentsTimeSource.upcoming:
        NotificationService().notify(notifyUpcomingAppointmentsChanged);
        break;
    }
  }

  // Appointments Account

  void changeAccountPreferences({bool? newAppointment, bool? morningReminder, bool? nightReminder}) {
    if (_account != null) {
      bool changed = false;
      if (newAppointment != null) {
        _account!.notificationsAppointmentNew = newAppointment;
        changed = true;
      }
      if (morningReminder != null) {
        _account!.notificationsAppointmentReminderMorning = morningReminder;
        changed = true;
      }
      if (nightReminder != null) {
        _account!.notificationsAppointmentReminderNight = nightReminder;
        changed = true;
      }
      if (changed) {
        _updateAccountPreferences();
      }
    }
  }

  Future<void> _initAccount() async {
    _account = await _loadAccountFromCache();
    if (_account != null) {
      _updateAccount();
    } else {
      String? accountJsonString = await _loadAccountStringFromNet();
      _account = AppointmentsAccount.fromJson(JsonUtils.decodeMap(accountJsonString));
      if (_account != null) {
        _saveAccountStringToCache(accountJsonString);
        NotificationService().notify(notifyAppointmentsAccountChanged);
      } else if (Auth2().isLoggedIn && (_isLastAccountResponseSuccessful == true)) {
        // if the backend returns successful response without account, then populate the account with default values
        _initAccountOnFirstSignIn();
      }
    }
  }

  File _getAccountCacheFile() => File(join(_appDocDir.path, _accountCacheDocName));

  Future<String?> _loadAccountStringFromCache() async {
    File accountFile = _getAccountCacheFile();
    return await accountFile.exists() ? await accountFile.readAsString() : null;
  }

  Future<void> _saveAccountStringToCache(String? value) async {
    await _getAccountCacheFile().writeAsString(value ?? '', flush: true);
  }

  Future<AppointmentsAccount?> _loadAccountFromCache() async {
    return AppointmentsAccount.fromJson(JsonUtils.decodeMap(await _loadAccountStringFromCache()));
  }

  Future<String?> _loadAccountStringFromNet() async {
    if (StringUtils.isNotEmpty(Config().appointmentsUrl) && Auth2().isLoggedIn) {
      String? url = "${Config().appointmentsUrl}/services/account";
      http.Response? response = await Network().get(url, auth: Auth2());
      int? responseCode = response?.statusCode;
      String? responseString = response?.body;
      if (responseCode == 200) {
        _isLastAccountResponseSuccessful = true;
        return responseString;
      } else {
        Log.w('Failed to load Appointments Account. Response:\n$responseCode: $responseString');
        _isLastAccountResponseSuccessful = false;
        return null;
      }
    } else {
      _isLastAccountResponseSuccessful = null;
      return null;
    }
  }

  Future<void> _updateAccount() async {
    String? accountJsonString = await _loadAccountStringFromNet();
    AppointmentsAccount? apptsAccount = AppointmentsAccount.fromJson(JsonUtils.decodeMap(accountJsonString));
    if (_account != apptsAccount) {
      _account = apptsAccount;
      _saveAccountStringToCache(accountJsonString);
      NotificationService().notify(notifyAppointmentsAccountChanged);
    }
  }

  Future<void> _initAccountOnFirstSignIn() async {
    // By Default
    AppointmentsAccount defaultNewAccount = AppointmentsAccount(
        notificationsAppointmentNew: true, notificationsAppointmentReminderMorning: true, notificationsAppointmentReminderNight: true);
    Map<String, String> headers = {'Content-Type': 'application/json'};
    String? accountJsonString = JsonUtils.encode(defaultNewAccount.toJson());
    String? url = "${Config().appointmentsUrl}/services/account";
    http.Response? response = await Network().post(url, auth: Auth2(), body: accountJsonString, headers: headers);
    int? responseCode = response?.statusCode;
    String? responseString = response?.body;
    if (responseCode == 200) {
      _isLastAccountResponseSuccessful = true;
      _account = AppointmentsAccount.fromJson(JsonUtils.decodeMap(responseString));
      _saveAccountStringToCache(responseString);
    } else {
      Log.w('Failed to init default Appointments Account. Response:\n$responseCode: $responseString');
      _isLastAccountResponseSuccessful = false;
      _account = null;
      _saveAccountStringToCache(null);
    }
    NotificationService().notify(notifyAppointmentsAccountChanged);
  }

  Future<void> _updateAccountPreferences() async {
    String? accountJsonString = JsonUtils.encode(_account);
    Map<String, String> headers = {'Content-Type': 'application/json'};
    String? url = "${Config().appointmentsUrl}/services/account";
    http.Response? response = await Network().post(url, auth: Auth2(), body: accountJsonString, headers: headers);
    int? responseCode = response?.statusCode;
    String? responseString = response?.body;
    if (responseCode == 200) {
      _isLastAccountResponseSuccessful = true;
      _account = AppointmentsAccount.fromJson(JsonUtils.decodeMap(responseString));
      _saveAccountStringToCache(responseString);
    } else {
      Log.w('Failed to init default Appointments Account. Response:\n$responseCode: $responseString');
      _isLastAccountResponseSuccessful = false;
      _account = null;
      _saveAccountStringToCache(null);
    }
    NotificationService().notify(notifyAppointmentsAccountChanged);
  }

  // DeepLinks
  String get appointmentDetailUrl => '${DeepLink().appUrl}/appointment';

  void _onDeepLinkUri(Uri? uri) {
    if (uri != null) {
      Uri? appointmentUri = Uri.tryParse(appointmentDetailUrl);
      if ((appointmentUri != null) &&
          (appointmentUri.scheme == uri.scheme) &&
          (appointmentUri.authority == uri.authority) &&
          (appointmentUri.path == uri.path)) {
        try {
          _handleAppointmentDetail(uri.queryParameters.cast<String, dynamic>());
        } catch (e) {
          print(e.toString());
        }
      }
    }
  }

  void _handleAppointmentDetail(Map<String, dynamic>? params) {
    if ((params != null) && params.isNotEmpty) {
      if (_appointmentDetailsCache != null) {
        _cacheAppointmentDetail(params);
      } else {
        _processAppointmentDetail(params);
      }
    }
  }

  void _processAppointmentDetail(Map<String, dynamic> params) {
    NotificationService().notify(notifyAppointmentDetail, params);
  }

  void _cacheAppointmentDetail(Map<String, dynamic> params) {
    _appointmentDetailsCache?.add(params);
  }

  void _processCachedAppointmentDetails() {
    if (_appointmentDetailsCache != null) {
      List<Map<String, dynamic>> appointmentDetailsCache = _appointmentDetailsCache!;
      _appointmentDetailsCache = null;

      for (Map<String, dynamic> appointmentDetail in appointmentDetailsCache) {
        _processAppointmentDetail(appointmentDetail);
      }
    }
  }

  // Debug

  bool? get _useSampleData => Storage().debugUseSampleAppointments;

  // Providers

  Future<List<AppointmentProvider>?> loadProviders() async {
    if (_useSampleData != true) {
      String? url = "${Config().appointmentsUrl}/services/providers";
      http.Response? response = await Network().get(url, auth: Auth2());
      return (response?.statusCode == 200) ? AppointmentProvider.listFromJson(JsonUtils.decodeList(response?.body)) : null;
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      return _sampleProviders;
    }
  }

  List<AppointmentProvider> get _sampleProviders =>  <AppointmentProvider>[
    AppointmentProvider(id: '1', name: 'McKinley'),
    AppointmentProvider(id: '2', name: 'Grainger'),
    AppointmentProvider(id: '3', name: 'Lorem Ipsum'),
    AppointmentProvider(id: '4', name: 'Sit Dolor Amet'),
  ];

  // Units

  Future<List<AppointmentUnit>?> loadUnits({ required String providerId }) async {
    if (_useSampleData != true) {
      String? url = "${Config().appointmentsUrl}/services/units?providers-ids=$providerId";
      http.Response? response = await Network().get(url, auth: Auth2());
      return (response?.statusCode == 200) ? AppointmentUnit.listFromJson(JsonUtils.decodeList(response?.body)) : null;
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      return _sampleUnits;
    }
  }

  List<AppointmentUnit> get _sampleUnits => <AppointmentUnit>[
    AppointmentUnit(id: '11', name: 'House of Horror', address: '1109 S Lincoln Ave Urbana, IL 61801', hoursOfOperation: '8:00am - 17:30pm', imageUrl: 'https://horrorhouse.bg/wp-content/uploads/2020/09/logo-new.png', notes: 'Lorem ipsum sit dolor amet.'),
    AppointmentUnit(id: '12', name: "Dante's Inferno", address: '1103 S Sixth St Champaign, IL 61820', hoursOfOperation: '8:30am - 12:30pm', imageUrl: 'https://images.fineartamerica.com/images-medium-large-5/dantes-inferno-c1520-granger.jpg', notes: 'Proin sed lacinia ex.'),
    AppointmentUnit(id: '13', name: 'Spem Omnem Hic', address: '1402 Springfield Ave Urbana, IL 61801', hoursOfOperation: '7:00am - 9:00pm', imageUrl: 'https://assets.justinmind.com/wp-content/uploads/2018/11/Lorem-Ipsum-alternatives-768x492.png', notes: 'Class aptent taciti sociosqu ad litora.'),
    AppointmentUnit(id: '14', name: 'Blood, Toil, Tears, and Sweat', address: '505 E Armory Ave  Champaign, IL 61820', hoursOfOperation: '10:00am - 12:30pm', imageUrl: 'https://cdn.britannica.com/25/139425-138-050505D0/consideration-London-Houses-of-Parliament.jpg?w=450&h=450&c=crop', notes: 'Donec iaculis est eget leo egestas ullamcorper.'),
  ];

  // Persons

  Future<List<AppointmentPerson>?> loadPersons({ required String providerId, required String unitId }) async {
    if (_useSampleData != true) {
      String? url = "${Config().appointmentsUrl}/services/people";
      Map<String, String> headers = {
        'Content-Type': 'application/json'
      };
      String? post = JsonUtils.encode([{
        'provider_id': providerId,
        'unit_ids': [ unitId ],
      }]);
      http.Response? response = await Network().get(url, body: post, headers: headers, auth: Auth2());
      return (response?.statusCode == 200) ? AppointmentPerson.listFromJson(JsonUtils.decodeList(response?.body)) : null;
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      return _samplePersons;
    }
  }

  List<AppointmentPerson> get _samplePersons => <AppointmentPerson>[
    AppointmentPerson(id: '21', name: 'Agatha Christie', imageUrl: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSZcTCeGIZqe_mVUqcGGEGLh-L9wLCcnh3PLiXv4vWtBxRQABhBuq_G4yEoqub35xAQ6dU&usqp=CAU', notes: 'Vulputate mi sit amet mauris. Neque sodales ut etiam sit. Dictum at tempor commodo ullamcorper a. Duis at consectetur lorem donec massa.'),
    AppointmentPerson(id: '22', name: 'Amanda Lear',     imageUrl: 'https://filmitena.com/img/Actor/Middle/199175_Mid_20220525231650.jpg', notes: 'Ultricies tristique nulla aliquet enim tortor at auctor. Pulvinar pellentesque habitant morbi tristique senectus. Sapien pellentesque habitant morbi tristique senectus et netus.'),
    AppointmentPerson(id: '23', name: 'Bill Gates',      imageUrl: 'https://cdn.britannica.com/47/188747-050-1D34E743/Bill-Gates-2011.jpg', notes: 'Amet dictum sit amet justo donec enim diam. In vitae turpis massa sed elementum tempus egestas sed. In est ante in nibh mauris cursus mattis. Pellentesque adipiscing commodo elit at imperdiet.'),
    AppointmentPerson(id: '24', name: 'Chalres Darwin',  imageUrl: 'https://hips.hearstapps.com/hmg-prod/images/gettyimages-79035252.jpg?resize=1200:*', notes: 'Volutpat diam ut venenatis tellus in. Id faucibus nisl tincidunt eget nullam. Enim ut tellus elementum sagittis vitae et leo. Quisque id diam vel quam elementum pulvinar etiam. '),
    AppointmentPerson(id: '25', name: 'Fredy Mercury',   imageUrl: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS0T3LLSiq7oVJOuaHmELD9weLl_rc6qsTWBdRNJlAEpaJjlo50iD269nPFBtpT6lVXljU&usqp=CAU', notes: 'Vestibulum morbi blandit cursus risus at ultrices mi tempus imperdiet. Massa eget egestas purus viverra. Sagittis eu volutpat odio facilisis mauris sit amet massa vitae. Sit amet consectetur adipiscing elit pellentesque habitant morbi tristique.'),
    AppointmentPerson(id: '26', name: 'Frank Zapa',      imageUrl: 'https://ensembleparamirabo.com/sites/default/files/styles/photo_carree/public/compositeurs/zappa.jpg?h=9d6ce95a&itok=in8Bun6k', notes: 'Enim blandit volutpat maecenas volutpat blandit aliquam etiam. A cras semper auctor neque. Aenean sed adipiscing diam donec adipiscing.'),
    AppointmentPerson(id: '27', name: 'Michael Jackson', imageUrl: 'https://img.i-scmp.com/cdn-cgi/image/fit=contain,width=425,format=auto/sites/default/files/styles/768x768/public/images/methode/2018/08/29/22d69e08-aa71-11e8-8796-d12ba807e6e9_1280x720_113417.JPG?itok=Y1Fzf3rv', notes: 'Adipiscing vitae proin sagittis nisl rhoncus. Massa sed elementum tempus egestas. Morbi tristique senectus et netus. Turpis massa sed elementum tempus egestas sed sed.'),
    AppointmentPerson(id: '28', name: 'Speedy Gonzales', imageUrl: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT4x3cdYc6BQgsXy_OOsOvjjvTWQlRmSolj1d4KaIPyfNIri6f6AKNgcLtmNSsLQHK5_g4&usqp=CAU', notes: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Aenean sed adipiscing diam donec adipiscing tristique risus nec feugiat.'),
  ];

  // Time Slots And Questions

  Future<AppointmentTimeSlotsAndQuestions?> loadTimeSlotsAndQuestions({ String? providerId, String? unitId, String? personId, required DateTime dateLocal }) async {
    if (_useSampleData != true) {
      int startTime = dateLocal.millisecondsSinceEpoch;
      int endTime = startTime + 86400000; // 1 day in milliseconds = 24 * 60 * 60 * 1000
      String? url = "${Config().appointmentsUrl}/services/slots?provider-id=$providerId&unit-id=$unitId&person-id=$personId&start-time=$startTime&end-time=$endTime";
      http.Response? response = await Network().get(url, auth: Auth2());
      return (response?.statusCode == 200) ? AppointmentTimeSlotsAndQuestions.fromJson(JsonUtils.decodeMap(response?.body)) : null;
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      return AppointmentTimeSlotsAndQuestions(
        timeSlots: _sampleTimeSlots(dateLocal: dateLocal),
        questions: _sampleQuestions,
      );
    }
  }

  List<AppointmentTimeSlot> _sampleTimeSlots({ required DateTime dateLocal }) {
    DateTime midnighDateUtc = DateUtils.dateOnly(dateLocal).toUtc();
    DateTime startDateUtc = midnighDateUtc.add(Duration(hours: 8));
    DateTime endDateUtc = startDateUtc.add(Duration(hours: 12));
    Duration slotDuration = Duration(minutes: 30);
    List<AppointmentTimeSlot> result = <AppointmentTimeSlot>[];
    DateTime dateTimeUtc = startDateUtc;
    while (dateTimeUtc.isBefore(endDateUtc)) {
      DateTime endDateTime = dateTimeUtc.add(slotDuration);
      result.add(AppointmentTimeSlot(
        startTimeUtc: dateTimeUtc,
        endTimeUtc: endDateTime,
        capacity: 16,
        filled: (Random().nextInt(4) == 0) ? 16 : 0,
      ));
      dateTimeUtc = endDateTime;
    }
    return result;
  }

  List<AppointmentQuestion> get _sampleQuestions => <AppointmentQuestion>[
    AppointmentQuestion(id: "31", title: "Why do you want this appointment?", type: AppointmentQuestionType.text, required: true),
    AppointmentQuestion(id: "32", title: "What is your temperature?", type: AppointmentQuestionType.select, values: ["Below 36℃", "36-37℃", "37-38℃", "38-39℃", "39-40℃", "Over 40℃"], required: true),
    AppointmentQuestion(id: "33", title: "What are your symptoms?", type: AppointmentQuestionType.multiSelect, values: ["Fever", "Chills", "Shaking or Shivering", "Shortness of breath", "Difficulty breathing", "Muscle or joint pain", "Fatigue", "Loss of taste and/or smell", "Fever or chills", "Cough", "Sore Throat", "Nausea or vomiting", "Diarrhea"], required: true),
    AppointmentQuestion(id: "34", title: "Are you feeling sick?", type: AppointmentQuestionType.checkbox, required: true),
  ];

  List<AppointmentAnswer> get _sampleAnswers => <AppointmentAnswer>[
    AppointmentAnswer(questionId: "31", values: ["I don't know."]),
    AppointmentAnswer(questionId: "32", values: ["36-37℃"]),
    AppointmentAnswer(questionId: "33", values: ["Fever", "Chills", "Cough"]),
    AppointmentAnswer(questionId: "34", values: ["true"]),
  ];

  // Appointments

  Future<List<Appointment>?> loadAppointments({String? providerId}) async {
    if (_useSampleData != true) {
      String? url = "${Config().appointmentsUrl}/services/appointments?providers-ids=$providerId";
      http.Response? response = await Network().get(url, auth: Auth2());
      return (response?.statusCode == 200) ? Appointment.listFromJson(JsonUtils.decodeList(response?.body)) : null;
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      AppointmentProvider? provider = (providerId != null) ? _sampleProviders.firstWhere((provider) => provider.id == providerId, orElse: () => _sampleProviders.first) : null;
      if (provider != null) {
        return _sampleAppointments(provider: provider);
      }
      else {
        return <Appointment>[];
      }
    }
  }

  List<Appointment> _sampleAppointments({ required AppointmentProvider provider }) {
    DateTime now = DateTime.now();
    List<Appointment> appointments = <Appointment>[];

    for (int index = 0; index < 5; index++) {
      appointments.add(_sampleAppointment(provider: provider, day: now.add(Duration(days: index + 5))));
    }
    
    for (int index = 0; index < 5; index++) {
      appointments.add(_sampleAppointment(provider: provider, day: now.subtract(Duration(days: index + 5))));
    }

    return appointments;
  }

  Appointment _sampleAppointment({required AppointmentProvider provider, required DateTime day}) {
    String id = Uuid().v1();
    AppointmentType type = ((Random().nextInt(3) % 3) == 0) ? AppointmentType.online : AppointmentType.in_person;

    List<AppointmentUnit> units = _sampleUnits;
    AppointmentUnit unit = units[Random().nextInt(units.length)];

    AppointmentOnlineDetails? details = (type == AppointmentType.online) ? AppointmentOnlineDetails(
      meetingId: id.substring(0, 8).toUpperCase(),
      url: "https://mymckinley.illinois.edu",
      meetingPasscode: id.substring(24, 30).toUpperCase(),
    ) : null;
    
    List<AppointmentPerson> persons = _samplePersons;
    AppointmentPerson person = persons[Random().nextInt(persons.length)];
    
    bool cancelled = ((Random().nextInt(3) % 5) == 0);

    DateTime startTimeUtc = DateTime(day.year, day.month, day.day, Random().nextInt(8) + 8, 30).toUtc();
    DateTime endTimeUtc = startTimeUtc.add(Duration(minutes: 30));

    return Appointment(
      id: id,
      type: type,
      startTimeUtc: startTimeUtc,
      endTimeUtc: endTimeUtc,

      provider: provider,
      unit: unit,
      person: person,
      answers: _sampleAnswers,

      host: null,
      location: null,
      onlineDetails: details,
      instructions: 'Sample instructions (${5 - Random().nextInt(5) + 1})',
      cancelled: cancelled,
    );
  }
  
  /*<Appointment>[

    Appointment.fromJson({"id":"08c122e3-2174-438b-94d4-f231198c26bc","type":"InPerson","provider":provider.toJson(),"date":"2023-04-14T07:30:444Z","location":{"id":"555556","title":"McKinley Health Center, East wing, 3rd floor","latitude":40.10291,"longitude":-88.21961,"phone":"555-333-777"},"cancelled":false,"instructions":"Some instructions 1 ...","host":{"first_name":"John","last_name":"Doe"}}) ?? Appointment(),
    Appointment.fromJson({"id":"08c122e3-2174-438b-94d4-f231198c26ba","type":"InPerson","provider":provider.toJson(),"date":"2023-04-13T07:30:444Z","location":{"id":"555555","title":"McKinley Health Center, East wing, 3rd floor","latitude":40.10291,"longitude":-88.21961,"phone":"555-333-777"},"cancelled":false,"instructions":"Some instructions 1 ...","host":{"first_name":"John","last_name":"Doe"}}) ?? Appointment(),
    Appointment.fromJson({"id":"08c122e3-2174-438b-f231198c26ba","type":"Online","provider":provider.toJson(),"date":"2023-04-12T08:22:444Z","online_details":{"url":"https://mymckinley.illinois.edu","meeting_id":"asdasd","meeting_passcode":"passs"},"cancelled":false,"instructions":"Some instructions 2 ...","host":{"first_name":"JoAnn","last_name":"Doe"}}) ?? Appointment(),
    Appointment.fromJson({"id":"2174-438b-94d4-f231198c26ba","type":"InPerson","provider":provider.toJson(),"date":"2023-04-11T10:30:444Z","location":{"id":"777","title":"McKinley Health Center 8, South wing, 2nd floor","latitude":40.08514,"longitude":-88.27801,"phone":"555-444-777"},"cancelled":false,"instructions":"Some instructions 3 ...","host":{"first_name":"Bill","last_name":""}}) ?? Appointment(),
    Appointment.fromJson({"id":"08c122e3","type":"Online","provider":provider.toJson(),"date":"2023-04-10T11:34:444Z","online_details":{"url":"https://mymckinley.illinois.edu","meeting_id":"09jj","meeting_passcode":"dfkj3940"},"cancelled":false,"instructions":"Some instructions 4 ...","host":{"first_name":"Peter","last_name":"Grow"}}) ?? Appointment(),
    
    Appointment.fromJson({"id":"08c122e3-2174-438b-94d4-f231198c26bc","provider":provider.toJson(),"date":"2023-02-14T07:30:444Z","type":"InPerson","location":{"id":"555556","title":"McKinley Health Center, East wing, 3rd floor","latitude":40.10291,"longitude":-88.21961,"phone":"555-333-777"},"cancelled":false,"instructions":"Some instructions 1 ...","host":{"first_name":"John","last_name":"Doe"}}) ?? Appointment(),
    Appointment.fromJson({"id":"08c122e3-2174-438b-94d4-f231198c26ba","provider":provider.toJson(),"date":"2023-02-13T07:30:444Z","type":"InPerson","location":{"id":"555555","title":"McKinley Health Center, East wing, 3rd floor","latitude":40.10291,"longitude":-88.21961,"phone":"555-333-777"},"cancelled":false,"instructions":"Some instructions 1 ...","host":{"first_name":"John","last_name":"Doe"}}) ?? Appointment(),
    Appointment.fromJson({"id":"08c122e3-2174-438b-f231198c26ba","provider":provider.toJson(),"date":"2023-02-12T08:22:444Z","type":"Online","online_details":{"url":"https://mymckinley.illinois.edu","meeting_id":"asdasd","meeting_passcode":"passs"},"cancelled":false,"instructions":"Some instructions 2 ...","host":{"first_name":"JoAnn","last_name":"Doe"}}) ?? Appointment(),
    Appointment.fromJson({"id":"2174-438b-94d4-f231198c26ba","provider":provider.toJson(),"date":"2023-02-11T10:30:444Z","type":"InPerson","location":{"id":"777","title":"McKinley Health Center 8, South wing, 2nd floor","latitude":40.08514,"longitude":-88.27801,"phone":"555-444-777"},"cancelled":false,"instructions":"Some instructions 3 ...","host":{"first_name":"Bill","last_name":""}}) ?? Appointment(),
    Appointment.fromJson({"id":"08c122e3","provider":provider.toJson(),"date":"2023-02-10T11:34:444Z","type":"Online","online_details":{"url":"https://mymckinley.illinois.edu","meeting_id":"09jj","meeting_passcode":"dfkj3940"},"cancelled":false,"instructions":"Some instructions 4 ...","host":{"first_name":"Peter","last_name":"Grow"}}) ?? Appointment(),
  ];*/

  Future<Appointment?> createAppointment({
    AppointmentProvider? provider,
    AppointmentUnit? unit,
    AppointmentPerson? person,
    AppointmentType? type,
    AppointmentTimeSlot? timeSlot,
    List<AppointmentAnswer>? answers,
  }) async {
    if (_useSampleData != true) {
      String? url = "${Config().appointmentsUrl}/services/appointments";
      Map<String, String> headers = {
        'Content-Type': 'application/json'
      };
      String? post = JsonUtils.encode({
        'provider_id': provider?.id,
        'unit_id': unit?.id,
        'person_id': person?.id,
        'type': appointmentTypeToString(type),
        'time': timeSlot?.startTimeUtc?.millisecondsSinceEpoch,
        'answers': AppointmentAnswer.listToJson(answers),
      });
      http.Response? response = await Network().post(url, body: post, headers: headers, auth: Auth2());
      if (response?.statusCode == 200) {
        return Appointment.fromJson(JsonUtils.decodeMap(response?.body));
      }
      throw AppointmentsException.fromServerResponse(response);
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      if (Random().nextInt(2) == 0) {
        NotificationService().notify(notifyAppointmentsChanged);
        return Appointment(provider: provider, unit: unit, person: person, type: type, startTimeUtc: timeSlot?.startTimeUtc, endTimeUtc: timeSlot?.endTimeUtc, answers: answers);
      }
      else {
        throw AppointmentsException.unknown('Random Create Failure');
      }
    }
  }

  Future<Appointment?> updateAppointment(Appointment appointment, {
    AppointmentType? type,
    AppointmentTimeSlot? timeSlot,
    List<AppointmentAnswer>? answers,
  }) async {
    if (_useSampleData != true) {
      String? url = "${Config().appointmentsUrl}/services/appointments/${appointment.id}";
      Map<String, String> headers = {
        'Content-Type': 'application/json'
      };
      String? post = JsonUtils.encode({
        'type': appointmentTypeToString(type),
        'time': timeSlot?.startTimeUtc?.millisecondsSinceEpoch,
        'answers': AppointmentAnswer.listToJson(answers),
      });
      http.Response? response = await Network().put(url, body: post, headers: headers, auth: Auth2());
      if (response?.statusCode == 200) {
        return Appointment.fromJson(JsonUtils.decodeMap(response?.body));
      }
      throw AppointmentsException.fromServerResponse(response);
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      if (Random().nextInt(2) == 0) {
        NotificationService().notify(notifyAppointmentsChanged);
        return Appointment.fromOther(appointment, type: type, startTimeUtc: timeSlot?.startTimeUtc, endTimeUtc: timeSlot?.endTimeUtc, answers: answers);
      }
      else {
        throw AppointmentsException.unknown('Random Update Failure');
      }
    }
  }

  Future<Appointment?> cancelAppointment(Appointment appointment) async {
    if (_useSampleData != true) {
        String? url = "${Config().appointmentsUrl}/services/appointments/${appointment.id}";
        http.Response? response = await Network().delete(url, auth: Auth2());
        if (response?.statusCode == 200) {
          return Appointment.fromOther(appointment, cancelled: true);
        }
        throw AppointmentsException.fromServerResponse(response);
    }
    else {
      await Future.delayed(Duration(milliseconds: 1500));
      if (Random().nextInt(2) == 0) {
        NotificationService().notify(notifyAppointmentsChanged);
        return Appointment.fromOther(appointment, cancelled: true);
      }
      else {
        throw AppointmentsException.unknown('Random Update Failure');
      }
    }
  }
}

enum AppointmentsError { serverResponse, internal, unknown }

class AppointmentsException implements Exception {
  final AppointmentsError error;
  final String? description;

  AppointmentsException({ this.error = AppointmentsError.unknown, this.description});

  factory AppointmentsException.fromServerResponse(http.Response? response) => AppointmentsException(
    error: AppointmentsError.serverResponse,
    description: StringUtils.isNotEmpty(response?.body) ? response?.body : response?.reasonPhrase
  );

  factory AppointmentsException.internal([String? description]) => AppointmentsException(
    error: AppointmentsError.internal,
    description: description
  );
  
  factory AppointmentsException.unknown([String? description]) => AppointmentsException(
    error: AppointmentsError.unknown,
    description: description
  );

  @override
  String toString() => description ?? errorDescription;

  String get errorDescription {
    switch (error) {
      case AppointmentsError.serverResponse: return 'Server Response Error';
      case AppointmentsError.internal: return 'Internal Error Occured';
      case AppointmentsError.unknown: return 'Unknown Error Occured';
    }
  }
}
