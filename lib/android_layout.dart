import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Android 15부터는 앱이 하단 내비게이션 바 뒤까지 그려지므로, 그 높이만큼의 하단 여백.
///
/// iOS 레이아웃은 기존과 같게 두기 위해 Android가 아니면 [EdgeInsets.zero]를 돌려준다.
EdgeInsets androidBottomInset(BuildContext context) =>
    defaultTargetPlatform == TargetPlatform.android
    ? EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)
    : EdgeInsets.zero;
