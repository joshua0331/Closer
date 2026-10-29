import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/judge_service.dart';
import '../services/muse_image_service.dart';
import 'courtroom_scene.dart';
import 'demo_access_page.dart';

class CourtExperience extends StatefulWidget {
  const CourtExperience({
    super.key,
    required this.preferences,
    this.judge,
    this.artwork,
    this.now,
    this.initialNames,
    this.initialTopic,
    this.caseId,
    this.onCaseClosed,
  });
  final SharedPreferences preferences;
  final JudgeService? judge;
  final MuseImageService? artwork;
  final DateTime Function()? now;
  final List<String>? initialNames;
  final String? initialTopic, caseId;
  final Future<void> Function(Map<String, dynamic>)? onCaseClosed;
  @override
  State<CourtExperience> createState() => _CourtExperienceState();
}

class _CourtExperienceState extends State<CourtExperience> {
  final _form = GlobalKey<FormState>();
  final _panelScroll = ScrollController();
  final _names = [TextEditingController(), TextEditingController()];
  final _statements = [TextEditingController(), TextEditingController()];
  final _topic = TextEditingController();
  final _request = TextEditingController();
  final _crossQuestions = [TextEditingController(), TextEditingController()];
  final _crossAnswers = [TextEditingController(), TextEditingController()];
  final _rebuttals = [TextEditingController(), TextEditingController()];
  final _judgeAnswers = [TextEditingController(), TextEditingController()];
  final _appealReason = TextEditingController();
  final _appealResponse = TextEditingController();
  List<String> _judgeQuestions = ['', ''];
  final List<Map<String, dynamic>> _evidence = [];
  final List<Map<String, dynamic>> _rulingHistory = [];
  List<Map<String, dynamic>> _evidenceReview = [];
  Map<String, dynamic>? _ruling;
  int _exhibitCounter = 0;
  int _turnSeconds = 120;
  bool _hasAppealed = false;
  bool _recorded = false;
  static const _speakers = {
    1: 0,
    2: 1,
    3: 0,
    4: 1,
    5: 1,
    6: 0,
    7: 0,
    8: 1,
    10: 0,
    11: 1,
    14: 1,
    15: 0,
  };
  bool get _timed => _speakers.containsKey(_stage);
  DateTime get _now => (widget.now ?? DateTime.now)();
  final _agreement = TextEditingController();
  final List<String?> _photos = [null, null];
  final _approved = [false, false];
  late final JudgeService _judge = widget.judge ?? JudgeService();
  late final MuseImageService _artwork = widget.artwork ?? MuseImageService();
  String? _generatedScene;
  String? _artResponseId;
  String? _promptVersion;
  int _stage = 0;
  int _remaining = 120;
  Timer? _timer;
  Timer? _draftSave;
  Future<void> _draftWrites = Future.value();
  late String _caseId =
      widget.caseId ?? DateTime.now().microsecondsSinceEpoch.toString();
  DateTime? _deadline;
  bool _busy = false;
  String? _error;
  JudgeResult? _result;
  bool _practice = false;

