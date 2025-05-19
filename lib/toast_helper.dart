import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:toastification/toastification.dart';

class ToastHelper {
  static Future<ToastificationItem> showToast({
    required BuildContext context,
    required String title,
    String? description,
    Color? color,
    Color? borderColor,
    ToastificationStyle? toastificationStyle,
  }) async {
    late ToastificationItem notification;

    void onPressed() => toastification.dismiss(notification);

    notification = toastification.show(
      context: context,
      type: ToastificationType.success,
      style: toastificationStyle ?? ToastificationStyle.fillColored,
      autoCloseDuration: const Duration(seconds: 3),
      borderSide: toastificationStyle != null
          ? BorderSide(
              color: borderColor ?? Colors.white,
            )
          : null,
      primaryColor: color,
      backgroundColor:
          toastificationStyle != null ? color ?? Colors.black : null,
      showIcon: false,
      borderRadius: BorderRadius.circular(12.r),
      showProgressBar: false,
      closeButtonShowType: CloseButtonShowType.none,
      // closeOnClick: true,
      pauseOnHover: false,
      dragToClose: true,
      dismissDirection: DismissDirection.up,
      description: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.left,
                  maxLines: 2,
                ),
                if (description != null)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 7.h,
                    ),
                    child: Text(
                      description,
                      textAlign: TextAlign.left,
                      maxLines: 3,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              IconButton(
                key: const Key('close_button'),
                onPressed: onPressed,
                icon: Icon(
                  Icons.close,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return notification;
  }

  static void successToast({
    required BuildContext context,
    required String title,
    String? description,
    ToastificationStyle? toastificationStyle,
  }) {
    showToast(
      context: context,
      title: title,
      description: description,
      color: Colors.greenAccent,
      borderColor: Colors.green,
      toastificationStyle: toastificationStyle,
    );
  }

  static void failureToast({
    required BuildContext context,
    required String title,
    String? description,
    ToastificationStyle? toastificationStyle,
  }) {
    showToast(
      context: context,
      title: title,
      description: description,
      color: Colors.redAccent,
      borderColor: Colors.red,
      toastificationStyle: toastificationStyle,
    );
  }

  static void warningToast({
    required BuildContext context,
    required String title,
    String? description,
    ToastificationStyle? toastificationStyle,
  }) {
    showToast(
      context: context,
      title: title,
      description: description,
      color: Colors.yellowAccent,
      borderColor: Colors.yellow,
      toastificationStyle: toastificationStyle,
    );
  }
}