  @override
  void initState() {
    super.initState();
    try {
      final raw = widget.preferences.getString('court_profile_v1');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _generatedScene = data['generatedScene'] as String?;
        _artResponseId = data['artResponseId'] as String?;
        _promptVersion = data['promptVersion'] as String?;
        for (var i = 0; i < 2; i++) {
          _names[i].text = (data['names'] as List)[i] as String;
          _photos[i] = (data['photos'] as List)[i] as String?;
        }
      }
    } catch (_) {
      _error = 'Could not restore the local profiles. Please enter your names again.';
    }
    if (widget.initialNames?.length == 2) {
      for (var i = 0; i < 2; i++) {
        _names[i].text = widget.initialNames![i];
      }
    }
    _topic.text = widget.initialTopic ?? '';
    _restoreDraft();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _draftSave?.cancel();
    if (!_recorded) unawaited(_persistDraft());
    _panelScroll.dispose();
    for (final controller in [
      ..._names,
      ..._statements,
      ..._crossQuestions,
      ..._crossAnswers,
      ..._rebuttals,
      ..._judgeAnswers,
      _topic,
      _request,
      _agreement,
      _appealReason,
      _appealResponse,
    ]) {
      controller.dispose();
    }
    if (widget.judge == null) _judge.close();
    if (widget.artwork == null) _artwork.close();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    _scheduleDraft();
    try {
      final saved = await widget.preferences.setString(
        'court_profile_v1',
        jsonEncode({
          'names': _names.map((e) => e.text.trim()).toList(),
          'photos': _photos,
          'generatedScene': _generatedScene,
          'artResponseId': _artResponseId,
          'promptVersion': _promptVersion,
        }),
      );
      if (!saved && mounted) {
        setState(() => _error = 'Could not save profiles on this device.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save profiles on this device.');
      }
    }
  }

  Future<void> _photo(int side) async {
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 90,
      );
      if (image == null || !mounted) return;
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/court_face_${side}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await image.saveTo(path);
      if (!mounted) return;
      setState(() {
        _photos[side] = path;
        _generatedScene = null;
        _artResponseId = null;
        _promptVersion = null;
      });
      await _saveProfile();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not use that photo. Check photo access and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateScene() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create your pixel-art characters?'),
        content: const Text(
          'Both selected portraits and the courtroom reference will be sent through your server to Meta Muse Image. Confirm that both people consent to this use of their photos. The result is an AI illustration and may not perfectly match their faces.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('We consent — generate'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photos = await Future.wait(
        _photos.map((path) => File(path!).readAsBytes()),
      );
      final artwork = await _artwork.generate(photos);
      final codec = await ui.instantiateImageCodec(artwork.bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/muse_court_${DateTime.now().microsecondsSinceEpoch}.png';
      await File(path).writeAsBytes(artwork.bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _generatedScene = path;
        _artResponseId = artwork.responseId;
        _promptVersion = artwork.promptVersion;
      });
      await _saveProfile();
    } on ArtworkException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create your artwork. Select PNG or JPEG portraits and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, TextEditingController> get _draftFields => {
    'name0': _names[0],
    'name1': _names[1],
    'topic': _topic,
    'request': _request,
    'agreement': _agreement,
    'appealReason': _appealReason,
    'appealResponse': _appealResponse,
    for (var i = 0; i < 2; i++) ...{
      'statement$i': _statements[i],
      'crossQuestion$i': _crossQuestions[i],
      'crossAnswer$i': _crossAnswers[i],
      'rebuttal$i': _rebuttals[i],
      'judgeAnswer$i': _judgeAnswers[i],
    },
  };

  void _scheduleDraft() {
    if (widget.caseId == null || _recorded) return;
    _draftSave?.cancel();
    _draftSave = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_persistDraft()),
    );
  }

  Future<void> _persistDraft() {
    if (widget.caseId == null || _recorded) return Future.value();
    final snapshot = jsonEncode({
      'fields': _draftFields.map((key, value) => MapEntry(key, value.text)),
      'stage': _stage,
      'turnSeconds': _turnSeconds,
      'remaining': _remaining,
      'deadline': _deadline?.toIso8601String(),
      'photos': _photos,
      'generatedScene': _generatedScene,
      'artResponseId': _artResponseId,
      'promptVersion': _promptVersion,
      'evidence': _evidence,
      'exhibitCounter': _exhibitCounter,
      'evidenceReview': _evidenceReview,
      'judgeQuestions': _judgeQuestions,
      'ruling': _ruling,
      'rulingHistory': _rulingHistory,
      'model': _result?.model,
      'practice': _practice,
      'hasAppealed': _hasAppealed,
      'approved': _approved,
    });
    _draftWrites = _draftWrites.then((_) async {
      try {
        final saved = await widget.preferences.setString(
          'court_draft_$_caseId',
          snapshot,
        );
        if (!saved && mounted) {
          setState(
            () => _error = 'Could not save this hearing draft on this device.',
          );
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _error = 'Could not save this hearing draft on this device.',
          );
        }
      }
    });
    return _draftWrites;
  }

  void _restoreDraft() {
    if (widget.caseId == null) return;
    try {
      final raw = widget.preferences.getString('court_draft_$_caseId');
      if (raw == null) return;
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      final fields = draft['fields'] as Map<String, dynamic>;
      for (final field in _draftFields.entries) {
        field.value.text = fields[field.key] as String? ?? '';
      }
      final stage = draft['stage'] as int;
      if (stage < 0 || stage > 17) throw const FormatException();
      _stage = stage;
      _turnSeconds = draft['turnSeconds'] as int;
      _remaining = draft['remaining'] as int;
      for (var i = 0; i < 2; i++) {
        _photos[i] = (draft['photos'] as List)[i] as String?;
        _approved[i] = (draft['approved'] as List)[i] as bool;
      }
      _generatedScene = draft['generatedScene'] as String?;
      _artResponseId = draft['artResponseId'] as String?;
      _promptVersion = draft['promptVersion'] as String?;
      _evidence.addAll(
        (draft['evidence'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      _exhibitCounter = draft['exhibitCounter'] as int;
      _evidenceReview = (draft['evidenceReview'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _judgeQuestions = List<String>.from(draft['judgeQuestions'] as List);
      _ruling = draft['ruling'] == null
          ? null
          : Map<String, dynamic>.from(draft['ruling'] as Map);
      _rulingHistory.addAll(
        (draft['rulingHistory'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      final model = draft['model'] as String?;
      _result = model == null ? null : JudgeResult('', model);
      _practice = draft['practice'] as bool;
      _hasAppealed = draft['hasAppealed'] as bool;
      final deadline = DateTime.tryParse(draft['deadline'] as String? ?? '');
      if (_timed && deadline != null) {
        _remaining = (deadline.difference(_now).inMilliseconds / 1000)
            .ceil()
            .clamp(0, _turnSeconds);
        if (_remaining > 0) _startTimer();
      }
    } catch (_) {
      _stage = 0;
      _error = 'Could not restore the entire hearing draft. Please review the case details.';
    }
  }

  void _pause() {
    _timer?.cancel();
    _deadline = null;
  }

  void _startTimer() {
    _deadline = _now.add(Duration(seconds: _remaining));
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final milliseconds = _deadline!.difference(_now).inMilliseconds;
      setState(() {
        _remaining = milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;
        if (_remaining == 0) _pause();
      });
    });
  }

  void _timerToggle() {
    if (_busy || _remaining == 0) return;
    setState(() {
      if (_timer?.isActive ?? false) {
        _pause();
      } else {
        _startTimer();
      }
    });
    _scheduleDraft();
  }

  void _enterStage(int stage) {
    _pause();
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = stage;
      _remaining = _turnSeconds;
      _error = null;
      if (_timed) _startTimer();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _panelScroll.hasClients) _panelScroll.jumpTo(0);
    });
    _scheduleDraft();
  }

  TextEditingController? get _activeController => switch (_stage) {
    1 || 2 => _statements[_stage - 1],
    3 => _crossQuestions[0],
    4 => _crossAnswers[1],
    5 => _crossQuestions[1],
    6 => _crossAnswers[0],
    7 || 8 => _rebuttals[_stage - 7],
    10 || 11 => _judgeAnswers[_stage - 10],
    14 => _appealReason,
    15 => _appealResponse,
    _ => null,
  };

  void _next() {
    if (_busy) return;
    if (_stage == 0) {
      if ([
        ..._names,
        _topic,
        _request,
      ].any((field) => field.text.trim().isEmpty)) {
        _form.currentState!.validate();
        setState(
          () => _error = 'Enter both names, the disagreement and the requested compensation.',
        );
        return;
      }
      unawaited(_saveProfile());
    } else {
      final current = _activeController;
      if (current != null && current.text.trim().isEmpty) {
        if (_remaining == 0) {
          current.text = '[No response supplied before the time limit.]';
        } else {
          _form.currentState!.validate();
          return;
        }
      }
    }
    _enterStage(_stage + 1);
  }

  Future<void> _addEvidence(int owner) async {
    if (_busy ||
        _remaining == 0 ||
        _evidence.where((entry) => entry['owner'] == owner).length >= 2) {
      return;
    }
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 1000000) {
        if (mounted) {
          setState(
            () => _error = 'Choose an evidence photo smaller than 1 MB.',
          );
        }
        return;
      }
      if (!mounted) return;
      final caption = await showDialog<String>(
        context: context,
        builder: (_) => const _EvidenceCaption(),
      );
      if (caption == null || !mounted) return;
      if (_remaining == 0) {
        setState(
          () => _error = 'Your turn ended before the exhibit was submitted.',
        );
        return;
      }
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/court_exhibit_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      _scheduleDraft();
      setState(() {
        _exhibitCounter++;
        _evidence.add({
          'id': 'E$_exhibitCounter',
          'owner': owner,
          'caption': caption,
          'path': path,
        });
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not attach this exhibit. Check photo access and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewEvidence(Map<String, dynamic> exhibit) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${exhibit['id']} · ${_names[exhibit['owner'] as int].text}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(
              File(exhibit['path'] as String),
              errorBuilder: (_, error, stack) =>
                  const Text('Local evidence file unavailable.'),
            ),
            const SizedBox(height: 12),
            Text(exhibit['caption'] as String),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<Map<String, dynamic>> _docket() async {
    final exhibits = <Map<String, dynamic>>[];
    for (final entry in _evidence) {
      final bytes = await File(entry['path'] as String).readAsBytes();
      if (bytes.length > 1000000) {
        throw const JudgeException('An exhibit exceeds the upload limit.');
      }
      exhibits.add({
        'id': entry['id'],
        'owner': entry['owner'],
        'caption': entry['caption'],
        'image_base64': base64Encode(bytes),
      });
    }
    return {
      'topic': _topic.text.trim(),
      'requestedRemedy': _request.text.trim(),
      'names': _names.map((e) => e.text.trim()).toList(),
      'statements': _statements.map((e) => e.text.trim()).toList(),
      'crossQuestions': _crossQuestions.map((e) => e.text.trim()).toList(),
      'crossAnswers': _crossAnswers.map((e) => e.text.trim()).toList(),
      'rebuttals': _rebuttals.map((e) => e.text.trim()).toList(),
      'judgeQuestions': _judgeQuestions,
      'judgeAnswers': _judgeAnswers.map((e) => e.text.trim()).toList(),
      'evidence': exhibits,
      'appealReason': _appealReason.text.trim(),
      'appealResponse': _appealResponse.text.trim(),
      'priorRuling': _ruling,
    };
  }

  Future<void> _judgeAction(String action) async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'questions'
              ? 'Let the judge examine the case?'
              : 'Send the case for a ruling?',
        ),
        content: Text(
          'This sends both names, the requested compensation, testimony, questions, answers, rebuttals and ${_evidence.length} evidence photo(s) with captions to Meta Muse Spark through your server. Confirm you have permission to share these exhibits. Character portraits are excluded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send to the judge'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _judge.hearing(action, await _docket());
      if (!mounted) return;
      setState(() {
        _practice = false;
        _result = JudgeResult('', result.model);
        _evidenceReview = (result.result['evidenceReview'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (action == 'questions') {
          _judgeQuestions = List<String>.from(
            result.result['questions'] as List,
          );
        } else {
          _ruling = result.result;
          _rulingHistory.add({
            'model': result.model,
            'practice': false,
            'ruling': Map<String, dynamic>.from(_ruling!),
          });
          _agreement.text = _ruling!['proposedRemedy'] as String;
          _approved.fillRange(0, 2, false);
        }
      });
      _enterStage(
        action == 'questions'
            ? 10
            : action == 'appeal'
            ? 17
            : 13,
      );
    } on JudgeException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the case or evidence. No new ruling was issued.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _practiceAction(String action) {
    setState(() {
      _practice = true;
      _result = const JudgeResult('', 'offline-practice');
      _evidenceReview = _evidence
          .map(
            (entry) => <String, dynamic>{
              'id': entry['id'],
              'observation': 'Not examined in practice mode.',
              'limitation': 'No model has read this photo.',
            },
          )
          .toList();
      if (action == 'questions') {
        _judgeQuestions = [
          'What part of your requested outcome matters most, and why?',
          'Which part of the request could you willingly agree to, and what would you change?',
        ];
      } else {
        _ruling = {
          'decision': 'alternative',
          'requestedRemedy': _request.text.trim(),
          'proposedRemedy': 'Each propose one small practical action, then choose a shared next step together.',
          'reasoning': action == 'appeal'
              ? 'Scripted appeal practice only. No real appeal review has occurred.'
              : 'Scripted practice only. This is not an AI ruling and does not evaluate the evidence.',
          'uncertainties': 'No evidence was examined. No finding about either person is made.',
          'evidenceReview': _evidenceReview,
        };
        _rulingHistory.add({
          'model': 'offline-practice',
          'practice': true,
          'ruling': Map<String, dynamic>.from(_ruling!),
        });
        _agreement.text = _ruling!['proposedRemedy'] as String;
        _approved.fillRange(0, 2, false);
      }
    });
    _enterStage(
      action == 'questions'
          ? 10
          : action == 'appeal'
          ? 17
          : 13,
    );
  }

  Future<void> _closeCase({bool accepted = true}) async {
    if (_recorded ||
        _busy ||
        (accepted && !_approved.every((value) => value))) {
      return;
    }
    setState(() => _busy = true);
    try {
      final raw = widget.preferences.getString('court_cases_v1');
      final history = raw == null
          ? <dynamic>[]
          : jsonDecode(raw) as List<dynamic>;
      final transcript = await _docket();
      transcript['evidence'] = _evidence
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final record = <String, dynamic>{
        'id': _caseId,
        'names': _names.map((e) => e.text.trim()).toList(),
        'topic': _topic.text.trim(),
        'requestedRemedy': _request.text.trim(),
        'agreement': accepted
            ? _agreement.text.trim()
            : 'Not agreed · case left unresolved',
        'status': accepted ? 'accepted' : 'unresolved',
        'verdict': _ruling,
        'rulingHistory': _rulingHistory,
        'case': transcript,
        'model': _result!.model,
        'practice': _practice,
        'date': DateTime.now().toIso8601String(),
      };
      history.removeWhere((entry) => entry is Map && entry['id'] == _caseId);
      history.insert(0, record);
      final saved = await widget.preferences.setString(
        'court_cases_v1',
        jsonEncode(history.take(30).toList()),
      );
      if (!saved) throw const FormatException();
      await widget.onCaseClosed?.call(record);
      _draftSave?.cancel();
      await _draftWrites;
      await widget.preferences.remove('court_draft_$_caseId');
      if (mounted) {
        setState(() {
          _recorded = true;
          _stage = 18;
          _error = null;
          if (!accepted) _agreement.text = 'Not agreed · case left unresolved';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save this case. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    if (widget.caseId != null) {
      Navigator.pop(context);
      return;
    }
    _pause();
    setState(() {
      _stage = 0;
      _caseId = DateTime.now().microsecondsSinceEpoch.toString();
      for (final field in [
        ..._statements,
        ..._crossQuestions,
        ..._crossAnswers,
        ..._rebuttals,
        ..._judgeAnswers,
        _topic,
        _request,
        _agreement,
        _appealReason,
        _appealResponse,
      ]) {
        field.clear();
      }
      _evidence.clear();
      _evidenceReview.clear();
      _rulingHistory.clear();
      _judgeQuestions = ['', ''];
      _ruling = null;
      _result = null;
      _error = null;
      _hasAppealed = false;
      _recorded = false;
      _approved.fillRange(0, 2, false);
      _remaining = _turnSeconds;
    });
  }

  Future<void> _history() async {
    List<dynamic> cases;
    try {
      cases = jsonDecode(
        widget.preferences.getString('court_cases_v1') ?? '[]',
      ) as List<dynamic>;
    } catch (_) {
      cases = [];
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Closed cases',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (cases.isEmpty)
                const Text('Your shared agreements will appear here.'),
              for (final entry in cases)
                Card(
                  child: ListTile(
                    title: Text(entry['topic'] as String),
                    subtitle: Text(
                      '${entry['agreement']}\n${entry['practice'] == true ? 'Practice verdict' : entry['model']}',
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scene = CourtroomScene(
      generatedScene: _generatedScene,
      names: _names.map((e) => e.text).toList(),
      active: _speakers[_stage] ?? -1,
    );
    final panel = Form(
      key: _form,
      child: ListView(
        controller: _panelScroll,
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFA32E21)),
              ),
            ),
          ...switch (_stage) {
            0 => _setup(),
            1 || 2 => _opening(),
            3 || 4 || 5 || 6 => _cross(),
            7 || 8 => _rebuttal(),
            9 => _review('questions'),
            10 || 11 => _judgeAnswer(),
            12 => _review('verdict'),
            13 || 17 => _decision(),
            14 || 15 => _appeal(),
            16 => _review('appeal'),
            _ => _closed(),
          },
          const SizedBox(height: 16),
          const Text(
            'One-device prototype · Photos uploaded only with your consent',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF7E695A)),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF2D1A15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D1A15),
        foregroundColor: const Color(0xFFFFDFAB),
        title: const Text(
          'COUPLE COURT',
          style: TextStyle(
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'AI demo access',
            onPressed: _busy
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DemoAccessPage(),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
            icon: const Icon(Icons.vpn_key_outlined),
          ),
          IconButton(
            onPressed: _busy ? null : _history,
            tooltip: 'Closed cases',
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final content = Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFF5E3),
                border: Border(
                  top: BorderSide(color: Color(0xFFC79555), width: 3),
                ),
              ),
              child: Material(type: MaterialType.transparency, child: panel),
            );
            if (bounds.maxWidth > bounds.maxHeight && bounds.maxWidth > 650) {
              return Row(
                children: [
                  Expanded(flex: 3, child: Center(child: scene)),
                  Expanded(flex: 2, child: content),
                ],
              );
            }
            return Column(
              children: [
                scene,
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _title(String eyebrow, String title, String body) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: const TextStyle(
          letterSpacing: 2,
          fontSize: 11,
          color: Color(0xFF99703C),
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        title,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w800,
          color: Color(0xFF442A20),
        ),
      ),
      const SizedBox(height: 8),
      Text(body),
      const SizedBox(height: 18),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    int length = 50,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey(label),
      controller: controller,
      readOnly: _busy || (_timed && _remaining == 0),
      minLines: lines,
      maxLines: lines,
      maxLength: length,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) {
        if (controller == _agreement) {
          setState(() => _approved.fillRange(0, 2, false));
        }
        _scheduleDraft();
      },
      validator: (text) =>
          text == null || text.trim().isEmpty ? 'Please fill this in.' : null,
    ),
  );

  List<Widget> _setup() => [
    _title(
      'All rise',
      'Small disputes. A fair hearing.',
      'Meet your judge, tell both sides, and leave with a next step you both choose.',
    ),
    for (var i = 0; i < 2; i++) ...[
      _field(
        _names[i],
        i == 0 ? 'Claimant’s name (filing the case)' : 'Respondent’s name',
      ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _photo(i),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _photos[i] == null
                    ? 'Add partner ${i + 1} face'
                    : 'Change partner ${i + 1} face',
              ),
            ),
          ),
          if (_photos[i] != null)
            IconButton(
              tooltip: 'Remove partner ${i + 1} face',
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _photos[i] = null;
                        _generatedScene = null;
                        _artResponseId = null;
                        _promptVersion = null;
                      });
                      unawaited(_saveProfile());
                    },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      const SizedBox(height: 12),
    ],
    const Text(
      'Choose two close-up portraits you have permission to use. Muse Image will redraw both people into the pixel-art courtroom. Selected photos are not placed over the characters.',
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed:
          _busy || !_artwork.configured || _photos.any((photo) => photo == null)
          ? null
          : _generateScene,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.palette_outlined),
      label: Text(
        _busy
            ? 'Creating your courtroom…'
            : _generatedScene == null
            ? 'Create our characters with Muse Image'
            : 'Regenerate with Muse Image',
      ),
    ),
    const SizedBox(height: 8),
    Text(
      _generatedScene != null
          ? 'Scene created with Muse Image · muse-image-1.0'
          : _artwork.configured
          ? 'Add both portraits, then generate your scene. You can also try the hearing with the reference artwork.'
          : 'Reference artwork shown. Connect Meta Model API to create your personalized scene.',
      style: const TextStyle(fontSize: 12),
    ),
    const SizedBox(height: 18),
    _field(_topic, 'What is the disagreement?', lines: 2, length: 1000),
    _field(
      _request,
      'What compensation or action are you requesting?',
      lines: 2,
      length: 1000,
    ),
    const Text(
      'Ask for a small, voluntary everyday action, such as cooking dinner once. The judge may adjust or decline the request.',
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<int>(
      initialValue: _turnSeconds,
      decoration: const InputDecoration(labelText: 'Time per speaking turn'),
      items: const [
        DropdownMenuItem(value: 60, child: Text('1 minute')),
        DropdownMenuItem(value: 120, child: Text('2 minutes')),
        DropdownMenuItem(value: 180, child: Text('3 minutes')),
      ],
      onChanged: _busy
          ? null
          : (value) => setState(() => _turnSeconds = value!),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: _busy ? null : _next,
      icon: const Icon(Icons.gavel),
      label: const Text('Enter the courtroom'),
    ),
  ];

  Widget _clock() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _remaining == 0
                ? const Color(0xFFA32E21)
                : const Color(0xFF442A20),
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: _busy || _remaining == 0 ? null : _timerToggle,
          icon: Icon(
            (_timer?.isActive ?? false) ? Icons.pause : Icons.play_arrow,
          ),
          label: Text(
            _remaining == 0
                ? 'Time is up'
                : (_timer?.isActive ?? false)
                ? 'Pause timer'
                : 'Resume timer',
          ),
        ),
      ],
    ),
  );

  Widget _continue(String label) => FilledButton(
    onPressed: _busy ? null : _next,
    child: Text(_remaining == 0 && _timed ? 'Time is up — continue' : label),
  );

  List<Widget> _exhibits({int? canAdd}) => [
    if (canAdd != null)
      OutlinedButton.icon(
        onPressed:
            _busy ||
                _remaining == 0 ||
                _evidence.where((e) => e['owner'] == canAdd).length >= 2
            ? null
            : () => _addEvidence(canAdd),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Attach evidence photo'),
      ),
    if (canAdd != null)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Up to 2 photos per person · 1 MB each · Your caption is a claim, not proof.',
          style: TextStyle(fontSize: 12),
        ),
      ),
    for (final entry in _evidence)
      Card(
        child: ListTile(
          onTap: () => _viewEvidence(entry),
          leading: SizedBox(
            width: 44,
            height: 44,
            child: Image.file(
              File(entry['path'] as String),
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  const Icon(Icons.broken_image_outlined),
            ),
          ),
          title: Text('${entry['id']} · ${_names[entry['owner'] as int].text}'),
          subtitle: Text(entry['caption'] as String),
          trailing: canAdd == entry['owner'] && !_busy && _remaining > 0
              ? IconButton(
                  tooltip: 'Remove exhibit ${entry['id']}',
                  onPressed: () {
                    setState(() => _evidence.remove(entry));
                    _scheduleDraft();
                  },
                  icon: const Icon(Icons.close),
                )
              : const Icon(Icons.zoom_in),
        ),
      ),
  ];

  List<Widget> _opening() {
    final owner = _stage - 1;
    return [
      _title(
        'Opening · ${owner == 0 ? 'Claimant' : 'Respondent'}',
        '${_names[owner].text.trim()}, the floor is yours.',
        'Tell your side and attach photos you want the judge to examine. Both people can see every submitted exhibit.',
      ),
      _clock(),
      Text(
        'Requested compensation: ${_request.text.trim()}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      _field(
        _statements[owner],
        'Your opening statement',
        lines: 4,
        length: 2000,
      ),
      ..._exhibits(canAdd: owner),
      const SizedBox(height: 12),
      _continue(owner == 0 ? 'Hear the respondent' : 'Begin cross-examination'),
    ];
  }

  List<Widget> _cross() {
    final asking = _stage == 3 || _stage == 5;
    final person = _speakers[_stage]!;
    final other = 1 - person;
    return [
      _title(
        'Cross-examination · ${asking ? 'Question' : 'Answer'}',
        asking
            ? '${_names[person].text.trim()}, ask your partner.'
            : '${_names[person].text.trim()}, your answer.',
        asking
            ? 'Ask one clear, respectful question about the case or an exhibit. Your partner answers during their own timed turn.'
            : 'Answer the question directly. If you cannot establish a fact, say so.',
      ),
      _clock(),
      if (!asking)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${_names[other].text}: ${_crossQuestions[other].text}',
            ),
          ),
        ),
      _field(
        asking ? _crossQuestions[person] : _crossAnswers[person],
        asking ? 'Question for your partner' : 'Your answer',
        lines: 3,
        length: 2000,
      ),
      ..._exhibits(),
      _continue(
        asking
            ? 'Give your partner the floor'
            : _stage == 6
            ? 'Begin rebuttals'
            : 'Ask the claimant a question',
      ),
    ];
  }

  List<Widget> _rebuttal() {
    final person = _stage - 7;
    return [
      _title(
        'Rebuttal',
        '${_names[person].text.trim()}, respond to the other side.',
        'Address a disputed point, clarify your testimony or challenge an exhibit’s context.',
      ),
      _clock(),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Other side’s opening: ${_statements[1 - person].text}'),
        ),
      ),
      _field(_rebuttals[person], 'Your rebuttal', lines: 4, length: 2000),
      ..._exhibits(canAdd: person),
      _continue(
        person == 0 ? 'Hear the respondent’s rebuttal' : 'Review the case',
      ),
    ];
  }

  List<Widget> _review(String action) => [
    _title(
      action == 'questions'
          ? 'Evidence review'
          : action == 'appeal'
          ? 'Appeal review'
          : 'Final submissions',
      action == 'questions'
          ? 'The judge has questions.'
          : action == 'appeal'
          ? 'A second look at the ruling.'
          : 'Ready for the ruling?',
      'Review the full record. The judge examines submitted evidence photos and weighs both accounts, but cannot authenticate images or verify their context.',
    ),
    Text(
      'Case: ${_topic.text}',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 8),
    Text('Claimant requests: ${_request.text}'),
    for (var i = 0; i < 2; i++)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _names[i].text,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Opening: ${_statements[i].text}'),
              const SizedBox(height: 8),
              Text('Asked: ${_crossQuestions[i].text}'),
              Text('Answered partner: ${_crossAnswers[i].text}'),
              const SizedBox(height: 8),
              Text('Rebuttal: ${_rebuttals[i].text}'),
              if (action != 'questions') ...[
                const SizedBox(height: 8),
                Text('Judge asked: ${_judgeQuestions[i]}'),
                Text('Answer: ${_judgeAnswers[i].text}'),
              ],
            ],
          ),
        ),
      ),
    ..._exhibits(),
    if (action == 'appeal') ...[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Prior proposal: ${_ruling!['proposedRemedy']}\n\nAppeal: ${_appealReason.text}\n\nClaimant’s response: ${_appealResponse.text}',
          ),
        ),
      ),
    ],
    if (!_judge.configured)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'The Meta judge is not connected yet. Practice mode does not examine photos.',
        ),
      ),
    FilledButton.icon(
      onPressed: _busy || !_judge.configured
          ? null
          : () => _judgeAction(action),
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.gavel),
      label: Text(
        _busy
            ? 'The judge is reviewing…'
            : action == 'questions'
            ? 'Ask judge to examine evidence'
            : action == 'appeal'
            ? 'Submit appeal to judge'
            : 'Request final verdict',
      ),
    ),
    OutlinedButton(
      onPressed: _busy ? null : () => _practiceAction(action),
      child: Text(
        action == 'questions'
            ? 'Use practice questions'
            : action == 'appeal'
            ? 'Review appeal in practice'
            : 'Try a practice verdict',
      ),
    ),
  ];

  List<Widget> _judgeAnswer() {
    final person = _stage - 10;
    return [
      _title(
        _practice
            ? 'Practice question · scripted'
            : 'Question from ${_result!.model}',
        '${_names[person].text.trim()}, the judge asks…',
        _judgeQuestions[person],
      ),
      _clock(),
      _field(_judgeAnswers[person], 'Answer the judge', lines: 4, length: 2000),
      ..._reviewedEvidence(),
      _continue(
        person == 0
            ? 'Judge’s question for the respondent'
            : 'Prepare the final verdict',
      ),
    ];
  }

  List<Widget> _reviewedEvidence() => [
    for (final review in _evidenceReview)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${review['id']} · ${_practice ? 'Practice placeholder' : 'Judge’s visual observation'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(review['observation'] as String),
              const SizedBox(height: 6),
              Text('Limit: ${review['limitation']}'),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _decision() => [
    _title(
      _practice ? 'Offline practice · scripted' : 'Meta AI · ${_result!.model}',
      _stage == 17 ? 'The appeal decision' : 'The judge’s ruling',
      'A voluntary proposal for an everyday dispute. Either person may decline.',
    ),
    Text(
      'Original request: ${_request.text}',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 12),
    Text(
      'Decision: ${_ruling!['decision']}',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 8),
    SelectableText(
      _ruling!['proposedRemedy'] as String,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 16),
    Text(_ruling!['reasoning'] as String),
    const SizedBox(height: 12),
    Text('Uncertainty: ${_ruling!['uncertainties']}'),
    ..._reviewedEvidence(),
    for (var i = 0; i < 2; i++)
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${_names[i].text.trim()} accepts this proposal'),
        value: _approved[i],
        onChanged: _busy
            ? null
            : (value) => setState(() => _approved[i] = value!),
      ),
    FilledButton(
      onPressed: _busy || !_approved.every((value) => value)
          ? null
          : () => _closeCase(),
      child: const Text('Accept & close case'),
    ),
    if (!_hasAppealed)
      OutlinedButton(
        onPressed: _busy
            ? null
            : () {
                _hasAppealed = true;
                _enterStage(14);
              },
        child: const Text('Respondent: appeal this ruling'),
      ),
    TextButton(
      onPressed: _busy ? null : () => _closeCase(accepted: false),
      child: const Text('Decline & leave unresolved'),
    ),
    const Text(
      'Both acceptances happen on this phone. One appeal is available in this prototype.',
      style: TextStyle(fontSize: 12),
    ),
  ];

  List<Widget> _appeal() {
    final respondent = _stage == 14;
    return [
      _title(
        'Appeal · ${respondent ? 'Respondent' : 'Claimant’s response'}',
        '${_names[respondent ? 1 : 0].text.trim()}, your turn.',
        respondent
            ? 'Explain what the judge missed or why the proposed compensation should change. You may submit another exhibit if you have a slot.'
            : 'Respond to the appeal grounds. Address the facts rather than the person.',
      ),
      _clock(),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Previous proposal: ${_ruling!['proposedRemedy']}${respondent ? '' : '\n\nAppeal: ${_appealReason.text}'}',
          ),
        ),
      ),
      _field(
        respondent ? _appealReason : _appealResponse,
        respondent ? 'Grounds for appeal' : 'Response to the appeal',
        lines: 4,
        length: 2000,
      ),
      ..._exhibits(canAdd: respondent ? 1 : 0),
      _continue(respondent ? 'Let the claimant respond' : 'Review the appeal'),
    ];
  }

  List<Widget> _closed() => [
    _title(
      'Case closed',
      _agreement.text.startsWith('Not agreed')
          ? 'The case remains unresolved.'
          : 'A little more understanding.',
      'The outcome and hearing record are saved on this device.',
    ),
    Text(_agreement.text, style: const TextStyle(fontSize: 19)),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _reset,
      child: Text(
        widget.caseId == null ? 'Start a new case' : 'Back to Closer',
      ),
    ),
  ];
}

class _EvidenceCaption extends StatefulWidget {
  const _EvidenceCaption();
  @override
  State<_EvidenceCaption> createState() => _EvidenceCaptionState();
}

class _EvidenceCaptionState extends State<_EvidenceCaption> {
  final _caption = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Describe this exhibit'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Say what you think this photo shows and what context might be missing. Only share images you have permission to use.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _caption,
            maxLength: 500,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Evidence caption'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Add a caption.' : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _caption.text.trim());
          }
        },
        child: const Text('Submit exhibit'),
      ),
    ],
  );
}
